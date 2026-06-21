import SwiftUI
import Charts

// MARK: - Measurements Trend
struct MeasurementsTrendView: View {
    let entries: [BodyWeightEntry]

    private let metrics: [(String, KeyPath<BodyWeightEntry, Double?>, Color)] = [
        ("Taille", \.waistCm, .statusPurple),
        ("Bras",   \.armsCm,  .statusBlue),
        ("Cuisses",\.thighsCm,Color.forge),
        ("Hanches",\.hipsCm,  .pink),
        ("Cou",    \.neckCm,  .teal),
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
                            Text(label).font(.appCaption.weight(.medium)).foregroundColor(.appTextPrimary)
                            Spacer()
                            let diff = (vals.last?.1 ?? 0) - (vals.first?.1 ?? 0)
                            Text(String(format: "%+.1f cm", diff))
                                .font(.appCaption.weight(.bold))
                                .foregroundColor(diff <= 0 ? .statusGreen : .statusRed)
                            Text(String(format: "%.0f", vals.last?.1 ?? 0))
                                .font(.appLabel.weight(.black)).foregroundColor(color)
                        }
                        MiniLineChart(values: vals.map(\.1), color: color)
                            .frame(height: 28)
                    }
                }
            }
        }
        .padding(16).glassCard(color: .statusPurple, intensity: 0.04)
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

// MARK: - Volume Landmarks Card
struct VolumeLandmarksCard: View {
    let landmarks: [String: MuscleLandmark]

    private var sorted: [(String, MuscleLandmark)] {
        landmarks.sorted { a, b in
            let priorityA = a.1.zone == .overMRV ? 0 : a.1.zone == .underMEV ? 1 : 2
            let priorityB = b.1.zone == .overMRV ? 0 : b.1.zone == .underMEV ? 1 : 2
            return priorityA != priorityB ? priorityA < priorityB : a.0 < b.0
        }
    }

