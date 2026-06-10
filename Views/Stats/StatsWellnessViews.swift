import SwiftUI

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
                        .stroke(AppTheme.shared.selectedTheme == .monochrome ? Color.white : Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

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
                    Text("Dernière:").font(.appCaption).foregroundColor(.gray)
                    Text(String(format: "%.1f / 10", s))
                        .font(.appCaption.weight(.bold))
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

// MARK: - Recovery Composite Score View
struct RecoveryCompositeScoreView: View {
    let log: [RecoveryEntry]
    @AppStorage("steps_daily_goal") private var stepsGoal: Int = 10000

    private enum ComponentStatus { case green, yellow, red }

    private func score(_ r: RecoveryEntry) -> Double? {
        var components: [(Double, Double)] = []
        if let sh = r.sleepHours  { components.append((min(sh / 8.0, 1.0), 0.30)) }
        if let sq = r.sleepQuality { components.append((sq / 10.0, 0.20)) }
        if let s  = r.soreness     { components.append(((11.0 - s) / 10.0, 0.20)) }
        if let h  = r.hrv          { components.append((min(h / 80.0, 1.0), 0.20)) }
        if let st = r.steps.map(Double.init) { components.append((min(st / Double(stepsGoal), 1.0), 0.10)) }
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
                        .stroke(AppTheme.shared.selectedTheme == .monochrome ? Color.white.opacity(0.6) : Color.teal, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

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
                        .foregroundColor(Color.forge)
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
                Text(xLabel).font(.appMicro).foregroundColor(.gray)
                Spacer()
                Text(yLabel).font(.appMicro).foregroundColor(.gray)
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
                        Text("Humeur").font(.appMicro.weight(.semibold)).foregroundColor(.purple)
                        Spacer()
                        Text(String(format: "Moy. %.1f / 10", avgMood))
                            .font(.appMicro).foregroundColor(.purple.opacity(0.7))
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
                        Text("Score bien-être").font(.appMicro.weight(.semibold)).foregroundColor(Color.forge)
                        Text("(100 = optimal)").font(.system(size: 8)).foregroundColor(.gray.opacity(0.6))
                        Spacer()
                        Text(String(format: "Moy. %.0f / 100", avgStress))
                            .font(.appMicro).foregroundColor(Color.forge.opacity(0.7))
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
                            .stroke(Color.forge, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        }
                    }
                    .frame(height: 55)
                }
            }

            HStack(spacing: 12) {
                Label("Humeur (1–10)", systemImage: "circle.fill").font(.appMicro).foregroundColor(.purple)
                Label("Bien-être (0–100)", systemImage: "circle.fill").font(.appMicro).foregroundColor(Color.forge)
                Label("PSS", systemImage: "circle.fill").font(.appMicro).foregroundColor(.green)
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
                        .foregroundColor(Color.forge)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.habitName).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        Text("Meilleure série : \(s.longestStreak) jours")
                            .font(.system(size: 10)).foregroundColor(.gray)
                    }
                    Spacer()
                    if s.currentStreak > 0 {
                        Text("\(s.currentStreak)🔥")
                            .font(.appLabel.weight(.bold)).foregroundColor(Color.forge)
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
                        Text(rec.categoryLabel).font(.appCaption.weight(.bold)).foregroundColor(pssColor(rec.category))
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

// MARK: - HRV Baseline Card

struct HRVBaselineCard: View {
    let data: HRVAnalysis

    private var accentColor: Color {
        data.hrvZone != nil ? data.zoneColor : (data.flagRest ? .red : .cyan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── En-tête ──────────────────────────────────────────────────────
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(accentColor)
                Text("BASELINE HRV PERSONNALISÉE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if data.streakAlert {
                    Text("⚠️ FATIGUE \(data.consecutiveLowDays)J")
                        .font(.system(size: 10, weight: .black)).foregroundColor(.red)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red.opacity(0.12)).clipShape(Capsule())
                } else if data.flagRest {
                    Text("⚠️ REPOS")
                        .font(.system(size: 10, weight: .black)).foregroundColor(.red)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red.opacity(0.12)).clipShape(Capsule())
                }
            }

            // ── Métriques ─────────────────────────────────────────────────────
            HStack(spacing: 16) {
                if let today = data.todayRmssd {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AUJOURD'HUI").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                        HStack(spacing: 3) {
                            Text(String(format: "%.0f ms", today))
                                .font(.system(size: 18, weight: .black)).foregroundColor(accentColor)
                            Text(data.trendArrow).font(.appLabel.weight(.bold)).foregroundColor(data.trendColor)
                        }
                    }
                }
                if let avg7 = data.hrv7dAvg {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MOY. 7J").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                        Text(String(format: "%.0f ms", avg7))
                            .font(.system(size: 18, weight: .black)).foregroundColor(.white.opacity(0.8))
                    }
                }
                if let baseline = data.hrv30dAvg {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BASELINE 30J").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                        Text(String(format: "%.0f ms", baseline))
                            .font(.system(size: 18, weight: .black)).foregroundColor(.cyan)
                    }
                }
                if let cv = data.hrvCv {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CV 30J").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                        Text(String(format: "%.0f%%", cv))
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(cv < 10 ? .green : cv < 20 ? .orange : .red)
                    }
                } else if let sd = data.sd30d {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("±SD").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                        Text(String(format: "%.0f ms", sd))
                            .font(.system(size: 18, weight: .black)).foregroundColor(.gray)
                    }
                }
                Spacer()
            }

            // ── Score normalisé ───────────────────────────────────────────────
            if let score = data.hrvScore, data.baselineAvailable {
                HStack(spacing: 6) {
                    Text(String(format: "%.0f%%", score))
                        .font(.system(size: 22, weight: .black)).foregroundColor(accentColor)
                    Text("vs baseline 7j")
                        .font(.appCaption).foregroundColor(.gray)
                }
            }

            // ── Message contextuel ────────────────────────────────────────────
            if let msg = data.contextualMessage {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(data.hrvZone == "red" ? .red.opacity(0.9) : .gray)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let dev = data.deviationFrom30d {
                Text(dev >= 0 ? String(format: "+%.0f ms vs baseline 30j", dev) : String(format: "%.0f ms vs baseline 30j", dev))
                    .font(.appCaption).foregroundColor(dev >= 0 ? .green : .orange)
            }

            Text("\(data.dataPoints30d) jours de données (30j)")
                .font(.system(size: 10)).foregroundColor(.gray.opacity(0.6))
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Soreness Threshold Card

struct SorenessThresholdCard: View {
    let data: SorenessThreshold
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt.heart.fill").foregroundColor(.red)
                Text("SEUIL COURBATURES PERSONNEL")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            }

            if let msg = data.message {
                Text(msg)
                    .font(.appLabel).foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                if let low = data.avgSorenessLowVol {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FAIBLE VOL").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                        Text(String(format: "%.1f/10", low))
                            .font(.appBody.weight(.black)).foregroundColor(.green)
                    }
                }
                if let high = data.avgSorenessHighVol {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FORT VOL").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                        Text(String(format: "%.1f/10", high))
                            .font(.appBody.weight(.black)).foregroundColor(.red)
                    }
                }
                if let thresh = data.thresholdVol {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SEUIL").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                        Text(_formatK(units.display(thresh)) + " \(units.label)")
                            .font(.appBody.weight(.black)).foregroundColor(Color.forge)
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

                    let stepsVals    = recovery.compactMap { $0.steps.map { min(Double($0) / 1000.0, 20.0) } }
                    let energyVals   = recovery.compactMap { $0.energyPre }
                    let restingHrVals = recovery.compactMap { $0.restingHr }

                    if !sleepVals.isEmpty {
                        WellnessSparkline(label: "Sommeil", values: movingAvg(sleepVals), color: .blue, range: 1...10)
                    }
                    if !sorenessVals.isEmpty {
                        WellnessSparkline(label: "Douleurs", values: movingAvg(sorenessVals), color: Color.forge, range: 1...10, invertTrend: true)
                    }
                    if !fatigueVals.isEmpty {
                        WellnessSparkline(label: "Fatigue", values: movingAvg(fatigueVals), color: .purple, range: 1...10, invertTrend: true)
                    }
                    if !stepsVals.isEmpty {
                        WellnessSparkline(label: "Pas (k)", values: movingAvg(stepsVals), color: .cyan, range: 0...20)
                    }
                    if !energyVals.isEmpty {
                        WellnessSparkline(label: "Énergie", values: movingAvg(energyVals), color: .green, range: 1...10)
                    }
                    if !restingHrVals.isEmpty {
                        WellnessSparkline(label: "FC repos", values: movingAvg(restingHrVals), color: .red, range: 40...100, invertTrend: true)
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
                .font(.appCaption).foregroundColor(.gray)
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

    // volume/RPE ratio per day of week — avoids session-type bias toward heavy days
    private var efficiencyByDow: [Int: Double] {
        let cutoff = DateFormatter.isoDate.string(from: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 90 * 86400))
        var totals: [Int: Double] = [:]
        var counts: [Int: Int] = [:]
        for (dateStr, session) in sessions {
            guard dateStr >= cutoff,
                  let date = DateFormatter.isoDate.date(from: dateStr),
                  let rpe = session.rpe, rpe > 0 else { continue }
            let dow = (Calendar.current.component(.weekday, from: date) + 5) % 7 // 0=Mon
            let vol: Double
            if let sv = session.sessionVolume, sv > 0 {
                vol = sv
            } else {
                vol = weights.values.flatMap { $0.history ?? [] }.filter { $0.date == dateStr }
                    .compactMap { e -> Double? in
                        if let v = e.exerciseVolume, v > 0 { return v }
                        guard let w = e.weight, let r = e.reps else { return nil }
                        return w * totalReps(r)
                    }.reduce(0, +)
            }
            guard vol > 0 else { continue }
            totals[dow, default: 0] += vol / rpe
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
        efficiencyByDow.max(by: { $0.value < $1.value })?.key
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("JOUR LE PLUS EFFICACE")
                        .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                    Text("(volume / RPE)")
                        .font(.appMicro).foregroundColor(.gray.opacity(0.7))
                }
                Spacer()
                if let best = bestDow {
                    Text("→ \(dayNames[best])")
                        .font(.appCaption.weight(.bold)).foregroundColor(Color.forge)
                }
            }
            let vols = efficiencyByDow
            let maxV = vols.values.max() ?? 1
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7, id: \.self) { d in
                    let v = vols[d] ?? 0
                    let isBest = d == bestDow
                    VStack(spacing: 3) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isBest ? Color.forge : Color.forge.opacity(0.3))
                            .frame(height: max(CGFloat(maxV > 0 ? v / maxV : 0) * 60, 3))
                        Text(dayNames[d])
                            .font(.appMicro).foregroundColor(isBest ? Color.forge : .gray)
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
                    .foregroundColor(Color.forge).font(.appCaption)
                Text("STRESS → DÉCLENCHEURS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            }
            Text(insightText)
                .font(.appLabel.weight(.semibold))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).glassCard(color: Color.forge, intensity: 0.04).cornerRadius(14)
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

