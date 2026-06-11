import SwiftUI

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
                    Text("±10%").font(.appMicro).foregroundColor(.gray)
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
                        Text(item.0).font(.appMicro).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 100, alignment: .bottom)
                }
            }
            .frame(height: 100)
        }
        .padding(16).background(Color.appCard).cornerRadius(14)
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
                hit: p >= protTarget * 0.9,
                partial: p >= protTarget * 0.75 && p < protTarget * 0.9
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

            HStack(spacing: 0) {
                compKPI("\(Int(complianceRate * 100))%", "jours atteints", complianceRate >= 0.8 ? .green : complianceRate >= 0.5 ? .orange : .red)
                Divider().background(Color.appSeparator).frame(height: 36)
                compKPI("\(hitCount)/\(statuses.count)", "jours trackés", .blue)
                Divider().background(Color.appSeparator).frame(height: 36)
                compKPI("\(Int(avgProteines))g", "moy. / jour", avgProteines >= protTarget ? .green : .orange)
            }

            if !statuses.isEmpty {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(statuses) { day in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.hit ? Color.green : day.partial ? Color.orange : Color.appSurfaceInset)
                            .frame(height: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                            )
                    }
                }

                HStack(spacing: 12) {
                    legendDot(.green,           "Objectif atteint")
                    legendDot(Color.forge,          "≥ 75%")
                    legendDot(Color.appSurfaceInset, "< 75%")
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
            Text(value).font(.appHeadline.weight(.black)).foregroundColor(color)
            Text(label).font(.appMicro).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.appMicro).foregroundColor(.gray)
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
                StatsMacroBar(label: "Protéines",value: avgP, target: target.proteines,color: Color.forge, unit: "g")
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
                Text("/ \(Int(t))\(unit)").font(.appMicro).foregroundColor(.gray)
            }
            Text(label).font(.appMicro.weight(.semibold)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: 80, alignment: .bottom)
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
                    .font(.appCaption.weight(.bold))
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
                        .stroke(Color.forge, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
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
                    macroColumn(label: "Entraînement", bucket: t, color: Color.forge, n: data.nTraining)
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
            Text(label).font(.appCaption.weight(.bold)).foregroundColor(color)
            Text("(\(n) jours)").font(.appMicro).foregroundColor(.gray)
            macroRow("Calories", String(format: "%.0f kcal", bucket.avgCal), color)
            macroRow("Protéines", String(format: "%.0f g", bucket.avgProt), .green)
            macroRow("Glucides", String(format: "%.0f g", bucket.avgCarbs), .yellow)
            macroRow("Lipides", String(format: "%.0f g", bucket.avgFat), Color.forge)
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
        .padding(16).glassCard()
    }

    @ViewBuilder private var miniDualChart: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let n = pairs.count
            let step = w / CGFloat(max(n - 1, 1))
            let maxVol = pairs.map(\.volume).max() ?? 1

            Path { path in
                for (i, p) in pairs.enumerated() {
                    let x = CGFloat(i) * step
                    let y = h * (1 - CGFloat(p.volume / maxVol))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color(hex: "F5A623"), style: StrokeStyle(lineWidth: 2, lineCap: .round))

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
                Text("Volume").font(.appMicro).foregroundColor(.gray)
            }
            HStack(spacing: 4) {
                Rectangle().fill(Color.green).frame(width: 16, height: 2)
                Text("Adherence macros").font(.appMicro).foregroundColor(.gray)
            }
        }
    }
}