    private func zoneColor(_ zone: MuscleLandmark.Zone) -> Color {
        switch zone {
        case .underMEV:       return .statusBlue
        case .optimal:        return .statusGreen
        case .approachingMRV: return .statusOrange
        case .overMRV:        return .statusRed
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
                    .font(.appCaption)
                    .foregroundColor(.statusPurple)
                Text("VOLUME HEBDO — LANDMARKS")
                    .font(.system(size: 10, weight: .bold)).tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                CardInfoButton(title: "Volume landmarks", entries: InfoEntry.volumeLandmarkEntries)
            }

            HStack(spacing: 14) {
                legendDot(.statusBlue,   "Sous le min")
                legendDot(.statusGreen,  "Optimal")
                legendDot(Color.forge, "Proche du max")
                legendDot(.statusRed,    "Surcharge")
            }

            GeometryReader { outer in
                VStack(spacing: 7) {
                    ForEach(sorted, id: \.0) { muscle, lm in
                        let barW = outer.size.width - 190
                        let ratio = min(Double(lm.weeklySets) / Double(lm.mrv), 1.2)
                        HStack(spacing: 8) {
                            Text(muscle.localizedMuscleGroup)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.appTextPrimary)
                                .frame(width: 100, alignment: .leading)
                                .lineLimit(1)

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.appSurfaceInset)
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(zoneColor(lm.zone).opacity(0.8))
                                    .frame(width: min(barW * ratio, barW), height: 8)
                                Rectangle()
                                    .fill(Color.appOnSurface.opacity(0.4))
                                    .frame(width: 1, height: 12)
                                    .offset(x: barW * Double(lm.mev) / Double(lm.mrv))
                                Rectangle()
                                    .fill(Color.appOnSurface.opacity(0.25))
                                    .frame(width: 1, height: 12)
                                    .offset(x: min(barW * Double(lm.mav) / Double(lm.mrv), barW - 1))
                            }
                            .frame(height: 12)

                            Text("\(lm.weeklySets)")
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(zoneColor(lm.zone))
                                .frame(width: 22, alignment: .trailing)

                            Text(zoneLabel(lm.zone))
                                .font(.appMicro.weight(.semibold))
                                .foregroundColor(zoneColor(lm.zone).opacity(0.8))
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(height: CGFloat(sorted.count) * (12 + 7) - 7)

            Text("MEV · MAV · MRV d'après Renaissance Periodization (Israetel et al.)")
                .font(.appMicro).foregroundColor(.gray.opacity(0.6))
                .padding(.top, 2)

            let specificsEntries: [(String, [String: Int])] = sorted.compactMap { muscle, lm in
                guard let detail = lm.specificDetail, !detail.isEmpty else { return nil }
                return (muscle, detail)
            }
            if !specificsEntries.isEmpty {
                Divider().background(Color.appSeparatorStrong)
                VStack(alignment: .leading, spacing: 5) {
                    Text("DÉTAIL PAR MUSCLE SPÉCIFIQUE")
                        .font(.appMicro.weight(.bold)).tracking(2)
                        .foregroundColor(.gray)
                    ForEach(specificsEntries, id: \.0) { muscleKey, detail in
                        ForEach(detail.sorted(by: { $0.value > $1.value }), id: \.key) { specific, count in
                            HStack {
                                Text("\(muscleKey.localizedMuscleGroup) → \(specific)")
                                    .font(.appCaption)
                                    .foregroundColor(Color.appOnSurface.opacity(0.65))
                                Spacer()
                                Text("\(count) sets")
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundColor(Color.appOnSurface.opacity(0.65))
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
        .cornerRadius(16)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.appMicro.weight(.medium)).foregroundColor(.gray)
        }
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

    private var deltaSpan: (lean: Double, fat: Double, label: String)? {
        guard points.count >= 2 else { return nil }
        let cutoff = DateFormatter.isoDate.string(from: Date(timeIntervalSince1970: Date().timeIntervalSince1970 - 30 * 86400))
        let recent = points.filter { $0.date >= cutoff }
        let first: RecompPoint
        let last: RecompPoint
        let label: String
        if recent.count >= 2, let f = recent.first, let l = recent.last {
            first = f; last = l; label = "30j"
        } else if let f = points.dropLast().last, let l = points.last {
            first = f; last = l; label = "depuis \(f.date.suffix(5))"
        } else { return nil }
        return (lean: last.leanMass - first.leanMass, fat: last.fatMass - first.fatMass, label: label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BODY RECOMPOSITION — 3 COURBES")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            if points.count < 3 {
                EmptyChartPlaceholder(message: "Logge ton % de masse grasse pour activer le recomp tracker")
            } else {
                recompChart
                if let d = deltaSpan {
                    deltaRow(d)
                }
            }
        }
        .padding(16).glassCard()
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
                recompLine(\.fatMass,  color: Color.bodyComp(.fat).opacity(0.8),  step: step, h: h, minV: minV, range: range)
                recompLine(\.leanMass, color: Color.bodyComp(.lean),              step: step, h: h, minV: minV, range: range)
            }
        }
        .frame(height: 100)

        HStack(spacing: 16) {
            legendDot(.gray,                   "Poids total")
            legendDot(Color.bodyComp(.fat),    "Masse grasse")
            legendDot(Color.bodyComp(.lean),   "Masse maigre")
        }
        .font(.system(size: 10)).foregroundColor(.gray)
    }

    @ViewBuilder private func deltaRow(_ d: (lean: Double, fat: Double, label: String)) -> some View {
        Rectangle().fill(Color.appSurfaceInset).frame(height: 0.5)
        HStack(spacing: 20) {
            deltaKPI(
                label: "Masse maigre (\(d.label))",
                value: units.format(d.lean, decimals: 1),
                good: d.lean >= 0
            )
            deltaKPI(
                label: "Masse grasse (\(d.label))",
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
                .foregroundColor(good ? .statusGreen : .statusOrange)
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

// MARK: - Season Comparison Card
struct SeasonComparisonCard: View {
    let data: SeasonComparisonData
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(Color.forge).font(.system(size: 12))
                Text("COMPARAISON SAISONS")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            }

            if let current = data.current {
                seasonTable(current: current, previous: data.previous)
            } else {
                Text("Aucune saison active")
                    .font(.appLabel).foregroundColor(.gray)
            }
        }
        .padding(16).glassCard()
    }

    @ViewBuilder private func seasonTable(current: SeasonCompStats, previous: SeasonCompStats?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("").frame(height: 16)
                Text("Vol. moy/sem").font(.appCaption).foregroundColor(.gray)
                Text("Séances").font(.appCaption).foregroundColor(.gray)
                Text("PSS moy.").font(.appCaption).foregroundColor(.gray)
                Text("Δ poids").font(.appCaption).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .center, spacing: 10) {
                Text(current.title ?? "En cours")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(Color.forge)
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
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
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
            .font(.appLabel.weight(.bold))
            .foregroundColor(dim ? .gray : .white)
            .frame(height: 18)
    }

    @ViewBuilder private func weightCell(_ delta: Double?, dim: Bool = false) -> some View {
        if let d = delta {
            let sign = d > 0 ? "+" : ""
            let color: Color = dim ? .gray : (d < 0 ? .statusGreen : .statusOrange)
            Text("\(sign)\(units.format(d, decimals: 1))")
                .font(.appLabel.weight(.bold))
                .foregroundColor(color)
                .frame(height: 18)
        } else {
            Text("—").font(.appLabel.weight(.bold)).foregroundColor(.gray).frame(height: 18)
        }
    }

    @ViewBuilder private func deltaArrow(_ a: Double?, _ b: Double?, higherBetter: Bool) -> some View {
        if let c = a, let p = b, p != 0 {
            let diff = c - p
            let isGood = higherBetter ? diff > 0 : diff < 0
            let pct = Int(round(abs(diff) / abs(p) * 100))
            let sym = diff > 0 ? "↑" : "↓"
            Text("\(sym)\(pct)%")
                .font(.appMicro.weight(.bold))
                .foregroundColor(isGood ? .statusGreen : .statusOrange)
                .frame(height: 18)
        } else {
            Text("").frame(height: 18)
        }
    }
}

// MARK: - Transformation Markers Card
struct TransformationMarkersCard: View {
    let warRoomStats: WarRoomSummaryStats?
    @State private var showGate = false

    var body: some View {
        let showWarRoom = warRoomStats?.warStartDate != nil
        VStack(alignment: .leading, spacing: 12) {
            Text("MARQUEURS DE TRANSFORMATION")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            if showWarRoom, let wr = warRoomStats {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(wr.totalVictories)")
                        .font(.system(size: 30, weight: .black))
                        .foregroundColor(Color.appSuccess)
                        .contentTransition(.numericText())
                    Text("jours de victoire")
                        .font(.appCaption).foregroundColor(.gray)
                    Text("Ne descend jamais")
                        .font(.appMicro).foregroundColor(.gray.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.appSuccess.opacity(0.07))
                .cornerRadius(12)
            } else {
                Button { showGate = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 15))
                            .foregroundColor(Color.forge.opacity(0.7))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Ton premier jour de victoire t'attend")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.appTextPrimary)
                            Text("Démarre War Room")
                                .font(.appCaption)
                                .foregroundColor(Color.forge.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.forge.opacity(0.4))
                    }
                    .padding(12)
                    .background(Color.forge.opacity(0.06))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16).glassCard()
        .sheet(isPresented: $showGate) { WarRoomGateView() }
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
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.appTextPrimary)
                                    .lineLimit(1)
                                Spacer()
                                let sign = lift.delta >= 0 ? "+" : ""
                                Text("\(sign)\(lift.deltaPct)%")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(lift.delta >= 0 ? .statusGreen : .statusOrange)
                            }
                            GeometryReader { g in
                                let w = g.size.width
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.gray.opacity(0.25))
                                        .frame(width: w * CGFloat(lift.baseline / maxCurrent), height: 8)
                                    Capsule()
                                        .fill(lift.delta >= 0 ? Color.trendPositive : Color.forge)
                                        .frame(width: w * CGFloat(lift.current / maxCurrent), height: 8)
                                        .opacity(0.85)
                                }
                            }
                            .frame(height: 8)
                            HStack {
                                Text("Baseline: \(units.format(lift.baseline, decimals: 0))")
                                    .font(.appMicro).foregroundColor(.gray)
                                Spacer()
                                Text("Actuel: \(units.format(lift.current, decimals: 0))")
                                    .font(.appMicro.weight(.semibold))
                                    .foregroundColor(Color.forge)
                            }
                        }
                    }
                }
            }
        }
        .padding(16).glassCard()
    }
}

