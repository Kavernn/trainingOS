import SwiftUI

// MARK: - Coverage Warning (F)
/// Bannière silencieuse par défaut ; affichée seulement si la couverture
/// d'une carte nutrition tombe < 70 %. Rend la représentativité visible
/// quand les stats s'appuient sur un sous-ensemble mince.
private struct CoverageWarning: View {
    let included: Int
    let expected: Int
    let label: String   // ex. "jours loggués", "semaines évaluables"

    private static let threshold: Double = 0.70
    private var pct: Double { expected > 0 ? Double(included) / Double(expected) : 1.0 }

    @ViewBuilder var body: some View {
        if pct < Self.threshold {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundColor(Color.appWarning)
                Text("Couverture \(Int((pct * 100).rounded())) % — \(included)/\(expected) \(label).")
                    .font(.appMicro).foregroundColor(Color.appWarning)
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Nutrition Compliance
struct NutritionComplianceChart: View {
    /// Fenêtre /api/stats/nutrition_history — axe par date, cible par jour,
    /// source-aware (detailed vs estimated).
    let history: [DayNutritionHistory]

    /// Jour tracé : conformité calculée selon la source. Les jours vides et
    /// les estimations sans pct déclaré sont retirés du graphe (comptés
    /// séparément pour affichage).
    private struct Point: Identifiable {
        let id: String
        let date: String
        let pct: Double
        let labelValue: Double   // kcal effectifs OU 100 × pct pour affichage
    }

    /// detailed  → cal / targetCalories   (nil cible → exclu)
    /// estimated avec pct → pctCaloriesDeclared directement
    /// estimated SANS pct → exclu (counter)
    /// jour vide → exclu (pas de bar)
    private var points: [Point] {
        history.compactMap { d -> Point? in
            if d.isDetailed {
                guard let cal = d.calories, let tgt = d.targetCalories, tgt > 0 else { return nil }
                return Point(id: d.date, date: d.date, pct: cal / Double(tgt), labelValue: cal)
            }
            if d.isEstimated, let pct = d.pctCaloriesDeclared {
                let cal = d.calories ?? 0
                return Point(id: d.date, date: d.date, pct: pct, labelValue: cal)
            }
            return nil
        }
    }

    private var excludedWithoutPct: Int {
        history.filter { $0.isEstimated && $0.pctCaloriesDeclared == nil }.count
    }

    private var displayed: [Point] { Array(points.suffix(30)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMPLIANCE CALORIES (\(points.count) JOURS)")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(displayed) { pt in
                    let clipped = min(pt.pct, 1.4)
                    let color: Color = pt.pct >= 0.9 && pt.pct <= 1.1 ? Color.appSuccess
                                    : pt.pct <  0.9                   ? Color.appWarning
                                    : Color.appDanger
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", pt.labelValue))
                            .font(.system(size: 7)).foregroundColor(color.opacity(0.8))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.7))
                            .frame(height: max(CGFloat(clipped) * 60, 2))
                        Text(shortDate(pt.date))
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
                    .stroke(Color.appOnSurface.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            )

            HStack(spacing: 12) {
                Label("Cible adaptative par jour", systemImage: "target")
                    .font(.appMicro).foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.appSuccess).frame(width: 6, height: 6)
                    Text("±10%").font(.appMicro).foregroundColor(.gray)
                }
            }

            if excludedWithoutPct > 0 {
                Text("\(excludedWithoutPct) jour\(excludedWithoutPct > 1 ? "s" : "") estimé\(excludedWithoutPct > 1 ? "s" : "") sans pourcentage enregistré — exclu\(excludedWithoutPct > 1 ? "s" : "") de la compliance.")
                    .font(.appMicro).foregroundColor(.gray.opacity(0.8))
            }
            CoverageWarning(included: points.count, expected: history.count, label: "jours évaluables")
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
    /// Dict keyed by date ISO (YYYY-MM-DD). Compare la distribution RPE sur
    /// 4 dernières semaines COMPLÈTES (fenêtre récente) vs les 4 précédentes.
    /// La semaine en cours est exclue (données partielles).
    /// Affichage en % de chaque fenêtre, pas en nombre absolu.
    /// Garde-fou sur le TOTAL de la fenêtre (n < 8) : la colonne entière
    /// affiche "Pas assez de données (n = X)". Une tranche à 0 est une info,
    /// pas un manque — pas de garde-fou par tranche.
    let sessions: [String: SessionEntry]

    private static let minSessionsPerWindow: Int = 8
    private static let buckets = ["1-2", "3-4", "5-6", "7-8", "9-10"]
    private static let windowWeeks: Int = 4

    private struct Window {
        let label: String
        let counts: [Int]
        var total: Int { counts.reduce(0, +) }
        var pcts: [Double] {
            guard total > 0 else { return [0, 0, 0, 0, 0] }
            return counts.map { Double($0) / Double(total) }
        }
    }

    private func bucketize(_ dates: Set<String>) -> [Int] {
        var counts = [0, 0, 0, 0, 0]
        for (date, s) in sessions where dates.contains(date) {
            guard let rpe = s.rpe else { continue }
            let idx = min(max(Int((rpe - 1) / 2), 0), 4)
            counts[idx] += 1
        }
        return counts
    }

    /// Fenêtres : [J-28 … J-1 de la semaine passée] vs [J-56 … J-29].
    /// Démarrage : lundi de la semaine en cours (ISO) → on recule.
    private var pair: (recent: Window, previous: Window)? {
        let cal = Calendar(identifier: .iso8601)
        let today = Date()
        guard let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start,
              let recentStart   = cal.date(byAdding: .day, value: -7 * Self.windowWeeks, to: currentWeekStart),
              let previousStart = cal.date(byAdding: .day, value: -7 * Self.windowWeeks, to: recentStart)
        else { return nil }
        let fmt = DateFormatter.isoDate
        func dates(from start: Date, days: Int) -> Set<String> {
            Set((0..<days).compactMap { cal.date(byAdding: .day, value: $0, to: start) }.map(fmt.string(from:)))
        }
        let recentDates   = dates(from: recentStart,   days: 7 * Self.windowWeeks)
        let previousDates = dates(from: previousStart, days: 7 * Self.windowWeeks)
        return (
            Window(label: "4 dernières sem.", counts: bucketize(recentDates)),
            Window(label: "4 précédentes",    counts: bucketize(previousDates))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DISTRIBUTION RPE — 4 SEMAINES VS 4 PRÉCÉDENTES")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)

            if let p = pair {
                HStack(alignment: .top, spacing: 12) {
                    windowCard(window: p.recent,   color: Color.forge)
                    windowCard(window: p.previous, color: Color.gray)
                }
            } else {
                EmptyChartPlaceholder(message: "Fenêtres indisponibles")
            }
        }
        .padding(16).background(Color.appCard).cornerRadius(14)
    }

    @ViewBuilder private func windowCard(window w: Window, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(w.label).font(.appMicro.weight(.semibold)).foregroundColor(.gray)
                }
                Spacer()
                Text("n = \(w.total)").font(.appMicro).foregroundColor(.gray)
            }

