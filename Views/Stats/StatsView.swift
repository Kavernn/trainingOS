import SwiftUI
import Charts

// MARK: - Helpers
private func totalReps(_ reps: String) -> Double {
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

private func avgReps(_ reps: String) -> Double {
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

private func isoWeekKey(_ dateStr: String) -> String {
    guard let d = DateFormatter.isoDate.date(from: dateStr) else { return "" }
    let epochDays = (Int(d.timeIntervalSince1970) + TimeZone.current.secondsFromGMT()) / 86400
    return "W\((epochDays + 3) / 7)"
}

private func weekLabel(_ key: String) -> String {
    guard key.hasPrefix("W"), let weekIdx = Int(key.dropFirst()) else { return key }
    let tz = TimeZone.current.secondsFromGMT()
    let d = Date(timeIntervalSince1970: TimeInterval(weekIdx * 7 * 86400 - 3 * 86400 - tz))
    let f = DateFormatter(); f.dateFormat = "d MMM"; f.locale = Locale(identifier: "fr_CA")
    return f.string(from: d)
}

private func _formatK(_ v: Double) -> String {
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
        let days: Int?
        switch self {
        case .month1: days = 30
        case .month3: days = 90
        case .month6: days = 180
        case .all:    days = nil
        }
        guard let d = days else { return nil }
        let date = Date(timeIntervalSince1970: Date().timeIntervalSince1970 - Double(d) * 86400.0)
        return DateFormatter.isoDate.string(from: date)
    }
}

// MARK: - Main View
struct StatsView: View {
    @State private var weights:          [String: WeightData]    = [:]
    @State private var sessions:         [String: SessionEntry]  = [:]
    @State private var hiitLog:          [HIITEntry]             = []
    @State private var bodyWeight:       [BodyWeightEntry]       = []
    @State private var recoveryLog:      [RecoveryEntry]         = []
    @State private var nutritionTarget:  NutritionSettings?      = nil
    @State private var nutritionDays:    [NutritionDay]          = []
    @State private var acwr:             ACWRData?               = nil
    @State private var muscleStats:      [String: MuscleStatEntry]  = [:]
    @State private var muscleLandmarks:  [String: MuscleLandmark]   = [:]
    @State private var inventoryTypes:   [String: String]            = [:]
    @State private var isLoading    = true
    @State private var fetchError   = false
    @State private var selectedExercise: String? = nil
    @State private var searchText   = ""
    @State private var selectedTab: Int = 0
    @State private var period: StatsPeriod = .month3

    // ── Stats Expansion State ────────────────────────────────────────
    @State private var weeklyTonnage:      [WeeklyTonnageEntry]        = []
    @State private var patternVolume:      PatternVolumeData?          = nil
    @State private var complianceWeeks:    [ComplianceWeek]            = []
    @State private var oneRmTrend:         [String: [OneRMPoint]]      = [:]
    @State private var hiitCompletion:     [HIITCompletionEntry]       = []
    @State private var macrosByDayType:    MacrosByDayType?            = nil
    @State private var proteinWeightRatio: [ProteinWeightPoint]        = []
    @State private var moodTrend:          [MoodTrendPoint]            = []
    @State private var pssHistory:         [PSSRecord]                 = []
    @State private var selfCareStreaks:    [SelfCareStreak]            = []
    @State private var selfCareCompliance: SelfCareComplianceData?     = nil
    @State private var sorenessScatter:    [ScatterPoint]              = []
    @State private var sleepScatter:       [ScatterPoint]              = []
    @State private var rpeProgression:     RPEProgressionData?         = nil
    @State private var rirByExercise:      [RIREntry]                  = []
    @State private var pushPullRatio:      WeeklyReportPushPull?       = nil
    @State private var sorenessThreshold:  SorenessThreshold?          = nil
    @State private var hrvBaseline:        HRVBaseline?                = nil

    // ── New stats data ────────────────────────────────────────────────────
    @State private var adherenceData:    AdherenceData?         = nil
    @State private var seasonComparison: SeasonComparisonData?  = nil
    @State private var warRoomStats:     WarRoomSummaryStats?   = nil
    @State private var graveyardCount:   Int                    = 0
    @State private var deloadStatus:     DeloadStatusData?      = nil
    @State private var intensityData:    IntensityData?         = nil

    // ── KPI cache — recomputed in recalcKPIs() called from applyStats() ──
    @State private var cachedCurrentStreak: Int = 0
    @State private var cachedBestStreak: Int = 0
    @State private var cachedWeeklyVolume: Double = 0
    @State private var cachedPersonalRecords: [(String, Double)] = []

    // ── KPIs ────────────────────────────────────────────────────────
    var totalSessions: Int { sessions.count }

    var sessionsThisMonth: Int {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"
        let key = fmt.string(from: Date())
        return sessions.keys.filter { $0.hasPrefix(key) }.count
    }

    var avgRPE30: Double {
        let cutoff = Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 30 * 86400.0)
        let cutStr = DateFormatter.isoDate.string(from: cutoff)
        let rpes = sessions.compactMap { date, e -> Double? in
            date >= cutStr ? e.rpe : nil
        }
        return rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
    }

    var currentStreak: Int { cachedCurrentStreak }
    var bestStreak: Int    { cachedBestStreak }
    var weeklyVolume: Double { cachedWeeklyVolume }

    var exercisesCount: Int { weights.filter { $0.value.history?.isEmpty == false }.count }

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
    private var last8Weeks: [String] {
        let tz = TimeZone.current.secondsFromGMT()
        let todayDays = (Int(Date().timeIntervalSince1970) + tz) / 86400
        return (0..<8).reversed().map { i in "W\((todayDays - i * 7 + 3) / 7)" }
    }

    var weeklyFrequency: [(String, Double)] {
        var counts: [String: Double] = [:]
        sessions.keys.forEach { counts[isoWeekKey($0), default: 0] += 1 }
        return last8Weeks.map { ($0, counts[$0] ?? 0) }
    }

    var weeklyVolumeChart: [(String, Double)] {
        var vols: [String: Double] = [:]
        for (_, data) in weights {
            for e in data.history ?? [] {
                guard let date = e.date else { continue }
                let vol: Double
                if let ev = e.exerciseVolume, ev > 0 {
                    vol = UnitSettings.shared.display(ev)
                } else {
                    guard let w = e.weight, let r = e.reps else { continue }
                    vol = UnitSettings.shared.display(w * totalReps(r))
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
    private func weekBounds(weeksAgo: Int) -> (String, String) {
        let tz = TimeZone.current.secondsFromGMT()
        let todayDays = (Int(Date().timeIntervalSince1970) + tz) / 86400
        let weekday = ((todayDays + 4) % 7) + 1
        let daysSinceMonday = (weekday + 5) % 7
        let mondayDays = todayDays - daysSinceMonday - weeksAgo * 7
        let monday = Date(timeIntervalSince1970: TimeInterval(mondayDays * 86400 - tz))
        let sunday = Date(timeIntervalSince1970: TimeInterval((mondayDays + 6) * 86400 - tz))
        return (DateFormatter.isoDate.string(from: monday), DateFormatter.isoDate.string(from: sunday))
    }

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
            if let v = e.exerciseVolume, v > 0 { return v }
            guard let w = e.weight, let r = e.reps else { return nil }
            return w * totalReps(r)
        }.reduce(0, +)
    }
    var lastWeekVolume: Double {
        let (mon, sun) = weekBounds(weeksAgo: 1)
        return weights.values.flatMap { $0.history ?? [] }.filter {
            guard let d = $0.date else { return false }; return d >= mon && d <= sun
        }.compactMap { e -> Double? in
            if let v = e.exerciseVolume, v > 0 { return v }
            guard let w = e.weight, let r = e.reps else { return nil }
            return w * totalReps(r)
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
        let now = Date().timeIntervalSince1970
        let last4 = sessions.filter {
            guard let d = DateFormatter.isoDate.date(from: $0.key) else { return false }
            return now - d.timeIntervalSince1970 < 28 * 86400
        }.count
        let prev4 = sessions.filter {
            guard let d = DateFormatter.isoDate.date(from: $0.key) else { return false }
            let delta = now - d.timeIntervalSince1970
            return delta >= 28 * 86400 && delta < 56 * 86400
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

    private var tabAmbientColor: Color {
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
                            .padding(.vertical, 8)
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

    // ── Tab content ───────────────────────────────────────────────────
    @ViewBuilder private var vueGlobaleTab: some View {

        // 1. Smart Insights (moved inside tab)
        if !smartInsights.isEmpty {
            SmartInsightsBanner(insights: smartInsights)
                .padding(.horizontal, 16)
        }

        // 2. Activity Rings — Score de constance
        if let adh = adherenceData {
            AdherenceRingsCard(data: adh)
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.02)
        }

        // 3. Cette semaine vs semaine précédente
        WeekComparisonCard(
            thisWeekSessions: thisWeekSessions, lastWeekSessions: lastWeekSessions,
            thisWeekVolume: thisWeekVolume,     lastWeekVolume: lastWeekVolume,
            thisWeekAvgRPE: thisWeekAvgRPE,     lastWeekAvgRPE: lastWeekAvgRPE
        )
        .padding(.horizontal, 16)

        // 4. KPI Grid
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            KPICard(value: "\(filteredSessions.count)", label: "Séances (\(period.rawValue))", color: .orange)
            KPICard(value: "\(sessionsThisMonth)", label: "Mois actuel", color: .blue)
            KPICard(
                value: currentStreak > 0 ? "\(currentStreak)🔥" : "0",
                label: "Streak",
                color: .red,
                subtitle: "jours cons."
            )
            KPICard(
                value: avgRPEPeriod > 0 ? String(format: "%.1f", avgRPEPeriod) : "—",
                label: "RPE moy.",
                color: .purple
            )
            KPICard(value: weeklyVolume > 0 ? formatK(weeklyVolume) : "—", label: "Vol. sem.", color: .green)
            KPICard(
                value: thisWeekAvgDuration > 0 ? "\(Int(thisWeekAvgDuration))min" : "—",
                label: "Durée moy.",
                color: .cyan,
                subtitle: {
                    guard thisWeekAvgDuration > 0, lastWeekAvgDuration > 0 else { return nil }
                    let d = Int(thisWeekAvgDuration - lastWeekAvgDuration)
                    if d == 0 { return nil }
                    return d > 0 ? "+\(d) vs sem. préc." : "\(d) vs sem. préc."
                }()
            )
        }
        .padding(.horizontal, 16)
        .appearAnimation(delay: 0.05)

        // 5. Heatmap 90 jours
        SessionHeatmapView(
            sessions: sessions,
            hiitDates: Set(hiitLog.compactMap(\.date).map { String($0.prefix(10)) }),
            bestStreak: bestStreak
        )
        .padding(.horizontal, 16)

        // 6. Season Comparison
        if let comp = seasonComparison {
            SeasonComparisonCard(data: comp)
                .padding(.horizontal, 16)
                .appearAnimation(delay: 0.08)
        }

        // 7. Marqueurs de transformation
        TransformationMarkersCard(tombstoneCount: graveyardCount, warRoomStats: warRoomStats)
            .padding(.horizontal, 16)
            .appearAnimation(delay: 0.10)

        // 8. Badges
        if !earnedBadges.isEmpty {
            BadgesView(badges: earnedBadges)
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }

    @ViewBuilder private var performanceTab: some View {

        // 1. Charge — ACWR
        if let acwrData = acwr {
            ACWRCardView(data: acwrData)
                .padding(.horizontal, 16)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 18)).foregroundColor(.gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACWR non disponible")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.gray)
                    Text("Logge au moins 4 semaines de séances avec RPE et durée")
                        .font(.system(size: 11)).foregroundColor(.gray.opacity(0.6))
                }
                Spacer()
            }
            .padding(14).background(Color.appCard).cornerRadius(14)
            .padding(.horizontal, 16)
        }

        // 2. Tonnage hebdo + fréquence
        HStack(spacing: 12) {
            SimpleBarChart(
                title: "FRÉQUENCE / SEM",
                data: weeklyFrequency.map { (weekLabel($0.0), $0.1) },
                color: .orange,
                unit: "séances"
            )
            SimpleBarChart(
                title: "VOLUME / SEM",
                data: weeklyVolumeChart.map { (weekLabel($0.0), UnitSettings.shared.display($0.1)) },
                color: .blue,
                unit: UnitSettings.shared.label
            )
        }
        .padding(.horizontal, 16)

        // 3. Volume / muscle / semaine (hard sets vs landmarks)
        if !muscleLandmarks.isEmpty {
            VolumeLandmarksCard(landmarks: muscleLandmarks)
                .padding(.horizontal, 16)
        }

        // 4. Intensité relative (%1RM)
        if let intensity = intensityData, intensity.avgPct1rm != nil {
            IntensityCard(data: intensity)
                .padding(.horizontal, 16)
        }

        // 5. Équilibre Push/Pull/Legs
        if let pv = patternVolume {
            PatternVolumeView(data: pv)
                .padding(.horizontal, 16)
        }

        // 6. Programme compliance
        if complianceWeeks.count >= 2 {
            ComplianceProgrammeView(weeks: complianceWeeks)
                .padding(.horizontal, 16)
        }

        // 7. Jours depuis deload
        if let dl = deloadStatus {
            DeloadStatusCard(data: dl)
                .padding(.horizontal, 16)
        }

        // 8. RPE + intensité
        if filteredSessions.count >= 5 {
            RPEDistributionView(sessions: filteredSessions)
                .padding(.horizontal, 16)
        }

        if let rp = rpeProgression {
            RPEProgressionView(data: rp)
                .padding(.horizontal, 16)
        }

        if !rirByExercise.isEmpty {
            RIRByExerciseView(entries: rirByExercise)
                .padding(.horizontal, 16)
        }

        let sessionsWithEnergy = filteredSessions.compactMap { d, e -> (String, Int)? in
            e.energyPre.map { (d, $0) }
        }.sorted { $0.0 < $1.0 }.suffix(20).map { $0 }
        if sessionsWithEnergy.count >= 3 {
            EnergyTrendView(data: sessionsWithEnergy)
                .padding(.horizontal, 16)
        }

        if !oneRmTrend.isEmpty {
            OneRMTrendView(trend: oneRmTrend)
                .padding(.horizontal, 16)
        }

        if rpeHistory.count >= 3 {
            RPEChartView(data: rpeHistory)
                .padding(.horizontal, 16)
        } else {
            EmptyChartPlaceholder(message: "Logge au moins 3 séances avec RPE pour voir la tendance")
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }

    @ViewBuilder private var corpsTab: some View {
        let filteredBW = filteredBodyWeight
        let bwWithFat  = filteredBW.filter { $0.bodyFat != nil && ($0.bodyFat ?? 0) > 0 }

        // 1. Body Recomposition Tracker (flagship — remplace les 2 courbes séparées)
        if bwWithFat.count >= 3 {
            BodyRecompView(entries: Array(filteredBW.reversed()))
                .padding(.horizontal, 16)
        } else if filteredBW.count >= 2 {
            WeightChartView(entries: Array(filteredBW.prefix(20).reversed()))
                .padding(.horizontal, 16)
            EmptyChartPlaceholder(message: "Logge ton % de masse grasse pour activer le Body Recomp Tracker")
                .padding(.horizontal, 16)
        } else {
            EmptyChartPlaceholder(message: "Logge au moins 2 pesées pour voir la courbe de poids")
                .padding(.horizontal, 16)
        }

        // 2. Recovery composite
        if filteredRecovery.count >= 5 {
            RecoveryCompositeScoreView(log: Array(filteredRecovery.prefix(30).reversed()))
                .padding(.horizontal, 16)
        }

        // 3. Mensurations
        if filteredBW.filter({ $0.waistCm != nil || $0.armsCm != nil }).count >= 2 {
            MeasurementsTrendView(entries: Array(filteredBW.prefix(20).reversed()))
                .padding(.horizontal, 16)
        }

        // 4. Soreness threshold
        if let st = sorenessThreshold, st.thresholdVol != nil {
            SorenessThresholdCard(data: st)
                .padding(.horizontal, 16)
        }

        // 5. HIIT
        if !hiitLog.isEmpty {
            HIITStatsSection(log: hiitLog)
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }

    @ViewBuilder private var nutritionTab: some View {
        let fn = filteredNutrition
        if fn.count >= 3, let target = nutritionTarget {
            NutritionComplianceChart(days: fn, target: target)
                .padding(.horizontal, 16)
            ProteinComplianceView(days: fn, target: target)
                .padding(.horizontal, 16)
            if target.glucides != nil || target.lipides != nil {
                MacrosBreakdownView(days: fn, target: target)
                    .padding(.horizontal, 16)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 40)).foregroundColor(.gray)
                Text("Données nutritionnelles insuffisantes.")
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }

        if proteinWeightRatio.count >= 5 {
            ProteinWeightRatioView(data: proteinWeightRatio)
                .padding(.horizontal, 16)
        }

        if let mdt = macrosByDayType, mdt.nTraining >= 3, mdt.nRest >= 3 {
            MacrosDayTypeView(data: mdt)
                .padding(.horizontal, 16)
        }

        // Nutrition vs Performance correlation
        let fn2 = filteredNutrition
        if fn2.count >= 30, !weeklyTonnage.isEmpty {
            NutritionVsPerfView(nutritionDays: fn2, weeklyTonnage: weeklyTonnage, target: nutritionTarget)
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }

    @ViewBuilder private var bienetreTab: some View {

        // 1. HRV en tête (actionnable immédiatement)
        if let hrv = hrvBaseline, hrv.baseline != nil {
            HRVBaselineCard(data: hrv)
                .padding(.horizontal, 16)
        }

        // 2. Corrélation sommeil → performance (enrichie)
        if sleepScatter.count >= 12 {
            SleepPerformanceInsightView(scatter: sleepScatter)
                .padding(.horizontal, 16)
        } else if sleepScatter.count >= 5 {
            ScatterPlotView(
                data: sleepScatter,
                xLabel: "Qualité sommeil (J-1)",
                yLabel: "Volume séance (J)",
                title: "SOMMEIL → PERFORMANCE",
                color: .blue
            )
            .padding(.horizontal, 16)
        }

        // 3. Wellness trend (3 sparklines)
        if filteredRecovery.count >= 7 {
            WellnessTrendView(recovery: Array(filteredRecovery.prefix(30).reversed()), pssHistory: pssHistory)
                .padding(.horizontal, 16)
        }

        // 4. Mood & PSS
        if !moodTrend.isEmpty {
            MoodStressTrendView(data: moodTrend, pssHistory: pssHistory)
                .padding(.horizontal, 16)
        } else {
            EmptyChartPlaceholder(message: "Logge ton humeur quotidiennement pour voir la tendance")
                .padding(.horizontal, 16)
        }

        if !pssHistory.isEmpty {
            PSSHistoryView(records: pssHistory)
                .padding(.horizontal, 16)
        }

        // 5. Meilleur jour de la semaine
        if !sessions.isEmpty {
            BestDayOfWeekView(sessions: sessions, weights: weights)
                .padding(.horizontal, 16)
        }

        // 6. Corrélation stress → cravings (War Room, conditionnel)
        if warRoomStats?.warStartDate != nil {
            StressCravingsInsightView(pssHistory: pssHistory, warRoomStats: warRoomStats)
                .padding(.horizontal, 16)
        }

        // 7. Volume → douleurs musculaires
        if sorenessScatter.count >= 5 {
            ScatterPlotView(
                data: sorenessScatter,
                xLabel: "Volume J-1 (lbs)",
                yLabel: "Soreness J (1–10)",
                title: "VOLUME → DOULEURS MUSCULAIRES",
                color: .orange
            )
            .padding(.horizontal, 16)
        }

        if !selfCareStreaks.isEmpty {
            SelfCareStreaksView(streaks: selfCareStreaks, compliance: selfCareCompliance)
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }

    @ViewBuilder private var exercicesTab: some View {

        // 1. Progression force 6 mois (flagship)
        if !oneRmTrend.isEmpty {
            StrengthProgressionCard(trend: oneRmTrend, weights: weights)
                .padding(.horizontal, 16)
        }

        // 2. PRs actuels
        if !personalRecords.isEmpty {
            PersonalRecordsView(records: personalRecords)
                .padding(.horizontal, 16)
        }

        // 3. Top 5 fréquence
        if !weights.isEmpty {
            Top5FrequencyView(weights: weights)
                .padding(.horizontal, 16)
        }

        // 4. 1RM trend par exercice
        if !oneRmTrend.isEmpty {
            OneRMTrendView(trend: oneRmTrend)
                .padding(.horizontal, 16)
        }

        // 5. Exercices — recherche et poids actuels
        VStack(alignment: .leading, spacing: 8) {
            Text("POIDS ACTUELS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                .padding(.horizontal, 16)
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("Rechercher un exercice...", text: $searchText)
                    .foregroundColor(.white).tint(.orange)
            }
            .padding(12)
            .background(Color.appCard).cornerRadius(12)
            .padding(.horizontal, 16)

            ForEach(exercisesWithHistory, id: \.0) { name, data in
                ExerciseStatRow(name: name, data: data)
                    .padding(.horizontal, 16)
                    .onTapGesture { selectedExercise = name }
            }
        }

        Spacer(minLength: 32)
    }

    private func formatK(_ v: Double) -> String { _formatK(v) }

    // Local decodable mirror of the stats response
    private struct StatsAPIResponse: Codable {
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

    private struct WellnessAPIResponse: Codable {
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

    private func recalcKPIs() {
        let fmt = DateFormatter.isoDate
        let base = Date().timeIntervalSince1970
        var count = 0
        for i in 0..<365 {
            let key = fmt.string(from: Date(timeIntervalSince1970: base - Double(i) * 86400.0))
            if sessions[key] != nil { count += 1 }
            else if i == 0 { }
            else { break }
        }
        cachedCurrentStreak = count

        let sorted = sessions.keys.compactMap { fmt.date(from: $0) }.sorted()
        if sorted.isEmpty {
            cachedBestStreak = 0
        } else {
            var best = 1; var cur = 1
            for i in 1..<sorted.count {
                let diff = Int(round((sorted[i].timeIntervalSince1970 - sorted[i-1].timeIntervalSince1970) / 86400.0))
                if diff == 1 { cur += 1; best = max(best, cur) } else { cur = 1 }
            }
            cachedBestStreak = best
        }

        let epochDays = (Int(base) + TimeZone.current.secondsFromGMT()) / 86400
        let weekday = ((epochDays + 4) % 7) + 1
        let daysSinceMonday = (weekday + 5) % 7
        let mondayStr = fmt.string(from: Date(timeIntervalSince1970: base - Double(daysSinceMonday) * 86400.0))
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

    private func applyStats(_ r: StatsAPIResponse) {
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

    private func applyWellness(_ r: WellnessAPIResponse) {
        moodTrend          = r.moodTrend
        pssHistory         = r.pssHistory
        selfCareStreaks    = r.selfCareStreaks
        selfCareCompliance = r.selfCareCompliance
        sorenessScatter    = r.sorenessVolumeScatter
        sleepScatter       = r.sleepVolumeScatter
        rpeProgression     = r.rpeProgression
        rirByExercise      = r.rirByExercise
    }

    private func loadData() async {
        fetchError = false

        // 1. Show cached data immediately (no spinner if cache exists)
        if let cached = CacheService.shared.load(for: "stats_data"),
           let decoded = try? JSONDecoder().decode(StatsAPIResponse.self, from: cached) {
            applyStats(decoded)
            isLoading = false
        }

        // 2. Fetch fresh data — parallel with ACWR
        var req = URLRequest(url: URL(string: "\(APIService.shared.baseURL)/api/stats_data")!)
        req.timeoutInterval = 15
        if let (data, _) = try? await URLSession.authed.data(for: req),
           let decoded = try? JSONDecoder().decode(StatsAPIResponse.self, from: data) {
            CacheService.shared.save(data, for: "stats_data")
            applyStats(decoded)
        } else if weights.isEmpty {
            // No cache and network failed → show error state
            fetchError = true
        }
        // sequential — async let LIFO crash on iOS 26 beta
        acwr = try? await APIService.shared.fetchACWR()

        // Fetch wellness data (Bien-être tab)
        var wellnessReq = URLRequest(url: URL(string: "\(APIService.shared.baseURL)/api/stats_wellness")!)
        wellnessReq.timeoutInterval = 20
        if let cachedW = CacheService.shared.load(for: "stats_wellness"),
           let decodedW = try? JSONDecoder().decode(WellnessAPIResponse.self, from: cachedW) {
            applyWellness(decodedW)
        }
        if let (wData, _) = try? await URLSession.authed.data(for: wellnessReq),
           let decodedW = try? JSONDecoder().decode(WellnessAPIResponse.self, from: wData) {
            CacheService.shared.save(wData, for: "stats_wellness")
            applyWellness(decodedW)
        }

        isLoading = false
        // Schedule contextual notifications (inactivity + streak milestones)
        NotificationService.scheduleContextual(
            sessionDates: Array(sessions.keys),
            currentStreak: currentStreak
        )

        // Load push:pull ratio + soreness threshold
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/weekly_report"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? JSONDecoder().decode(WeeklyReport.self, from: d),
               let ppr = r.pushPullRatio {
                await MainActor.run { pushPullRatio = ppr }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/soreness_threshold"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? JSONDecoder().decode(SorenessThreshold.self, from: d) {
                await MainActor.run { sorenessThreshold = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/hrv_baseline"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? JSONDecoder().decode(HRVBaseline.self, from: d) {
                await MainActor.run { hrvBaseline = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/adherence"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? JSONDecoder().decode(AdherenceData.self, from: d) {
                await MainActor.run { adherenceData = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/seasons/comparison"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? JSONDecoder().decode(SeasonComparisonData.self, from: d) {
                await MainActor.run { seasonComparison = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/war_room/summary"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? JSONDecoder().decode(WarRoomSummaryStats.self, from: d) {
                await MainActor.run { warRoomStats = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/graveyard"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? JSONDecoder().decode(GraveyardResponse.self, from: d) {
                await MainActor.run { graveyardCount = r.tombstones.count }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/deload_status"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? JSONDecoder().decode(DeloadStatusData.self, from: d) {
                await MainActor.run { deloadStatus = r }
            }
        }
        Task {
            if let url = URL(string: "\(APIService.shared.baseURL)/api/stats/intensity"),
               let (d, _) = try? await URLSession.authed.data(from: url),
               let r = try? JSONDecoder().decode(IntensityData.self, from: d) {
                await MainActor.run { intensityData = r }
            }
        }
    }
}

// MARK: - ACWR Card
struct ACWRCardView: View {
    let data: ACWRData

    private var zoneColor: Color {
        switch data.zone.code {
        case "optimal":  return .green
        case "caution":  return .orange
        case "danger":   return .red
        case "under":    return .blue
        default:         return .gray
        }
    }

    private var isLowConfidence: Bool { data.confidence == "low" }
    private var isEstimate: Bool { data.confidence == "moderate" }

    private var relativeLoadText: String {
        guard data.chronicLoad > 0 else { return "" }
        let pct = Int(round((data.ratio - 1.0) * 100))
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(pct)% vs ta moyenne 28j"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ACWR — CHARGE AIGUË/CHRONIQUE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if isEstimate {
                    Text("ESTIMATION")
                        .font(.system(size: 8, weight: .bold)).tracking(1)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                }
            }

            if isLowConfidence {
                // Pas assez d'historique — ne pas afficher le ratio
                VStack(alignment: .leading, spacing: 6) {
                    Text("Données insuffisantes")
                        .font(.system(size: 20, weight: .bold)).foregroundColor(.gray)
                    Text("\(data.daysOfData) / 28 jours de données")
                        .font(.system(size: 12)).foregroundColor(.gray.opacity(0.6))
                    ProgressView(value: Double(data.daysOfData), total: 28)
                        .tint(.gray).frame(maxWidth: 160)
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    // Ratio
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "%.2f", data.ratio))
                            .font(.system(size: 40, weight: .black))
                            .foregroundColor(zoneColor)
                        Text(data.zone.label)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(zoneColor.opacity(0.2))
                            .foregroundColor(zoneColor)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    if !relativeLoadText.isEmpty {
                        Text(relativeLoadText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(zoneColor)
                    }
                }
            }

            // Recommendation
            if !data.zone.recommendation.isEmpty {
                Text(data.zone.recommendation)
                    .font(.system(size: 12)).foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Sparkline — seulement si données suffisantes
            if !isLowConfidence, data.trend.count > 1 {
                ACWRSparkline(trend: data.trend)
            }
        }
        .padding(16).glassCard(color: isLowConfidence ? .gray : zoneColor, intensity: 0.05).cornerRadius(14)
    }
}

private struct ACWRSparkline: View {
    let trend: [ACWRWeek]

    private let thresholds: [(Double, Color)] = [
        (1.5, .red), (1.3, .orange), (0.8, .blue)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TENDANCE 8 SEMAINES")
                .font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let ratios = trend.map(\.ratio)
                let maxVal = max((ratios.max() ?? 1.6), 1.6)
                let step = w / CGFloat(trend.count - 1)

                ZStack(alignment: .topLeading) {
                    // Optimal zone band (0.8–1.3)
                    let bandTop  = h * (1 - CGFloat(1.3 / maxVal))
                    let bandBot  = h * (1 - CGFloat(0.8 / maxVal))
                    Rectangle()
                        .fill(Color.green.opacity(0.07))
                        .frame(width: w, height: max(0, bandBot - bandTop))
                        .offset(x: 0, y: bandTop)

                    // Threshold lines
                    ForEach(thresholds, id: \.0) { level, color in
                        let y = h * (1 - CGFloat(level / maxVal))
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
                            .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }

                    // Ratio line
                    if trend.count > 1 {
                        Path { path in
                            for (i, week) in trend.enumerated() {
                                let x = CGFloat(i) * step
                                let y = week.ratio > 0
                                    ? h * (1 - CGFloat(week.ratio / maxVal))
                                    : h
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else if week.ratio > 0 { path.addLine(to: CGPoint(x: x, y: y)) }
                                else { path.move(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        // Dots coloured by zone
                        ForEach(Array(trend.enumerated()), id: \.0) { i, week in
                            if week.ratio > 0 {
                                let x = CGFloat(i) * step
                                let y = h * (1 - CGFloat(week.ratio / maxVal))
                                let dot = dotColor(week.ratio)
                                Circle().fill(dot).frame(width: 5, height: 5).position(x: x, y: y)
                            }
                        }
                    }
                }
            }
            .frame(height: 70)

            // X-axis labels (first, mid, last)
            HStack {
                Text(trend.first?.week ?? "").font(.system(size: 9)).foregroundColor(.gray.opacity(0.6))
                Spacer()
                Text(trend[trend.count / 2].week).font(.system(size: 9)).foregroundColor(.gray.opacity(0.6))
                Spacer()
                Text(trend.last?.week ?? "").font(.system(size: 9)).foregroundColor(.gray.opacity(0.6))
            }
        }
    }

    private func dotColor(_ ratio: Double) -> Color {
        if ratio == 0   { return .gray }
        if ratio < 0.8  { return .blue }
        if ratio <= 1.3 { return .green }
        if ratio <= 1.5 { return .orange }
        return .red
    }
}

// MARK: - Heatmap (muscu=orange, HIIT=blue, both=purple)
struct SessionHeatmapView: View {
    let sessions: [String: SessionEntry]
    var hiitDates: Set<String> = []
    var bestStreak: Int = 0
    private let days = 90

    enum CellType { case none, muscu, hiit, both }

    private var cells: [(String, CellType)] {
        let base = Date().timeIntervalSince1970
        return (0..<days).reversed().map { offset in
            let date = Date(timeIntervalSince1970: base - Double(offset) * 86400.0)
            let key = DateFormatter.isoDate.string(from: date)
            let hasMuscu = sessions[key] != nil
            let hasHIIT  = hiitDates.contains(key)
            let type: CellType = hasMuscu && hasHIIT ? .both : hasMuscu ? .muscu : hasHIIT ? .hiit : .none
            return (key, type)
        }
    }

    var activeDays: Int { cells.filter { $0.1 != .none }.count }

    private func cellColor(_ t: CellType) -> Color {
        switch t {
        case .none:  return Color(hex: "191926")
        case .muscu: return .orange
        case .hiit:  return .blue
        case .both:  return .purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("90 DERNIERS JOURS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if bestStreak > 1 {
                    Text("Best \(bestStreak)🔥")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.orange)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 15), spacing: 3) {
                ForEach(cells, id: \.0) { _, type in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cellColor(type))
                        .frame(height: 16)
                }
            }
            HStack(spacing: 12) {
                Text("\(activeDays) séances").font(.system(size: 11)).foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text("Muscu").font(.system(size: 10)).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                    Text("HIIT").font(.system(size: 10)).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.purple).frame(width: 8, height: 8)
                    Text("Les 2").font(.system(size: 10)).foregroundColor(.gray)
                }
            }
        }
        .padding(16).glassCard().cornerRadius(14)
    }
}

//// MARK: - Badges View

struct BadgesView: View {
    let badges: [StatsView.Badge]
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "medal.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 13, weight: .bold))
                Text("Badges")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                let count = badges.filter(\.earned).count
                Text("\(count)/\(badges.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
            }

            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(badges) { badge in
                    VStack(spacing: 4) {
                        Text(badge.icon)
                            .font(.system(size: 24))
                            .opacity(badge.earned ? 1.0 : 0.25)
                        Text(badge.title)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(badge.earned ? badge.color : .gray)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(badge.earned ? badge.color.opacity(0.1) : Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(badge.earned ? badge.color.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1))
                    .cornerRadius(10)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.15), lineWidth: 1))
        .cornerRadius(14)
    }
}

// MARK: - Week Comparison Card
struct WeekComparisonCard: View {
    let thisWeekSessions: Int;  let lastWeekSessions: Int
    let thisWeekVolume: Double; let lastWeekVolume: Double
    let thisWeekAvgRPE: Double; let lastWeekAvgRPE: Double
    @ObservedObject private var units = UnitSettings.shared

    private func delta(_ a: Double, _ b: Double) -> (String, Color) {
        let d = a - b
        if abs(d) < 0.01 { return ("=", .gray) }
        let s = d > 0 ? "+\(String(format: "%.0f", abs(d)))" : "-\(String(format: "%.0f", abs(d)))"
        return (s, d > 0 ? .green : .red)
    }
    private func deltaInt(_ a: Int, _ b: Int) -> (String, Color) {
        let d = a - b
        if d == 0 { return ("=", .gray) }
        return (d > 0 ? "+\(d)" : "\(d)", d > 0 ? .green : .red)
    }

    private var weekVerdict: (text: String, color: Color) {
        let volumeUp = thisWeekVolume >= lastWeekVolume * 0.98
        let sessionsUp = thisWeekSessions >= lastWeekSessions
        let hasData = lastWeekVolume > 0 || lastWeekSessions > 0

        guard hasData else { return ("Pas encore assez de données.", .gray) }

        if volumeUp && sessionsUp {
            return ("Volume en hausse, sessions stables ou en hausse. Tu montes.", .green)
        } else if !volumeUp && !sessionsUp {
            return ("Volume en baisse, sessions en baisse. Le relâchement s'installe.", .red)
        } else if volumeUp && !sessionsUp {
            return ("Moins de séances, plus de volume par séance. Tu condenses.", .orange)
        } else {
            return ("Plus de séances, volume en baisse. L'intensité recule.", .orange)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOI VS TOI — SEMAINE PASSÉE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    Text("").font(.system(size: 11)).frame(height: 18)
                    Text("Séances").font(.system(size: 12)).foregroundColor(.gray)
                    Text("Volume").font(.system(size: 12)).foregroundColor(.gray)
                    Text("RPE moy.").font(.system(size: 12)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // This week
                VStack(alignment: .center, spacing: 10) {
                    Text("Cette sem.").font(.system(size: 10, weight: .bold)).foregroundColor(.orange)
                    Text("\(thisWeekSessions)").font(.system(size: 14, weight: .black)).foregroundColor(.white)
                    Text(thisWeekVolume > 0 ? _formatK(thisWeekVolume) : "—").font(.system(size: 14, weight: .black)).foregroundColor(.white)
                    Text(thisWeekAvgRPE > 0 ? String(format: "%.1f", thisWeekAvgRPE) : "—").font(.system(size: 14, weight: .black)).foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)

                // Delta
                VStack(alignment: .center, spacing: 10) {
                    Text("").font(.system(size: 10)).frame(height: 18)
                    let ds = deltaInt(thisWeekSessions, lastWeekSessions)
                    Text(ds.0).font(.system(size: 12, weight: .bold)).foregroundColor(ds.1)
                    let dv = delta(thisWeekVolume, lastWeekVolume)
                    Text(dv.0).font(.system(size: 12, weight: .bold)).foregroundColor(dv.1)
                    let dr = delta(thisWeekAvgRPE, lastWeekAvgRPE)
                    Text(dr.0).font(.system(size: 12, weight: .bold)).foregroundColor(dr.1)
                }
                .frame(width: 40)

                // Last week
                VStack(alignment: .center, spacing: 10) {
                    Text("Sem. passée").font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
                    Text("\(lastWeekSessions)").font(.system(size: 14, weight: .bold)).foregroundColor(.gray)
                    Text(lastWeekVolume > 0 ? _formatK(lastWeekVolume) : "—").font(.system(size: 14, weight: .bold)).foregroundColor(.gray)
                    Text(lastWeekAvgRPE > 0 ? String(format: "%.1f", lastWeekAvgRPE) : "—").font(.system(size: 14, weight: .bold)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
            }

            // Verdict
            let verdict = weekVerdict
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            Text(verdict.text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(verdict.color)
        }
        .padding(16).glassCard().cornerRadius(14)
    }
}

// MARK: - Personal Records
struct PersonalRecordsView: View {
    let records: [(String, Double)]
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEILLEURS 1RM ESTIMÉS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            let maxORM = records.map(\.1).max() ?? 1
            VStack(spacing: 6) {
                ForEach(Array(records.enumerated()), id: \.0) { i, record in
                    HStack(spacing: 10) {
                        Text("\(i + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                            .frame(width: 16)
                        Text(record.0)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(hex: "191926")).frame(height: 6)
                            Capsule()
                                .fill(prColor(i))
                                .frame(width: 80 * (record.1 / maxORM), height: 6)
                        }
                        .frame(width: 80, height: 6)
                        Text(units.format(record.1, decimals: 0))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(prColor(i))
                            .frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16).glassCard().cornerRadius(14)
    }

    private func prColor(_ rank: Int) -> Color {
        switch rank {
        case 0: return .yellow
        case 1: return .gray
        case 2: return Color(hex: "cd7f32")
        default: return .orange
        }
    }
}

// MARK: - Simple Bar Chart
struct SimpleBarChart: View {
    let title: String
    let data: [(String, Double)]
    let color: Color
    let unit: String

    var maxVal: Double { data.map(\.1).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .bold)).tracking(2).foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(data.enumerated()), id: \.0) { i, item in
                        let pct = maxVal > 0 ? item.1 / maxVal : 0
                        let isLast = i == data.count - 1
                        VStack(spacing: 0) {
                            Spacer()
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isLast ? color : color.opacity(0.4))
                                .frame(height: max(CGFloat(pct) * 60, 2))
                        }
                        .frame(maxWidth: .infinity, maxHeight: 60)
                    }
                }
                .frame(height: 60)

                // Show label for first and last
                HStack {
                    Text(data.first?.0 ?? "")
                        .font(.system(size: 8)).foregroundColor(.gray)
                    Spacer()
                    if let last = data.last, last.1 > 0 {
                        Text(formatVal(last.1))
                            .font(.system(size: 9, weight: .bold)).foregroundColor(color)
                    }
                }
            }
        }
        .padding(12).glassCard(color: color, intensity: 0.04).cornerRadius(12)
        .frame(maxWidth: .infinity)
    }

    private func formatVal(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.0fK", v / 1000) }
        return String(format: "%.0f", v)
    }
}

// MARK: - Top 5 Volume
struct Top5VolumeView: View {
    let data: [(String, Double)]

    var maxVol: Double { data.map(\.1).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP 5 — VOLUME CUMULÉ")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            GeometryReader { outer in
                VStack(spacing: 8) {
                    ForEach(Array(data.enumerated()), id: \.0) { i, item in
                        HStack(spacing: 10) {
                            Text(item.0)
                                .font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                                .lineLimit(1).frame(width: 120, alignment: .leading)
                            let barW = outer.size.width - 184
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(hex: "191926")).frame(height: 8)
                                Capsule()
                                    .fill(barColor(i))
                                    .frame(width: barW * (item.1 / maxVol), height: 8)
                            }
                            .frame(height: 8)
                            Text(formatK(item.1))
                                .font(.system(size: 11, weight: .bold)).foregroundColor(barColor(i))
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(height: CGFloat(data.count) * (8 + 8) - 8)
        }
        .padding(16).glassCard().cornerRadius(14)
    }

    private func barColor(_ i: Int) -> Color {
        [Color.orange, .blue, .purple, .green, .red][i % 5]
    }

    private func formatK(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", v/1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", v/1_000) }
        return String(format: "%.0f", v)
    }
}

