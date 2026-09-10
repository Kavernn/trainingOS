import SwiftUI
import Charts

// MARK: - ACWR Card
struct ACWRCardView: View {
    let data: ACWRData

    private var formattedRatio: String {
        String(format: "%.2f", locale: Locale(identifier: "fr_CA"), data.ratio)
    }

    private var zoneColor: Color {
        switch data.zone.code {
        case "optimal":  return .appSuccess
        case "caution":  return .appWarning
        case "danger":   return .appDanger   // sang — toujours rouge, même en surgical
        case "under":    return .appTextSecondary
        default:         return .appTextMuted
        }
    }

    private var hasIncompleteHistory: Bool { data.daysOfData < 28 }
    private var factualZoneLabel: String {
        switch data.zone.code {
        case "under": return "Sous la plage 0,8–1,3"
        case "optimal": return "Dans la plage 0,8–1,3"
        case "caution": return "Au-dessus de la plage 0,8–1,3"
        case "danger": return "Au-dessus du seuil 1,5"
        default: return "Données insuffisantes"
        }
    }

    private var relativeLoadText: String {
        guard data.chronicLoad > 0 else { return "" }
        let pct = Int(round((data.ratio - 1.0) * 100))
        if pct == 0 {
            return "Charge récente au niveau de la référence 28 j"
        }
        let direction = pct > 0 ? "au-dessus de" : "sous"
        return "Charge récente : \(abs(pct)) % \(direction) la référence 28 j"
    }

    private var accessibilityZoneLabel: String {
        switch data.zone.code {
        case "under": return "Sous la plage de référence de 0,8 à 1,3."
        case "optimal": return "Dans la plage de référence de 0,8 à 1,3."
        case "caution": return "Au-dessus de la plage de référence de 0,8 à 1,3."
        case "danger": return "Au-dessus du seuil de 1,5."
        default: return ""
        }
    }

    private var accessibilitySummary: String {
        if hasIncompleteHistory {
            return "Charge interne. Historique de charge en construction. \(data.daysOfData) jours sur les 28 requis."
        }

        var parts = [
            "Charge interne.",
            "Ratio charge récente sur référence 28 jours : \(formattedRatio).",
            accessibilityZoneLabel
        ]
        if !relativeLoadText.isEmpty {
            parts.append("\(relativeLoadText).")
        }
        if data.trend.count > 1 {
            let current = data.trend.last.map { formattedRatio($0.ratio) } ?? formattedRatio
            parts.append("Tendance sur huit semaines. Valeur actuelle \(current).")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func formattedRatio(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "fr_CA"), value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RATIO CHARGE RÉCENTE / RÉFÉRENCE")
                    .font(.appMicro).tracking(2).foregroundColor(.appTextMuted)
                Spacer()
            }

            if hasIncompleteHistory {
                // Pas assez d'historique — ne pas afficher le ratio
                VStack(alignment: .leading, spacing: 8) {
                    Text("Historique en construction")
                        .font(.system(size: 22, weight: .bold)).foregroundColor(.appTextMuted)
                    Text("\(data.daysOfData) / 28 jours depuis la première charge enregistrée")
                        .font(.appCaption).foregroundColor(.appTextSecondary)
                    ProgressView(value: Double(data.daysOfData), total: 28)
                        .tint(.appTextMuted).frame(maxWidth: 160)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(formattedRatio)
                        .font(.system(size: 42, weight: .black))
                        .foregroundColor(.appTextPrimary)
                    Text(factualZoneLabel)
                        .font(.appCaption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(zoneColor.opacity(0.2))
                        .foregroundColor(zoneColor)
                        .clipShape(Capsule())

                    if !relativeLoadText.isEmpty {
                        Text(relativeLoadText)
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(.appTextSecondary)
                    }
                }
            }

            // Sparkline — seulement si données suffisantes
            if !hasIncompleteHistory, data.trend.count > 1 {
                ACWRSparkline(trend: data.trend)
            }
        }
        .padding(16).glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
}

private struct ACWRSparkline: View {
    let trend: [ACWRWeek]

