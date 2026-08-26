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

// MARK: - Main View
struct StatsView: View {
    @EnvironmentObject private var theme: AppTheme
    @ObservedObject var units = UnitSettings.shared
    @State var weights:          [String: WeightData]    = [:]
    @State var sessions:         [String: SessionEntry]  = [:]
    @State var hiitLog:          [HIITEntry]             = []
    @State var bodyWeight:       [BodyWeightEntry]       = []
    @State var recoveryLog:      [RecoveryEntry]         = []
    @State var nutritionTarget:  NutritionSettings?      = nil
    @State var nutritionDays:    [NutritionDay]          = []
    @State var acwr:             ACWRData?               = nil
    @State var activeDeload:      DeloadStatus?           = nil
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
    @State var sorenessThreshold:  SorenessThreshold?          = nil
    @State var hrvAnalysis:        HRVAnalysis?                = nil
    @State var forceAccessoryTimeline: [ForceAccessoryPoint]  = []
    @State var recentPRs:              [RecentPR]              = []

    // ── New stats data ────────────────────────────────────────────────────
    @State var adherenceData:    AdherenceData?         = nil
    @State var seasonComparison: SeasonComparisonData?  = nil
    @State var warRoomStats:     WarRoomSummaryStats?   = nil
@State var deloadStatus:     DeloadStatusData?      = nil
    @State var intensityData:    IntensityData?         = nil
    // ── Streak — source serveur unique (/api/stats/streaks) ─────────────────
    @State var streakData: StreakResponse? = nil
    // ── KPI cache — recomputed in recalcKPIs() called from applyStats() ──
    @State var cachedWeeklyVolume: Double = 0

    // ── KPIs ────────────────────────────────────────────────────────
    var totalSessions: Int {
        sessions.values.reduce(0) { $0 + ($1.sessionCount ?? 1) }
    }

    var sessionsThisMonth: Int {
        let key = DateFormatter.isoYearMonth.string(from: Date())
        return sessions.reduce(0) { acc, kv in
            kv.key.hasPrefix(key) ? acc + (kv.value.sessionCount ?? 1) : acc
        }
    }

    var avgRPE30: Double {
        let cutoff = Calendar.mtl.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let cutStr = DateFormatter.isoDate.string(from: cutoff)
        let rpes = sessions.compactMap { date, e -> Double? in
            date >= cutStr ? e.rpe : nil
        }
        return rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
    }

    var currentStreak: Int { streakData?.currentStreak ?? 0 }
    var bestStreak: Int    { streakData?.bestStreak    ?? 0 }
    var weeklyVolume: Double { cachedWeeklyVolume }

    var exercisesCount: Int { weights.filter { $0.value.history?.isEmpty == false }.count }

