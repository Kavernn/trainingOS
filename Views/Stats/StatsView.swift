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
    let y = Calendar.current.component(.yearForWeekOfYear, from: d)
    let w = Calendar.current.component(.weekOfYear, from: d)
    return String(format: "%04d-W%02d", y, w)
}

private func weekLabel(_ key: String) -> String {
    let parts = key.split(separator: "-")
    guard parts.count == 2,
          let year = Int(parts[0]),
          let week = Int(parts[1].dropFirst()) else { return key }
    var c = DateComponents(); c.yearForWeekOfYear = year; c.weekOfYear = week; c.weekday = 2
    guard let d = Calendar.current.date(from: c) else { return key }
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

    var currentStreak: Int {
        let fmt = DateFormatter.isoDate
        let base = Date().timeIntervalSince1970
        var count = 0
        for i in 0..<365 {
            let key = fmt.string(from: Date(timeIntervalSince1970: base - Double(i) * 86400.0))
            if sessions[key] != nil { count += 1 }
            else if i == 0 { /* today not yet logged — keep looking */ }
            else { break }
        }
        return count
    }

    var bestStreak: Int {
        let sorted = sessions.keys.compactMap { DateFormatter.isoDate.date(from: $0) }.sorted()
        guard !sorted.isEmpty else { return 0 }
        var best = 1; var cur = 1
        for i in 1..<sorted.count {
            let diff = Int(round((sorted[i].timeIntervalSince1970 - sorted[i-1].timeIntervalSince1970) / 86400.0))
            if diff == 1 { cur += 1; best = max(best, cur) } else { cur = 1 }
        }
        return best
    }

    var weeklyVolume: Double {
        let weekday = Calendar.current.component(.weekday, from: Date()) // Sun=1, Mon=2..Sat=7
        let daysSinceMonday = (weekday + 5) % 7
        let monday = Date(timeIntervalSince1970: Date().timeIntervalSince1970 - Double(daysSinceMonday) * 86400.0)
        let mondayStr = DateFormatter.isoDate.string(from: monday)
        return weights.values.flatMap { $0.history ?? [] }.compactMap { e -> Double? in
            guard let date = e.date, date >= mondayStr else { return nil }
            if let vol = e.exerciseVolume, vol > 0 { return vol }
            guard let w = e.weight, let r = e.reps else { return nil }
            return w * totalReps(r)
        }.reduce(0, +)
    }

    var exercisesCount: Int { weights.filter { $0.value.history?.isEmpty == false }.count }

    // ── Personal Records ─────────────────────────────────────────────
    var personalRecords: [(String, Double)] {
        weights.compactMap { name, data -> (String, Double)? in
            // Bodyweight exercises have no meaningful 1RM (load varies with body weight)
            if inventoryTypes[name] == "bodyweight" { return nil }
            let best = data.history?.compactMap { e -> Double? in
                if let stored = e.oneRM, stored > 0 { return stored }
                guard let w = e.weight, w > 0, let r = e.reps else { return nil }
                let avg = avgReps(r); guard avg > 0 else { return nil }
                return w * (1 + avg / 30.0)
            }.max()
            return best.map { (name, $0) }
        }
        .sorted { $0.1 > $1.1 }
        .prefix(10).map { $0 }
    }

    // ── Weekly charts ─────────────────────────────────────────────────
    private var last8Weeks: [String] {
        var result: [String] = []
        var date = Date()
        for _ in 0..<8 {
            let y = Calendar.current.component(.yearForWeekOfYear, from: date)
            let w = Calendar.current.component(.weekOfYear, from: date)
            result.append(String(format: "%04d-W%02d", y, w))
            date = Date(timeIntervalSince1970: date.timeIntervalSince1970 - 7 * 86400.0)
        }
        return result.reversed()
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
    private func weekBounds(weeksAgo: Int) -> (String, String) {
        let cal = Calendar.current
        let today = Date()
        let daysSinceMonday = (cal.component(.weekday, from: today) + 5) % 7
        let monday = Date(timeIntervalSince1970: today.timeIntervalSince1970 - Double(daysSinceMonday + weeksAgo * 7) * 86400)
        let sunday = Date(timeIntervalSince1970: monday.timeIntervalSince1970 + 6 * 86400)
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
                insights.append(("arrow.up.circle.fill", "Fréquence +\(pct)% vs 4 semaines précédentes", .green))
            } else if pct <= -15 {
                insights.append(("arrow.down.circle.fill", "Fréquence \(pct)% vs 4 semaines précédentes", .orange))
            }
        }
        if let a = acwr, a.zone.code == "risk" || a.zone.code == "danger" {
            insights.append(("exclamationmark.triangle.fill", "ACWR \(String(format: "%.2f", a.ratio)) — charge élevée, récupère", .red))
        }
        if currentStreak > 0 && currentStreak < bestStreak && currentStreak >= bestStreak - 2 {
            insights.append(("flame.fill", "À \(bestStreak - currentStreak) séance(s) de ton meilleur streak !", .orange))
        } else if currentStreak >= 7 {
            insights.append(("flame.fill", "Streak de \(currentStreak) jours — continue !", .orange))
        }
        return Array(insights.prefix(3))
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
                    ProgressView().tint(.orange).scaleEffect(1.3)
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

                        if selectedTab < 4 {
                            PeriodPicker(selected: $period)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                if selectedTab == 0, !smartInsights.isEmpty {
                                    SmartInsightsBanner(insights: smartInsights)
                                        .padding(.horizontal, 16)
                                }
                                if selectedTab == 0 { vueGlobaleTab }
                                else if selectedTab == 1 { performanceTab }
                                else if selectedTab == 2 { corpsTab }
                                else if selectedTab == 3 { nutritionTab }
                                else { exercicesTab }
                            }
                            .padding(.vertical, 8)
                        }
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
        let fs = filteredSessions
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            KPICard(value: "\(fs.count)",   label: "Séances",    color: .orange)
            KPICard(value: "\(sessionsThisMonth)", label: "Ce mois",  color: .blue)
            KPICard(value: currentStreak > 0 ? "\(currentStreak)🔥" : "0", label: "Streak", color: .red)
            KPICard(value: avgRPEPeriod > 0 ? String(format: "%.1f", avgRPEPeriod) : "—", label: "RPE moy.", color: .purple)
            KPICard(value: weeklyVolume > 0 ? formatK(weeklyVolume) : "—", label: "Vol. sem.", color: .green)
            KPICard(value: "\(exercisesCount)", label: "Exercices", color: .cyan)
        }
        .padding(.horizontal, 16)
        .appearAnimation(delay: 0.05)

        SessionHeatmapView(
            sessions: sessions,
            hiitDates: Set(hiitLog.compactMap(\.date).map { String($0.prefix(10)) }),
            bestStreak: bestStreak
        )
        .padding(.horizontal, 16)

        if !personalRecords.isEmpty {
            PersonalRecordsView(records: personalRecords)
                .padding(.horizontal, 16)
        }

        WeekComparisonCard(
            thisWeekSessions: thisWeekSessions, lastWeekSessions: lastWeekSessions,
            thisWeekVolume: thisWeekVolume,     lastWeekVolume: lastWeekVolume,
            thisWeekAvgRPE: thisWeekAvgRPE,     lastWeekAvgRPE: lastWeekAvgRPE
        )
        .padding(.horizontal, 16)

        BadgesView(badges: earnedBadges)
            .padding(.horizontal, 16)

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

        if !top5Volume.isEmpty {
            Top5VolumeView(data: top5Volume)
                .padding(.horizontal, 16)
        }

        if !muscleStats.isEmpty {
            MuscleBreakdownView(stats: muscleStats)
                .padding(.horizontal, 16)
        }

        if !muscleLandmarks.isEmpty {
            VolumeLandmarksCard(landmarks: muscleLandmarks)
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }

    @ViewBuilder private var performanceTab: some View {
        if let acwrData = acwr {
            ACWRCardView(data: acwrData)
                .padding(.horizontal, 16)
        }

        if rpeHistory.count >= 3 {
            RPEChartView(data: rpeHistory)
                .padding(.horizontal, 16)
        } else {
            EmptyChartPlaceholder(message: "Logge au moins 3 séances avec RPE pour voir la tendance")
                .padding(.horizontal, 16)
        }

        let sessionsWithDuration = filteredSessions.filter { $0.value.durationMin != nil }
        if sessionsWithDuration.count >= 2 {
            TrainingLoadChart(sessions: filteredSessions, last8Weeks: last8Weeks)
                .padding(.horizontal, 16)
        }

        let sessionsWithEnergy = filteredSessions.compactMap { d, e -> (String, Int)? in
            e.energyPre.map { (d, $0) }
        }.sorted { $0.0 < $1.0 }.suffix(20).map { $0 }
        if sessionsWithEnergy.count >= 3 {
            EnergyTrendView(data: sessionsWithEnergy)
                .padding(.horizontal, 16)
        }

        if filteredSessions.count >= 5 {
            RPEDistributionView(sessions: filteredSessions)
                .padding(.horizontal, 16)
        }

        if !muscleStats.isEmpty {
            MuscleVolumeView(stats: muscleStats)
                .padding(.horizontal, 16)
        }

        Spacer(minLength: 32)
    }

    @ViewBuilder private var corpsTab: some View {
        let filteredBW = filteredBodyWeight
        if filteredBW.count >= 2 {
            WeightChartView(entries: Array(filteredBW.prefix(20).reversed()))
                .padding(.horizontal, 16)
        } else {
            EmptyChartPlaceholder(message: "Logge au moins 2 pesées pour voir la courbe de poids")
                .padding(.horizontal, 16)
        }

        if filteredBW.filter({ $0.waistCm != nil || $0.armsCm != nil }).count >= 2 {
            MeasurementsTrendView(entries: Array(filteredBW.prefix(20).reversed()))
                .padding(.horizontal, 16)
        }

        if filteredRecovery.count >= 3 {
            RecoveryScoreChart(log: Array(filteredRecovery.prefix(14).reversed()))
                .padding(.horizontal, 16)
        }

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
        } else {
            VStack(spacing: 12) {
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 40)).foregroundColor(.gray)
                Text("Pas assez de données nutrition")
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }

        Spacer(minLength: 32)
    }

    @ViewBuilder private var exercicesTab: some View {
        if !weights.isEmpty {
            PRTrackerView(weights: weights)
                .padding(.horizontal, 16)
        }

        if !top5Volume.isEmpty {
            Top5VolumeView(data: top5Volume)
                .padding(.horizontal, 16)
        }

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
            .background(Color(hex: "11111c")).cornerRadius(12)
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

    // Local decodable mirror of the stats response (StatsResponse in APIService is private)
    private struct StatsAPIResponse: Codable {
        let weights:         [String: WeightData]
        let sessions:        [String: SessionEntry]
        let hiitLog:         [HIITEntry]
        let bodyWeight:      [BodyWeightEntry]
        let recoveryLog:     [RecoveryEntry]
        let nutritionTarget: NutritionSettings?
        let nutritionDays:   [NutritionDay]
        let muscleStats:     [String: MuscleStatEntry]
        let inventoryTypes:  [String: String]?
        let muscleLandmarks: [String: MuscleLandmark]?
        enum CodingKeys: String, CodingKey {
            case weights, sessions
            case hiitLog         = "hiit_log"
            case bodyWeight      = "body_weight"
            case recoveryLog     = "recovery_log"
            case nutritionTarget = "nutrition_target"
            case nutritionDays   = "nutrition_days"
            case muscleStats     = "muscle_stats"
            case inventoryTypes  = "inventory_types"
            case muscleLandmarks = "muscle_landmarks"
        }
    }

    private func applyStats(_ r: StatsAPIResponse) {
        weights         = r.weights
        sessions        = r.sessions
        hiitLog         = r.hiitLog
        bodyWeight      = r.bodyWeight
        recoveryLog     = r.recoveryLog
        nutritionTarget = r.nutritionTarget
        nutritionDays   = r.nutritionDays
        muscleStats     = r.muscleStats
        inventoryTypes  = r.inventoryTypes ?? [:]
        muscleLandmarks = r.muscleLandmarks ?? [:]
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
        async let acwrTask = APIService.shared.fetchACWR()
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let decoded = try? JSONDecoder().decode(StatsAPIResponse.self, from: data) {
            CacheService.shared.save(data, for: "stats_data")
            applyStats(decoded)
        } else if weights.isEmpty {
            // No cache and network failed → show error state
            fetchError = true
        }
        acwr = try? await acwrTask
        isLoading = false
        // Schedule contextual notifications (inactivity + streak milestones)
        NotificationService.scheduleContextual(
            sessionDates: Array(sessions.keys),
            currentStreak: currentStreak
        )
    }
}