    private let thresholds: [(Double, Color)] = [
        (1.5, Color.appDanger), (1.3, Color.appWarning), (0.8, Color.appTextMuted)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("ÉVOLUTION DU RATIO")
                    .font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.appTextMuted)
                Spacer()
                Text("8 SEMAINES")
                    .font(.appMicro.weight(.semibold)).foregroundColor(.appTextSecondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Plage de référence : 0,8–1,3")
                    .font(.appMicro).foregroundColor(.appTextSecondary)
                Spacer()
                if let currentRatio = trend.last?.ratio {
                    Text("Actuel · \(formattedRatio(currentRatio))")
                        .font(.appMicro.weight(.semibold)).foregroundColor(.appTextPrimary)
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let ratios = trend.map(\.ratio)
                let maxVal = max((ratios.max() ?? 1.6), 1.6)
                let step = w / CGFloat(trend.count - 1)

                ZStack(alignment: .topLeading) {
                    // Reference zone band (0.8–1.3)
                    let bandTop  = h * (1 - CGFloat(1.3 / maxVal))
                    let bandBot  = h * (1 - CGFloat(0.8 / maxVal))
                    Rectangle()
                        .fill(Color.appTextMuted.opacity(0.07))
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
                        .stroke(Color.appOnSurface.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        // Dots coloured by zone
                        ForEach(Array(trend.enumerated()), id: \.0) { i, week in
                            if week.ratio > 0 {
                                let x = CGFloat(i) * step
                                let y = h * (1 - CGFloat(week.ratio / maxVal))
                                let dot = dotColor(week.ratio)
                                let size: CGFloat = i == trend.count - 1 ? 8 : 5
                                Circle().fill(dot).frame(width: size, height: size).position(x: x, y: y)
                            }
                        }
                    }
                }
            }
            .frame(height: 70)

            // Relative labels only: the endpoint does not expose bucket dates.
            HStack {
                Text(relativeLabel(at: 0)).font(.appMicro).foregroundColor(.appTextMuted)
                Spacer()
                if trend.count > 2 {
                    Text(relativeLabel(at: trend.count / 2)).font(.appMicro).foregroundColor(.appTextMuted)
                    Spacer()
                }
                Text("Aujourd’hui").font(.appMicro).foregroundColor(.appTextMuted)
            }
        }
    }

    private func formattedRatio(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "fr_CA"), value)
    }

    private func relativeLabel(at index: Int) -> String {
        let weeksAgo = max(trend.count - 1 - index, 0)
        return weeksAgo == 1 ? "−1 sem." : "−\(weeksAgo) sem."
    }

    private func dotColor(_ ratio: Double) -> Color {
        if ratio == 0   { return .appTextMuted }
        if ratio < 0.8  { return .appTextSecondary }
        if ratio <= 1.3 { return Color.appSuccess }
        if ratio <= 1.5 { return Color.appWarning }
        return .appDanger
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
        case .none:  return Color.appSurfaceInset
        case .muscu: return Color.forge
        case .hiit:  return Color.gray
        case .both:  return Color.gray.opacity(0.5)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CALENDRIER D’ACTIVITÉ")
                    .font(.appMicro).tracking(2).foregroundColor(.gray)
                Spacer()
            }
            Text("Musculation + HIIT · 90 derniers jours")
                .font(.appCaption).foregroundColor(.gray)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 15), spacing: 3) {
                ForEach(cells, id: \.0) { date, type in
                    RoundedRectangle(cornerRadius: 2) // shape inline
                        .fill(cellColor(type))
                        .frame(height: 16)
                        .accessibilityLabel(cellAccessibilityLabel(date: date, type: type))
                }
            }
            HStack(spacing: 12) {
                Text("\(activeDays) jours avec activité").font(.appCaption).foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.forge).frame(width: 8, height: 8)
                    Text("Muscu").font(.appCaption).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.gray).frame(width: 8, height: 8)
                    Text("HIIT").font(.appCaption).foregroundColor(.gray)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.gray.opacity(0.5)).frame(width: 8, height: 8)
                    Text("Les 2").font(.appCaption).foregroundColor(.gray)
                }
            }
        }
        .padding(16).glassCard()
    }

    private func cellAccessibilityLabel(date: String, type: CellType) -> String {
        switch type {
        case .none: return "\(date). Aucune activité musculation ou HIIT."
        case .muscu: return "\(date). Musculation."
        case .hiit: return "\(date). HIIT."
        case .both: return "\(date). Musculation et HIIT."
        }
    }
}