// MARK: - Force Hero Card
struct ForceHeroCard: View {
    let trend: [String: [OneRMPoint]]

    // Fixed data colors — independent of theme (données ≠ déco)
    private let liftColors: [Color] = [
        Color(hex: "FF9F0A"),  // amber
        Color(hex: "30D158"),  // green
        Color(hex: "0A84FF"),  // blue
        Color(hex: "BF5AF2"),  // purple
        Color(hex: "32ADE6"),  // cyan
    ]

    private struct NormalizedLift: Identifiable {
        let id: String
        let name: String
        let color: Color
        let points: [(date: Date, pct: Double)]
        let deltaPct: Int
    }

    private var lifts: [NormalizedLift] {
        trend
            .sorted { $0.value.count > $1.value.count }
            .prefix(5)
            .enumerated()
            .compactMap { idx, kv in
                let sorted = kv.value.sorted { $0.date < $1.date }
                guard let baseline = sorted.first?.oneRM, baseline > 0,
                      sorted.count >= 2 else { return nil }
                let pts = sorted.compactMap { pt -> (date: Date, pct: Double)? in
                    guard let d = DateFormatter.isoDate.date(from: pt.date) else { return nil }
                    return (d, pt.oneRM / baseline * 100.0)
                }
                guard pts.count >= 2 else { return nil }
                let current = sorted.last?.oneRM ?? baseline
                let deltaPct = Int(round((current - baseline) / baseline * 100))
                return NormalizedLift(id: kv.key, name: kv.key,
                                     color: liftColors[idx % liftColors.count],
                                     points: pts, deltaPct: deltaPct)
            }
    }