// MARK: - HIIT Stats
struct HIITStatsSection: View {
    let log: [HIITEntry]

    var rpeHistory: [(Int, Double)] {
        log.enumerated().compactMap { i, e in e.rpe.map { (i, $0) } }.suffix(15).map { $0 }
    }

    var avgRPE: Double {
        let r = log.compactMap(\.rpe)
        return r.isEmpty ? 0 : r.reduce(0, +) / Double(r.count)
    }

    var avgRounds: Double {
        let r = log.compactMap(\.rounds).map(Double.init)
        return r.isEmpty ? 0 : r.reduce(0, +) / Double(r.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HIIT — \(log.count) SESSIONS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            HStack(spacing: 12) {
                KPICard(value: "\(log.count)", label: "Sessions", color: .red)
                KPICard(value: avgRPE > 0 ? String(format: "%.1f", avgRPE) : "—", label: "RPE moy.", color: .orange)
                KPICard(value: avgRounds > 0 ? String(format: "%.0f", avgRounds) : "—", label: "Rounds moy.", color: .purple)
            }

            if rpeHistory.count >= 3 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RPE — DERNIÈRES SESSIONS")
                        .font(.system(size: 9, weight: .bold)).tracking(2).foregroundColor(.gray)
                    GeometryReader { geo in
                        let step = geo.size.width / CGFloat(rpeHistory.count - 1)
                        Path { path in
                            for (i, (_, rpe)) in rpeHistory.enumerated() {
                                let x = CGFloat(i) * step
                                let y = geo.size.height * (1 - rpe / 10.0)
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        ForEach(rpeHistory, id: \.0) { i, rpe in
                            let x = CGFloat(i) * step
                            let y = geo.size.height * (1 - rpe / 10.0)
                            Circle().fill(Color.red).frame(width: 5, height: 5)
                                .position(x: x, y: y)
                        }
                    }
                    .frame(height: 60)
                }
                .padding(12).background(Color.appCard).cornerRadius(10)
            }
        }
        .padding(16).glassCard(color: .red, intensity: 0.04).cornerRadius(14)
    }
}