    var daysElapsedThisWeek: Int {
        let cal = Calendar.mtl
        let (mon, _) = weekBounds(weeksAgo: 0)
        guard let monDate = DateFormatter.isoDate.date(from: mon) else { return 7 }
        let today = cal.startOfDay(for: Date())
        let days  = cal.dateComponents([.day], from: monDate, to: today).day ?? 0
        return max(1, days + 1)
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

    // ── Weekly charts ─────────────────────────────────────────────────
    var last8Weeks: [String] {
        let cal = Calendar(identifier: .iso8601)
        return (0..<8).reversed().map { i in
            (cal.date(byAdding: .weekOfYear, value: -i, to: Date()) ?? Date()).isoWeekKey
        }
    }

    var weeklyFrequency: [(String, Double)] {
        var counts: [String: Double] = [:]
        for (date, entry) in filteredSessions {
            counts[isoWeekKey(date), default: 0] += Double(entry.sessionCount ?? 1)
        }
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

    // ── Week comparison ───────────────────────────────────────────────
    func weekBounds(weeksAgo: Int) -> (String, String) { Date().isoWeekBounds(weeksAgo: weeksAgo) }

    var thisWeekSessions:   Int {
        let (mon, sun) = weekBounds(weeksAgo: 0)
        return sessions.reduce(0) { acc, kv in
            (kv.key >= mon && kv.key <= sun) ? acc + (kv.value.sessionCount ?? 1) : acc
        }
    }
    var lastWeekSessions:   Int {
        let (mon, sun) = weekBounds(weeksAgo: 1)
        return sessions.reduce(0) { acc, kv in
            (kv.key >= mon && kv.key <= sun) ? acc + (kv.value.sessionCount ?? 1) : acc
        }
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

    // ── Recovery Profile ──────────────────────────────────────────────
    var recoveryProfile: (avgDays: Double, sampleSize: Int)? {
        let heavy = sessions.filter { ($0.value.rpe ?? 0) >= 7.5 }
        guard !heavy.isEmpty else { return nil }
        let sortedRec = filteredRecovery.sorted { ($0.date ?? "") < ($1.date ?? "") }
        var days: [Int] = []
        for (sessionDate, _) in heavy {
            let after = sortedRec.filter { ($0.date ?? "") > sessionDate }
            guard let recovered = after.first(where: { ($0.soreness ?? 10) < 3 }),
                  let rd = recovered.date,
                  let sd = DateFormatter.isoDate.date(from: sessionDate),
                  let recovDate = DateFormatter.isoDate.date(from: rd) else { continue }
            let d = Int(recovDate.timeIntervalSince(sd) / 86400)
            if d > 0 && d <= 10 { days.append(d) }
        }
        guard days.count >= 3 else { return nil }
        let avg = Double(days.reduce(0, +)) / Double(days.count)
        return (avg, days.count)
    }

    // ── Smart Insights ────────────────────────────────────────────────
    var smartInsights: [(icon: String, text: String, color: Color)] {
        var insights: [(String, String, Color)] = []
        let cal   = Calendar.mtl
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
                insights.append(("arrow.up.circle.fill", "Fréquence +\(pct)% vs les 4 semaines précédentes. Tu accélères.", .statusGreen))
            } else if pct <= -15 {
                insights.append(("arrow.down.circle.fill", "Fréquence \(pct)% vs les 4 semaines précédentes. Le rythme faiblit.", Color.forge))
            }
        }
        if let a = acwr, ["caution", "danger"].contains(a.zone.code) {
            insights.append(("exclamationmark.triangle.fill", "ACWR \(String(format: "%.2f", a.ratio)) — tu surcharges ta base. La fatigue s'accumule.", .statusRed))
        }
        if currentStreak > 0 && currentStreak < bestStreak && currentStreak >= bestStreak - 2 {
            let gap = bestStreak - currentStreak
            insights.append(("flame.fill", "Streak: \(currentStreak) jours — \(gap) de ton record. À portée.", Color.forge))
        } else if currentStreak >= 7 {
            insights.append(("flame.fill", "Streak: \(currentStreak) jours. Record: \(bestStreak). Reste en course.", Color.forge))
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
                             "\(overdue.0.localizedMuscleGroup) absent depuis \(overdue.1) jours. Le groupe régresse.",
                             .statusBlue))
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
            Badge(id: "first_session",   icon: "🏋️", title: "Premier set",     desc: "1ère séance",             earned: totalSessions >= 1,       color: Color.forge),
            Badge(id: "sessions_10",     icon: "💪", title: "10 séances",       desc: "10 séances au total",     earned: totalSessions >= 10,      color: Color.forge),
            Badge(id: "sessions_30",     icon: "🏆", title: "30 séances",       desc: "30 séances au total",     earned: totalSessions >= 30,      color: .statusYellow),
            Badge(id: "sessions_100",    icon: "💎", title: "100 séances",      desc: "100 séances au total",    earned: totalSessions >= 100,     color: .statusCyan),
            Badge(id: "streak_7",        icon: "🔥", title: "Streak 7j",        desc: "7 jours consécutifs",     earned: bestStreak >= 7,          color: .statusRed),
            Badge(id: "streak_14",       icon: "🔥", title: "Streak 14j",       desc: "14 jours consécutifs",    earned: bestStreak >= 14,         color: .statusRed),
            Badge(id: "streak_30",       icon: "⚡", title: "Streak 30j",       desc: "30 jours consécutifs",    earned: bestStreak >= 30,         color: .statusPurple),
            Badge(id: "exercises_10",    icon: "📚", title: "10 exercices",     desc: "10 exercices différents", earned: exercisesCount >= 10,     color: .statusBlue),
            Badge(id: "perfect_month",   icon: "🌟", title: "Mois actif",       desc: "20 séances en 1 mois",   earned: sessionsThisMonth >= 20,  color: .statusYellow),
            Badge(id: "pr_5",            icon: "🥇", title: "5 records",        desc: "5 exercices avec PR",     earned: recentPRs.count >= 5, color: .statusGreen),
        ]
    }

    var tabAmbientColor: Color {
        switch selectedTab {
        case 1: return .statusOrange
        case 2: return .statusRed
        case 3: return .statusGreen
        case 4: return .statusPurple
        case 5: return .statusCyan
        default: return .statusBlue
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
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                        if [2, 3, 4].contains(selectedTab) {
                            PeriodPicker(selected: $period)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }

                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 16) {
                                if selectedTab == 0 { vueGlobaleTab }
                                else if selectedTab == 1 { chargeVolumeTab }
                                else if selectedTab == 2 { intensiteTab }
                                else if selectedTab == 3 { corpsTab }
                                else if selectedTab == 4 { nutritionTab }
                                else if selectedTab == 5 { exercicesTab }
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

        let iso = Calendar.mtl
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

        activeDeload = try? await APIService.shared.fetchDeloadStatus()
        isLoading = false
        await APIService.shared.syncDeloadFlag()
        NotificationService.scheduleContextual(
            sessionDates: Array(sessions.keys),
            currentStreak: currentStreak
        )

        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/soreness_threshold"),
               let d = try? await APIService.shared.fetchWithCache(url: url, key: "soreness_threshold"),
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
               let d = try? await APIService.shared.fetchWithCache(url: url, key: "adherence"),
               let r = try? APIService.decoder.decode(AdherenceData.self, from: d) {
                await MainActor.run { adherenceData = r }
            }
        }
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
                await MainActor.run { recentPRs = r.recentPRs }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/war_room/summary"),
               let d = try? await APIService.shared.fetchWithCache(url: url, key: "war_room_summary"),
               let r = try? APIService.decoder.decode(WarRoomSummaryStats.self, from: d) {
                await MainActor.run { warRoomStats = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/deload_status"),
               let d = try? await APIService.shared.fetchWithCache(url: url, key: "deload_status"),
               let r = try? APIService.decoder.decode(DeloadStatusData.self, from: d) {
                await MainActor.run { deloadStatus = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/stats/intensity"),
               let d = try? await APIService.shared.fetchWithCache(url: url, key: "stats_intensity"),
               let r = try? APIService.decoder.decode(IntensityData.self, from: d) {
                await MainActor.run { intensityData = r }
            }
        }
    }
}
