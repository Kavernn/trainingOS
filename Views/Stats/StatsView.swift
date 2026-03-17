import SwiftUI

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
    @State private var muscleStats:      [String: MuscleStatEntry] = [:]
    @State private var isLoading    = true
    @State private var selectedExercise: String? = nil
    @State private var searchText   = ""

    // ── KPIs ────────────────────────────────────────────────────────
    var totalSessions: Int { sessions.count }

    var sessionsThisMonth: Int {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"
        let key = fmt.string(from: Date())
        return sessions.keys.filter { $0.hasPrefix(key) }.count
    }

    var avgRPE30: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let cutStr = DateFormatter.isoDate.string(from: cutoff)
        let rpes = sessions.compactMap { date, e -> Double? in
            date >= cutStr ? e.rpe : nil
        }
        return rpes.isEmpty ? 0 : rpes.reduce(0, +) / Double(rpes.count)
    }

    var currentStreak: Int {
        var count = 0; var date = Date()
        while true {
            let key = DateFormatter.isoDate.string(from: date)
            if sessions[key] != nil { count += 1 }
            else if count == 0 { }
            else { break }
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
            if count > 365 { break }
        }
        return count
    }

    var bestStreak: Int {
        let sorted = sessions.keys.compactMap { DateFormatter.isoDate.date(from: $0) }.sorted()
        guard !sorted.isEmpty else { return 0 }
        var best = 1; var cur = 1
        for i in 1..<sorted.count {
            let diff = Calendar.current.dateComponents([.day], from: sorted[i-1], to: sorted[i]).day ?? 0
            if diff == 1 { cur += 1; best = max(best, cur) } else { cur = 1 }
        }
        return best
    }

    var weeklyVolume: Double {
        let monday = Calendar.current.date(from: {
            var c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            c.weekday = 2; return c
        }())!
        let mondayStr = DateFormatter.isoDate.string(from: monday)
        return weights.values.flatMap { $0.history ?? [] }.compactMap { e -> Double? in
            guard let date = e.date, date >= mondayStr,
                  let w = e.weight, let r = e.reps else { return nil }
            return w * totalReps(r)
        }.reduce(0, +)
    }

    var exercisesCount: Int { weights.filter { $0.value.history?.isEmpty == false }.count }

    // ── Personal Records ─────────────────────────────────────────────
    var personalRecords: [(String, Double)] {
        weights.compactMap { name, data -> (String, Double)? in
            let best = data.history?.compactMap { e -> Double? in
                guard let w = e.weight, let r = e.reps else { return nil }
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
            date = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: date)!
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
                guard let date = e.date, let w = e.weight, let r = e.reps else { continue }
                vols[isoWeekKey(date), default: 0] += w * totalReps(r)
            }
        }
        return last8Weeks.map { ($0, vols[$0] ?? 0) }
    }

    // ── Top 5 volume ─────────────────────────────────────────────────
    var top5Volume: [(String, Double)] {
        weights.compactMap { name, data -> (String, Double)? in
            let vol = data.history?.compactMap { e -> Double? in
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

    // ── Body ─────────────────────────────────────────────────────────
    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .blue)
                if isLoading {
                    ProgressView().tint(.orange).scaleEffect(1.3)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {

                            // KPIs
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                KPICard(value: "\(totalSessions)",   label: "Séances",    color: .orange)
                                KPICard(value: "\(sessionsThisMonth)", label: "Ce mois",  color: .blue)
                                KPICard(value: currentStreak > 0 ? "\(currentStreak)🔥" : "0", label: "Streak", color: .red)
                                KPICard(value: avgRPE30 > 0 ? String(format: "%.1f", avgRPE30) : "—", label: "RPE 30j", color: .purple)
                                KPICard(value: weeklyVolume > 0 ? formatK(weeklyVolume) : "—", label: "Vol. sem.", color: .green)
                                KPICard(value: "\(exercisesCount)", label: "Exercices", color: .cyan)
                            }
                            .padding(.horizontal, 16)
                            .appearAnimation(delay: 0.05)

                            // Heatmap
                            SessionHeatmapView(sessions: sessions, bestStreak: bestStreak)
                                .padding(.horizontal, 16)

                            // Personal Records
                            if !personalRecords.isEmpty {
                                PersonalRecordsView(records: personalRecords)
                                    .padding(.horizontal, 16)
                            }

                            // Weekly charts
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

                            // Top 5 volume
                            if !top5Volume.isEmpty {
                                Top5VolumeView(data: top5Volume)
                                    .padding(.horizontal, 16)
                            }

                            // Muscle breakdown
                            if !muscleStats.isEmpty {
                                MuscleBreakdownView(stats: muscleStats)
                                    .padding(.horizontal, 16)
                            }

                            // RPE chart
                            if rpeHistory.count >= 3 {
                                RPEChartView(data: rpeHistory)
                                    .padding(.horizontal, 16)
                            }

                            // HIIT stats
                            if !hiitLog.isEmpty {
                                HIITStatsSection(log: hiitLog)
                                    .padding(.horizontal, 16)
                            }

                            // Body weight curve
                            if bodyWeight.count >= 2 {
                                WeightChartView(entries: Array(bodyWeight.prefix(20).reversed()))
                                    .padding(.horizontal, 16)
                            }

                            // Body measurements trend
                            if bodyWeight.filter({ $0.waistCm != nil || $0.armsCm != nil }).count >= 2 {
                                MeasurementsTrendView(entries: Array(bodyWeight.prefix(20).reversed()))
                                    .padding(.horizontal, 16)
                            }

                            // Training load (RPE × durée)
                            let sessionsWithDuration = sessions.filter { $0.value.durationMin != nil }
                            if sessionsWithDuration.count >= 2 {
                                TrainingLoadChart(sessions: sessions, last8Weeks: last8Weeks)
                                    .padding(.horizontal, 16)
                            }

                            // Energy pré-séance trend
                            let sessionsWithEnergy = sessions.compactMap { d, e -> (String, Int)? in
                                e.energyPre.map { (d, $0) }
                            }.sorted { $0.0 < $1.0 }.suffix(20).map { $0 }
                            if sessionsWithEnergy.count >= 3 {
                                EnergyTrendView(data: sessionsWithEnergy)
                                    .padding(.horizontal, 16)
                            }

                            // Recovery score trend
                            if recoveryLog.count >= 3 {
                                RecoveryScoreChart(log: Array(recoveryLog.prefix(14).reversed()))
                                    .padding(.horizontal, 16)
                            }

                            // ACWR — Acute:Chronic Workload Ratio
                            if let acwrData = acwr {
                                ACWRCardView(data: acwrData)
                                    .padding(.horizontal, 16)
                            }

                            // Nutrition compliance
                            if nutritionDays.count >= 3, let target = nutritionTarget {
                                NutritionComplianceChart(days: nutritionDays, target: target)
                                    .padding(.horizontal, 16)
                            }

                            // RPE distribution
                            if sessions.count >= 5 {
                                RPEDistributionView(sessions: sessions)
                                    .padding(.horizontal, 16)
                            }

                            // Exercise list
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
                        .padding(.vertical, 16)
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

    private func formatK(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return String(format: "%.0f", v)
    }

    private func loadData() async {
        isLoading = true
        async let statsTask = APIService.shared.fetchStatsData()
        async let acwrTask  = APIService.shared.fetchACWR()
        if let r = try? await statsTask {
            weights = r.weights; sessions = r.sessions
            hiitLog = r.hiitLog; bodyWeight = r.bodyWeight
            recoveryLog = r.recoveryLog
            nutritionTarget = r.nutritionTarget
            nutritionDays = r.nutritionDays
            muscleStats = r.muscleStats
        }
        acwr = try? await acwrTask
        isLoading = false
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

// MARK: - Heatmap (updated with streak stats)
struct SessionHeatmapView: View {
    let sessions: [String: SessionEntry]
    var bestStreak: Int = 0
    private let days = 90

    private var cells: [(String, Bool)] {
        (0..<days).reversed().map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            let key = DateFormatter.isoDate.string(from: date)
            return (key, sessions[key] != nil)
        }
    }

    var activeDays: Int { cells.filter(\.1).count }

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
                ForEach(cells, id: \.0) { _, has in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(has ? Color.orange : Color(hex: "191926"))
                        .frame(height: 16)
                }
            }
            HStack {
                Text("\(activeDays) séances").font(.system(size: 11)).foregroundColor(.gray)
                Spacer()
                Text("\(Int(Double(activeDays) / 90.0 * 100))% actif").font(.system(size: 11)).foregroundColor(.orange)
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
                            let vals = history.compactMap(\.weight)
                            if vals.count >= 2 {
                                ExerciseProgressChart(values: vals).padding(.horizontal, 16)
                            }
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

// MARK: - Exercise Progress Chart
struct ExerciseProgressChart: View {
    let values: [Double]
    var minVal: Double { values.min() ?? 0 }
    var maxVal: Double { max(values.max() ?? 0, minVal + 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROGRESSION")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            GeometryReader { geo in
                let count = values.count
                guard count >= 2 else { return AnyView(EmptyView()) }
                let step = geo.size.width / CGFloat(count - 1)
                return AnyView(
                    Path { path in
                        for (i, val) in values.enumerated() {
                            let x = CGFloat(i) * step
                            let y = geo.size.height * (1 - (val - minVal) / (maxVal - minVal))
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                )
            }
            .frame(height: 60)
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