// MARK: - Sleep Debt Card
struct SleepDebtCard: View {
    let recovery: [RecoveryEntry]
    @AppStorage("sleep_goal_hours") private var sleepGoal: Double = 8.0

    private var last7Hours: [Double] {
        recovery
            .sorted { ($0.date ?? "") > ($1.date ?? "") }
            .prefix(7)
            .compactMap(\.sleepHours)
    }

    private var totalDebt: Double {
        last7Hours.reduce(0) { $0 + max(0, sleepGoal - $1) }
    }

    private var avgSleep: Double? {
        guard !last7Hours.isEmpty else { return nil }
        return last7Hours.reduce(0, +) / Double(last7Hours.count)
    }

    private var debtColor: Color {
        if totalDebt < 2 { return .green }
        if totalDebt < 5 { return .orange }
        return .red
    }

    private var insightText: String {
        if totalDebt <= 0 { return "Aucune dette — tu respectes ton objectif sommeil. Excellent." }
        if totalDebt < 2  { return "Dette légère : \(String(format: "%.1f", totalDebt))h sur 7 jours. Récupère ce week-end." }
        if totalDebt < 5  { return "Dette modérée : \(String(format: "%.1f", totalDebt))h sur 7 jours. Ton HRV et ta récup en souffrent probablement." }
        return "Dette sévère : \(String(format: "%.1f", totalDebt))h en 7 jours. Dors davantage avant ta prochaine séance lourde."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DETTE DE SOMMEIL — 7 JOURS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text("obj. \(String(format: "%.0f", sleepGoal))h/j")
                    .font(.system(size: 10)).foregroundColor(.gray.opacity(0.6))
            }
            if last7Hours.isEmpty {
                EmptyChartPlaceholder(message: "Logge tes heures de sommeil quotidiennement")
            } else {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(totalDebt <= 0 ? "0h" : "-\(String(format: "%.1f", totalDebt))h")
                            .font(.system(size: 28, weight: .black)).foregroundColor(debtColor)
                        Text("dette accumulée").font(.appCaption).foregroundColor(.gray)
                    }
                    Spacer()
                    if let avg = avgSleep {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: "%.1fh", avg))
                                .font(.system(size: 28, weight: .black)).foregroundColor(.white)
                            Text("moy. / nuit").font(.appCaption).foregroundColor(.gray)
                        }
                    }
                }
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
                Text(insightText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).glassCard().cornerRadius(14)
    }
}

