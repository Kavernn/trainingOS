import SwiftUI
import Charts

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

func avgReps(_ reps: String) -> Double {
    let s = reps.trimmingCharacters(in: .whitespaces).lowercased()
    guard let first = s.first, first.isNumber || first == "." else { return 0 }
    if s.contains(",") {
        let nums = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return nums.isEmpty ? 0 : nums.reduce(0, +) / Double(nums.count)
    }
    if let r = s.range(of: "x") {
        if let _ = Double(s[s.startIndex..<r.lowerBound]),
           let rps = Double(s[r.upperBound...]) { return rps }
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
        let cal = Calendar.current
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

// MARK: - Main View
struct StatsView: View {
    @ObservedObject private var units = UnitSettings.shared
    @State var weights:          [String: WeightData]    = [:]
    @State var sessions:         [String: SessionEntry]  = [:]
    @State var hiitLog:          [HIITEntry]             = []
    @State var bodyWeight:       [BodyWeightEntry]       = []
    @State var recoveryLog:      [RecoveryEntry]         = []
    @State var nutritionTarget:  NutritionSettings?      = nil
    @State var nutritionDays:    [NutritionDay]          = []
    @State var acwr:             ACWRData?               = nil
    @State var muscleStats:      [String: MuscleStatEntry]  = [:]
    @State var muscleLandmarks:  [String: MuscleLandmark]   = [:]
    @State var inventoryTypes:   [String: String]            = [:]
    @State var isLoading    = true
    @State var fetchError   = false
    @State var selectedExercise: String? = nil
    @State var searchText   = ""
    @State var selectedTab: Int = 0
    @State var period: StatsPeriod = .month3

    // ── Stats Expansion State ────────────────────────────────────────
    @State var weeklyTonnage:      [WeeklyTonnageEntry]        = []
    @State var patternVolume:      PatternVolumeData?          = nil
    @State var complianceWeeks:    [ComplianceWeek]            = []
    @State var oneRmTrend:         [String: [OneRMPoint]]      = [:]
    @State var hiitCompletion:     [HIITCompletionEntry]       = []
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
    @State var pushPullRatio:      WeeklyReportPushPull?       = nil
    @State var sorenessThreshold:  SorenessThreshold?          = nil
    @State var hrvAnalysis:        HRVAnalysis?                = nil

    // ── New stats data ────────────────────────────────────────────────────
    @State var adherenceData:    AdherenceData?         = nil
    @State var seasonComparison: SeasonComparisonData?  = nil
    @State var warRoomStats:     WarRoomSummaryStats?   = nil
    @State var graveyardCount:   Int                    = 0
    @State var deloadStatus:     DeloadStatusData?      = nil
    @State var intensityData:    IntensityData?         = nil
    @State var ritualStats:      RitualStats?           = nil

    // ── Streak — source serveur unique (P1.2) ───────────────────────────────
    @State var streakData: StreakResponse? = nil
    // ── KPI cache — recomputed in recalcKPIs() called from applyStats() ──
    @State var cachedCurrentStreak: Int = 0
    @State var cachedBestStreak: Int = 0
    @State var cachedWeeklyVolume: Double = 0
    @State var cachedPersonalRecords: [(String, Double)] = []

    // ── KPIs ────────────────────────────────────────────────────────
    var totalSessions: Int { sessions.count }

    var sessionsThisMonth: Int {
        let key = DateFormatter.isoYearMonth.string(from: Date())
        return sessions.keys.filter { $0.hasPrefix(key) }.count
    }

    var avgRPE30: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let cutStr = DateFormatter.isoDate.string(from: cutoff)
        let rpes = sessions.compactMap { date, e -> Double? in
            date >= cutStr ? e.rpe : nil
        }
        return rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
    }

    var currentStreak: Int { streakData?.currentStreak ?? cachedCurrentStreak }
    var bestStreak: Int    { streakData?.bestStreak    ?? cachedBestStreak }
    var weeklyVolume: Double { cachedWeeklyVolume }

    var exercisesCount: Int { weights.filter { $0.value.history?.isEmpty == false }.count }

    var daysElapsedThisWeek: Int {
        let (mon, _) = weekBounds(weeksAgo: 0)
        guard let monDate = DateFormatter.isoDate.date(from: mon) else { return 7 }
        return max(1, Int(Date().timeIntervalSince(monDate) / 86400) + 1)
    }

    var avgSessionDuration: Double {
        let durations = filteredSessions.values.compactMap(\.durationMin).filter { $0 > 0 }
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }

    var volumeVelocityPct: Int? {
        guard lastWeekVolume > 0 else { return nil }
        let pct = (thisWeekVolume - lastWeekVolume) / lastWeekVolume * 100
        return Int(round(pct))
    }

    // ── Personal Records ─────────────────────────────────────────────
    var personalRecords: [(String, Double)] { cachedPersonalRecords }

    // ── Weekly charts ─────────────────────────────────────────────────
    var last8Weeks: [String] {
        let cal = Calendar(identifier: .iso8601)
        return (0..<8).reversed().map { i in
            (cal.date(byAdding: .weekOfYear, value: -i, to: Date()) ?? Date()).isoWeekKey
        }
    }

    var weeklyFrequency: [(String, Double)] {
        var counts: [String: Double] = [:]
        filteredSessions.keys.forEach { counts[isoWeekKey($0), default: 0] += 1 }
        return last8Weeks.map { ($0, counts[$0] ?? 0) }
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

    // ── Top 5 volume ─────────────────────────────────────────────────
    var top5Volume: [(String, Double)] {
        weights.compactMap { name, data -> (String, Double)? in
            let vol = data.history?.compactMap { e -> Double? in
                if let ev = e.exerciseVolume, ev > 0 { return ev }
                guard let w = e.weight, let r = e.reps else { return nil }
                return w * totalReps(r)
            }.reduce(0, +) ?? 0
            return vol > 0 ? (name, vol) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(5).map { $0 }
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

    var avgRPEPeriod: Double {
        let rpes = filteredSessions.compactMap { _, e -> Double? in e.rpe }
        return rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
    }

    // ── Week comparison ───────────────────────────────────────────────
    func weekBounds(weeksAgo: Int) -> (String, String) { Date().isoWeekBounds(weeksAgo: weeksAgo) }

    var thisWeekSessions:   Int {
        let (mon, sun) = weekBounds(weeksAgo: 0)
        return sessions.keys.filter { $0 >= mon && $0 <= sun }.count
    }
    var lastWeekSessions:   Int {
        let (mon, sun) = weekBounds(weeksAgo: 1)
        return sessions.keys.filter { $0 >= mon && $0 <= sun }.count
    }
    var thisWeekVolume: Double {
        let (mon, sun) = weekBounds(weeksAgo: 0)
        return weights.values.flatMap { $0.history ?? [] }.filter {
            guard let d = $0.date else { return false }; return d >= mon && d <= sun
        }.compactMap { e -> Double? in
            if let v = e.exerciseVolume, v > 0 { return UnitSettings.shared.display(v) }
            guard let w = e.weight, let r = e.reps else { return nil }
            return UnitSettings.shared.display(w * totalReps(r))
        }.reduce(0, +)
    }
    var lastWeekVolume: Double {
        let (mon, sun) = weekBounds(weeksAgo: 1)
        return weights.values.flatMap { $0.history ?? [] }.filter {
            guard let d = $0.date else { return false }; return d >= mon && d <= sun
        }.compactMap { e -> Double? in
            if let v = e.exerciseVolume, v > 0 { return UnitSettings.shared.display(v) }
            guard let w = e.weight, let r = e.reps else { return nil }
            return UnitSettings.shared.display(w * totalReps(r))
        }.reduce(0, +)
    }
    var thisWeekAvgRPE: Double {
        let (mon, sun) = weekBounds(weeksAgo: 0)
        let rpes = sessions.filter { $0.key >= mon && $0.key <= sun }.compactMap { $0.value.rpe }
        return rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
    }
    var lastWeekAvgRPE: Double {
        let (mon, sun) = weekBounds(weeksAgo: 1)
        let rpes = sessions.filter { $0.key >= mon && $0.key <= sun }.compactMap { $0.value.rpe }
        return rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
    }
    var thisWeekAvgDuration: Double {
        let (mon, sun) = weekBounds(weeksAgo: 0)
        let d = sessions.compactMap { date, e -> Double? in
            guard date >= mon, date <= sun else { return nil }
            guard let dm = e.durationMin, dm > 0 else { return nil }
            return dm
        }
        return d.isEmpty ? 0 : d.reduce(0, +) / Double(d.count)
    }
    var lastWeekAvgDuration: Double {
        let (mon, sun) = weekBounds(weeksAgo: 1)
        let d = sessions.compactMap { date, e -> Double? in
            guard date >= mon, date <= sun else { return nil }
            guard let dm = e.durationMin, dm > 0 else { return nil }
            return dm
        }
        return d.isEmpty ? 0 : d.reduce(0, +) / Double(d.count)
    }

    // ── Smart Insights ────────────────────────────────────────────────
    var smartInsights: [(icon: String, text: String, color: Color)] {
        var insights: [(String, String, Color)] = []
        let cal   = Calendar.current
        let w4ago = cal.date(byAdding: .weekOfYear, value: -4, to: Date()) ?? Date()
        let w8ago = cal.date(byAdding: .weekOfYear, value: -8, to: Date()) ?? Date()
        let last4 = sessions.filter {
            guard let d = DateFormatter.isoDate.date(from: $0.key) else { return false }
            return d >= w4ago
        }.count
        let prev4 = sessions.filter {
            guard let d = DateFormatter.isoDate.date(from: $0.key) else { return false }
            return d >= w8ago && d < w4ago
        }.count
        if prev4 > 0 {
            let pct = Int(round(Double(last4 - prev4) / Double(prev4) * 100))
            if pct >= 10 {
                insights.append(("arrow.up.circle.fill", "Fréquence +\(pct)% vs les 4 semaines précédentes. Tu accélères.", .green))
            } else if pct <= -15 {
                insights.append(("arrow.down.circle.fill", "Fréquence \(pct)% vs les 4 semaines précédentes. Le rythme faiblit.", .orange))
            }
        }
        if let a = acwr, ["caution", "danger"].contains(a.zone.code) {
            insights.append(("exclamationmark.triangle.fill", "ACWR \(String(format: "%.2f", a.ratio)) — tu surcharges ta base. La fatigue s'accumule.", .red))
        }
        if currentStreak > 0 && currentStreak < bestStreak && currentStreak >= bestStreak - 2 {
            let gap = bestStreak - currentStreak
            insights.append(("flame.fill", "Streak: \(currentStreak) jours — \(gap) de ton record. À portée.", .orange))
        } else if currentStreak >= 7 {
            insights.append(("flame.fill", "Streak: \(currentStreak) jours. Record: \(bestStreak). Reste en course.", .orange))
        }
        // Muscle gap: show the most overdue muscle if 7+ days without training
        let todayStr = DateFormatter.isoDate.string(from: Date())
        let todayDate = DateFormatter.isoDate.date(from: todayStr) ?? Date()
        let overdueList = muscleStats
            .compactMap { key, stat -> (String, Int)? in
                guard let last = DateFormatter.isoDate.date(from: stat.lastDate) else { return nil }
                let days = Int(todayDate.timeIntervalSince(last) / 86400)
                return days >= 7 ? (key, days) : nil
            }
            .sorted { $0.1 > $1.1 }
        if let overdue = overdueList.first {
            insights.append(("exclamationmark.circle.fill",
                             "\(overdue.0.capitalized) absent depuis \(overdue.1) jours. Le groupe régresse.",
                             .blue))
        }
        return Array(insights.prefix(4))
    }

    // ── Badges ────────────────────────────────────────────────────────
    struct Badge: Identifiable {
        let id: String
        let icon: String
        let title: String
        let desc: String
        let earned: Bool
        let color: Color
    }
    var earnedBadges: [Badge] {
        [
            Badge(id: "first_session",   icon: "🏋️", title: "Premier set",     desc: "1ère séance",             earned: totalSessions >= 1,       color: .orange),
            Badge(id: "sessions_10",     icon: "💪", title: "10 séances",       desc: "10 séances au total",     earned: totalSessions >= 10,      color: .orange),
            Badge(id: "sessions_30",     icon: "🏆", title: "30 séances",       desc: "30 séances au total",     earned: totalSessions >= 30,      color: .yellow),
            Badge(id: "sessions_100",    icon: "💎", title: "100 séances",      desc: "100 séances au total",    earned: totalSessions >= 100,     color: .cyan),
            Badge(id: "streak_7",        icon: "🔥", title: "Streak 7j",        desc: "7 jours consécutifs",     earned: bestStreak >= 7,          color: .red),
            Badge(id: "streak_14",       icon: "🔥", title: "Streak 14j",       desc: "14 jours consécutifs",    earned: bestStreak >= 14,         color: .red),
            Badge(id: "streak_30",       icon: "⚡", title: "Streak 30j",       desc: "30 jours consécutifs",    earned: bestStreak >= 30,         color: .purple),
            Badge(id: "exercises_10",    icon: "📚", title: "10 exercices",     desc: "10 exercices différents", earned: exercisesCount >= 10,     color: .blue),
            Badge(id: "perfect_month",   icon: "🌟", title: "Mois actif",       desc: "20 séances en 1 mois",   earned: sessionsThisMonth >= 20,  color: .yellow),
            Badge(id: "pr_5",            icon: "🥇", title: "5 records",        desc: "5 exercices avec PR",     earned: personalRecords.count >= 5, color: .green),
        ]
    }

    var tabAmbientColor: Color {
        switch selectedTab {
        case 1: return .orange
        case 2: return .green
        case 3: return .purple
        case 4: return .cyan
        default: return .blue
        }
    }

    // ── Body ─────────────────────────────────────────────────────────
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: tabAmbientColor)
                if isLoading {
                    AppLoadingView()
                } else if fetchError {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash").font(.system(size: 40)).foregroundColor(.gray)
                        Text("Impossible de charger les stats").foregroundColor(.gray)
                        Button("Réessayer") { Task { await loadData() } }
                            .foregroundColor(.orange).fontWeight(.semibold)
                    }
                } else if weights.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.bar").font(.system(size: 40)).foregroundColor(.gray.opacity(0.4))
                        Text("Tes stats se construisent séance après séance.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Text("Continue à logger.")
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                    .padding(.horizontal, 40)
                } else {
                    VStack(spacing: 0) {
                        StatsTabBar(selectedTab: $selectedTab)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                        if selectedTab < 5 {
                            PeriodPicker(selected: $period)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }

                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 16) {
                                if selectedTab == 0 { vueGlobaleTab }
                                else if selectedTab == 1 { performanceTab }
                                else if selectedTab == 2 { corpsTab }
                                else if selectedTab == 3 { nutritionTab }
                                else if selectedTab == 4 { exercicesTab }
                                else { bienetreTab }
                            }
                            .padding(.top, 8)
                            .padding(.bottom, contentBottomPadding)
                        }
                        .refreshable { await loadData() }
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: Binding(
                get: { selectedExercise.map { ExerciseWrapper(name: $0) } },
                set: { selectedExercise = $0?.name }
            )) { wrapper in
                ExerciseDetailView(name: wrapper.name, data: weights[wrapper.name])
            }
        }
        .task { await loadData() }
    }

    func formatK(_ v: Double) -> String { _formatK(v) }

    // Local decodable mirror of the stats response
    struct StatsAPIResponse: Codable {
        let weights:              [String: WeightData]
        let sessions:             [String: SessionEntry]
        let hiitLog:              [HIITEntry]
        let bodyWeight:           [BodyWeightEntry]
        let recoveryLog:          [RecoveryEntry]
        let nutritionTarget:      NutritionSettings?
        let nutritionDays:        [NutritionDay]
        let muscleStats:          [String: MuscleStatEntry]
        let inventoryTypes:       [String: String]?
        let muscleLandmarks:      [String: MuscleLandmark]?
        let weeklyTonnage:        [WeeklyTonnageEntry]?
        let patternVolume:        PatternVolumeData?
        let programmeCompliance:  [ComplianceWeek]?
        let oneRmTrend:           [String: [OneRMPoint]]?
        let hiitCompletion:       [HIITCompletionEntry]?
        let macrosByDayType:      MacrosByDayType?
        let proteinWeightRatio:   [ProteinWeightPoint]?

        enum CodingKeys: String, CodingKey {
            case weights, sessions
            case hiitLog            = "hiit_log"
            case bodyWeight         = "body_weight"
            case recoveryLog        = "recovery_log"
            case nutritionTarget    = "nutrition_target"
            case nutritionDays      = "nutrition_days"
            case muscleStats        = "muscle_stats"
            case inventoryTypes     = "inventory_types"
            case muscleLandmarks    = "muscle_landmarks"
            case weeklyTonnage      = "weekly_tonnage"
            case patternVolume      = "pattern_volume"
            case programmeCompliance = "programme_compliance"
            case oneRmTrend         = "one_rm_trend"
            case hiitCompletion     = "hiit_completion"
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

    func recalcKPIs() {
        let fmt = DateFormatter.isoDate

        // Streak now comes from server (P1.2); cachedCurrentStreak/bestStreak kept as fallback only

        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = TimeZone.current
        let daysSinceMonday = (iso.component(.weekday, from: Date()) + 5) % 7
        let mondayDate = iso.date(byAdding: .day, value: -daysSinceMonday, to: Date()) ?? Date()
        let mondayStr = fmt.string(from: mondayDate)
        // Unique source de vérité : exercise history, identique à weeklyVolumeChart.
        cachedWeeklyVolume = weights.values.flatMap { $0.history ?? [] }.compactMap { e -> Double? in
            guard let date = e.date, date >= mondayStr else { return nil }
            if let vol = e.exerciseVolume, vol > 0 { return UnitSettings.shared.display(vol) }
            guard let w = e.weight, let r = e.reps else { return nil }
            return UnitSettings.shared.display(w * totalReps(r))
        }.reduce(0, +)

        cachedPersonalRecords = weights.compactMap { name, data -> (String, Double)? in
            let isBodyweight = inventoryTypes[name] == "bodyweight"
            let best = data.history?.compactMap { e -> Double? in
                if isBodyweight { return (e.oneRM ?? 0) > 0 ? e.oneRM : nil }
                if let stored = e.oneRM, stored > 0 { return stored }
                if let sets = e.sets, !sets.isEmpty {
                    return sets.compactMap { s -> Double? in
                        let r = avgReps(s.reps)
                        guard r >= 1, r <= 15, s.weight > 0 else { return nil }
                        return r <= 10
                            ? s.weight * (1 + r / 30.0)
                            : s.weight * (36.0 / (37.0 - r))
                    }.max()
                }
                guard let w = e.weight, w > 0, let r = e.reps else { return nil }
                let avg = avgReps(r)
                guard avg >= 1, avg <= 15 else { return nil }
                return avg <= 10
                    ? w * (1 + avg / 30.0)
                    : w * (36.0 / (37.0 - avg))
            }.max()
            return best.map { (name, $0) }
        }
        .sorted { $0.1 > $1.1 }
        .prefix(10).map { $0 }
    }

    func applyStats(_ r: StatsAPIResponse) {
        weights            = r.weights
        sessions           = r.sessions
        hiitLog            = r.hiitLog
        bodyWeight         = r.bodyWeight
        recoveryLog        = r.recoveryLog
        nutritionTarget    = r.nutritionTarget
        nutritionDays      = r.nutritionDays
        muscleStats        = r.muscleStats
        inventoryTypes     = r.inventoryTypes ?? [:]
        muscleLandmarks    = r.muscleLandmarks ?? [:]
        weeklyTonnage      = r.weeklyTonnage ?? []
        patternVolume      = r.patternVolume
        complianceWeeks    = r.programmeCompliance ?? []
        oneRmTrend         = r.oneRmTrend ?? [:]
        hiitCompletion     = r.hiitCompletion ?? []
        macrosByDayType    = r.macrosByDayType
        proteinWeightRatio = r.proteinWeightRatio ?? []
        recalcKPIs()
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
        } else if weights.isEmpty {
            // No cache and network failed → show error state
            fetchError = true
        }
        // sequential — async let LIFO crash on iOS 26 beta
        acwr = try? await APIService.shared.fetchACWR()

        // Fetch wellness data (Bien-être tab)
        guard let wellnessURL = URL(string: "\(APIService.shared.baseURL)/api/stats_wellness") else { return }
        var wellnessReq = URLRequest(url: wellnessURL)
        wellnessReq.timeoutInterval = 20
        if let cachedW = CacheService.shared.load(for: "stats_wellness"),
           let decodedW = try? APIService.decoder.decode(WellnessAPIResponse.self, from: cachedW) {
            applyWellness(decodedW)
        }
        if let (wData, _) = try? await URLSession.authed.data(for: wellnessReq),
           let decodedW = try? APIService.decoder.decode(WellnessAPIResponse.self, from: wData) {
            CacheService.shared.save(wData, for: "stats_wellness")
            applyWellness(decodedW)
        }

        // Streak — source serveur unique (P1.2)
        streakData = try? await APIService.shared.fetchStreaks(date: AppState.shared.todayStr)

        isLoading = false
        // Schedule contextual notifications (inactivity + streak milestones)
        NotificationService.scheduleContextual(
            sessionDates: Array(sessions.keys),
            currentStreak: currentStreak
        )

        // Load push:pull ratio + soreness threshold
        Task {
            if let r = try? await APIService.shared.fetchWeeklyReport(),
               let ppr = r.pushPullRatio {
                await MainActor.run { pushPullRatio = ppr }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/soreness_threshold"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? APIService.decoder.decode(SorenessThreshold.self, from: d) {
                await MainActor.run { sorenessThreshold = r }
            }
        }
        Task {
            if let r = try? await APIService.shared.fetchHRVAnalysis() {
                await MainActor.run { hrvAnalysis = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/adherence"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? APIService.decoder.decode(AdherenceData.self, from: d) {
                await MainActor.run { adherenceData = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/seasons/comparison"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? APIService.decoder.decode(SeasonComparisonData.self, from: d) {
                await MainActor.run { seasonComparison = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/war_room/summary"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? APIService.decoder.decode(WarRoomSummaryStats.self, from: d) {
                await MainActor.run { warRoomStats = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/graveyard?count_only=true"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? APIService.decoder.decode(GraveyardCount.self, from: d) {
                await MainActor.run { graveyardCount = r.totalCount }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/deload_status"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? APIService.decoder.decode(DeloadStatusData.self, from: d) {
                await MainActor.run { deloadStatus = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/stats/intensity"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? APIService.decoder.decode(IntensityData.self, from: d) {
                await MainActor.run { intensityData = r }
            }
        }
        Task {
            if let rs = try? await APIService.shared.fetchRitualStats() {
                await MainActor.run { ritualStats = rs }
            }
        }
    }
}