// MARK: - ACWR Card
struct ACWRCardView: View {
    let data: ACWRData

    private var zoneColor: Color {
        switch data.zone.code {
        case "optimal": return .green
        case "risk":    return .orange
        case "danger":  return .red
        case "under":   return .blue
        default:        return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACWR — CHARGE AIGUË/CHRONIQUE")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            HStack(alignment: .top, spacing: 16) {
                // Big ratio
                VStack(alignment: .leading, spacing: 4) {
                    Text(data.ratio > 0 ? String(format: "%.2f", data.ratio) : "—")
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

                // Loads
                VStack(alignment: .trailing, spacing: 6) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Aiguë (7j)").font(.system(size: 10)).foregroundColor(.gray)
                        Text("\(data.acuteLoad, specifier: "%.0f")")
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Chronique (28j)").font(.system(size: 10)).foregroundColor(.gray)
                        Text("\(data.chronicLoad, specifier: "%.0f")")
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    }
                }
            }

            // Recommendation
            if !data.zone.recommendation.isEmpty {
                Text(data.zone.recommendation)
                    .font(.system(size: 12)).foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 8-week trend sparkline
            if data.trend.count > 1 {
                ACWRSparkline(trend: data.trend)
            }
        }
        .padding(16).glassCard(color: zoneColor, intensity: 0.05).cornerRadius(14)
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
        .background(Color(hex: "11111c"))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CETTE SEMAINE VS DERNIÈRE")
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
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(hex: "191926")).frame(height: 6)
                                Capsule()
                                    .fill(prColor(i))
                                    .frame(width: geo.size.width * (record.1 / maxORM), height: 6)
                            }
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

            VStack(spacing: 8) {
                ForEach(Array(data.enumerated()), id: \.0) { i, item in
                    HStack(spacing: 10) {
                        Text(item.0)
                            .font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                            .lineLimit(1).frame(width: 120, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(hex: "191926")).frame(height: 8)
                                Capsule()
                                    .fill(barColor(i))
                                    .frame(width: geo.size.width * (item.1 / maxVol), height: 8)
                            }
                        }
                        .frame(height: 8)
                        Text(formatK(item.1))
                            .font(.system(size: 11, weight: .bold)).foregroundColor(barColor(i))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
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
                .padding(12).background(Color(hex: "11111c")).cornerRadius(10)
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
        .padding(16).background(Color(hex: "11111c")).cornerRadius(14)
    }

    private func rpeColor(_ rpe: Double) -> Color {
        if rpe >= 8 { return .red }; if rpe >= 6 { return .orange }; return .green
    }
}