// MARK: - RPE Chart
struct RPEChartView: View {
    let data: [(String, Double)]
    var maxY: Double { 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ÉVOLUTION RPE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                ZStack {
                    ForEach([5.0, 7.0, 10.0], id: \.self) { level in
                        let y = geo.size.height * (1 - level / maxY)
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        Text("\(Int(level))")
                            .font(.system(size: 9)).foregroundColor(.gray.opacity(0.5))
                            .position(x: 12, y: y)
                    }
                    if data.count > 1 {
                        let step = geo.size.width / CGFloat(data.count - 1)
                        Path { path in
                            for (i, (_, rpe)) in data.enumerated() {
                                let x = CGFloat(i) * step
                                let y = geo.size.height * (1 - rpe / maxY)
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        ForEach(Array(data.enumerated()), id: \.0) { i, entry in
                            let x = CGFloat(i) * step
                            let y = geo.size.height * (1 - entry.1 / maxY)
                            Circle().fill(rpeColor(entry.1)).frame(width: 6, height: 6).position(x: x, y: y)
                        }
                    }
                }
            }
            .frame(height: 80)

            if let last = data.last {
                HStack {
                    Text("Dernière:").font(.system(size: 11)).foregroundColor(.gray)
                    Text("RPE \(last.1, specifier: "%.1f")")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(rpeColor(last.1))
                }
            }
        }
        .padding(16).background(Color.appCard).cornerRadius(14)
    }

    private func rpeColor(_ rpe: Double) -> Color { RPEHelper.color(for: rpe) }
}

// MARK: - KPI Card
struct KPICard: View {
    let value: String
    let label: String
    let color: Color
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .black)).foregroundColor(color)
                .contentTransition(.numericText()).minimumScaleFactor(0.6).lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .medium)).tracking(1).foregroundColor(.gray)
                .lineLimit(1)
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 8)).foregroundColor(.gray.opacity(0.55))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassCard(color: color, intensity: 0.05).cornerRadius(12)
    }
}

// MARK: - Exercise Stat Row
struct ExerciseStatRow: View {
    let name: String
    @ObservedObject private var units = UnitSettings.shared
    let data: WeightData

    private var isBodyweight: Bool { (data.currentWeight ?? 0) == 0 }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                if let reps = data.lastReps, !reps.isEmpty {
                    Text(reps).font(.system(size: 12)).foregroundColor(.gray)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let w = data.currentWeight, w > 0 {
                    Text(units.format(w))
                        .font(.system(size: 16, weight: .black)).foregroundColor(.orange)
                    if let history = data.history, history.count > 1,
                       let first = history.last?.weight, let last = history.first?.weight,
                       first > 0, last > 0 {
                        let diff = last - first
                        Text(diff >= 0 ? "+\(diff, specifier: "%.1f")" : "\(diff, specifier: "%.1f")")
                            .font(.system(size: 11)).foregroundColor(diff >= 0 ? .green : .red)
                    }
                } else {
                    Text("Poids corps")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.cyan.opacity(0.7))
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.gray)
        }
        .padding(14).glassCard().cornerRadius(12)
    }
}

// MARK: - Exercise Detail
struct ExerciseWrapper: Identifiable { let id = UUID(); let name: String }

struct ExerciseDetailView: View {
    let name: String
    let data: WeightData?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 4) {
                            if let w = data?.currentWeight {
                                Text(units.format(w))
                                    .font(.system(size: 48, weight: .black)).foregroundColor(.orange)
                            }
                            if let reps = data?.lastReps {
                                Text("Dernières reps: \(reps)").font(.system(size: 14)).foregroundColor(.gray)
                            }
                        }
                        .padding()

                        if let history = data?.history, history.count >= 2 {
                            StrengthCurveChart(history: history)
                                .padding(.horizontal, 16)
                        }

                        if let history = data?.history, !history.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("HISTORIQUE")
                                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                                ForEach(history, id: \.date) { entry in
                                    HStack {
                                        Text(entry.date ?? "—").font(.system(size: 13)).foregroundColor(.gray)
                                        Spacer()
                                        Text(units.format(entry.weight ?? 0))
                                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                                        Text(entry.reps ?? "").font(.system(size: 13)).foregroundColor(.gray)
                                        if let note = entry.note, !note.isEmpty {
                                            Text(note).font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(note.hasPrefix("+") ? .green : .yellow)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    Divider().background(Color.white.opacity(0.06))
                                }
                            }
                            .padding(16).background(Color.appCard).cornerRadius(14)
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .navigationTitle(name).navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let w = data?.currentWeight, let reps = data?.lastReps {
                        let oneRMStr = data?.history?.first?.oneRM.map { String(format: "→ 1RM estimé %.1f\(units.label)", $0) } ?? ""
                        ShareLink(item: "🏆 Record personnel — TrainingOS\n\(name) : \(units.format(w)) × \(reps) \(oneRMStr)") {
                            Image(systemName: "square.and.arrow.up").foregroundColor(.orange)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Measurements Trend
struct MeasurementsTrendView: View {
    let entries: [BodyWeightEntry]

    private let metrics: [(String, KeyPath<BodyWeightEntry, Double?>, Color)] = [
        ("Taille", \.waistCm, .purple),
        ("Bras",   \.armsCm,  .blue),
        ("Cuisses",\.thighsCm,.orange),
        ("Hanches",\.hipsCm,  .pink),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MENSURATIONS (cm)")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            ForEach(metrics, id: \.0) { label, kp, color in
                let vals = entries.compactMap { e -> (String, Double)? in
                    guard let v = e[keyPath: kp] else { return nil }
                    return (e.date, v)
                }
                if vals.count >= 2 {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle().fill(color).frame(width: 6, height: 6)
                            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.white)
                            Spacer()
                            let diff = vals.last!.1 - vals.first!.1
                            Text(String(format: "%+.1f cm", diff))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(diff <= 0 ? .green : .red)
                            Text(String(format: "%.0f", vals.last!.1))
                                .font(.system(size: 13, weight: .black)).foregroundColor(color)
                        }
                        MiniLineChart(values: vals.map(\.1), color: color)
                            .frame(height: 28)
                    }
                }
            }
        }
        .padding(16).glassCard(color: .purple, intensity: 0.04).cornerRadius(14)
    }
}

