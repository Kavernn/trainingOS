import SwiftUI
import Charts
import OSLog

private let statsHistoryLogger = Logger(subsystem: "TrainingOS", category: "stats_history")

// MARK: - Helpers
func totalReps(_ reps: String) -> Double {
    let s = reps.trimmingCharacters(in: .whitespaces).lowercased()
    if s.contains(",") {
        return s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.reduce(0, +)
    }
    if let r = s.range(of: "x") {
        if let sets = Double(s[s.startIndex..<r.lowerBound]),
           let rps  = Double(s[r.upperBound...]) { return sets * rps }
    }
    return Double(s) ?? 0
}

func isoWeekKey(_ dateStr: String) -> String {
    DateFormatter.isoDate.date(from: dateStr)?.isoWeekKey ?? ""
}

func weekLabel(_ key: String) -> String {
    let parts = key.components(separatedBy: "-W")
    guard parts.count == 2, let yr = Int(parts[0]), let wk = Int(parts[1]) else { return key }
    var comps = DateComponents()
    comps.yearForWeekOfYear = yr; comps.weekOfYear = wk; comps.weekday = 2
    let cal = Calendar(identifier: .iso8601)
    guard let d = cal.date(from: comps) else { return key }
    return DateFormatter.shortDateFRCA.string(from: d)
}

func _formatK(_ v: Double) -> String {
    if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
    if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
    return String(format: "%.0f", v)
}

// MARK: - Period Selector
enum StatsPeriod: String, CaseIterable {
    case month1 = "1M"
    case month3 = "3M"
    case month6 = "6M"
    case all    = "Tout"

    var cutoff: String? {
        let cal = Calendar.mtl
        let months: Int
        switch self {
        case .month1: months = -1
        case .month3: months = -3
        case .month6: months = -6
        case .all:    return nil
        }
        let date = cal.date(byAdding: .month, value: months, to: Date()) ?? Date()
        return DateFormatter.isoDate.string(from: date)
    }
}

// MARK: - Primary Stats Navigation
enum StatsTab: String, CaseIterable, Identifiable {
    case overview
    case strength
    case load
    case consistency
    case body

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: return "Vue d’ensemble"
        case .strength: return "Force"
        case .load: return "Charge"
        case .consistency: return "Régularité"
        case .body: return "Corps"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "chart.bar.xaxis"
        case .strength: return "dumbbell.fill"
        case .load: return "chart.line.uptrend.xyaxis"
        case .consistency: return "calendar.badge.clock"
        case .body: return "figure.stand"
        }
    }

    var accessibilityLabel: String { title }
}

private enum StatsCockpitPolicy {
    static let progressionDays = 90
    static let weeklyDays = 84
    static let muscleDays = 30
}

// MARK: - Main View
struct StatsView: View {
    @EnvironmentObject private var theme: AppTheme
    @ObservedObject var units = UnitSettings.shared
    @State var weights:          [String: WeightData]    = [:]
    @State var sessions:         [String: SessionEntry]  = [:]
    @State var hiitLog:          [HIITEntry]             = []
    /// Logs cardio pour la heatmap Régularité (parité avec la définition
    /// serveur du streak qui compte workout + HIIT + cardio).
    @State var cardioLog:        [CardioEntry]           = []
    @State var bodyWeight:       [BodyWeightEntry]       = []
    @State var recoveryLog:      [RecoveryEntry]         = []
    @State var nutritionTarget:  NutritionSettings?      = nil
    /// Cible calorique adaptative — source unique (energy?.targetCalories via /api/energy/daily).
    /// `nil` si <7j TDEE historique → labels cachés (règle anti-fantôme).
    @State var targetCalories:   Int?                    = nil
    @State var nutritionDays:    [NutritionDay]          = []
    /// Fenêtre nutrition_history source-aware (A2) : expose source +
    /// pct_declared + target_calories_snapshot par jour. Vue consommateur :
    /// NutritionComplianceChart (compliance par source), MacrosBreakdownView
    /// (détaillés uniquement). Alimenté par /api/stats/nutrition_history.
    @State var statsNutritionHistory: [DayNutritionHistory] = []
    @State var acwr:             ACWRData?               = nil
    @State var activeDeload:      DeloadStatus?           = nil
    @State var isLoading    = true
    @State var fetchError   = false
    @State var selectedExercise: String? = nil
    @State var searchText   = ""
    @State var selectedTab: StatsTab = .overview
    @State var period: StatsPeriod = .month3
    @State var cockpitData: StatsCockpitResponse? = nil
    @State var cockpitError: String? = nil
    @State var isLoadingCockpit = false