// MARK: - KPI Card
struct KPICard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .black)).foregroundColor(color)
                .contentTransition(.numericText()).minimumScaleFactor(0.6).lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .medium)).tracking(1).foregroundColor(.gray)
                .lineLimit(1)
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                if let reps = data.lastReps {
                    Text(reps).font(.system(size: 12)).foregroundColor(.gray)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let w = data.currentWeight {
                    Text(units.format(w))
                        .font(.system(size: 16, weight: .black)).foregroundColor(.orange)
                }
                if let history = data.history, history.count > 1,
                   let first = history.last?.weight, let last = history.first?.weight {
                    let diff = last - first
                    Text(diff >= 0 ? "+\(diff, specifier: "%.1f")" : "\(diff, specifier: "%.1f")")
                        .font(.system(size: 11)).foregroundColor(diff >= 0 ? .green : .red)
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
                Color(hex: "080810").ignoresSafeArea()
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
                            .padding(16).background(Color(hex: "11111c")).cornerRadius(14)
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .navigationTitle(name).navigationBarTitleDisplayMode(.large)
            .keyboardOkButton()
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
        .padding(16).background(Color(hex: "11111c")).cornerRadius(14)
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
                        .stroke(Color.indigo, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

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
        }
        .padding(16).glassCard(color: .indigo, intensity: 0.05).cornerRadius(14)
    }
}