struct MiniLineChart: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let mn = values.min() ?? 0
            let mx = max(values.max() ?? 1, mn + 0.01)
            let step = geo.size.width / CGFloat(values.count - 1)
            Path { path in
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * step
                    let y = geo.size.height * (1 - CGFloat((v - mn) / (mx - mn)))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Body Fat Chart
struct BodyFatChartView: View {
    let entries: [BodyWeightEntry]
    @ObservedObject private var units = UnitSettings.shared

    private var data: [(String, Double)] {
        entries.compactMap { e -> (String, Double)? in
            guard let bf = e.bodyFat, bf > 0 else { return nil }
            return (e.date, bf)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("% MASSE GRASSE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let last = data.last {
                    Text(String(format: "%.1f%%", last.1))
                        .font(.system(size: 18, weight: .black)).foregroundColor(.purple)
                }
            }
            if data.count >= 2 {
                let vals = data.map(\.1)
                let mn = (vals.min() ?? 0) - 1
                let mx = (vals.max() ?? 30) + 1
                GeometryReader { geo in
                    let step = geo.size.width / CGFloat(data.count - 1)
                    ZStack {
                        Path { path in
                            for (i, (_, v)) in data.enumerated() {
                                let x = CGFloat(i) * step
                                let y = geo.size.height * (1 - CGFloat((v - mn) / (mx - mn)))
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        ForEach(Array(data.enumerated()), id: \.0) { i, entry in
                            let x = CGFloat(i) * step
                            let y = geo.size.height * (1 - CGFloat((entry.1 - mn) / (mx - mn)))
                            Circle().fill(Color.purple).frame(width: 5, height: 5).position(x: x, y: y)
                        }
                    }
                }
                .frame(height: 60)

                if let first = data.first, let last = data.last {
                    let diff = last.1 - first.1
                    HStack {
                        Text("Début: \(String(format: "%.1f%%", first.1))").font(.system(size: 10)).foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%+.1f%%", diff))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(diff <= 0 ? .green : .red)
                    }
                }
            } else {
                Text("Données insuffisantes — continue à logger.").font(.system(size: 12)).foregroundColor(.gray)
            }
        }
        .padding(16).glassCard(color: .purple, intensity: 0.04).cornerRadius(14)
    }
}

// MARK: - Training Load Chart
struct TrainingLoadChart: View {
    let sessions: [String: SessionEntry]
    let last8Weeks: [String]

    var weeklyLoad: [(String, Double)] {
        var loads: [String: Double] = [:]
        for (date, s) in sessions {
            guard let rpe = s.rpe, let dur = s.durationMin else { continue }
            let key = isoWeekKey(date)
            loads[key, default: 0] += rpe * dur
        }
        return last8Weeks.map { ($0, loads[$0] ?? 0) }
    }

    var body: some View {
        SimpleBarChart(
            title: "CHARGE D'ENTRAÎNEMENT / SEM (RPE × min)",
            data: weeklyLoad.map { (weekLabel($0.0), $0.1) },
            color: .orange,
            unit: "u.a."
        )
    }
}

// MARK: - Energy Trend
struct EnergyTrendView: View {
    let data: [(String, Int)]   // (date, energy 1-5)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ÉNERGIE PRÉ-SÉANCE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                let step = data.count > 1 ? geo.size.width / CGFloat(data.count - 1) : geo.size.width
                ZStack {
                    // Grid lines at 1,3,5
                    ForEach([1, 3, 5], id: \.self) { level in
                        let y = geo.size.height * (1 - CGFloat(level - 1) / 4.0)
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        Text("\(level)").font(.system(size: 8)).foregroundColor(.gray.opacity(0.4))
                            .position(x: 10, y: y)
                    }
                    if data.count > 1 {
                        Path { path in
                            for (i, (_, e)) in data.enumerated() {
                                let x = CGFloat(i) * step
                                let y = geo.size.height * (1 - CGFloat(e - 1) / 4.0)
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        ForEach(Array(data.enumerated()), id: \.0) { i, entry in
                            let x = CGFloat(i) * step
                            let y = geo.size.height * (1 - CGFloat(entry.1 - 1) / 4.0)
                            Circle().fill(energyColor(entry.1)).frame(width: 7, height: 7).position(x: x, y: y)
                        }
                    }
                }
            }
            .frame(height: 70)

            HStack {
                Text("1 = Épuisé").font(.system(size: 9)).foregroundColor(.red)
                Spacer()
                if let last = data.last {
                    Text("Dernière: \(energyLabel(last.1))")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(energyColor(last.1))
                }
                Spacer()
                Text("5 = Excellent").font(.system(size: 9)).foregroundColor(.green)
            }
        }
        .padding(16).background(Color.appCard).cornerRadius(14)
    }

    private func energyColor(_ v: Int) -> Color { v >= 4 ? .green : v == 3 ? .yellow : .red }
    private func energyLabel(_ v: Int) -> String {
        ["", "Épuisé 😴", "Fatigué 😕", "Normal 😐", "En forme 💪", "Excellent ⚡"][v]
    }
}

// MARK: - Recovery Score Chart
struct RecoveryScoreChart: View {
    let log: [RecoveryEntry]

    private func score(_ e: RecoveryEntry) -> Double {
        var total = 0.0; var count = 0.0
        if let sq = e.sleepQuality { total += sq; count += 1 }
        if let s  = e.soreness     { total += (10 - s); count += 1 }
        if let h  = e.sleepHours   { total += min(h / 8.0 * 10, 10); count += 1 }
        // HRV : plus haut = meilleure récup. Normalise 0-100ms → 0-10
        if let hrv = e.hrv, hrv > 0 { total += min(hrv / 80.0 * 10, 10); count += 1 }
        // FC repos : plus bas = meilleure récup. Normalise 40-85bpm → 0-10
        if let hr = e.restingHr, hr > 0 { total += max(0, min((85 - hr) / 45.0 * 10, 10)); count += 1 }
        return count > 0 ? total / count : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCORE DE RÉCUPÉRATION")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            let scores = log.map { ($0.date ?? "", score($0)) }
            let maxS: Double = 10

            GeometryReader { geo in
                let step = scores.count > 1 ? geo.size.width / CGFloat(scores.count - 1) : geo.size.width
                ZStack {
                    ForEach([5.0, 7.5, 10.0], id: \.self) { level in
                        let y = geo.size.height * (1 - level / maxS)
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    }
                    if scores.count > 1 {
                        Path { path in
                            for (i, (_, s)) in scores.enumerated() {
                                let x = CGFloat(i) * step
                                let y = geo.size.height * (1 - CGFloat(s / maxS))
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        ForEach(Array(scores.enumerated()), id: \.0) { i, entry in
                            let x = CGFloat(i) * step
                            let y = geo.size.height * (1 - CGFloat(entry.1 / maxS))
                            let col: Color = entry.1 >= 7 ? .green : entry.1 >= 4 ? .yellow : .red
                            Circle().fill(col).frame(width: 6, height: 6).position(x: x, y: y)
                        }
                    }
                }
            }
            .frame(height: 70)

            if let last = log.last {
                let s = score(last)
                HStack {
                    Text("Dernière:").font(.system(size: 11)).foregroundColor(.gray)
                    Text(String(format: "%.1f / 10", s))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(s >= 7 ? .green : s >= 4 ? .yellow : .red)
                }
            }
            if let last = log.last {
                HStack(spacing: 16) {
                    if let hrv = last.hrv, hrv > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform.path.ecg").font(.system(size: 10)).foregroundColor(.cyan)
                            Text("HRV \(Int(hrv))ms").font(.system(size: 10, weight: .semibold)).foregroundColor(.cyan)
                        }
                    }
                    if let hr = last.restingHr, hr > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill").font(.system(size: 10)).foregroundColor(.red)
                            Text("FC repos \(Int(hr)) bpm").font(.system(size: 10, weight: .semibold)).foregroundColor(.red)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(16).glassCard(color: .blue, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - Nutrition Compliance
struct NutritionComplianceChart: View {
    let days: [NutritionDay]
    let target: NutritionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMPLIANCE CALORIES (\(days.count) JOURS)")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            let targetCal = target.calories ?? 2000
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days.suffix(30)) { day in
                    let cal = day.calories ?? 0
                    let pct = targetCal > 0 ? min(cal / targetCal, 1.4) : 0
                    let color: Color = pct >= 0.9 && pct <= 1.1 ? .green : pct < 0.9 ? .orange : .red
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", cal))
                            .font(.system(size: 7)).foregroundColor(color.opacity(0.8))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.7))
                            .frame(height: max(CGFloat(pct) * 60, 2))
                        Text(shortDate(day.date ?? ""))
                            .font(.system(size: 7)).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 80, alignment: .bottom)
                }
            }
            .frame(height: 80)
            .overlay(
                GeometryReader { geo in
                    Path { p in
                        let y = geo.size.height * (1 - 1.0 / 1.4)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            )

            HStack(spacing: 12) {
                Label("Objectif: \(Int(targetCal)) kcal", systemImage: "target")
                    .font(.system(size: 10)).foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("±10%").font(.system(size: 9)).foregroundColor(.gray)
                }
            }
        }
        .padding(16).background(Color.appCard).cornerRadius(14)
    }

    private func shortDate(_ d: String) -> String {
        let parts = d.split(separator: "-")
        guard parts.count == 3 else { return d }
        return "\(parts[2])/\(parts[1])"
    }
}

// MARK: - RPE Distribution
struct RPEDistributionView: View {
    let sessions: [String: SessionEntry]

    var distribution: [(String, Int)] {
        let buckets = ["1-2", "3-4", "5-6", "7-8", "9-10"]
        var counts = [0, 0, 0, 0, 0]
        for s in sessions.values {
            guard let rpe = s.rpe else { continue }
            let idx = min(Int((rpe - 1) / 2), 4)
            counts[idx] += 1
        }
        return zip(buckets, counts).map { $0 }
    }

    var total: Int { distribution.map(\.1).reduce(0, +) }

    private let colors: [Color] = [.green, .teal, .yellow, .orange, .red]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DISTRIBUTION RPE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(distribution.enumerated()), id: \.0) { i, item in
                    let pct = total > 0 ? Double(item.1) / Double(total) : 0
                    VStack(spacing: 4) {
                        Text("\(item.1)").font(.system(size: 10, weight: .bold)).foregroundColor(colors[i])
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colors[i])
                            .frame(height: max(CGFloat(pct) * 80, 2))
                        Text(item.0).font(.system(size: 9)).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 100, alignment: .bottom)
                }
            }
            .frame(height: 100)
        }
        .padding(16).background(Color.appCard).cornerRadius(14)
    }
}

// MARK: - Strength Curve Chart (1RM over time)
struct StrengthCurveChart: View {
    let history: [WeightHistoryEntry]
    @ObservedObject private var units = UnitSettings.shared
    @State private var metric: ChartMetric = .oneRM

    enum ChartMetric: String, CaseIterable {
        case oneRM = "1RM estimé"
        case weight = "Poids"
    }

    private struct DataPoint: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let isPR: Bool
    }

    private var points: [DataPoint] {
        let entries = history.compactMap { e -> (Date, Double)? in
            guard let dateStr = e.date,
                  let date = DateFormatter.isoDate.date(from: dateStr) else { return nil }
            let value: Double
            switch metric {
            case .oneRM:
                if let stored = e.oneRM, stored > 0 { value = stored }
                else if let w = e.weight, w > 0, let r = e.reps {
                    let avg = avgReps(r)
                    guard avg > 0 else { return nil }
                    value = w * (1 + avg / 30.0)
                } else { return nil }
            case .weight:
                guard let w = e.weight, w > 0 else { return nil }
                value = w
            }
            return (date, units.display(value))
        }.sorted { $0.0 < $1.0 }

        guard !entries.isEmpty else { return [] }
        let prValue = entries.map(\.1).max() ?? 0
        return entries.map { date, val in
            DataPoint(id: date.description, date: date, value: val, isPR: val >= prValue)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("COURBE DE FORCE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Picker("", selection: $metric) {
                    ForEach(ChartMetric.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            if points.count < 2 {
                Text("Données insuffisantes — continue à logger.")
                    .font(.system(size: 13)).foregroundColor(.gray)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            } else {
                Chart {
                    ForEach(points) { p in
                        LineMark(
                            x: .value("Date", p.date),
                            y: .value(metric.rawValue, p.value)
                        )
                        .foregroundStyle(Color.orange)
                        .interpolationMethod(.monotone)

                        PointMark(
                            x: .value("Date", p.date),
                            y: .value(metric.rawValue, p.value)
                        )
                        .foregroundStyle(p.isPR ? Color.orange : Color.orange.opacity(0.4))
                        .symbolSize(p.isPR ? 80 : 30)
                    }

                    if let pr = points.last(where: \.isPR) {
                        RuleMark(y: .value("PR", pr.value))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.orange.opacity(0.3))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("PR \(units.format(pr.value))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                            .foregroundStyle(Color.gray)
                    }
                }
                .chartYAxis {
                    AxisMarks { val in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                        AxisValueLabel()
                            .foregroundStyle(Color.gray)
                    }
                }
                .chartPlotStyle { plot in
                    plot.background(Color.clear)
                }
                .frame(height: 180)
            }
        }
        .padding(16).background(Color.appCard).cornerRadius(14)
    }
}

// MARK: - Muscle Breakdown
struct MuscleBreakdownView: View {
    let stats: [String: MuscleStatEntry]
    @ObservedObject private var units = UnitSettings.shared

    private var sorted: [(String, MuscleStatEntry)] {
        stats.sorted { $0.value.volume > $1.value.volume }
    }

    private var maxVolume: Double {
        sorted.first?.1.volume ?? 1
    }

    private func formatVol(_ lbs: Double) -> String {
        let v = units.display(lbs)
        if v >= 1_000 { return String(format: "%.0fK \(units.label)", v / 1_000) }
        return String(format: "%.0f \(units.label)", v)
    }

    private func daysSince(_ dateStr: String) -> Int? {
        guard let d = DateFormatter.isoDate.date(from: dateStr) else { return nil }
        return Int(Date().timeIntervalSince(d) / 86400)
    }

    private func freshnessColor(_ days: Int?) -> Color {
        guard let d = days else { return .gray }
        if d <= 2 { return .orange }
        if d <= 5 { return .green }
        return .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "MUSCLES TRAVAILLÉS", icon: "figure.strengthtraining.traditional")

            GeometryReader { outer in
                VStack(spacing: 8) {
                    ForEach(sorted, id: \.0) { muscle, entry in
                        HStack(spacing: 10) {
                            Text(muscle.capitalized)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 110, alignment: .leading)

                            let barW = outer.size.width - 168
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.06))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(freshnessColor(daysSince(entry.lastDate)).opacity(0.7))
                                    .frame(width: barW * CGFloat(entry.volume / maxVolume))
                            }
                            .frame(height: 8)

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(formatVol(entry.volume))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))
                                if let days = daysSince(entry.lastDate) {
                                    Text(days == 0 ? "auj." : "\(days)j")
                                        .font(.system(size: 9))
                                        .foregroundColor(freshnessColor(days))
                                }
                            }
                            .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(height: CGFloat(sorted.count) * (8 + 8) - 8)

            HStack(spacing: 16) {
                legendDot(.orange, "≤ 2j")
                legendDot(.green,  "3–5j")
                legendDot(.gray,   "+5j")
            }
        }
        .padding(16)
        .glassCard()
        .cornerRadius(16)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 10)).foregroundColor(.gray)
        }
    }
}

// MARK: - PR Tracker

struct PRTrackerView: View {
    let weights: [String: WeightData]

    private struct PREntry: Identifiable {
        let id = UUID()
        let name: String
        let prWeight: Double
        let prDate: String
        let isRecent: Bool  // < 30 jours
    }

    private var prs: [PREntry] {
        let now = Date()
        return weights.compactMap { name, data -> PREntry? in
            guard let history = data.history, !history.isEmpty else { return nil }
            guard let best = history.max(by: { ($0.weight ?? 0) < ($1.weight ?? 0) }),
                  let w = best.weight, w > 0, let date = best.date else { return nil }
            let isRecent: Bool
            if let d = DateFormatter.isoDate.date(from: date) {
                isRecent = Int(now.timeIntervalSince(d) / 86400) <= 30
            } else { isRecent = false }
            return PREntry(name: name, prWeight: w, prDate: date, isRecent: isRecent)
        }
        .sorted { $0.prWeight > $1.prWeight }
        .prefix(10).map { $0 }
    }