    // ── Stats Expansion State ────────────────────────────────────────
    @State var weeklyTonnage:      [WeeklyTonnageEntry]        = []
    @State var oneRmTrend:         [String: [OneRMPoint]]      = [:]
    @State var macrosByDayType:    MacrosByDayType?            = nil
    @State var proteinWeightRatio: [ProteinWeightPoint]        = []
    @State var moodTrend:          [MoodTrendPoint]            = []
    @State var pssHistory:         [PSSRecord]                 = []
    @State var selfCareStreaks:    [SelfCareStreak]            = []
    @State var selfCareCompliance: SelfCareComplianceData?     = nil
    @State var sorenessScatter:    [ScatterPoint]              = []
    @State var sleepScatter:       [ScatterPoint]              = []
    @State var rpeProgression:     RPEProgressionData?         = nil
    @State var rirByExercise:      [RIREntry]                  = []
    @State var hrvAnalysis:        HRVAnalysis?                = nil
    @State var isLoadingStatsWellness = false
    @State var hasLoadedStatsWellness = false
    @State var isLoadingStatsHRV = false
    @State var hasLoadedStatsHRV = false
    @State var forceAccessoryTimeline: [ForceAccessoryPoint]  = []
    @State var recentPRs:              [RecentPR]              = []
    @State var lastPR:                 LastPROverall?          = nil

    // ── New stats data ────────────────────────────────────────────────────
    @State var seasonComparison: SeasonComparisonData?  = nil
    @State var warRoomStats:     WarRoomSummaryStats?   = nil
    @State var intensityData:    IntensityData?         = nil
    // ── Streak — source serveur unique (/api/stats/streaks) ─────────────────
    @State var streakData: StreakResponse? = nil

    // ── KPIs ────────────────────────────────────────────────────────
    var totalSessions: Int {
        sessions.values.reduce(0) { $0 + $1.sessionCount }
    }

    var sessionsThisMonth: Int {
        let key = DateFormatter.isoYearMonth.string(from: Date())
        return sessions.reduce(0) { acc, kv in
            kv.key.hasPrefix(key) ? acc + kv.value.sessionCount : acc
        }
    }

    var exercisesCount: Int { weights.filter { $0.value.history?.isEmpty == false }.count }

    // ── Personal Records ─────────────────────────────────────────────

    // ── Weekly charts ─────────────────────────────────────────────────
    var last8Weeks: [String] {
        let cal = Calendar(identifier: .iso8601)
        return (0..<8).reversed().map { i in
            (cal.date(byAdding: .weekOfYear, value: -i, to: Date()) ?? Date()).isoWeekKey
        }
    }

    var weeklyVolumeChart: [(String, Double)] {
        var vols: [String: Double] = [:]
        for (_, data) in weights {
            for e in data.history ?? [] {
                guard let date = e.date else { continue }
                let vol: Double
                if let ev = e.exerciseVolume, ev > 0 {
                    vol = ev
                } else {
                    guard let w = e.weight, let r = e.reps else { continue }
                    vol = w * totalReps(r)
                }
                vols[isoWeekKey(date), default: 0] += vol
            }
        }
        return last8Weeks.map { ($0, vols[$0] ?? 0) }
    }

    // ── RPE history ──────────────────────────────────────────────────
    var rpeHistory: [(String, Double)] {
        sessions.compactMap { date, e -> (String, Double)? in
            e.rpe.map { (date, $0) }
        }
        .sorted { $0.0 < $1.0 }.suffix(20).map { $0 }
    }

    var exercisesWithHistory: [(String, WeightData)] {
        let base = weights.filter { $0.value.history?.isEmpty == false }
        if searchText.isEmpty { return base.sorted { $0.key < $1.key } }
        return base.filter { $0.key.localizedCaseInsensitiveContains(searchText) }.sorted { $0.key < $1.key }
    }

    // ── Period-filtered data ──────────────────────────────────────────
    var filteredSessions: [String: SessionEntry] {
        guard let cutoff = period.cutoff else { return sessions }
        return sessions.filter { $0.key >= cutoff }
    }

    var filteredBodyWeight: [BodyWeightEntry] {
        guard let cutoff = period.cutoff else { return bodyWeight }
        return bodyWeight.filter { $0.date >= cutoff }
    }