// MARK: - Nutrition Compliance
struct NutritionComplianceChart: View {
    let days: [NutritionDay]
    let target: NutritionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMPLIANCE NUTRITION — 7 JOURS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            let targetCal = target.calories ?? 2000
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(days.suffix(7)) { day in
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
        .padding(16).background(Color(hex: "11111c")).cornerRadius(14)
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
        .padding(16).background(Color(hex: "11111c")).cornerRadius(14)
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
                Text("Pas assez de données")
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
        .padding(16).background(Color(hex: "11111c")).cornerRadius(14)
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
        return Calendar.current.dateComponents([.day], from: d, to: Date()).day
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

            VStack(spacing: 8) {
                ForEach(sorted, id: \.0) { muscle, entry in
                    HStack(spacing: 10) {
                        Text(muscle.capitalized)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 110, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.06))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(freshnessColor(daysSince(entry.lastDate)).opacity(0.7))
                                    .frame(width: geo.size.width * CGFloat(entry.volume / maxVolume))
                            }
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
        let cal = Calendar.current
        let now = Date()
        return weights.compactMap { name, data -> PREntry? in
            guard let history = data.history, !history.isEmpty else { return nil }
            guard let best = history.max(by: { ($0.weight ?? 0) < ($1.weight ?? 0) }),
                  let w = best.weight, w > 0, let date = best.date else { return nil }
            let isRecent: Bool
            if let d = DateFormatter.isoDate.date(from: date) {
                isRecent = cal.dateComponents([.day], from: d, to: now).day ?? 99 <= 30
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
                Text("Aucune donnée disponible")
                    .font(.system(size: 13)).foregroundColor(.gray).italic()
            } else {
                let maxW = prs.map(\.prWeight).max() ?? 1
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
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(hex: "191926")).frame(height: 6)
                                    Capsule()
                                        .fill(pr.isRecent ? Color.yellow : Color.orange.opacity(0.6))
                                        .frame(width: geo.size.width * (pr.prWeight / maxW), height: 6)
                                }
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
        }
        .padding(16)
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
    }
}