    private func shortDate(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let o = DateFormatter(); o.locale = Locale(identifier: "fr_CA"); o.dateFormat = "d MMM yyyy"
        return f.date(from: iso).map { o.string(from: $0) } ?? iso
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECORDS PERSONNELS (PR)")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.yellow).frame(width: 7, height: 7)
                    Text("< 30 jours").font(.system(size: 9)).foregroundColor(.gray)
                }
            }

            if prs.isEmpty {
                Text("Aucune donnée.")
                    .font(.system(size: 13)).foregroundColor(.gray).italic()
            } else {
                let maxW = prs.map(\.prWeight).max() ?? 1
                GeometryReader { outer in
                    VStack(spacing: 8) {
                        ForEach(prs) { pr in
                            HStack(spacing: 10) {
                                // Nom
                                Text(pr.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .frame(width: 130, alignment: .leading)

                                // Barre
                                let barW = outer.size.width - 225
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(hex: "191926")).frame(height: 6)
                                    Capsule()
                                        .fill(pr.isRecent ? Color.yellow : Color.orange.opacity(0.6))
                                        .frame(width: barW * (pr.prWeight / maxW), height: 6)
                                }
                                .frame(height: 6)

                                // Poids + date
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("\(UnitSettings.shared.display(pr.prWeight), specifier: "%.1f") \(UnitSettings.shared.label)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(pr.isRecent ? .yellow : .orange)
                                    Text(shortDate(pr.prDate))
                                        .font(.system(size: 9))
                                        .foregroundColor(.gray)
                                }
                                .frame(width: 75, alignment: .trailing)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(prs.count) * (6 + 8) - 8)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Protein Compliance

struct ProteinComplianceView: View {
    let days: [NutritionDay]
    let target: NutritionSettings

    private var protTarget: Double { target.proteines ?? 180 }

    private struct DayStatus: Identifiable {
        let id: String
        let date: String
        let proteines: Double
        let hit: Bool
        let partial: Bool  // >= 75% de l'objectif
    }

    private var statuses: [DayStatus] {
        days.compactMap { d in
            guard let date = d.date else { return nil }
            let p = d.proteines ?? 0
            return DayStatus(
                id: date, date: date, proteines: p,
                hit: p >= protTarget,
                partial: p >= protTarget * 0.75 && p < protTarget
            )
        }.sorted { $0.date < $1.date }
    }

    private var hitCount: Int { statuses.filter(\.hit).count }
    private var complianceRate: Double {
        statuses.isEmpty ? 0 : Double(hitCount) / Double(statuses.count)
    }
    private var avgProteines: Double {
        statuses.isEmpty ? 0 : statuses.map(\.proteines).reduce(0, +) / Double(statuses.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("COMPLIANCE PROTÉINES — 30J")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                Text("Objectif : \(Int(protTarget))g/j")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            // KPIs
            HStack(spacing: 0) {
                compKPI("\(Int(complianceRate * 100))%", "jours atteints", complianceRate >= 0.8 ? .green : complianceRate >= 0.5 ? .orange : .red)
                Divider().background(Color.white.opacity(0.07)).frame(height: 36)
                compKPI("\(hitCount)/\(statuses.count)", "jours trackés", .blue)
                Divider().background(Color.white.opacity(0.07)).frame(height: 36)
                compKPI("\(Int(avgProteines))g", "moy. / jour", avgProteines >= protTarget ? .green : .orange)
            }

            // Dot calendar
            if !statuses.isEmpty {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(statuses) { day in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.hit ? Color.green : day.partial ? Color.orange : Color(hex: "191926"))
                            .frame(height: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                            )
                    }
                }

                HStack(spacing: 12) {
                    legendDot(.green,           "Objectif atteint")
                    legendDot(.orange,          "≥ 75%")
                    legendDot(Color(hex: "191926"), "< 75%")
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    private func compKPI(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 17, weight: .black)).foregroundColor(color)
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
        }
    }
}

// MARK: - Macros Breakdown
struct MacrosBreakdownView: View {
    let days: [NutritionDay]
    let target: NutritionSettings

    private func avgMacro(_ kp: KeyPath<NutritionDay, Double?>) -> Double {
        let vals = days.compactMap { $0[keyPath: kp] }.filter { $0 > 0 }
        return vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MACROS — MOYENNE \(days.count)J")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            let avgG = avgMacro(\.glucides)
            let avgL = avgMacro(\.lipides)
            let avgP = avgMacro(\.proteines)
            let avgCal = avgMacro(\.calories)

            HStack(spacing: 10) {
                StatsMacroBar(label: "Glucides", value: avgG, target: target.glucides, color: .blue, unit: "g")
                StatsMacroBar(label: "Lipides",  value: avgL, target: target.lipides,  color: .yellow, unit: "g")
                StatsMacroBar(label: "Protéines",value: avgP, target: target.proteines,color: .orange, unit: "g")
            }

            HStack {
                Text("Moy. cal: \(Int(avgCal)) kcal")
                    .font(.system(size: 10)).foregroundColor(.gray)
                Spacer()
                if let tc = target.calories {
                    Text("Cible: \(Int(tc)) kcal")
                        .font(.system(size: 10)).foregroundColor(.gray)
                }
            }
        }
        .padding(16).background(Color.appCard).cornerRadius(14)
    }
}

private struct StatsMacroBar: View {
    let label: String
    let value: Double
    let target: Double?
    let color: Color
    let unit: String

    var pct: Double {
        guard let t = target, t > 0 else { return 0 }
        return min(value / t, 1.4)
    }
    var compliance: Color {
        guard target != nil else { return color }
        return pct >= 0.9 && pct <= 1.1 ? .green : pct < 0.9 ? .orange : .red
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(String(format: "%.0f%@", value, unit))
                .font(.system(size: 14, weight: .black)).foregroundColor(color)
            RoundedRectangle(cornerRadius: 4).fill(compliance.opacity(0.7))
                .frame(height: max(CGFloat(pct) * 50, 2))
            if let t = target {
                Text("/ \(Int(t))\(unit)").font(.system(size: 9)).foregroundColor(.gray)
            }
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: 80, alignment: .bottom)
    }
}

// MARK: - Volume par groupe musculaire

struct MuscleVolumeView: View {
    let stats: [String: MuscleStatEntry]

    private var sorted: [(String, Double)] {
        stats.map { ($0.key, $0.value.volume) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(10).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VOLUME PAR GROUPE MUSCULAIRE")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.gray)

            if sorted.isEmpty {
                Text("Aucune donnée.")
                    .font(.system(size: 13)).foregroundColor(.gray).italic()
            } else {
                let maxVol = sorted.first?.1 ?? 1
                GeometryReader { outer in
                    VStack(spacing: 8) {
                        ForEach(sorted, id: \.0) { muscle, volume in
                            HStack(spacing: 10) {
                                Text(muscle.capitalized)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .frame(width: 110, alignment: .leading)

                                let barW = outer.size.width - 202
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(hex: "191926")).frame(height: 6)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue.opacity(0.9), Color.blue.opacity(0.5)],
                                                startPoint: .leading, endPoint: .trailing
                                            )
                                        )
                                        .frame(width: barW * (volume / maxVol), height: 6)
                                }
                                .frame(height: 6)

                                Text("\(UnitSettings.shared.display(volume), specifier: "%.0f") \(UnitSettings.shared.label)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.blue.opacity(0.8))
                                    .frame(width: 72, alignment: .trailing)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(sorted.count) * (6 + 8) - 8)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Volume Landmarks Card
struct VolumeLandmarksCard: View {
    let landmarks: [String: MuscleLandmark]

    private var sorted: [(String, MuscleLandmark)] {
        landmarks.sorted { a, b in
            // Sort: over-MRV first, then under-MEV, then by muscle name
            let priorityA = a.1.zone == .overMRV ? 0 : a.1.zone == .underMEV ? 1 : 2
            let priorityB = b.1.zone == .overMRV ? 0 : b.1.zone == .underMEV ? 1 : 2
            return priorityA != priorityB ? priorityA < priorityB : a.0 < b.0
        }
    }

    private func zoneColor(_ zone: MuscleLandmark.Zone) -> Color {
        switch zone {
        case .underMEV:       return .blue
        case .optimal:        return .green
        case .approachingMRV: return .orange
        case .overMRV:        return .red
        }
    }

    private func zoneLabel(_ zone: MuscleLandmark.Zone) -> String {
        switch zone {
        case .underMEV:       return "↑ sets"
        case .optimal:        return "optimal ✓"
        case .approachingMRV: return "proche max"
        case .overMRV:        return "surcharge"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 11))
                    .foregroundColor(.purple)
                Text("VOLUME HEBDO — LANDMARKS")
                    .font(.system(size: 10, weight: .bold)).tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                CardInfoButton(title: "Volume landmarks", entries: InfoEntry.volumeLandmarkEntries)
            }

            // Legend
            HStack(spacing: 14) {
                legendDot(.blue,   "Sous le min")
                legendDot(.green,  "Optimal")
                legendDot(.orange, "Proche du max")
                legendDot(.red,    "Surcharge")
            }

            GeometryReader { outer in
                VStack(spacing: 7) {
                    ForEach(sorted, id: \.0) { muscle, lm in
                        let barW = outer.size.width - 190
                        let ratio = min(Double(lm.weeklySets) / Double(lm.mrv), 1.2)
                        HStack(spacing: 8) {
                            Text(muscle.capitalized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 100, alignment: .leading)
                                .lineLimit(1)

                            // Progress bar: filled to weekly_sets/mrv, marker at MEV and MAV
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(zoneColor(lm.zone).opacity(0.8))
                                    .frame(width: min(barW * ratio, barW), height: 8)
                                // MEV marker
                                Rectangle()
                                    .fill(Color.white.opacity(0.4))
                                    .frame(width: 1, height: 12)
                                    .offset(x: barW * Double(lm.mev) / Double(lm.mrv))
                                // MAV marker
                                Rectangle()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(width: 1, height: 12)
                                    .offset(x: min(barW * Double(lm.mav) / Double(lm.mrv), barW - 1))
                            }
                            .frame(height: 12)

                            Text("\(lm.weeklySets)")
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(zoneColor(lm.zone))
                                .frame(width: 22, alignment: .trailing)

                            Text(zoneLabel(lm.zone))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(zoneColor(lm.zone).opacity(0.8))
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(height: CGFloat(sorted.count) * (12 + 7) - 7)

            Text("MEV · MAV · MRV d'après Renaissance Periodization (Israetel et al.)")
                .font(.system(size: 9)).foregroundColor(.gray.opacity(0.6))
                .padding(.top, 2)
        }
        .padding(16)
        .glassCard()
        .cornerRadius(16)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(.gray)
        }
    }
}


// MARK: - Stats Tab Bar
struct StatsTabBar: View {
    @Binding var selectedTab: Int

    private let tabs: [(icon: String, label: String)] = [
        ("chart.bar.fill",           "Synthèse"),
        ("bolt.fill",                "Perf"),
        ("figure.stand",             "Corps"),
        ("fork.knife",               "Nutrition"),
        ("dumbbell.fill",            "Force"),
        ("heart.text.square.fill",   "Bien-être"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.3)) { selectedTab = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tabs[i].icon)
                            .font(.system(size: 13, weight: selectedTab == i ? .bold : .regular))
                        Text(tabs[i].label)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(selectedTab == i ? .orange : .gray)
                    .background(selectedTab == i ? Color.orange.opacity(0.12) : Color.clear)
                    .cornerRadius(10)
                }
            }
        }
        .padding(4)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Period Picker
struct PeriodPicker: View {
    @Binding var selected: StatsPeriod