// MARK: - Recovery Profile Card
struct RecoveryProfileCard: View {
    let avgDays: Double
    let sampleSize: Int

    private var profileColor: Color {
        if avgDays <= 1.5 { return .green }
        if avgDays <= 3.0 { return .orange }
        return .red
    }

    private var insightText: String {
        if avgDays <= 1.5 { return "Tu récupères vite. Tu peux enchaîner les séances lourdes à \(Int(round(avgDays))) jour d'intervalle." }
        if avgDays <= 3.0 { return "Récupération standard. Prévois \(Int(round(avgDays))) jours entre deux séances à RPE 8+." }
        return "Récupération lente. Espace tes séances lourdes d'au moins \(Int(round(avgDays))) jours pour éviter de cumuler la fatigue."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROFIL DE RÉCUPÉRATION")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 6) {
                Text(String(format: "%.1f", avgDays))
                    .font(.system(size: 36, weight: .black)).foregroundColor(profileColor)
                Text("jours")
                    .font(.system(size: 14, weight: .medium)).foregroundColor(.gray)
                    .padding(.bottom, 6)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("après RPE 8+").font(.appCaption).foregroundColor(.gray)
                    Text("pour soreness < 3").font(.appCaption).foregroundColor(.gray)
                    Text("(\(sampleSize) séances)").font(.system(size: 10)).foregroundColor(.gray.opacity(0.6))
                }
            }
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            Text(insightText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).glassCard().cornerRadius(14)
    }
}

