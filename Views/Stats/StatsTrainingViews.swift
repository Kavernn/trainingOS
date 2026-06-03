import SwiftUI
import Charts

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

// MARK: - Badges View
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
    var daysElapsed: Int = 7
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
        let hasData = lastWeekVolume > 0 || lastWeekSessions > 0
        guard hasData else { return ("Pas encore assez de données.", .gray) }

        // Semaine en cours avec peu de jours — comparaison biaisée
        if daysElapsed <= 3 {
            return ("Semaine en cours (J+\(daysElapsed)) — chiffres partiels, reviens jeudi.", .gray)
        }

        let volumeUp = thisWeekVolume >= lastWeekVolume * 0.98
        let sessionsUp = thisWeekSessions >= lastWeekSessions

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

    private var isNull: Bool { value == "—" }

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .black))
                .foregroundColor(isNull ? .gray.opacity(0.35) : color)
                .contentTransition(.numericText()).minimumScaleFactor(0.6).lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .semibold)).tracking(1.3)
                .foregroundColor(.gray.opacity(0.65))
                .textCase(.uppercase).lineLimit(1)
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 8)).foregroundColor(.gray.opacity(0.45))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard(color: isNull ? .gray : color, intensity: isNull ? 0.02 : 0.05).cornerRadius(12)
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
        return r >= 0.77 && r <= 1.3 ? .green : .orange
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