    var body: some View {
        HStack(spacing: 6) {
            ForEach(StatsPeriod.allCases, id: \.self) { p in
                Button {
                    withAnimation(.spring(response: 0.25)) { selected = p }
                } label: {
                    Text(p.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(selected == p ? Color.orange : Color(hex: "1a1a28"))
                        .foregroundColor(selected == p ? .black : .gray)
                        .cornerRadius(20)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Smart Insights Banner
struct SmartInsightsBanner: View {
    let insights: [(icon: String, text: String, color: Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill").foregroundColor(.yellow).font(.system(size: 10))
                Text("INSIGHTS").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(insights.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        Image(systemName: insights[i].icon)
                            .foregroundColor(insights[i].color)
                            .font(.system(size: 13))
                            .frame(width: 18)
                        Text(insights[i].text)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Tonnage Hebdo Chart
struct TonnageBarChartView: View {
    let entries: [WeeklyTonnageEntry]
    private let units = UnitSettings.shared

    private var maxVol: Double { entries.map(\.totalVolume).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TONNAGE HEBDOMADAIRE (8 SEM.)")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let last = entries.last {
                    Text(_formatK(units.display(last.totalVolume)) + " " + units.label)
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.green)
                }
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let pct = maxVol > 0 ? e.totalVolume / maxVol : 0
                    let isLast = i == entries.count - 1
                    VStack(spacing: 2) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isLast ? Color.green : Color.green.opacity(0.4))
                            .frame(height: max(CGFloat(pct) * 70, 3))
                        Text(shortWeek(e.weekStart))
                            .font(.system(size: 7)).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 90)
                }
            }
            .frame(height: 90)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    private func shortWeek(_ iso: String) -> String {
        guard iso.count >= 10,
              let d = DateFormatter.isoDate.date(from: String(iso.prefix(10))) else { return "" }
        let f = DateFormatter(); f.dateFormat = "d/M"; f.locale = Locale(identifier: "fr_CA")
        return f.string(from: d)
    }
}

// MARK: - Pattern Volume Chart
struct PatternVolumeView: View {
    let data: PatternVolumeData
    private let units = UnitSettings.shared

    private var entries: [(String, Double, Color)] {
        [
            ("Push",  data.push  ?? 0, .orange),
            ("Pull",  data.pull  ?? 0, .blue),
            ("Hinge", data.hinge ?? 0, .purple),
            ("Squat", data.squat ?? 0, .green),
            ("Carry", data.carry ?? 0, .yellow),
            ("Core",  data.core  ?? 0, .cyan),
        ].filter { $0.1 > 0 }
    }
    private var maxVal: Double { entries.map(\.1).max() ?? 1 }
    private var pushPullRatio: String? {
        let push = data.push ?? 0, pull = data.pull ?? 0
        guard push > 0, pull > 0 else { return nil }
        let ratio = pull / push
        return String(format: "Pull:Push = %.2f", ratio)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("VOLUME PAR PATTERN (4 SEM.)")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let r = pushPullRatio {
                    Text(r)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(pushPullBalance)
                }
            }
            GeometryReader { outer in
                let barW = max(0, outer.size.width - 102)
                VStack(spacing: 10) {
                    ForEach(entries, id: \.0) { name, vol, color in
                        let pct = CGFloat(maxVal > 0 ? vol / maxVal : 0)
                        HStack(spacing: 8) {
                            Text(name)
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                                .frame(width: 42, alignment: .leading)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color.opacity(0.7))
                                .frame(width: max(0, barW * pct), height: 14)
                            Spacer(minLength: 0)
                            Text(_formatK(units.display(vol)))
                                .font(.system(size: 10)).foregroundColor(.gray)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(height: entries.isEmpty ? 0 : CGFloat(entries.count) * 24 - 10)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    private var pushPullBalance: Color {
        guard let push = data.push, let pull = data.pull, push > 0 else { return .gray }
        let r = pull / push
        return r >= 0.8 && r <= 1.4 ? .green : .orange
    }
}

// MARK: - Programme Compliance
struct ComplianceProgrammeView: View {
    let weeks: [ComplianceWeek]

    private var overallRate: Double {
        let total = weeks.reduce(0) { $0 + $1.planned }
        let done  = weeks.reduce(0) { $0 + $1.done }
        return total > 0 ? Double(done) / Double(total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("COMPLIANCE PROGRAMME")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text(String(format: "%.0f%%", overallRate * 100))
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(overallRate >= 0.8 ? .green : overallRate >= 0.6 ? .orange : .red)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(weeks.enumerated()), id: \.0) { i, w in
                    let pct = w.planned > 0 ? Double(min(w.done, w.planned)) / Double(w.planned) : 0
                    let isLast = i == weeks.count - 1
                    let color: Color = pct >= 1.0 ? .green : pct >= 0.5 ? .orange : .red
                    VStack(spacing: 2) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isLast ? color : color.opacity(0.5))
                            .frame(height: max(CGFloat(pct) * 60, 3))
                        Text("\(w.done)/\(w.planned)")
                            .font(.system(size: 7)).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 75)
                }
            }
            .frame(height: 75)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - 1RM Trend View
struct OneRMTrendView: View {
    let trend: [String: [OneRMPoint]]
    private let units = UnitSettings.shared
    @State private var selectedExercise: String = ""

    private var exercises: [String] { Array(trend.keys).sorted() }
    private var currentExercise: String { selectedExercise.isEmpty ? (exercises.first ?? "") : selectedExercise }
    private var points: [OneRMPoint] { trend[currentExercise] ?? [] }
    private var maxRM: Double { points.map(\.oneRM).max() ?? 1 }
    private var minRM: Double { points.map(\.oneRM).min() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TENDANCE 1RM — BLOC ACTIF")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let last = points.last, let first = points.first, last.oneRM > first.oneRM {
                    Text("+\(String(format: "%.1f", last.oneRM - first.oneRM)) \(units.label)")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.green)
                }
            }
            if exercises.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(exercises, id: \.self) { ex in
                            Button {
                                withAnimation { selectedExercise = ex }
                            } label: {
                                Text(ex)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(currentExercise == ex ? Color.orange : Color(hex: "1a1a28"))
                                    .foregroundColor(currentExercise == ex ? .black : .gray)
                                    .cornerRadius(20)
                            }
                        }
                    }
                }
            }
            GeometryReader { geo in
                if points.count >= 2 {
                    let range = maxRM - minRM
                    let pad: Double = range > 0 ? range * 0.1 : 5
                    let lo = minRM - pad, hi = maxRM + pad, span = hi - lo
                    let step = geo.size.width / CGFloat(points.count - 1)
                    ZStack {
                        Path { p in
                            for (i, pt) in points.enumerated() {
                                let x = CGFloat(i) * step
                                let y = geo.size.height * (1 - CGFloat((pt.oneRM - lo) / span))
                                if i == 0 { p.move(to: .init(x: x, y: y)) }
                                else { p.addLine(to: .init(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                        ForEach(Array(points.enumerated()), id: \.0) { i, pt in
                            let x = CGFloat(i) * step
                            let y = geo.size.height * (1 - CGFloat((pt.oneRM - lo) / span))
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                                .position(x: x, y: y)
                        }
                    }
                }
            }
            .frame(height: 80)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - RPE Progression View
struct RPEProgressionView: View {
    let data: RPEProgressionData

    private var buckets: [(String, Double?, Color)] {[
        ("<7",   data.lt7,   .blue),
        ("7–8",  data.r7_8,  .green),
        ("8–9",  data.r8_9,  .orange),
        ("9–10", data.r9_10, .red),
    ]}
    private var maxAbs: Double {
        buckets.compactMap { $0.1 }.map { abs($0) }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUELLE INTENSITÉ TE FAIT PROGRESSER ?")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            Text("Gain de charge moyen sur la séance suivante par zone d'intensité")
                .font(.system(size: 10)).foregroundColor(.gray.opacity(0.7))
            GeometryReader { outer in
                VStack(spacing: 10) {
                    ForEach(buckets, id: \.0) { name, val, color in
                        let pct = val.map { abs($0) / max(maxAbs, 1) } ?? 0
                        let c = (val ?? 0) >= 0 ? color : Color.red
                        let barW = outer.size.width - 126
                        HStack(spacing: 8) {
                            Text("RPE \(name)")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                                .frame(width: 60, alignment: .leading)
                            HStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 3).fill(c).frame(width: max(barW * CGFloat(pct), 2), height: 14)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 14)
                            if let v = val {
                                Text(v >= 0 ? "+\(String(format: "%.1f", v))%" : "\(String(format: "%.1f", v))%")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor((v) >= 0 ? .green : .red)
                                    .frame(width: 50, alignment: .trailing)
                            } else {
                                Text("—").font(.system(size: 10)).foregroundColor(.gray).frame(width: 50, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .frame(height: CGFloat(buckets.count) * (14 + 10) - 10)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - RIR By Exercise View
struct RIRByExerciseView: View {
    let entries: [RIREntry]
    private var maxRIR: Double { entries.map(\.avgRir).max() ?? 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RIR MOYEN PAR EXERCICE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            Text("Reps In Reserve — distance à l'échec musculaire")
                .font(.system(size: 10)).foregroundColor(.gray.opacity(0.7))
            GeometryReader { outer in
                VStack(spacing: 10) {
                    ForEach(entries.prefix(8)) { e in
                        let pct = maxRIR > 0 ? e.avgRir / maxRIR : 0
                        let c: Color = e.avgRir <= 1 ? .red : e.avgRir <= 2 ? .orange : .green
                        let barW = outer.size.width - 164
                        HStack(spacing: 8) {
                            Text(e.exercise)
                                .font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                                .frame(width: 120, alignment: .leading).lineLimit(1)
                            RoundedRectangle(cornerRadius: 3).fill(c.opacity(0.7))
                                .frame(width: barW * CGFloat(pct), height: 12)
                            Spacer(minLength: 0)
                            Text(String(format: "%.1f", e.avgRir))
                                .font(.system(size: 10, weight: .bold)).foregroundColor(c)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(height: CGFloat(min(entries.count, 8)) * (12 + 10) - 10)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - HIIT Completion View
struct HIITCompletionView: View {
    let entries: [HIITCompletionEntry]
    private var avgRate: Double {
        let r = entries.filter { $0.roundsPlanned > 0 }.map(\.rate)
        return r.isEmpty ? 0 : r.reduce(0,+)/Double(r.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HIIT — TAUX DE COMPLETION")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text(String(format: "Moy. %.0f%%", avgRate * 100))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(avgRate >= 0.85 ? .green : .orange)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.0) { i, e in
                    let isLast = i == entries.count - 1
                    let c: Color = e.rate >= 1.0 ? .green : e.rate >= 0.7 ? .orange : .red
                    VStack(spacing: 2) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isLast ? c : c.opacity(0.5))
                            .frame(height: max(CGFloat(e.rate) * 60, 3))
                        Text("\(e.roundsCompleted)/\(e.roundsPlanned)")
                            .font(.system(size: 7)).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70)
                }
            }
            .frame(height: 70)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Recovery Composite Score View
struct RecoveryCompositeScoreView: View {
    let log: [RecoveryEntry]

    private enum ComponentStatus { case green, yellow, red }

    private func score(_ r: RecoveryEntry) -> Double? {
        var components: [(Double, Double)] = []
        if let sh = r.sleepHours  { components.append((min(sh / 8.0, 1.0), 0.30)) }
        if let sq = r.sleepQuality { components.append((sq / 10.0, 0.20)) }
        if let s  = r.soreness     { components.append(((11.0 - s) / 10.0, 0.20)) }
        if let h  = r.hrv          { components.append((min(h / 80.0, 1.0), 0.20)) }
        if let st = r.steps.map(Double.init) { components.append((min(st / 8000.0, 1.0), 0.10)) }
        guard !components.isEmpty else { return nil }
        let totalWeight = components.map(\.1).reduce(0, +)
        let weightedSum = components.map { $0.0 * $0.1 }.reduce(0, +)
        return (weightedSum / totalWeight) * 100
    }

    private var points: [(String, Double)] {
        log.compactMap { r -> (String, Double)? in
            guard let d = r.date, let s = score(r) else { return nil }
            return (d, s)
        }
    }

    private func sleepStatus(_ r: RecoveryEntry) -> ComponentStatus {
        guard let h = r.sleepHours else { return .yellow }
        return h >= 7 ? .green : h >= 5.5 ? .yellow : .red
    }
    private func hrvStatus(_ r: RecoveryEntry) -> ComponentStatus {
        guard let h = r.hrv, h > 0 else { return .yellow }
        return h >= 50 ? .green : h >= 35 ? .yellow : .red
    }
    private func sorenessStatus(_ r: RecoveryEntry) -> ComponentStatus {
        guard let s = r.soreness else { return .yellow }
        return s <= 3 ? .green : s <= 6 ? .yellow : .red
    }
    private func statusColor(_ s: ComponentStatus) -> Color {
        switch s { case .green: return .green; case .yellow: return .yellow; case .red: return .red }
    }
    private func componentDot(_ label: String, _ status: ComponentStatus) -> some View {
        HStack(spacing: 4) {
            Circle().fill(statusColor(status)).frame(width: 7, height: 7)
            Text(label).font(.system(size: 10)).foregroundColor(.gray)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SCORE RÉCUPÉRATION")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let last = points.last {
                    let c: Color = last.1 >= 70 ? .green : last.1 >= 45 ? .orange : .red
                    Text(String(format: "%.0f/100", last.1))
                        .font(.system(size: 14, weight: .black)).foregroundColor(c)
                }
            }
            Text("Sommeil × HRV × Soreness × Steps")
                .font(.system(size: 10)).foregroundColor(.gray.opacity(0.7))
            GeometryReader { geo in
                if points.count >= 2 {
                    let maxS = 100.0
                    let step = geo.size.width / CGFloat(points.count - 1)
                    ZStack {
                        ForEach([45.0, 70.0], id: \.self) { threshold in
                            let y = geo.size.height * (1 - CGFloat(threshold / maxS))
                            Path { p in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: geo.size.width, y: y)) }
                                .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        }
                        Path { p in
                            for (i, pt) in points.enumerated() {
                                let x = CGFloat(i) * step
                                let y = geo.size.height * (1 - CGFloat(pt.1 / maxS))
                                if i == 0 { p.move(to: .init(x: x, y: y)) }
                                else { p.addLine(to: .init(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.teal, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                        ForEach(Array(points.enumerated()), id: \.0) { i, pt in
                            let c: Color = pt.1 >= 70 ? .green : pt.1 >= 45 ? .orange : .red
                            Circle().fill(c).frame(width: 6, height: 6)
                                .position(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(pt.1 / maxS)))
                        }
                    }
                }
            }
            .frame(height: 80)
            if let last = log.last {
                HStack(spacing: 14) {
                    componentDot("Sommeil",  sleepStatus(last))
                    componentDot("HRV",      hrvStatus(last))
                    componentDot("Soreness", sorenessStatus(last))
                }
                let allStatuses = [sleepStatus(last), hrvStatus(last), sorenessStatus(last)]
                if let s = score(last), s >= 45, allStatuses.contains(.red) {
                    Text("Score OK, mais un indicateur est en alerte")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Generic Scatter Plot View
struct ScatterPlotView: View {
    let data: [ScatterPoint]
    let xLabel: String
    let yLabel: String
    let title: String
    let color: Color

    private var xs: [Double] { data.map(\.x) }
    private var ys: [Double] { data.map(\.y) }
    private var minX: Double { xs.min() ?? 0 }
    private var maxX: Double { xs.max() ?? 1 }
    private var minY: Double { ys.min() ?? 0 }
    private var maxY: Double { ys.max() ?? 1 }

    private func pearsonR() -> Double {
        let n = Double(data.count)
        guard n > 1 else { return 0 }
        let mx = xs.reduce(0,+)/n, my = ys.reduce(0,+)/n
        let num = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0,+)
        let dx  = xs.map { pow($0 - mx, 2) }.reduce(0,+)
        let dy  = ys.map { pow($0 - my, 2) }.reduce(0,+)
        let den = sqrt(dx * dy)
        return den > 0 ? num / den : 0
    }

    var body: some View {
        let r = pearsonR()
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            GeometryReader { geo in
                let xRange = maxX - minX, yRange = maxY - minY
                let xPad = xRange * 0.05, yPad = yRange * 0.05
                let xLo = minX - xPad, xSpan = xRange + 2 * xPad
                let yLo = minY - yPad, ySpan = yRange + 2 * yPad
                ZStack {
                    // Grid
                    ForEach([0.25, 0.5, 0.75], id: \.self) { f in
                        Path { p in
                            let y = geo.size.height * CGFloat(1 - f)
                            p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: geo.size.width, y: y))
                        }
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    }
                    // Regression line
                    if data.count >= 5 && abs(r) >= 0.2 {
                        let n = Double(data.count)
                        let mx = xs.reduce(0,+)/n, my = ys.reduce(0,+)/n
                        let num = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0,+)
                        let den = xs.map { pow($0 - mx, 2) }.reduce(0,+)
                        let slope = den > 0 ? num/den : 0
                        let inter = my - slope * mx
                        let y0 = CGFloat(1 - (slope * xLo + inter - yLo) / ySpan) * geo.size.height
                        let y1 = CGFloat(1 - (slope * (xLo + xSpan) + inter - yLo) / ySpan) * geo.size.height
                        Path { p in p.move(to: .init(x: 0, y: y0)); p.addLine(to: .init(x: geo.size.width, y: y1)) }
                            .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    }
                    // Points
                    ForEach(data) { pt in
                        let px = CGFloat((pt.x - xLo) / xSpan) * geo.size.width
                        let py = geo.size.height * (1 - CGFloat((pt.y - yLo) / ySpan))
                        Circle().fill(color.opacity(0.7)).frame(width: 6, height: 6).position(x: px, y: py)
                    }
                }
            }
            .frame(height: 130)
            HStack {
                Text(xLabel).font(.system(size: 9)).foregroundColor(.gray)
                Spacer()
                Text(yLabel).font(.system(size: 9)).foregroundColor(.gray)
            }
            if abs(r) >= 0.3 {
                let direction = r > 0 ? "positive" : "négative"
                let strength = abs(r) >= 0.6 ? "forte" : "modérée"
                Text("Corrélation \(strength) \(direction) (r = \(String(format: "%.2f", r)), \(data.count) pts)")
                    .font(.system(size: 10)).foregroundColor(.gray.opacity(0.8))
            } else if data.count >= 5 {
                Text("Pas de corrélation significative (r = \(String(format: "%.2f", r)))")
                    .font(.system(size: 10)).foregroundColor(.gray.opacity(0.6))
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Protein/Weight Ratio View
struct ProteinWeightRatioView: View {
    let data: [ProteinWeightPoint]
    private let target: Double = 1.0
    private var maxR: Double { max(data.map(\.ratio).max() ?? 1, target * 1.2) }
    private var avg: Double {
        data.isEmpty ? 0 : data.map(\.ratio).reduce(0,+)/Double(data.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RATIO PROTÉINES / POIDS CORPOREL")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text(String(format: "Moy. %.2f g/lb", avg))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(avg >= 0.8 ? .green : .orange)
            }
            GeometryReader { geo in
                let step = data.count > 1 ? geo.size.width / CGFloat(data.count - 1) : geo.size.width
                ZStack {
                    // Target zone (0.8–1.2 g/lb)
                    let yTop = geo.size.height * (1 - CGFloat(1.2 / maxR))
                    let yBot = geo.size.height * (1 - CGFloat(0.8 / maxR))
                    Rectangle()
                        .fill(Color.green.opacity(0.08))
                        .frame(width: geo.size.width, height: yBot - yTop)
                        .position(x: geo.size.width/2, y: (yTop + yBot)/2)
                    // Target line
                    let yTarget = geo.size.height * (1 - CGFloat(target / maxR))
                    Path { p in p.move(to: .init(x: 0, y: yTarget)); p.addLine(to: .init(x: geo.size.width, y: yTarget)) }
                        .stroke(Color.green.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    // Line chart
                    if data.count >= 2 {
                        Path { p in
                            for (i, pt) in data.enumerated() {
                                let x = CGFloat(i) * step
                                let y = geo.size.height * (1 - CGFloat(pt.ratio / maxR))
                                if i == 0 { p.move(to: .init(x: x, y: y)) } else { p.addLine(to: .init(x: x, y: y)) }
                            }
                        }
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    }
                }
            }
            .frame(height: 90)
            Text("Zone verte = 0.8–1.2 g/lb — cible hypertrophie")
                .font(.system(size: 10)).foregroundColor(.gray.opacity(0.7))
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Macros Day Type View
struct MacrosDayTypeView: View {
    let data: MacrosByDayType

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MACROS : JOUR TRAINING VS REPOS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            if let t = data.training, let r = data.rest {
                HStack(spacing: 12) {
                    macroColumn(label: "Entraînement", bucket: t, color: .orange, n: data.nTraining)
                    macroColumn(label: "Repos", bucket: r, color: .blue, n: data.nRest)
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    private func macroColumn(label: String, bucket: MacroBucket, color: Color, n: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11, weight: .bold)).foregroundColor(color)
            Text("(\(n) jours)").font(.system(size: 9)).foregroundColor(.gray)
            macroRow("Calories", String(format: "%.0f kcal", bucket.avgCal), color)
            macroRow("Protéines", String(format: "%.0f g", bucket.avgProt), .green)
            macroRow("Glucides", String(format: "%.0f g", bucket.avgCarbs), .yellow)
            macroRow("Lipides", String(format: "%.0f g", bucket.avgFat), .orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }

    private func macroRow(_ name: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name).font(.system(size: 10)).foregroundColor(.gray)
            Spacer()
            Text(value).font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
        }
    }
}

// MARK: - Mood & Stress Trend View
struct MoodStressTrendView: View {
    let data: [MoodTrendPoint]
    let pssHistory: [PSSRecord]

    // mood_logs.score : slider 1–10 (MoodTrackerView)
    // life_stress_scores.score : LSS 0–100 (100 = récupération optimale, life_stress_engine.py)
    private let moodScaleMax: Double = 10.0
    private let stressScaleMax: Double = 100.0

    private var recentData: [MoodTrendPoint] { Array(data.suffix(30)) }
    private var n: Int { recentData.count }
    private var avgMood: Double {
        let m = recentData.compactMap(\.moodScore).map(Double.init)
        return m.isEmpty ? 0 : m.reduce(0,+)/Double(m.count)
    }
    private var avgStress: Double {
        let s = recentData.compactMap(\.lifeStressScore)
        return s.isEmpty ? 0 : s.reduce(0,+)/Double(s.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HUMEUR & BIEN-ÊTRE — 30 JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            // Graphique humeur (1-10, ↑ = bien)
            if n >= 2 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Humeur").font(.system(size: 9, weight: .semibold)).foregroundColor(.purple)
                        Spacer()
                        Text(String(format: "Moy. %.1f / 10", avgMood))
                            .font(.system(size: 9)).foregroundColor(.purple.opacity(0.7))
                    }
                    GeometryReader { geo in
                        let moodPts: [CGPoint] = recentData.enumerated().compactMap { i, pt in
                            guard let m = pt.moodScore else { return nil }
                            return CGPoint(
                                x: geo.size.width * CGFloat(i) / CGFloat(n - 1),
                                y: geo.size.height * (1 - CGFloat(Double(m) / moodScaleMax))
                            )
                        }
                        ZStack {
                            if moodPts.count >= 2 {
                                Path { p in
                                    moodPts.enumerated().forEach { i, pt in
                                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                                    }
                                }
                                .stroke(Color.purple, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                            }
                            ForEach(Array(pssHistory.prefix(5)), id: \.id) { rec in
                                if let idx = recentData.firstIndex(where: { $0.date == rec.date }) {
                                    let x = geo.size.width * CGFloat(idx) / CGFloat(n - 1)
                                    let c: Color = rec.category == "low" ? .green : rec.category == "moderate" ? .orange : .red
                                    Circle().fill(c).frame(width: 8, height: 8).position(x: x, y: geo.size.height * 0.5)
                                }
                            }
                        }
                    }
                    .frame(height: 55)
                }
            }

            // Graphique bien-être (LSS 0-100, 100 = optimal, ↑ = bien)
            if n >= 2 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Score bien-être").font(.system(size: 9, weight: .semibold)).foregroundColor(.orange)
                        Text("(100 = optimal)").font(.system(size: 8)).foregroundColor(.gray.opacity(0.6))
                        Spacer()
                        Text(String(format: "Moy. %.0f / 100", avgStress))
                            .font(.system(size: 9)).foregroundColor(.orange.opacity(0.7))
                    }
                    GeometryReader { geo in
                        let stressPts: [CGPoint] = recentData.enumerated().compactMap { i, pt in
                            guard let s = pt.lifeStressScore else { return nil }
                            return CGPoint(
                                x: geo.size.width * CGFloat(i) / CGFloat(n - 1),
                                y: geo.size.height * (1 - CGFloat(s / stressScaleMax))
                            )
                        }
                        if stressPts.count >= 2 {
                            Path { p in
                                stressPts.enumerated().forEach { i, pt in
                                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                                }
                            }
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        }
                    }
                    .frame(height: 55)
                }
            }

            HStack(spacing: 12) {
                Label("Humeur (1–10)", systemImage: "circle.fill").font(.system(size: 9)).foregroundColor(.purple)
                Label("Bien-être (0–100)", systemImage: "circle.fill").font(.system(size: 9)).foregroundColor(.orange)
                Label("PSS", systemImage: "circle.fill").font(.system(size: 9)).foregroundColor(.green)
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Self-Care Streaks View
struct SelfCareStreaksView: View {
    let streaks: [SelfCareStreak]
    let compliance: SelfCareComplianceData?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SELF-CARE — STREAKS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let c = compliance {
                    Text(String(format: "Compliance 30j: %.0f%%", c.rate30d * 100))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(c.rate30d >= 0.6 ? .green : .orange)
                }
            }
            if let c = compliance, !c.daily.isEmpty {
                SelfCareHeatStrip(daily: c.daily)
            }
            ForEach(Array(streaks.prefix(6)), id: \.habitId) { s in
                HStack(spacing: 10) {
                    Image(systemName: s.habitIcon)
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.habitName).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        Text("Meilleure série : \(s.longestStreak) jours")
                            .font(.system(size: 10)).foregroundColor(.gray)
                    }
                    Spacer()
                    if s.currentStreak > 0 {
                        Text("\(s.currentStreak)🔥")
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

struct SelfCareHeatStrip: View {
    let daily: [SelfCareDailyEntry]
    private var maxCount: Int { daily.map(\.count).max() ?? 1 }
    private var last30: [SelfCareDailyEntry] { Array(daily.suffix(30)) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(last30) { entry in
                let intensity = maxCount > 0 ? Double(entry.count) / Double(maxCount) : 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.teal.opacity(0.2 + intensity * 0.8))
                    .frame(height: 14)
            }
        }
    }
}

// MARK: - PSS History View
struct PSSHistoryView: View {
    let records: [PSSRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HISTORIQUE — STRESS PERÇU")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            ForEach(Array(records.prefix(5)), id: \.id) { rec in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.categoryLabel).font(.system(size: 11, weight: .bold)).foregroundColor(pssColor(rec.category))
                        Text(rec.date.prefix(10)).font(.system(size: 10)).foregroundColor(.gray)
                    }
                    Spacer()
                    Text("\(rec.score)/\(rec.maxScore)")
                        .font(.system(size: 14, weight: .black)).foregroundColor(pssColor(rec.category))
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(pssColor(rec.category).opacity(0.3))
                            .frame(width: geo.size.width * CGFloat(rec.score) / CGFloat(rec.maxScore), height: 8)
                    }
                    .frame(width: 60, height: 8)
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    private func pssColor(_ cat: String) -> Color {
        switch cat {
        case "low":      return .green
        case "moderate": return .orange
        default:         return .red
        }
    }
}

#Preview {
    StatsView()
        .environmentObject(AppState.shared)
}

// MARK: - Push/Pull Ratio Card

struct PushPullRatioCard: View {
    let data: WeeklyReportPushPull

    private var imbalanceColor: Color {
        guard let imb = data.imbalance else { return .green }
        return imb.contains("dominant") ? .orange : .green
    }

    private var imbalanceText: String {
        switch data.imbalance {
        case "push_dominant": return "Trop de PUSH — ajoute des tirages"
        case "pull_dominant": return "Trop de PULL — équilibre avec des poussées"
        default:              return "Ratio équilibré ✓"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.left.arrow.right").foregroundColor(.orange)
                Text("RATIO PUSH / PULL")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let ratio = data.ratio {
                    Text(String(format: "%.2f", ratio))
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(imbalanceColor)
                }
            }

            let total = data.pushVolume + data.pullVolume + data.legsVolume
            if total > 0 {
                VStack(spacing: 6) {
                    ForEach([
                        ("PUSH", data.pushVolume, Color.orange),
                        ("PULL", data.pullVolume, Color.blue),
                        ("LEGS", data.legsVolume, Color.green),
                    ], id: \.0) { label, vol, color in
                        HStack(spacing: 8) {
                            Text(label)
                                .font(.system(size: 10, weight: .bold)).tracking(1)
                                .foregroundColor(.gray)
                                .frame(width: 36, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06)).frame(height: 8)
                                    RoundedRectangle(cornerRadius: 3).fill(color)
                                        .frame(width: geo.size.width * CGFloat(vol / total), height: 8)
                                }
                            }
                            .frame(height: 8)
                            Text(_formatK(vol) + " lbs")
                                .font(.system(size: 10)).foregroundColor(.gray)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }

            Text(imbalanceText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(imbalanceColor)
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Soreness Threshold Card

struct SorenessThresholdCard: View {
    let data: SorenessThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt.heart.fill").foregroundColor(.red)
                Text("SEUIL COURBATURES PERSONNEL")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            }

            if let msg = data.message {
                Text(msg)
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                if let low = data.avgSorenessLowVol {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FAIBLE VOL").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                        Text(String(format: "%.1f/10", low))
                            .font(.system(size: 15, weight: .black)).foregroundColor(.green)
                    }
                }
                if let high = data.avgSorenessHighVol {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FORT VOL").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                        Text(String(format: "%.1f/10", high))
                            .font(.system(size: 15, weight: .black)).foregroundColor(.red)
                    }
                }
                if let thresh = data.thresholdVol {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SEUIL").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                        Text(_formatK(thresh) + " lbs")
                            .font(.system(size: 15, weight: .black)).foregroundColor(.orange)
                    }
                }
                Spacer()
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - HRV Baseline Card

struct HRVBaselineCard: View {
    let data: HRVBaseline

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(data.flagRest ? .red : .cyan)
                Text("BASELINE HRV PERSONNALISÉE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if data.flagRest {
                    Text("⚠️ REPOS")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 16) {
                if let baseline = data.baseline {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BASELINE 28J").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                        Text(String(format: "%.0f ms", baseline))
                            .font(.system(size: 18, weight: .black)).foregroundColor(.cyan)
                    }
                }
                if let sd = data.sd {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("±SD").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                        Text(String(format: "%.0f ms", sd))
                            .font(.system(size: 18, weight: .black)).foregroundColor(.gray)
                    }
                }
                if let today = data.todayHrv {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AUJOURD'HUI").font(.system(size: 9, weight: .bold)).tracking(1).foregroundColor(.gray)
                        Text(String(format: "%.0f ms", today))
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(data.flagRest ? .red : .green)
                    }
                }
                Spacer()
            }

            if let msg = data.message {
                Text(msg)
                    .font(.system(size: 12)).foregroundColor(.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let dev = data.deviation {
                Text(dev >= 0 ? String(format: "+%.0f ms vs baseline", dev) : String(format: "%.0f ms vs baseline", dev))
                    .font(.system(size: 11)).foregroundColor(dev >= 0 ? .green : .orange)
            }

            Text("\(data.dataPoints) jours de données")
                .font(.system(size: 10)).foregroundColor(.gray.opacity(0.6))
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Body Recomposition Tracker
struct BodyRecompView: View {
    let entries: [BodyWeightEntry]
    @ObservedObject private var units = UnitSettings.shared

    private struct RecompPoint: Identifiable {
        let id = UUID()
        let date: String
        let weight: Double
        let fatMass: Double
        let leanMass: Double
    }

    private var points: [RecompPoint] {
        entries.compactMap { e -> RecompPoint? in
            guard e.weight > 0, let bf = e.bodyFat, bf > 0 else { return nil }
            let fat  = e.weight * (bf / 100.0)
            let lean = e.weight - fat
            return RecompPoint(date: e.date, weight: e.weight, fatMass: fat, leanMass: lean)
        }
    }

    private var delta30: (lean: Double, fat: Double)? {
        guard points.count >= 2 else { return nil }
        let cutoff = DateFormatter.isoDate.string(from: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 30 * 86400))
        let recent = points.filter { $0.date >= cutoff }
        guard let first = recent.first, let last = recent.last else { return nil }
        return (lean: last.leanMass - first.leanMass, fat: last.fatMass - first.fatMass)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BODY RECOMPOSITION — 3 COURBES")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            if points.count < 3 {
                EmptyChartPlaceholder(message: "Logge ton % de masse grasse pour activer le recomp tracker")
            } else {
                recompChart
                if let d = delta30 {
                    deltaRow(d)
                }
            }
        }
        .padding(16).glassCard().cornerRadius(14)
    }

    private func chartY(_ v: Double, h: CGFloat, minV: Double, range: Double) -> CGFloat {
        h * (1 - CGFloat((v - minV) / range))
    }

    private func recompLine(_ kp: KeyPath<RecompPoint, Double>, color: Color, step: CGFloat, h: CGFloat, minV: Double, range: Double) -> some View {
        Path { path in
            for (i, p) in points.enumerated() {
                let x = CGFloat(i) * step
                let yv = chartY(p[keyPath: kp], h: h, minV: minV, range: range)
                if i == 0 { path.move(to: CGPoint(x: x, y: yv)) }
                else       { path.addLine(to: CGPoint(x: x, y: yv)) }
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    @ViewBuilder private var recompChart: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let allVals = points.flatMap { [$0.weight, $0.fatMass, $0.leanMass] }
            let minV = (allVals.min() ?? 0) * 0.95
            let maxV = (allVals.max() ?? 1) * 1.05
            let range = maxV - minV
            let step  = w / CGFloat(max(points.count - 1, 1))

            ZStack {
                recompLine(\.weight,   color: .gray.opacity(0.6),            step: step, h: h, minV: minV, range: range)
                recompLine(\.fatMass,  color: Color(hex: "E74C3C").opacity(0.8), step: step, h: h, minV: minV, range: range)
                recompLine(\.leanMass, color: Color(hex: "F5A623"),           step: step, h: h, minV: minV, range: range)
            }
        }
        .frame(height: 100)

        // Legend
        HStack(spacing: 16) {
            legendDot(.gray,                   "Poids total")
            legendDot(Color(hex: "E74C3C"),    "Masse grasse")
            legendDot(Color(hex: "F5A623"),    "Masse maigre")
        }
        .font(.system(size: 10)).foregroundColor(.gray)
    }

    @ViewBuilder private func deltaRow(_ d: (lean: Double, fat: Double)) -> some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
        HStack(spacing: 20) {
            deltaKPI(
                label: "Masse maigre (30j)",
                value: units.format(d.lean, decimals: 1),
                good: d.lean >= 0
            )
            deltaKPI(
                label: "Masse grasse (30j)",
                value: units.format(d.fat, decimals: 1),
                good: d.fat <= 0
            )
            Spacer()
        }
    }

    @ViewBuilder private func deltaKPI(label: String, value: String, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(good ? .green : .orange)
            Text(label)
                .font(.system(size: 10)).foregroundColor(.gray)
        }
    }

    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t)
        }
    }
}

// MARK: - Intensity Card (%1RM)
struct IntensityCard: View {
    let data: IntensityData

    private var zoneLabel: String {
        switch data.zone {
        case "force":        return "Zone force (>80%)"
        case "hypertrophie": return "Zone hypertrophie (65–80%)"
        default:             return "Zone volume / décharge (<65%)"
        }
    }
    private var zoneColor: Color {
        switch data.zone {
        case "force":        return .red
        case "hypertrophie": return .orange
        default:             return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INTENSITÉ RELATIVE — %1RM")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            HStack(alignment: .bottom, spacing: 12) {
                if let pct = data.avgPct1rm {
                    Text(String(format: "%.0f%%", pct))
                        .font(.system(size: 36, weight: .black))
                        .foregroundColor(zoneColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(zoneLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(zoneColor)
                    Text("\(data.setsCount) sets cette semaine")
                        .font(.system(size: 11)).foregroundColor(.gray)
                }
                Spacer()
            }

            // Zone gauge
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    // Background zones
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.blue.opacity(0.25)).frame(width: w * 0.65)
                        Rectangle().fill(Color.orange.opacity(0.25)).frame(width: w * 0.15)
                        Rectangle().fill(Color.red.opacity(0.25))
                    }
                    .cornerRadius(4)

                    // Cursor
                    if let pct = data.avgPct1rm {
                        let clamped = min(max(pct / 100.0, 0), 1.0)
                        Rectangle()
                            .fill(zoneColor)
                            .frame(width: 3, height: 20)
                            .offset(x: w * clamped - 1.5)
                    }
                }
                .frame(height: 12)
                .cornerRadius(4)

                // Zone labels
                HStack {
                    Text("<65%").font(.system(size: 8)).foregroundColor(.blue)
                    Spacer()
                    Text("65–80%").font(.system(size: 8)).foregroundColor(.orange)
                    Spacer()
                    Text(">80%").font(.system(size: 8)).foregroundColor(.red)
                }
                .offset(y: 16)
            }
            .frame(height: 32)
        }
        .padding(16).glassCard(color: zoneColor, intensity: 0.04).cornerRadius(14)
    }
}

// MARK: - Deload Status Card
struct DeloadStatusCard: View {
    let data: DeloadStatusData

    private var weeksSince: Int { data.weeksSinceDeload ?? 0 }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DELOAD")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                if data.deloadActif {
                    Text("Deload actif")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.blue)
                } else if let w = data.weeksSinceDeload {
                    Text("\(w) sem.")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(deloadColor)
                    Text("depuis le dernier deload")
                        .font(.system(size: 11)).foregroundColor(.gray)
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .black)).foregroundColor(.gray)
                    Text("pas encore de deload enregistré")
                        .font(.system(size: 11)).foregroundColor(.gray)
                }
            }
            Spacer()
            if data.recommande {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20)).foregroundColor(.orange)
                    Text("Recommandé")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.orange)
                }
            }
        }
        .padding(16).glassCard(color: deloadColor, intensity: 0.04).cornerRadius(14)
    }

    private var deloadColor: Color {
        if data.recommande { return .orange }
        guard let w = data.weeksSinceDeload else { return .gray }
        if w <= 4 { return .green }
        if w <= 6 { return .orange }
        return .red
    }
}

// MARK: - Adherence Rings Card
struct AdherenceRingsCard: View {
    let data: AdherenceData