    private var bestGainer: NormalizedLift? {
        lifts.max { $0.deltaPct < $1.deltaPct }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PROGRESSION FORCE — 6 MOIS")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)

            if lifts.isEmpty {
                EmptyChartPlaceholder(message: "Logge tes lifts composés pour voir ta force monter")
            } else {
                if let best = bestGainer {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(best.deltaPct >= 0 ? "+\(best.deltaPct)%" : "\(best.deltaPct)%")
                            .font(.system(size: 38, weight: .black))
                            .foregroundColor(best.deltaPct >= 0 ? Color(hex: "FF9F0A") : .statusRed)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(best.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.appTextPrimary)
                                .lineLimit(1)
                            Text("\(lifts.count) lift\(lifts.count > 1 ? "s" : "") en progression")
                                .font(.appCaption).foregroundColor(.gray)
                        }
                    }
                }

                let allPcts = lifts.flatMap { $0.points.map(\.pct) }
                let minY = (allPcts.min() ?? 100) * 0.97
                let maxY = (allPcts.max() ?? 100) * 1.05

                Chart {
                    ForEach(lifts) { lift in
                        ForEach(lift.points, id: \.date) { pt in
                            LineMark(
                                x: .value("Date", pt.date),
                                y: .value("%", pt.pct)
                            )
                            .foregroundStyle(lift.color)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                    }
                    RuleMark(y: .value("Baseline", 100))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.gray.opacity(0.25))
                }
                .chartLegend(.hidden)
                .chartYScale(domain: minY...maxY)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine().foregroundStyle(Color.appSurfaceInset)
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .foregroundStyle(Color.gray)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .stride(by: 5)) { val in
                        AxisGridLine().foregroundStyle(Color.appSurfaceInset)
                        AxisValueLabel {
                            if let v = val.as(Double.self) {
                                Text("\(Int(v))%")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.background(Color.clear) }
                .frame(height: 160)

                HStack(spacing: 14) {
                    ForEach(lifts) { lift in
                        HStack(spacing: 5) {
                            Circle().fill(lift.color).frame(width: 6, height: 6)
                            Text("\(lift.name.components(separatedBy: " ").prefix(2).joined(separator: " ")) \(lift.deltaPct >= 0 ? "+" : "")\(lift.deltaPct)%")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .glassCard(color: .forge, intensity: 0.03)
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
                else if let w = e.weight, w > 0, let r = e.reps,
                        let orm = estimateOneRM(weight: w, reps: avgReps(r)) {
                    value = orm
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
                    .font(.appLabel).foregroundColor(.gray)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            } else {
                Chart {
                    ForEach(points) { p in
                        LineMark(
                            x: .value("Date", p.date),
                            y: .value(metric.rawValue, p.value)
                        )
                        .foregroundStyle(Color.forge)
                        .interpolationMethod(.monotone)

                        PointMark(
                            x: .value("Date", p.date),
                            y: .value(metric.rawValue, p.value)
                        )
                        .foregroundStyle(p.isPR ? Color.forge : Color.forge.opacity(0.4))
                        .symbolSize(p.isPR ? 80 : 30)
                    }

                    if let pr = points.last(where: \.isPR) {
                        RuleMark(y: .value("PR", pr.value))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.forge.opacity(0.3))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("PR \(units.format(pr.value))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color.forge)
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisGridLine().foregroundStyle(Color.appSurfaceInset)
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                            .foregroundStyle(Color.gray)
                    }
                }
                .chartYAxis {
                    AxisMarks { val in
                        AxisGridLine().foregroundStyle(Color.appSurfaceInset)
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
        case "force":        return .statusRed
        case "hypertrophie": return .statusOrange
        default:             return .statusBlue
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
                        .font(.appCaption).foregroundColor(.gray)
                }
                Spacer()
            }

            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.statusBlue.opacity(0.25)).frame(width: w * 0.65)
                        Rectangle().fill(Color.forge.opacity(0.25)).frame(width: w * 0.15)
                        Rectangle().fill(Color.statusRed.opacity(0.25))
                    }
                    .cornerRadius(4)

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

                HStack {
                    Text("<65%").font(.system(size: 8)).foregroundColor(.statusBlue)
                    Spacer()
                    Text("65–80%").font(.system(size: 8)).foregroundColor(Color.forge)
                    Spacer()
                    Text(">80%").font(.system(size: 8)).foregroundColor(.statusRed)
                }
                .offset(y: 16)
            }
            .frame(height: 32)
        }
        .padding(16).glassCard(color: zoneColor, intensity: 0.04)
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
                        .font(.appBody.weight(.bold)).foregroundColor(.statusBlue)
                } else if let w = data.weeksSinceDeload {
                    Text("\(w) sem.")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(deloadColor)
                    Text("depuis le dernier deload")
                        .font(.appCaption).foregroundColor(.gray)
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .black)).foregroundColor(.gray)
                    Text("pas encore de deload enregistré")
                        .font(.appCaption).foregroundColor(.gray)
                }
            }
            Spacer()
            if data.recommande {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20)).foregroundColor(Color.forge)
                    Text("Recommandé")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(Color.forge)
                }
            }
        }
        .padding(16).glassCard(color: deloadColor, intensity: 0.04)
    }

    private var deloadColor: Color {
        if data.recommande { return .statusOrange }
        guard let w = data.weeksSinceDeload else { return .gray }
        if w <= 4 { return .statusGreen }
        if w <= 6 { return .statusOrange }
        return .statusRed
    }
}