    var filteredRecovery: [RecoveryEntry] {
        guard let cutoff = period.cutoff else { return recoveryLog }
        return recoveryLog.filter { ($0.date ?? "") >= cutoff }
    }

    var filteredNutrition: [NutritionDay] {
        guard let cutoff = period.cutoff else { return nutritionDays }
        return nutritionDays.filter { ($0.date ?? "") >= cutoff }
    }

    /// Fenêtre source-aware (A2) — période appliquée sur la date canonique.
    var filteredStatsNutrition: [DayNutritionHistory] {
        guard let cutoff = period.cutoff else { return statsNutritionHistory }
        return statsNutritionHistory.filter { $0.date >= cutoff }
    }

    // ── Week comparison ───────────────────────────────────────────────
    func weekBounds(weeksAgo: Int) -> (String, String) { Date().isoWeekBounds(weeksAgo: weeksAgo) }

    // ── Recovery Profile ──────────────────────────────────────────────
    // Pour chaque séance RPE ≥ 7.5, examine les logs recovery dans les 21 j
    // suivants :
    //   - au moins une mesure soreness < 3 → épisode `resolved` (jours réels
    //     depuis la séance ; aucun plafond artificiel sur la valeur).
    //   - fenêtre terminée (séance + 21 j ≤ aujourd'hui) + au moins une
    //     mesure soreness ≥ 3 et aucune < 3 → épisode `unresolved`.
    //   - fenêtre encore ouverte → "en cours", exclu des deux comptes.
    //   - aucune mesure soreness dans la fenêtre → exclu (pas de donnée
    //     ≠ pas récupéré).
    // Garde-fou médiane : minimum 5 épisodes résolus.
    var recoveryProfile: RecoveryProfile? {
        let heavy = sessions.filter { ($0.value.rpe ?? 0) >= Self.recoveryHeavyRpe }
        guard !heavy.isEmpty else { return nil }
        let sortedRec = filteredRecovery.sorted { ($0.date ?? "") < ($1.date ?? "") }
        let now = Date()

        var resolved: [Int] = []
        var unresolved = 0

        for (sessionDate, _) in heavy {
            guard let sd = DateFormatter.isoDate.date(from: sessionDate) else { continue }
            let cutoff = Calendar.mtl.date(byAdding: .day, value: Self.recoverySearchDays, to: sd) ?? sd

            var resolvedDay: Int?
            var hasMeasureInWindow = false
            for entry in sortedRec {
                guard let rdStr = entry.date,
                      let rd = DateFormatter.isoDate.date(from: rdStr),
                      rd > sd else { continue }
                if rd > cutoff { break }
                guard let soreness = entry.soreness else { continue }
                hasMeasureInWindow = true
                if soreness < 3 {
                    let d = Int(rd.timeIntervalSince(sd) / 86400)
                    if d > 0 { resolvedDay = d }
                    break
                }
            }

            if let d = resolvedDay {
                resolved.append(d)
                continue
            }
            // Fenêtre encore ouverte → en cours, on ne tranche pas.
            guard cutoff <= now else { continue }
            // Fenêtre terminée + mesures présentes toutes ≥ 3 → unresolved.
            // Fenêtre terminée + aucune mesure → exclu (silence de donnée).
            if hasMeasureInWindow { unresolved += 1 }
        }

        guard resolved.count + unresolved > 0 else { return nil }

        let stats: RecoveryProfile.Stats?
        if resolved.count >= Self.recoveryMinResolved {
            let sorted = resolved.sorted()
            stats = RecoveryProfile.Stats(
                medianDays: percentile(sorted, 0.5),
                p25Days:    percentile(sorted, 0.25),
                p75Days:    percentile(sorted, 0.75),
            )
        } else {
            stats = nil
        }
        return RecoveryProfile(
            stats: stats,
            resolvedCount: resolved.count,
            unresolvedCount: unresolved,
        )
    }

    private static let recoverySearchDays: Int = 21
    private static let recoveryMinResolved: Int = 5
    private static let recoveryHeavyRpe: Double = 7.5

    private func percentile(_ sorted: [Int], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        if sorted.count == 1 { return Double(sorted[0]) }
        let idx = Double(sorted.count - 1) * p
        let lo = Int(idx.rounded(.down))
        let hi = Int(idx.rounded(.up))
        if lo == hi { return Double(sorted[lo]) }
        let frac = idx - Double(lo)
        return Double(sorted[lo]) + frac * Double(sorted[hi] - sorted[lo])
    }