            if w.total < Self.minSessionsPerWindow {
                Text("Pas assez de données (n = \(w.total))")
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(Self.buckets.enumerated()), id: \.0) { i, label in
                        VStack(spacing: 2) {
                            Text("\(Int((w.pcts[i] * 100).rounded()))%")
                                .font(.system(size: 9, weight: .bold)).foregroundColor(color)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(0.75))
                                .frame(height: max(CGFloat(w.pcts[i]) * 60, 2))
                            Text(label).font(.appMicro).foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 80, alignment: .bottom)
                    }
                }
                .frame(height: 80)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurfaceInset)
        .cornerRadius(8)
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
                    .font(.appMicro.weight(.bold))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                Text("Objectif : \(Int(protTarget))g/j")
                    .font(.appMicro)
                    .foregroundColor(.gray)
            }

            HStack(spacing: 0) {
                compKPI("\(Int(complianceRate * 100))%", "jours atteints", complianceRate >= 0.8 ? Color.appSuccess : complianceRate >= 0.5 ? Color.appWarning : Color.appDanger)
                Divider().background(Color.appSeparator).frame(height: 36)
                compKPI("\(hitCount)/\(statuses.count)", "jours trackés", Color.gray)
                Divider().background(Color.appSeparator).frame(height: 36)
                compKPI("\(Int(avgProteines))g", "moy. / jour", avgProteines >= protTarget ? Color.appSuccess : Color.appWarning)
            }

            if !statuses.isEmpty {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(statuses) { day in
                        // shape géométrique inline — radius calibré à la taille de la cellule
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.hit ? Color.appSuccess : day.partial ? Color.appWarning : Color.appSurfaceInset)
                            .frame(height: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.appSurfaceInset, lineWidth: 0.5)
                            )
                    }
                }

                HStack(spacing: 12) {
                    legendDot(Color.appSuccess,  "Objectif atteint")
                    legendDot(Color.forge,          "≥ 75%")
                    legendDot(Color.appSurfaceInset, "< 75%")
                }
                // alignement fin sous grille
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    private func compKPI(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.appHeadline.weight(.black)).foregroundColor(color)
            Text(label).font(.appMicro).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            // shape géométrique inline — radius calibré au dot 10×10
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.appMicro).foregroundColor(.gray)
        }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RATIO PROTÉINES / POIDS CORPOREL")
                    .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                Text(String(format: "Moy. %.2f g/lb", avg))
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(avg >= 0.8 ? Color.appSuccess : Color.appWarning)
            }
            GeometryReader { geo in
                let step = data.count > 1 ? geo.size.width / CGFloat(data.count - 1) : geo.size.width
                ZStack {
                    // Target zone (0.8–1.2 g/lb)
                    let yTop = geo.size.height * (1 - CGFloat(1.2 / maxR))
                    let yBot = geo.size.height * (1 - CGFloat(0.8 / maxR))
                    Rectangle()
                        .fill(Color.appSuccess.opacity(0.08))
                        .frame(width: geo.size.width, height: yBot - yTop)
                        .position(x: geo.size.width/2, y: (yTop + yBot)/2)
                    // Target line
                    let yTarget = geo.size.height * (1 - CGFloat(target / maxR))
                    Path { p in p.move(to: .init(x: 0, y: yTarget)); p.addLine(to: .init(x: geo.size.width, y: yTarget)) }
                        .stroke(Color.appSuccess.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
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
                .font(.appMicro).foregroundColor(.gray.opacity(0.7))
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Nutrition vs Performance View (A3 + D)
/// Adhérence hebdo = part des jours "dans la cible" selon la règle source-aware :
///   detailed   → |calories - target_calories du jour| / target ≤ 10 %
///   estimated avec pct déclaré → |pct - 1.0| ≤ 10 %
///   estimated sans pct ou jour vide → non évaluable, exclu
/// Une semaine n'est retenue que si ≥ 4 jours évaluables (anti 2/2 = 100 %
/// trompeur). Corrélation adhérence ↔ volume via CorrelationGuard, pas de
/// split high/low ni texte pré-écrit.
struct NutritionVsPerfView: View {
    let history: [DayNutritionHistory]
    let weeklyTonnage: [WeeklyTonnageEntry]

    private static let targetTolerance: Double = 0.10
    private static let minEvaluableDaysPerWeek: Int = 4

    private struct WeekPair: Identifiable {
        let id = UUID()
        let weekStart: String
        let adherence: Double  // 0–1
        let evaluableDays: Int
        let volume: Double
    }

    /// Jour "en cible" selon source. nil = non évaluable (exclu).
    private func inTarget(_ d: DayNutritionHistory) -> Bool? {
        if d.isDetailed {
            guard let cal = d.calories, let tgt = d.targetCalories, tgt > 0 else { return nil }
            return abs(cal - Double(tgt)) / Double(tgt) <= Self.targetTolerance
        }
        if d.isEstimated, let pct = d.pctCaloriesDeclared {
            return abs(pct - 1.0) <= Self.targetTolerance
        }
        return nil
    }

    private var pairs: [WeekPair] {
        var byWeek: [String: [DayNutritionHistory]] = [:]
        for day in history {
            byWeek[isoWeekKey(day.date), default: []].append(day)
        }
        return weeklyTonnage.compactMap { t -> WeekPair? in
            let wk = isoWeekKey(t.weekStart)
            guard let days = byWeek[wk] else { return nil }
            let evaluables = days.compactMap(inTarget)
            guard evaluables.count >= Self.minEvaluableDaysPerWeek else { return nil }
            let adh = Double(evaluables.filter { $0 }.count) / Double(evaluables.count)
            return WeekPair(weekStart: t.weekStart, adherence: adh,
                            evaluableDays: evaluables.count, volume: t.totalVolume)
        }.sorted { $0.weekStart < $1.weekStart }
    }

    private var verdict: CorrelationVerdict {
        CorrelationGuard.evaluate(xs: pairs.map(\.adherence), ys: pairs.map(\.volume))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NUTRITION → PERFORMANCE")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)

            if pairs.isEmpty {
                EmptyChartPlaceholder(message: "Activé après plusieurs semaines avec ≥ 4 jours évaluables chacune")
            } else {
                miniDualChart
                Text(verdict.message)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(Color.appOnSurface.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                CoverageWarning(included: pairs.count, expected: weeklyTonnage.count,
                                label: "semaines évaluables")
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
            .stroke(Color.forge, style: StrokeStyle(lineWidth: 2, lineCap: .round))

            Path { path in
                for (i, p) in pairs.enumerated() {
                    let x = CGFloat(i) * step
                    let y = h * (1 - CGFloat(p.adherence))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.appSuccess, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3]))
        }
        .frame(height: 60)

        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Rectangle().fill(Color.forge).frame(width: 16, height: 2)
                Text("Volume").font(.appMicro).foregroundColor(.gray)
            }
            HStack(spacing: 4) {
                Rectangle().fill(Color.appSuccess).frame(width: 16, height: 2)
                Text("Adhérence calories").font(.appMicro).foregroundColor(.gray)
            }
        }
    }
}