    private struct Pillar {
        let label: String
        let pct: Int
        let color: Color
    }

    private var pillars: [Pillar] {
        [
            Pillar(label: "Body",   pct: data.bodyPct,   color: Color(hex: "F5A623")),
            Pillar(label: "Mind",   pct: data.mindPct,   color: .blue),
            Pillar(label: "Fuel",   pct: data.fuelPct,   color: .green),
            Pillar(label: "Spirit", pct: data.spiritPct, color: Color(hex: "9B59B6")),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CONSTANCE CE MOIS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("\(data.daysElapsed) jours écoulés")
                    .font(.system(size: 11)).foregroundColor(.gray)
            }

            HStack(spacing: 24) {
                ZStack {
                    ForEach(pillars.indices.reversed(), id: \.self) { i in
                        AdherenceArc(
                            pct: Double(pillars[i].pct) / 100.0,
                            color: pillars[i].color,
                            radius: CGFloat(40 - i * 8),
                            lineWidth: 6
                        )
                    }
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(pillars.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(pillars[i].color)
                                .frame(width: 8, height: 8)
                            Text(pillars[i].label)
                                .font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Text("\(pillars[i].pct)%")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(adherenceColor(pillars[i].pct))
                        }
                    }
                }
            }
        }
        .padding(16).glassCard().cornerRadius(14)
    }

    private func adherenceColor(_ pct: Int) -> Color {
        if pct >= 70 { return .green }
        if pct >= 40 { return .orange }
        return .red
    }
}

private struct AdherenceArc: View {
    let pct: Double
    let color: Color
    let radius: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .trim(from: 0, to: CGFloat(min(pct, 1.0)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: radius * 2, height: radius * 2)
                .animation(.easeOut(duration: 0.6), value: pct)
        }
    }
}