// MARK: - Badges View
// MARK: - Week Comparison Card
// MARK: - Personal Records
struct PersonalRecordsView: View {
    let records: [RecentPR]
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("RECORDS RÉCENTS")
                    .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
                Spacer()
                Text("30 JOURS")
                    .font(.appCaption.weight(.semibold)).foregroundColor(.appTextSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Records récents, 30 jours")

            VStack(spacing: 8) {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(record.name)
                                .font(.appLabel)
                                .foregroundColor(.appTextPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(formattedDate(record.date))
                                .font(.appCaption)
                                .foregroundColor(.appTextSecondary)
                                .lineLimit(1)
                        }

                        Text("1RM estimé · \(units.format(record.est1RM, decimals: 0))")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(Color.domainAccent(.training))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(record.name). Record récent. 1RM estimé \(units.format(record.est1RM, decimals: 0)). \(formattedDate(record.date))."
                    )
                }
            }
        }
        .padding(16).glassCard()
    }

    private func formattedDate(_ rawDate: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: rawDate) else { return rawDate }
        let calendar = Calendar.mtl
        if calendar.isDateInToday(date) { return "Aujourd’hui" }
        if calendar.isDateInYesterday(date) { return "Hier" }
        return DateFormatter.shortDateFRCA.string(from: date)
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
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(data.enumerated()), id: \.0) { i, item in
                        let pct = maxVal > 0 ? item.1 / maxVal : 0
                        let isLast = i == data.count - 1
                        VStack(spacing: 0) {
                            Spacer()
                            RoundedRectangle(cornerRadius: 3) // shape inline
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
                        .font(.appMicro).foregroundColor(.gray)
                    Spacer()
                    if let last = data.last, last.1 > 0 {
                        Text(formatVal(last.1))
                            .font(.appMicro.weight(.bold)).foregroundColor(color)
                    }
                }
            }
        }
        .padding(12).glassCard()
        .frame(maxWidth: .infinity)
    }

    private func formatVal(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.0fK", v / 1000) }
        return String(format: "%.0f", v)
    }
}

// MARK: - Top 5 Volume
// MARK: - HIIT Stats
// MARK: - RPE Chart
struct RPEChartView: View {
    let data: [(String, Double)]
    var maxY: Double { 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ÉVOLUTION RPE")
                .font(.appMicro).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                ZStack {
                    ForEach([5.0, 7.0, 10.0], id: \.self) { level in
                        let y = geo.size.height * (1 - level / maxY)
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                            .stroke(Color.appSurfaceInset, lineWidth: 1)
                        Text("\(Int(level))")
                            .font(.appMicro).foregroundColor(.gray.opacity(0.5))
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
                        .stroke(Color.forge, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

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
                    Text("Dernière:").font(.appCaption).foregroundColor(.gray)
                    Text("RPE \(last.1, specifier: "%.1f")")
                        .font(.appCaption.weight(.bold)).foregroundColor(rpeColor(last.1))
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
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 22, weight: .black))
                .foregroundColor(isNull ? .gray.opacity(0.35) : color)
                .contentTransition(.numericText()).minimumScaleFactor(0.6).lineLimit(1)
            Text(label)
                .font(.appMicro.weight(.semibold)).tracking(1.3)
                .foregroundColor(.gray.opacity(0.65))
                .textCase(.uppercase).lineLimit(1)
            if let sub = subtitle {
                Text(sub)
                    .font(.appMicro).foregroundColor(.gray.opacity(0.45))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard()
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
                Text(name).font(.appBody.weight(.semibold)).foregroundColor(.appTextPrimary)
                if let reps = data.lastReps, !reps.isEmpty {
                    Text(reps).font(.appCaption).foregroundColor(.gray)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let w = data.currentWeight, w > 0 {
                    Text(units.format(w))
                        .font(.appHeadline.weight(.black)).foregroundColor(Color.forge)
                    if let history = data.history, history.count > 1,
                       let first = history.last?.weight, let last = history.first?.weight,
                       first > 0, last > 0 {
                        let diff = last - first
                        Text(diff >= 0 ? "+\(diff, specifier: "%.1f")" : "\(diff, specifier: "%.1f")")
                            .font(.appCaption).foregroundColor(diff >= 0 ? .appSuccess : .appDanger)
                    }
                } else {
                    Text("Poids corps")
                        .font(.appCaption.weight(.medium))
                        .foregroundColor(Color.gray.opacity(0.7))
                }
            }
            Image(systemName: "chevron.right").font(.appCaption).foregroundColor(.gray)
        }
        .padding(14).glassCard()
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
                                    .font(.system(size: 42, weight: .black)).foregroundColor(Color.forge)
                            }
                            if let reps = data?.lastReps {
                                Text("Dernières reps: \(reps)").font(.appBody).foregroundColor(.gray)
                            }
                        }
                        .padding()