// MARK: - Protein Compliance

struct ProteinComplianceView: View {
    let days: [NutritionDay]
    let target: NutritionSettings

    private var protTarget: Double { target.proteines ?? 160 }

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
        .background(Color(hex: "11111c"))
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
                Text("Aucune donnée disponible")
                    .font(.system(size: 13)).foregroundColor(.gray).italic()
            } else {
                let maxVol = sorted.first?.1 ?? 1
                VStack(spacing: 8) {
                    ForEach(sorted, id: \.0) { muscle, volume in
                        HStack(spacing: 10) {
                            Text(muscle.capitalized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .frame(width: 110, alignment: .leading)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(hex: "191926")).frame(height: 6)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue.opacity(0.9), Color.blue.opacity(0.5)],
                                                startPoint: .leading, endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geo.size.width * (volume / maxVol), height: 6)
                                }
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
        }
        .padding(16)
        .background(Color(hex: "11111c"))
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
        case .underMEV:       return "< MEV"
        case .optimal:        return "optimal"
        case .approachingMRV: return "→ MRV"
        case .overMRV:        return "> MRV"
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
                legendDot(.blue,   "< MEV")
                legendDot(.green,  "Optimal")
                legendDot(.orange, "→ MRV")
                legendDot(.red,    "> MRV")
            }

            VStack(spacing: 7) {
                ForEach(sorted, id: \.0) { muscle, lm in
                    HStack(spacing: 8) {
                        Text(muscle.capitalized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 100, alignment: .leading)
                            .lineLimit(1)

                        // Progress bar: filled to weekly_sets/mrv, marker at MEV and MAV
                        GeometryReader { geo in
                            let w = geo.size.width
                            let ratio = min(Double(lm.weeklySets) / Double(lm.mrv), 1.2)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(zoneColor(lm.zone).opacity(0.8))
                                    .frame(width: min(w * ratio, w), height: 8)
                                // MEV marker
                                Rectangle()
                                    .fill(Color.white.opacity(0.4))
                                    .frame(width: 1, height: 12)
                                    .offset(x: w * Double(lm.mev) / Double(lm.mrv))
                                // MAV marker
                                Rectangle()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(width: 1, height: 12)
                                    .offset(x: min(w * Double(lm.mav) / Double(lm.mrv), w - 1))
                            }
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
        ("chart.bar.fill",  "Global"),
        ("bolt.fill",       "Perf"),
        ("figure.stand",    "Corps"),
        ("fork.knife",      "Nutrition"),
        ("dumbbell.fill",   "Exercices"),
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
        .background(Color(hex: "11111c"))
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
        .background(Color(hex: "11111c"))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.25), lineWidth: 1))
    }
}