// MARK: - Season Comparison Card
struct SeasonComparisonCard: View {
    let data: SeasonComparisonData
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.orange).font(.system(size: 12))
                Text("COMPARAISON SAISONS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            }

            if let current = data.current {
                seasonTable(current: current, previous: data.previous)
            } else {
                Text("Aucune saison active")
                    .font(.system(size: 13)).foregroundColor(.gray)
            }
        }
        .padding(16).glassCard().cornerRadius(14)
    }

    @ViewBuilder private func seasonTable(current: SeasonCompStats, previous: SeasonCompStats?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("").frame(height: 16)
                Text("Vol. moy/sem").font(.system(size: 11)).foregroundColor(.gray)
                Text("Séances").font(.system(size: 11)).foregroundColor(.gray)
                Text("PSS moy.").font(.system(size: 11)).foregroundColor(.gray)
                Text("Δ poids").font(.system(size: 11)).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .center, spacing: 10) {
                Text(current.title ?? "En cours")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.orange)
                    .lineLimit(1).frame(height: 16)
                valCell(current.volumeAvgWeek.map { units.format($0, decimals: 0) })
                valCell(current.sessionsCount.map { "\($0)" })
                valCell(current.pssAvg.map { "\($0)" })
                weightCell(current.weightDelta)
            }
            .frame(maxWidth: .infinity)

            if let prev = previous {
                VStack(alignment: .center, spacing: 10) {
                    Text("").frame(height: 16)
                    deltaArrow(current.volumeAvgWeek, prev.volumeAvgWeek, higherBetter: true)
                    deltaArrow(current.sessionsCount.map(Double.init), prev.sessionsCount.map(Double.init), higherBetter: true)
                    deltaArrow(current.pssAvg.map(Double.init), prev.pssAvg.map(Double.init), higherBetter: false)
                    Text("").frame(height: 18)
                }
                .frame(width: 40)

                VStack(alignment: .center, spacing: 10) {
                    Text(prev.title ?? "Précédente")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
                        .lineLimit(1).frame(height: 16)
                    valCell(prev.volumeAvgWeek.map { units.format($0, decimals: 0) }, dim: true)
                    valCell(prev.sessionsCount.map { "\($0)" }, dim: true)
                    valCell(prev.pssAvg.map { "\($0)" }, dim: true)
                    weightCell(prev.weightDelta, dim: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func valCell(_ v: String?, dim: Bool = false) -> some View {
        Text(v ?? "—")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(dim ? .gray : .white)
            .frame(height: 18)
    }

    @ViewBuilder private func weightCell(_ delta: Double?, dim: Bool = false) -> some View {
        if let d = delta {
            let sign = d > 0 ? "+" : ""
            let color: Color = dim ? .gray : (d < 0 ? .green : .orange)
            Text("\(sign)\(units.format(d, decimals: 1))")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
                .frame(height: 18)
        } else {
            Text("—").font(.system(size: 13, weight: .bold)).foregroundColor(.gray).frame(height: 18)
        }
    }

    @ViewBuilder private func deltaArrow(_ a: Double?, _ b: Double?, higherBetter: Bool) -> some View {
        if let c = a, let p = b, p != 0 {
            let diff = c - p
            let isGood = higherBetter ? diff > 0 : diff < 0
            let pct = Int(round(abs(diff) / abs(p) * 100))
            let sym = diff > 0 ? "↑" : "↓"
            Text("\(sym)\(pct)%")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(isGood ? .green : .orange)
                .frame(height: 18)
        } else {
            Text("").frame(height: 18)
        }
    }
}

// MARK: - Transformation Markers Card
struct TransformationMarkersCard: View {
    let tombstoneCount: Int
    let warRoomStats: WarRoomSummaryStats?

    var body: some View {
        let showWarRoom = warRoomStats?.warStartDate != nil
        VStack(alignment: .leading, spacing: 12) {
            Text("MARQUEURS DE TRANSFORMATION")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tombstoneCount > 0 ? "\(tombstoneCount)" : "—")
                        .font(.system(size: 30, weight: .black))
                        .foregroundColor(.orange)
                        .contentTransition(.numericText())
                    Text(tombstoneCount == 1 ? "limite enterrée" : "limites enterrées")
                        .font(.system(size: 11)).foregroundColor(.gray)
                    if tombstoneCount == 0 {
                        Text("Continue à logger")
                            .font(.system(size: 9)).foregroundColor(.gray.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.orange.opacity(0.07))
                .cornerRadius(12)

                if showWarRoom, let wr = warRoomStats {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(wr.totalVictories)")
                            .font(.system(size: 30, weight: .black))
                            .foregroundColor(Color(hex: "2ECC71"))
                            .contentTransition(.numericText())
                        Text("jours de victoire")
                            .font(.system(size: 11)).foregroundColor(.gray)
                        Text("Ne descend jamais")
                            .font(.system(size: 9)).foregroundColor(.gray.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(hex: "2ECC71").opacity(0.07))
                    .cornerRadius(12)
                }
            }
        }
        .padding(16).glassCard().cornerRadius(14)
    }
}

// MARK: - Strength Progression 6 months
struct StrengthProgressionCard: View {
    let trend: [String: [OneRMPoint]]
    let weights: [String: WeightData]
    @ObservedObject private var units = UnitSettings.shared

    private struct LiftDelta: Identifiable {
        let id = UUID()
        let name: String
        let current: Double
        let baseline: Double
        var delta: Double { current - baseline }
        var deltaPct: Int { baseline > 0 ? Int(round(delta / baseline * 100)) : 0 }
    }

    private var top5: [LiftDelta] {
        // Top 5 by session count (frequency proxy)
        let sorted = weights.sorted { ($0.value.history?.count ?? 0) > ($1.value.history?.count ?? 0) }
            .prefix(10).map(\.key)
        let cutoff180 = DateFormatter.isoDate.string(from: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 180 * 86400))

        return sorted.compactMap { name -> LiftDelta? in
            guard let pts = trend[name], !pts.isEmpty else { return nil }
            let sorted_pts = pts.sorted { $0.date < $1.date }
            guard let current = sorted_pts.last?.oneRM, current > 0 else { return nil }
            let baseline_pt = sorted_pts.first(where: { $0.date >= cutoff180 }) ?? sorted_pts.first
            guard let baseline = baseline_pt?.oneRM, baseline > 0 else { return nil }
            return LiftDelta(name: name, current: current, baseline: baseline)
        }
        .sorted { abs($0.deltaPct) > abs($1.deltaPct) }
        .prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROGRESSION FORCE — 6 MOIS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            if top5.isEmpty {
                EmptyChartPlaceholder(message: "Continue à logger — activé après 6 mois de données")
            } else {
                let maxCurrent = top5.map(\.current).max() ?? 1
                VStack(spacing: 10) {
                    ForEach(top5) { lift in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(lift.name)
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                let sign = lift.delta >= 0 ? "+" : ""
                                Text("\(sign)\(lift.deltaPct)%")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(lift.delta >= 0 ? .green : .orange)
                            }
                            GeometryReader { g in
                                let w = g.size.width
                                ZStack(alignment: .leading) {
                                    // Baseline bar (gray)
                                    Capsule()
                                        .fill(Color.gray.opacity(0.25))
                                        .frame(width: w * CGFloat(lift.baseline / maxCurrent), height: 8)
                                    // Current bar (amber)
                                    Capsule()
                                        .fill(lift.delta >= 0 ? Color(hex: "F5A623") : .orange)
                                        .frame(width: w * CGFloat(lift.current / maxCurrent), height: 8)
                                        .opacity(0.85)
                                }
                            }
                            .frame(height: 8)
                            HStack {
                                Text("Baseline: \(units.format(lift.baseline, decimals: 0))")
                                    .font(.system(size: 9)).foregroundColor(.gray)
                                Spacer()
                                Text("Actuel: \(units.format(lift.current, decimals: 0))")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Color(hex: "F5A623"))
                            }
                        }
                    }
                }
            }
        }
        .padding(16).glassCard().cornerRadius(14)
    }
}

// MARK: - Top 5 Frequency View
struct Top5FrequencyView: View {
    let weights: [String: WeightData]

    private var top5: [(String, Int)] {
        let cutoff = DateFormatter.isoDate.string(from: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 30 * 86400))
        var counts: [String: Int] = [:]
        for (name, data) in weights {
            let n = (data.history ?? []).filter { ($0.date ?? "") >= cutoff }.count
            if n > 0 { counts[name] = n }
        }
        return counts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP 5 EXERCICES (30J)")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            if top5.isEmpty {
                Text("Pas encore de données").font(.system(size: 12)).foregroundColor(.gray)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(top5.enumerated()), id: \.0) { i, item in
                        HStack(spacing: 10) {
                            Text("\(i + 1)")
                                .font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
                                .frame(width: 16)
                            Text(item.0)
                                .font(.system(size: 13)).foregroundColor(.white).lineLimit(1)
                            Spacer()
                            Text("\(item.1)×")
                                .font(.system(size: 13, weight: .bold)).foregroundColor(.orange)
                        }
                    }
                }
            }
        }
        .padding(16).glassCard().cornerRadius(14)
    }
}

// MARK: - Nutrition vs Performance View
struct NutritionVsPerfView: View {
    let nutritionDays: [NutritionDay]
    let weeklyTonnage: [WeeklyTonnageEntry]
    let target: NutritionSettings?

    private struct WeekPair: Identifiable {
        let id = UUID()
        let weekStart: String
        let adherence: Double  // 0–1
        let volume: Double
    }

    private var pairs: [WeekPair] {
        guard let tgt = target, let tgtCal = tgt.calories, tgtCal > 0 else { return [] }
        // Group nutrition by ISO week
        var nutByWeek: [String: [NutritionDay]] = [:]
        for day in nutritionDays {
            let wk = isoWeekKey(day.date ?? "")
            nutByWeek[wk, default: []].append(day)
        }
        return weeklyTonnage.compactMap { t -> WeekPair? in
            let wk = isoWeekKey(t.weekStart)
            guard let days = nutByWeek[wk], !days.isEmpty else { return nil }
            let adhDays = days.filter {
                guard let cal = $0.calories, cal > 0 else { return false }
                return abs(cal - tgtCal) / tgtCal <= 0.15
            }
            let adh = Double(adhDays.count) / Double(days.count)
            return WeekPair(weekStart: t.weekStart, adherence: adh, volume: t.totalVolume)
        }.sorted { $0.weekStart < $1.weekStart }
    }

    private var insight: String? {
        guard pairs.count >= 4 else { return nil }
        let highAdh = pairs.filter { $0.adherence >= 0.8 }
        let lowAdh  = pairs.filter { $0.adherence < 0.5 }
        guard !highAdh.isEmpty, !lowAdh.isEmpty else { return nil }
        let avgHigh = highAdh.map(\.volume).reduce(0, +) / Double(highAdh.count)
        let avgLow  = lowAdh.map(\.volume).reduce(0, +) / Double(lowAdh.count)
        guard avgLow > 0 else { return nil }
        let diff = Int(round((avgHigh - avgLow) / avgLow * 100))
        if abs(diff) < 5 { return "Pas de corrélation claire entre ta nutrition et ta performance." }
        let dir = diff > 0 ? "mieux" : "moins bien"
        return "Tu t'entraînes \(abs(diff))% \(dir) les semaines avec une bonne adherence macro (>80%)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NUTRITION → PERFORMANCE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            if pairs.count < 4 {
                EmptyChartPlaceholder(message: "Activé après 4 semaines de logs nutrition + workout")
            } else {
                miniDualChart
                if let msg = insight {
                    Text(msg)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16).glassCard().cornerRadius(14)
    }

    @ViewBuilder private var miniDualChart: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let n = pairs.count
            let step = w / CGFloat(max(n - 1, 1))
            let maxVol = pairs.map(\.volume).max() ?? 1

            // Volume line (amber)
            Path { path in
                for (i, p) in pairs.enumerated() {
                    let x = CGFloat(i) * step
                    let y = h * (1 - CGFloat(p.volume / maxVol))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color(hex: "F5A623"), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Adherence line (green)
            Path { path in
                for (i, p) in pairs.enumerated() {
                    let x = CGFloat(i) * step
                    let y = h * (1 - CGFloat(p.adherence))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3]))
        }
        .frame(height: 60)

        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Rectangle().fill(Color(hex: "F5A623")).frame(width: 16, height: 2)
                Text("Volume").font(.system(size: 9)).foregroundColor(.gray)
            }
            HStack(spacing: 4) {
                Rectangle().fill(Color.green).frame(width: 16, height: 2)
                Text("Adherence macros").font(.system(size: 9)).foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Sleep Performance Insight (enriched scatter)
struct SleepPerformanceInsightView: View {
    let scatter: [ScatterPoint]

    private var insight: String? {
        guard scatter.count >= 12 else { return nil }
        let goodSleep = scatter.filter { $0.x >= 7 }
        let poorSleep = scatter.filter { $0.x < 7 }
        guard !goodSleep.isEmpty, !poorSleep.isEmpty else { return nil }
        let avgGood = goodSleep.map(\.y).reduce(0, +) / Double(goodSleep.count)
        let avgPoor = poorSleep.map(\.y).reduce(0, +) / Double(poorSleep.count)
        guard avgPoor > 0 else { return nil }
        let diff = Int(round((avgGood - avgPoor) / avgPoor * 100))
        if abs(diff) < 5 { return "Pas de corrélation significative entre ton sommeil et tes performances." }
        let dir = diff > 0 ? "mieux" : "moins bien"
        return "Tu performes \(abs(diff))% \(dir) les jours après une nuit de qualité ≥ 7/10."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScatterPlotView(
                data: scatter,
                xLabel: "Qualité sommeil J-1 (1–10)",
                yLabel: "Volume séance J",
                title: "SOMMEIL → PERFORMANCE",
                color: .blue
            )
            if let msg = insight {
                Text(msg)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Wellness Trend (3 sparklines)
struct WellnessTrendView: View {
    let recovery: [RecoveryEntry]
    let pssHistory: [PSSRecord]

    private func movingAvg(_ values: [Double], window: Int = 7) -> [Double] {
        values.indices.map { i in
            let start = max(0, i - window + 1)
            let slice = values[start...i]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WELLNESS — TENDANCES 30J")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            if recovery.isEmpty {
                EmptyChartPlaceholder(message: "Logge ta récupération quotidiennement pour voir les tendances")
            } else {
                VStack(spacing: 8) {
                    let sleepVals = recovery.compactMap { $0.sleepQuality.map { Double($0) } }
                    let sorenessVals = recovery.compactMap { $0.soreness.map { Double($0) } }
                    let fatigueVals = recovery.compactMap { $0.fatigue.map { Double($0) } }

                    if !sleepVals.isEmpty {
                        WellnessSparkline(label: "Sommeil", values: movingAvg(sleepVals), color: .blue, range: 1...10)
                    }
                    if !sorenessVals.isEmpty {
                        WellnessSparkline(label: "Douleurs", values: movingAvg(sorenessVals), color: .orange, range: 1...10, invertTrend: true)
                    }
                    if !fatigueVals.isEmpty {
                        WellnessSparkline(label: "Fatigue", values: movingAvg(fatigueVals), color: .purple, range: 1...10, invertTrend: true)
                    }
                }
            }
        }
        .padding(16).glassCard().cornerRadius(14)
    }
}

private struct WellnessSparkline: View {
    let label: String
    let values: [Double]
    let color: Color
    let range: ClosedRange<Double>
    var invertTrend: Bool = false

    private var trend: Color {
        guard values.count >= 7 else { return .gray }
        let recent = Array(values.suffix(7)).reduce(0, +) / 7
        let earlier = Array(values.prefix(7)).reduce(0, +) / 7
        let diff = recent - earlier
        if abs(diff) < 0.3 { return .gray }
        let isGood = invertTrend ? diff < 0 : diff > 0
        return isGood ? .green : .red
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11)).foregroundColor(.gray)
                .frame(width: 56, alignment: .leading)

            GeometryReader { g in
                let w = g.size.width
                let h = g.size.height
                let step = w / CGFloat(max(values.count - 1, 1))
                let span = range.upperBound - range.lowerBound

                Path { path in
                    for (i, v) in values.enumerated() {
                        let x = CGFloat(i) * step
                        let y = h * (1 - CGFloat((v - range.lowerBound) / span))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .frame(height: 28)

            if let last = values.last {
                Text(String(format: "%.1f", last))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(trend)
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }
}

// MARK: - Best Day of Week
struct BestDayOfWeekView: View {
    let sessions: [String: SessionEntry]
    let weights: [String: WeightData]

    private let dayNames = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    private var volumeByDow: [Int: Double] {
        let cutoff = DateFormatter.isoDate.string(from: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 90 * 86400))
        var totals: [Int: Double] = [:]
        var counts: [Int: Int] = [:]
        for (dateStr, _) in sessions {
            guard dateStr >= cutoff,
                  let date = DateFormatter.isoDate.date(from: dateStr) else { continue }
            let dow = (Calendar.current.component(.weekday, from: date) + 5) % 7 // 0=Mon
            let vol = weights.values.flatMap { $0.history ?? [] }.filter { $0.date == dateStr }
                .compactMap { e -> Double? in
                    if let v = e.exerciseVolume, v > 0 { return v }
                    guard let w = e.weight, let r = e.reps else { return nil }
                    return w * totalReps(r)
                }.reduce(0, +)
            totals[dow, default: 0] += vol
            counts[dow, default: 0] += 1
        }
        var avgs: [Int: Double] = [:]
        for d in 0..<7 {
            let c = counts[d, default: 0]
            avgs[d] = c > 0 ? (totals[d] ?? 0) / Double(c) : 0
        }
        return avgs
    }

    private var bestDow: Int? {
        volumeByDow.max(by: { $0.value < $1.value })?.key
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MEILLEUR JOUR DE LA SEMAINE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let best = bestDow {
                    Text("→ \(dayNames[best])")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.orange)
                }
            }
            let vols = volumeByDow
            let maxV = vols.values.max() ?? 1
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7, id: \.self) { d in
                    let v = vols[d] ?? 0
                    let isBest = d == bestDow
                    VStack(spacing: 3) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isBest ? Color.orange : Color.orange.opacity(0.3))
                            .frame(height: max(CGFloat(maxV > 0 ? v / maxV : 0) * 60, 3))
                        Text(dayNames[d])
                            .font(.system(size: 9)).foregroundColor(isBest ? .orange : .gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 70)
                }
            }
            .frame(height: 70)
        }
        .padding(16).glassCard().cornerRadius(14)
    }
}

// MARK: - Stress → Cravings Insight (War Room)
struct StressCravingsInsightView: View {
    let pssHistory: [PSSRecord]
    let warRoomStats: WarRoomSummaryStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.orange).font(.system(size: 11))
                Text("STRESS → DÉCLENCHEURS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            }
            Text(insightText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).glassCard(color: .orange, intensity: 0.04).cornerRadius(14)
    }

    private var insightText: String {
        guard pssHistory.count >= 3 else {
            return "Continue à logger ton stress — cette stat s'active après quelques enregistrements."
        }
        let scores = pssHistory.compactMap { $0.score }
        let median = scores.sorted()[scores.count / 2]
        let highStress = pssHistory.filter { ($0.score ?? 0) > median }
        if highStress.isEmpty {
            return "Pas encore assez de données pour détecter un pattern stress → déclencheurs."
        }
        return "Tes niveaux de stress élevés (PSS > \(median)) coïncident souvent avec tes journées les plus difficiles. Reste vigilant."
    }
}