                        if let history = data?.history, !history.isEmpty {
                            StrengthCurveChart(exerciseName: name, history: history)
                                .padding(.horizontal, 16)
                        }

                        if let history = data?.history, !history.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("HISTORIQUE")
                                    .font(.appMicro).tracking(2).foregroundColor(.gray)
                                ForEach(history, id: \.date) { entry in
                                    HStack {
                                        Text(entry.date ?? "—").font(.appLabel).foregroundColor(.gray)
                                        Spacer()
                                        Text(units.format(entry.weight ?? 0))
                                            .font(.appBody.weight(.semibold)).foregroundColor(.appTextPrimary)
                                        Text(entry.reps ?? "").font(.appLabel).foregroundColor(.gray)
                                        if let note = entry.note, !note.isEmpty {
                                            Text(note).font(.appCaption.weight(.semibold))
                                                .foregroundColor(note.hasPrefix("+") ? .appSuccess : .appWarning)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    Divider().background(Color.appSeparator)
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
                            Image(systemName: "square.and.arrow.up").foregroundColor(Color.forge)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }.foregroundColor(Color.forge)
                }
            }
        }
    }
}

// MARK: - Training Load Chart
// MARK: - Energy Trend
struct EnergyTrendView: View {
    let data: [(String, Int)]   // (date, energy 1-5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ÉNERGIE PRÉ-SÉANCE")
                .font(.appMicro).tracking(2).foregroundColor(.gray)