    var tabAmbientColor: Color { .forge }

    // ── Body ─────────────────────────────────────────────────────────
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: tabAmbientColor)
                if isLoading {
                    AppLoadingView()
                } else if fetchError {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash").font(.appHero).foregroundColor(.gray)
                        Text("Impossible de charger les stats").foregroundColor(.gray)
                        Button("Réessayer") { Task { await loadData() } }
                            .foregroundColor(Color.forge).fontWeight(.semibold)
                    }
                } else if weights.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar").font(.appHero).foregroundColor(.gray.opacity(0.4))
                        Text("Tes stats se construisent séance après séance.")
                            .font(.appBody.weight(.medium))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Text("Continue à logger.")
                            .font(.appLabel)
                            .foregroundColor(.gray.opacity(0.6))
                    }
                    // offset lisibilité empty state
                    .padding(.horizontal, 40)
                } else {
                    VStack(spacing: 0) {
                        StatsTabBar(selectedTab: $selectedTab)
                            .padding(.horizontal, .appPagePadding)
                            .padding(.top, 4)

                        if selectedTab == .body {
                            PeriodPicker(selected: $period)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }

                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 16) {
                                switch selectedTab {
                                case .overview: vueGlobaleTab
                                case .strength: exercicesTab
                                case .load: chargeVolumeTab
                                case .consistency: consistencyTab
                                case .body: corpsTab
                                }
                            }
                            .padding(.top, 8)
                            .padding(.bottom, contentBottomPadding)
                        }
                        .refreshable {
                            await loadData()
                            await loadCockpitData()
                            if hasLoadedStatsWellness {
                                await loadStatsWellnessIfNeeded(force: true)
                            }
                            if hasLoadedStatsHRV {
                                await loadStatsHRVIfNeeded(force: true)
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink {
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 16) {
                                    PeriodPicker(selected: $period)
                                        .padding(.horizontal, 16)
                                    nutritionTab
                                }
                                .padding(.top, 8)
                                .padding(.bottom, contentBottomPadding)
                            }
                        } label: {
                            Label("Nutrition", systemImage: "fork.knife")
                        }
                        NavigationLink {
                            ScrollView(showsIndicators: false) {
                                bienetreTab
                                    .padding(.top, 8)
                                    .padding(.bottom, contentBottomPadding)
                            }
                            .task {
                                await loadStatsWellnessIfNeeded()
                                await loadStatsHRVIfNeeded()
                            }
                        } label: {
                            Label("Bien-être", systemImage: "heart.text.square.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("Autres analyses")
                    }
                }
            }
            .sheet(item: Binding(
                get: { selectedExercise.map { ExerciseWrapper(name: $0) } },
                set: { selectedExercise = $0?.name }
            )) { wrapper in
                ExerciseDetailView(name: wrapper.name, data: weights[wrapper.name])
            }
        }
        .task {
            await loadData()
            await loadCockpitData()
        }
    }

    func formatK(_ v: Double) -> String { _formatK(v) }

    /// Loads the new cockpit independently from the legacy Stats pipeline.
    /// A failed refresh keeps the last usable cockpit snapshot in memory.
    func loadCockpitData() async {
        guard !isLoadingCockpit else { return }
        isLoadingCockpit = true
        cockpitError = nil
        defer { isLoadingCockpit = false }

        do {
            cockpitData = try await APIService.shared.fetchStatsCockpit(
                asOf: AppState.shared.todayStr,
                progressionDays: StatsCockpitPolicy.progressionDays,
                weeklyDays: StatsCockpitPolicy.weeklyDays,
                muscleDays: StatsCockpitPolicy.muscleDays
            )
        } catch {
            cockpitError = error.localizedDescription
        }
    }

    // Local decodable mirror of the stats response
    struct StatsAPIResponse: Codable {
        let weights:              [String: WeightData]
        let sessions:             [String: SessionEntry]
        let hiitLog:              [HIITEntry]
        let bodyWeight:           [BodyWeightEntry]
        let recoveryLog:          [RecoveryEntry]
        let nutritionTarget:      NutritionSettings?
        let nutritionDays:        [NutritionDay]
        let weeklyTonnage:        [WeeklyTonnageEntry]?
        let oneRmTrend:           [String: [OneRMPoint]]?
        let macrosByDayType:      MacrosByDayType?
        let proteinWeightRatio:   [ProteinWeightPoint]?

        enum CodingKeys: String, CodingKey {
            case weights, sessions
            case hiitLog            = "hiit_log"
            case bodyWeight         = "body_weight"
            case recoveryLog        = "recovery_log"
            case nutritionTarget    = "nutrition_target"
            case nutritionDays      = "nutrition_days"
            case weeklyTonnage      = "weekly_tonnage"
            case oneRmTrend         = "one_rm_trend"
            case macrosByDayType    = "macros_by_day_type"
            case proteinWeightRatio = "protein_weight_ratio"
        }
    }

    struct WellnessAPIResponse: Codable {
        let moodTrend:             [MoodTrendPoint]
        let pssHistory:            [PSSRecord]
        let selfCareStreaks:        [SelfCareStreak]
        let selfCareCompliance:    SelfCareComplianceData?
        let sorenessVolumeScatter: [ScatterPoint]
        let sleepVolumeScatter:    [ScatterPoint]
        let rpeProgression:        RPEProgressionData?
        let rirByExercise:         [RIREntry]

        enum CodingKeys: String, CodingKey {
            case moodTrend             = "mood_trend"
            case pssHistory            = "pss_history"
            case selfCareStreaks        = "self_care_streaks"
            case selfCareCompliance    = "self_care_compliance"
            case sorenessVolumeScatter = "soreness_volume_scatter"
            case sleepVolumeScatter    = "sleep_volume_scatter"
            case rpeProgression        = "rpe_progression"
            case rirByExercise         = "rir_by_exercise"
        }
    }

    func applyStats(_ r: StatsAPIResponse) {
        weights            = r.weights
        sessions           = r.sessions
        hiitLog            = r.hiitLog
        bodyWeight         = r.bodyWeight
        recoveryLog        = r.recoveryLog
        nutritionTarget    = r.nutritionTarget
        nutritionDays      = r.nutritionDays
        weeklyTonnage      = r.weeklyTonnage ?? []
        oneRmTrend         = r.oneRmTrend ?? [:]
        macrosByDayType    = r.macrosByDayType
        proteinWeightRatio = r.proteinWeightRatio ?? []
    }

    func applyWellness(_ r: WellnessAPIResponse) {
        moodTrend          = r.moodTrend
        pssHistory         = r.pssHistory
        selfCareStreaks    = r.selfCareStreaks
        selfCareCompliance = r.selfCareCompliance
        sorenessScatter    = r.sorenessVolumeScatter
        sleepScatter       = r.sleepVolumeScatter
        rpeProgression     = r.rpeProgression
        rirByExercise      = r.rirByExercise
    }

    func loadData() async {
        fetchError = false

        // 1. Show cached data immediately (no spinner if cache exists)
        if let cached = CacheService.shared.load(for: "stats_data"),
           let decoded = try? APIService.decoder.decode(StatsAPIResponse.self, from: cached) {
            applyStats(decoded)
            isLoading = false
        }

        // 2. Fetch fresh data — parallel with ACWR
        guard let statsURL = URL(string: "\(APIService.shared.baseURL)/api/stats_data") else { return }
        var req = URLRequest(url: statsURL)
        req.timeoutInterval = 15
        if let (data, _) = try? await URLSession.authed.data(for: req),
           let decoded = try? APIService.decoder.decode(StatsAPIResponse.self, from: data) {
            CacheService.shared.save(data, for: "stats_data")
            applyStats(decoded)
            // stats_data est mis en cache 30 min — les repas loggés dans la journée
            // seraient périmés. On écrase uniquement aujourd'hui avec la source fraîche
            // (même endpoint que NutritionView, même comportement sans cache).
            // Échec silencieux : si l'appel rate, nutritionDays garde la valeur stats_data.
            if let nutrURL = URL(string: "\(APIService.shared.baseURL)/api/nutrition_data?days=1") {
                var nutrReq = URLRequest(url: nutrURL)
                nutrReq.cachePolicy = .reloadIgnoringLocalCacheData
                nutrReq.timeoutInterval = 10
                if let (nutrData, _) = try? await URLSession.authed.data(for: nutrReq),
                   let nutrDecoded = try? APIService.decoder.decode(NutritionDataResponse.self, from: nutrData),
                   let totals = nutrDecoded.totals {
                    let todayStr = AppState.shared.todayStr
                    let fresh = NutritionDay(date: todayStr,
                                             calories: totals.calories,
                                             proteines: totals.proteines,
                                             glucides: totals.glucides,
                                             lipides: totals.lipides)
                    nutritionDays = nutritionDays.filter { $0.date != todayStr } + [fresh]
                }
            }
        } else if weights.isEmpty {
            // No cache and network failed → show error state
            fetchError = true
        }
        // Cible calorique adaptative — même source que NutritionView / EnergyChart.
        targetCalories = (try? await APIService.shared.fetchEnergyDaily())?.targetCalories

        // Fenêtre source-aware pour NutritionComplianceChart + MacrosBreakdownView.
        // Pas de try? : do/catch explicite — un échec reste visible dans la console,
        // la vue affiche "données insuffisantes" si tableau vide.
        do {
            statsNutritionHistory = try await APIService.shared.fetchStatsNutritionHistory(days: 180)
        } catch {
            statsNutritionHistory = []
            statsHistoryLogger.error("fetchStatsNutritionHistory failed: \(error.localizedDescription, privacy: .public)")
        }

        // sequential — async let LIFO crash on iOS 26 beta
        acwr = try? await APIService.shared.fetchACWR()

        // Streak — source serveur unique (P1.2)
        streakData = try? await APIService.shared.fetchStreaks(date: AppState.shared.todayStr)

        // Cardio log pour la heatmap Régularité (parité streak serveur).
        cardioLog = (try? await APIService.shared.fetchCardioData()) ?? []

        activeDeload = try? await APIService.shared.fetchDeloadStatus()
        isLoading = false
        await APIService.shared.syncDeloadFlag()
        NotificationService.scheduleContextual(
            sessionDates: Array(sessions.keys),
            streak: streakData
        )

        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/seasons/comparison"),
               let d = try? await APIService.shared.fetchWithCache(url: url, key: "seasons_comparison"),
               let r = try? APIService.decoder.decode(SeasonComparisonData.self, from: d) {
                await MainActor.run { seasonComparison = r }
            }
        }
        Task {
            // 26 semaines : courbe hero affiche les 12 dernières, delta W1 vs W26.
            if let r = try? await APIService.shared.fetchForceVsAccessory(weeks: 26) {
                await MainActor.run { forceAccessoryTimeline = r.timeline }
            }
        }
        Task {
            // PRs récents backend (filtre baseline_count ≥ 2, 30j). Utilisé par
            // l'accent PR du hero, à la place du calcul iOS naïf sur weights.history
            // qui remontait des 1RM Epley aberrants (calf raise 736 lbs).
            if let r = try? await APIService.shared.fetchPRTracker() {
                await MainActor.run {
                    recentPRs = r.recentPRs
                    lastPR    = r.lastPR
                }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/war_room/summary"),
               let d = try? await APIService.shared.fetchWithCache(url: url, key: "war_room_summary"),
               let r = try? APIService.decoder.decode(WarRoomSummaryStats.self, from: d) {
                await MainActor.run { warRoomStats = r }
            }
        }
    }

    private func loadStatsWellnessIfNeeded(force: Bool = false) async {
        guard !isLoadingStatsWellness else { return }
        if hasLoadedStatsWellness && !force { return }

        isLoadingStatsWellness = true
        defer { isLoadingStatsWellness = false }

        guard let wellnessURL = URL(string: "\(APIService.shared.baseURL)/api/stats_wellness") else { return }
        var wellnessReq = URLRequest(url: wellnessURL)
        wellnessReq.timeoutInterval = 20

        if let cachedW = CacheService.shared.load(for: "stats_wellness"),
           let decodedW = try? APIService.decoder.decode(WellnessAPIResponse.self, from: cachedW) {
            applyWellness(decodedW)
            hasLoadedStatsWellness = true
        }

        if let (wData, _) = try? await URLSession.authed.data(for: wellnessReq),
           let decodedW = try? APIService.decoder.decode(WellnessAPIResponse.self, from: wData) {
            CacheService.shared.save(wData, for: "stats_wellness")
            applyWellness(decodedW)
            hasLoadedStatsWellness = true
        }
    }

    private func loadStatsHRVIfNeeded(force: Bool = false) async {
        guard !isLoadingStatsHRV else { return }
        if hasLoadedStatsHRV && !force { return }

        isLoadingStatsHRV = true
        defer { isLoadingStatsHRV = false }

        if let analysis = try? await APIService.shared.fetchHRVAnalysis() {
            hrvAnalysis = analysis
            hasLoadedStatsHRV = true
        }
    }
}