            GeometryReader { geo in
                let step = data.count > 1 ? geo.size.width / CGFloat(data.count - 1) : geo.size.width
                ZStack {
                    // Grid lines at 1,3,5
                    ForEach([1, 3, 5], id: \.self) { level in
                        let y = geo.size.height * (1 - CGFloat(level - 1) / 4.0)
                        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                            .stroke(Color.appSurfaceInset, lineWidth: 1)
                        Text("\(level)").font(.appMicro).foregroundColor(.gray.opacity(0.4))
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
                        .stroke(Color.forge, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

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
                Text("1 = Épuisé").font(.appMicro).foregroundColor(.appDanger)
                Spacer()
                if let last = data.last {
                    Text("Dernière: \(energyLabel(last.1))")
                        .font(.appMicro.weight(.bold)).foregroundColor(energyColor(last.1))
                }
                Spacer()
                Text("5 = Excellent").font(.appMicro).foregroundColor(.appSuccess)
            }
        }
        .padding(16).background(Color.appCard).cornerRadius(14)
    }

    private func energyColor(_ v: Int) -> Color { v >= 4 ? .appSuccess : v == 3 ? .appWarning : .appDanger }
    private func energyLabel(_ v: Int) -> String {
        ["", "Épuisé 😴", "Fatigué 😕", "Normal 😐", "En forme 💪", "Excellent ⚡"][v]
    }
}

// MARK: - Pattern Volume Chart
// MARK: - Programme Compliance
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TENDANCE 1RM — BLOC ACTIF")
                    .font(.appMicro).tracking(2).foregroundColor(.gray)
                Spacer()
                if let last = points.last, let first = points.first, last.oneRM > first.oneRM {
                    Text("+\(String(format: "%.1f", last.oneRM - first.oneRM)) \(units.label)")
                        .font(.appMicro.weight(.semibold)).foregroundColor(.appSuccess)
                }
            }
            if exercises.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(exercises, id: \.self) { ex in
                            Button {
                                withAnimation { selectedExercise = ex }
                            } label: {
                                Text(ex)
                                    .font(.appMicro.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(currentExercise == ex ? Color.forge : Color.appSurfaceInset)
                                    .foregroundColor(currentExercise == ex ? Color.onAccent : .gray)
                                    .clipShape(Capsule())
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
                        .stroke(Color.forge, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                        ForEach(Array(points.enumerated()), id: \.0) { i, pt in
                            let x = CGFloat(i) * step
                            let y = geo.size.height * (1 - CGFloat((pt.oneRM - lo) / span))
                            Circle().fill(Color.forge).frame(width: 6, height: 6)
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
        ("<7",   data.lt7,   Color.forge.opacity(0.30)),
        ("7–8",  data.r7_8,  Color.forge.opacity(0.55)),
        ("8–9",  data.r8_9,  Color.forge.opacity(0.75)),
        ("9–10", data.r9_10, Color.forge),
    ]}
    private var maxAbs: Double {
        buckets.compactMap { $0.1 }.map { abs($0) }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUELLE INTENSITÉ TE FAIT PROGRESSER ?")
                .font(.appMicro).tracking(2).foregroundColor(.gray)
            Text("Gain de charge moyen sur la séance suivante par zone d'intensité")
                .font(.appMicro).foregroundColor(.gray.opacity(0.7))
            GeometryReader { outer in
                VStack(spacing: 12) {
                    ForEach(buckets, id: \.0) { name, val, color in
                        let pct = val.map { abs($0) / max(maxAbs, 1) } ?? 0
                        let c = (val ?? 0) >= 0 ? color : Color.appDanger
                        let barW = outer.size.width - 126
                        HStack(spacing: 8) {
                            Text("RPE \(name)")
                                .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                                .frame(width: 60, alignment: .leading)
                            HStack(spacing: 0) {
                                RoundedRectangle(cornerRadius: 3) // shape inline.fill(c).frame(width: max(barW * CGFloat(pct), 2), height: 14)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 14)
                            if let v = val {
                                Text(v >= 0 ? "+\(String(format: "%.1f", v))%" : "\(String(format: "%.1f", v))%")
                                    .font(.appMicro.weight(.semibold))
                                    .foregroundColor((v) >= 0 ? .appSuccess : .appDanger)
                                    .frame(width: 50, alignment: .trailing)
                            } else {
                                Text("—").font(.appMicro).foregroundColor(.gray).frame(width: 50, alignment: .trailing)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("RIR MOYEN PAR EXERCICE")
                .font(.appMicro).tracking(2).foregroundColor(.gray)
            Text("Reps In Reserve — distance à l'échec musculaire")
                .font(.appMicro).foregroundColor(.gray.opacity(0.7))
            GeometryReader { outer in
                VStack(spacing: 12) {
                    ForEach(entries.prefix(8)) { e in
                        let pct = maxRIR > 0 ? e.avgRir / maxRIR : 0
                        let c: Color = e.avgRir <= 1 ? .appDanger : e.avgRir <= 2 ? .appWarning : .appSuccess
                        let barW = outer.size.width - 164
                        HStack(spacing: 8) {
                            Text(e.exercise)
                                .font(.appMicro.weight(.semibold)).foregroundColor(.appTextPrimary)
                                .frame(width: 120, alignment: .leading).lineLimit(1)
                            RoundedRectangle(cornerRadius: 3) // shape inline.fill(c.opacity(0.7))
                                .frame(width: barW * CGFloat(pct), height: 12)
                            Spacer(minLength: 0)
                            Text(String(format: "%.1f", e.avgRir))
                                .font(.appMicro.weight(.bold)).foregroundColor(c)
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

// MARK: - Top 5 Frequency View
// MARK: - Preview ACWR danger zone (Sin City N&B test)
// Vérifier que le rouge surgit UNIQUEMENT ici en mode surgical.
// À supprimer après validation device.
#Preview("ACWR — Danger (Sin City)") {
    let dangerZone = ACWRData(
        ratio: 1.65,
        acuteLoad: 825,
        chronicLoad: 500,
        zone: ACWRZone(
            code: "danger",
            label: "Danger (surmenage)",
            color: "red",
            recommendation: "Réduire l'intensité immédiatement. Risque de blessure élevé."
        ),
        trend: [
            ACWRWeek(week: "S-7", ratio: 0.95, acute: 460, chronic: 480),
            ACWRWeek(week: "S-6", ratio: 1.05, acute: 510, chronic: 490),
            ACWRWeek(week: "S-5", ratio: 1.10, acute: 550, chronic: 500),
            ACWRWeek(week: "S-4", ratio: 1.20, acute: 600, chronic: 500),
            ACWRWeek(week: "S-3", ratio: 1.35, acute: 675, chronic: 500),
            ACWRWeek(week: "S-2", ratio: 1.50, acute: 750, chronic: 500),
            ACWRWeek(week: "S-1", ratio: 1.65, acute: 825, chronic: 500)
        ],
        confidence: "high",
        daysOfData: 28
    )
    ScrollView {
        ACWRCardView(data: dangerZone)
            .padding()
    }
    .background(Color.appBg)
    .environmentObject(AppTheme.shared)
    .onAppear { AppTheme.shared.applyTheme(.sinCity) }
}

// MARK: - Stats Hero Card
