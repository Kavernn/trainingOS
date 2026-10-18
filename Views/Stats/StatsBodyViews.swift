import SwiftUI
import Charts

// MARK: - BodyProgressionColor
/// Palette unique pour les deltas Body (poids, masse grasse, tour de taille).
///
/// Règle : vert si le delta va dans le sens de l'objectif, forge sinon,
/// neutre (appTextSecondary) si |delta| ≤ zone morte OU si le goal est inconnu.
///
/// Zones mortes (absorbent le bruit de mesure) :
///  - weight   : ±1 % de `start` (eau/glycogène/sodium). Repli ±1 lb si start absent.
///  - bodyFat  : ±0,5 pp absolu (bruit Navy ±3 pp sur mesure isolée, systématique si conditions constantes).
///  - waist    : ±1 cm absolu (respiration, technique de mesure).
///
/// Goal :
///  - cut      → perte alignée, prise contrariée
///  - bulk     → prise alignée, perte contrariée
///  - maintain, recomp → tout écart hors zone morte = contrarié (dérive)
///  - nil / inconnu    → neutre (jamais d'objectif par défaut)
///
/// Masse grasse et tour de taille : toujours "lower is better", indépendants du goal.
enum BodyProgressionColor {
    enum Metric { case weight, bodyFat, waist }
    enum Direction { case aligned, misaligned, neutral }

    static func direction(delta: Double, start: Double?, metric: Metric, goal: String?) -> Direction {
        if inDeadZone(delta: delta, start: start, metric: metric) { return .neutral }
        switch metric {
        case .bodyFat, .waist:
            return delta < 0 ? .aligned : .misaligned
        case .weight:
            guard let g = goal?.lowercased() else { return .neutral }
            switch g {
            case "cut":                return delta < 0 ? .aligned : .misaligned
            case "bulk":               return delta > 0 ? .aligned : .misaligned
            case "maintain", "recomp": return .misaligned
            default:                   return .neutral
            }
        }
    }

    static func color(delta: Double, start: Double?, metric: Metric, goal: String?) -> Color {
        switch direction(delta: delta, start: start, metric: metric, goal: goal) {
        case .aligned:    return .statusGreen
        case .misaligned: return .forge
        case .neutral:    return .appTextSecondary
        }
    }

    private static func inDeadZone(delta: Double, start: Double?, metric: Metric) -> Bool {
        let threshold: Double
        switch metric {
        case .weight:  threshold = (start.map { abs($0) * 0.01 }) ?? 1.0
        case .bodyFat: threshold = 0.5
        case .waist:   threshold = 1.0
        }
        return abs(delta) <= threshold
    }
}

// MARK: - Body trajectories
private struct StatsBodyTrajectoryPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
}

struct StatsBodyOverviewHero: View {
    let entries: [BodyWeightEntry]
    let filteredEntries: [BodyWeightEntry]
    let period: StatsPeriod
    @ObservedObject private var units = UnitSettings.shared

    private var weightEntry: BodyWeightEntry? {
        entries.first(where: { $0.weight > 0 })
    }

    private var waistEntry: BodyWeightEntry? {
        entries.first(where: { ($0.waistCm ?? 0) > 0 })
    }

    private var bodyFatEntry: BodyWeightEntry? {
        entries.first(where: { ($0.bodyFat ?? 0) > 0 })
    }

    private var hasBodyMetric: Bool {
        weightEntry != nil || waistEntry != nil || bodyFatEntry != nil
    }

    private var secondaryDatesDiffer: Bool {
        guard let waistEntry, let bodyFatEntry else { return false }
        return waistEntry.date != bodyFatEntry.date
    }

    private var points: [StatsBodyTrajectoryPoint] {
        filteredEntries.reversed().compactMap { entry in
            guard entry.weight > 0, let date = DateFormatter.isoDate.date(from: entry.date) else { return nil }
            return StatsBodyTrajectoryPoint(id: "\(entry.date)-weight", date: date, value: entry.weight)
        }
    }

    private var weightDelta: Double? {
        guard points.count >= 2 else { return nil }
        return points[points.count - 1].value - points[0].value
    }

    private var periodLabel: String {
        switch period {
        case .month1: return "1 MOIS"
        case .month3: return "3 MOIS"
        case .month6: return "6 MOIS"
        case .all: return "TOUT"
        }
    }

    private var accessibilitySummary: String {
        guard hasBodyMetric else {
            return "Évolution corporelle, période \(periodLabel.lowercased()). Aucune mesure corporelle disponible."
        }

        var parts = ["Évolution corporelle, période \(periodLabel.lowercased())."]
        if let weightEntry {
            parts.append("Poids \(units.format(weightEntry.weight, decimals: 1)), mesuré \(spokenDate(weightEntry.date)).")
        }
        if let weightDelta {
            parts.append("Variation de la première à la dernière mesure : \(formattedWeightDelta(weightDelta)).")
        } else if points.count == 1 {
            parts.append("Une seule mesure de poids sur cette période.")
        } else if weightEntry != nil {
            parts.append("Aucune mesure de poids sur cette période.")
        }
        if let waistEntry, let waist = waistEntry.waistCm {
            parts.append("Tour de taille \(formattedDecimal(waist)) centimètres, mesuré \(spokenDate(waistEntry.date)).")
        }
        if let bodyFatEntry, let bodyFat = bodyFatEntry.bodyFat {
            parts.append("Masse grasse \(formattedDecimal(bodyFat)) pour cent, mesurée \(spokenDate(bodyFatEntry.date)).")
        }
        if secondaryDatesDiffer {
            parts.append("Les dernières valeurs peuvent provenir de dates différentes.")
        }
        return parts.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("ÉVOLUTION CORPORELLE")
                        .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
                    Spacer()
                    Text(periodLabel)
                        .font(.appCaption.weight(.semibold)).foregroundColor(.appTextSecondary)
                }

                if !hasBodyMetric {
                    Text("Aucune mesure corporelle disponible.")
                        .font(.appBody).foregroundColor(.appTextSecondary)
                } else {
                    weightSection

                    if waistEntry != nil || bodyFatEntry != nil {
                        secondaryMetrics
                    }

                    if secondaryDatesDiffer {
                        Text("Les dernières valeurs peuvent provenir de dates différentes.")
                            .font(.appMicro).foregroundColor(.appTextMuted)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)

            Divider().overlay(Color.appSeparatorSubtle)

            NavigationLink {
                BodyCompView()
            } label: {
                HStack {
                    Text("Gérer les mesures")
                        .font(.appLabel.weight(.semibold)).foregroundColor(.appTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appCaption.weight(.semibold)).foregroundColor(.appTextSecondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre la gestion des mesures corporelles.")
        }
        .padding(16).background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
    }

    @ViewBuilder
    private var weightSection: some View {
        if let weightEntry {
            VStack(alignment: .leading, spacing: 4) {
                Text("POIDS")
                    .font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.appTextMuted)
                Text(units.format(weightEntry.weight, decimals: 1))
                    .font(.appTitle.weight(.bold)).foregroundColor(.appTextPrimary)
                Text(displayDate(weightEntry.date))
                    .font(.appCaption).foregroundColor(.appTextSecondary)
            }

            if points.count >= 2 {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Poids", units.display(point.value)))
                        .foregroundStyle(Color.appTextSecondary)
                    PointMark(x: .value("Date", point.date), y: .value("Poids", units.display(point.value)))
                        .foregroundStyle(
                            point.id == points.last?.id
                                ? Color.domainAccent(.training)
                                : Color.appTextSecondary
                        )
                        .symbolSize(point.id == points.last?.id ? 55 : 20)
                }
                .chartYAxisLabel(units.label)
                .frame(height: 130)
                .accessibilityHidden(true)

                if let weightDelta {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Première → dernière mesure")
                            .font(.appCaption).foregroundColor(.appTextSecondary)
                        Spacer()
                        Text(formattedWeightDelta(weightDelta))
                            .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                    }
                }
            } else if points.count == 1 {
                Text("Une seule mesure sur cette période.")
                    .font(.appCaption).foregroundColor(.appTextSecondary)
            } else {
                Text("Aucune mesure de poids sur cette période.")
                    .font(.appCaption).foregroundColor(.appTextSecondary)
            }
        }
    }

    // MARK: - Secondary metrics (waist + body fat sparklines)

    private struct SecondaryPoint: Identifiable {
        let id: String
        let date: Date
        let value: Double
    }

    private func secondarySeries(_ extract: (BodyWeightEntry) -> Double?) -> [SecondaryPoint] {
        filteredEntries.reversed().compactMap { entry in
            guard let v = extract(entry), v > 0,
                  let date = DateFormatter.isoDate.date(from: entry.date) else { return nil }
            return SecondaryPoint(id: "\(entry.date)-\(v)", date: date, value: v)
        }
    }

    private var waistPoints: [SecondaryPoint]   { secondarySeries { $0.waistCm } }
    private var bodyFatPoints: [SecondaryPoint] { secondarySeries { $0.bodyFat } }

    /// Nombre de semaines théorique de la période sélectionnée. nil pour `.all`
    /// (pas de notion de "fenêtre tronquée" à afficher).
    private var periodWeeks: Int? {
        switch period {
        case .month1: return 4
        case .month3: return 13
        case .month6: return 26
        case .all:    return nil
        }
    }

    private func seriesDelta(_ pts: [SecondaryPoint]) -> Double? {
        guard let first = pts.first, let last = pts.last, pts.count >= 2 else { return nil }
        return last.value - first.value
    }

    private func coverageWeeks(_ pts: [SecondaryPoint]) -> Int? {
        guard let oldest = pts.first else { return nil }
        let days = Calendar.mtl.dateComponents([.day], from: oldest.date, to: Date()).day ?? 0
        return max(1, Int(ceil(Double(days) / 7.0)))
    }

    private var secondaryMetrics: some View {
        HStack(alignment: .top, spacing: 12) {
            if let waistEntry, let waist = waistEntry.waistCm {
                secondaryMetric(
                    title: "TOUR DE TAILLE",
                    value: "\(formattedDecimal(waist)) cm",
                    date: waistEntry.date,
                    points: waistPoints,
                    metric: .waist,
                    deltaSuffix: "cm",
                    deltaDecimals: 1
                )
            }
            if let bodyFatEntry, let bodyFat = bodyFatEntry.bodyFat {
                secondaryMetric(
                    title: "MASSE GRASSE",
                    value: "\(formattedDecimal(bodyFat)) %",
                    date: bodyFatEntry.date,
                    points: bodyFatPoints,
                    metric: .bodyFat,
                    deltaSuffix: "%",
                    deltaDecimals: 1
                )
            }
        }
    }

    private func secondaryMetric(
        title: String,
        value: String,
        date: String,
        points: [SecondaryPoint],
        metric: BodyProgressionColor.Metric,
        deltaSuffix: String,
        deltaDecimals: Int
    ) -> some View {
        let delta = seriesDelta(points)
        let start = points.first?.value
        let color: Color = delta.map {
            BodyProgressionColor.color(delta: $0, start: start, metric: metric, goal: nil)
        } ?? .appTextSecondary

        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appMicro.weight(.bold)).foregroundColor(.appTextMuted)
            Text(value)
                .font(.appHeadline.weight(.semibold)).foregroundColor(.appTextPrimary)
            if points.count >= 2 {
                Chart(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value("v", p.value))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", p.date), y: .value("v", p.value))
                        .foregroundStyle(color)
                        .symbolSize(4)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 20)
            }
            if let delta {
                let sign = delta > 0 ? "+" : (delta < 0 ? "−" : "")
                let magnitude = String(
                    format: "%.\(deltaDecimals)f", locale: Locale(identifier: "fr_CA"), abs(delta)
                )
                HStack(spacing: 6) {
                    Text("\(sign)\(magnitude) \(deltaSuffix)")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(color).monospacedDigit()
                    if let weeks = coverageWeeks(points),
                       let periodWeeks, weeks < periodWeeks {
                        Text("sur \(weeks) sem")
                            .font(.appMicro).foregroundColor(.appTextMuted)
                    }
                }
            }
            Text(displayDate(date))
                .font(.appMicro).foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedWeightDelta(_ value: Double) -> String {
        let formatted = units.format(abs(value), decimals: 1)
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "−\(formatted)" }
        return units.format(0, decimals: 1)
    }

    private func formattedDecimal(_ value: Double) -> String {
        let decimals = value.rounded() == value ? 0 : 1
        return String(format: "%.\(decimals)f", locale: Locale(identifier: "fr_CA"), value)
    }

    private func displayDate(_ rawDate: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: rawDate) else { return rawDate }
        let calendar = Calendar.mtl
        if calendar.isDateInToday(date) { return "Aujourd’hui" }
        if calendar.isDateInYesterday(date) { return "Hier" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return DateFormatter.shortDateFRCA.string(from: date)
        }
        return Self.longDateFormatter.string(from: date)
    }

    private func spokenDate(_ rawDate: String) -> String {
        displayDate(rawDate).lowercased()
    }

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.timeZone = TimeZone(identifier: "America/Montreal") ?? .current
        return formatter
    }()
}

struct StatsBodyFatTrajectoryView: View {
    let entries: [BodyWeightEntry]
    let period: StatsPeriod

    private var points: [StatsBodyTrajectoryPoint] {
        entries.reversed().compactMap { entry in
            guard let bodyFat = entry.bodyFat, bodyFat > 0,
                  let date = DateFormatter.isoDate.date(from: entry.date) else { return nil }
            return StatsBodyTrajectoryPoint(id: "\(entry.date)-body-fat", date: date, value: bodyFat)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("MASSE GRASSE")
                    .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
                Spacer()
                Text(StatsBodyDetailFormatting.periodLabel(period))
                    .font(.appCaption.weight(.semibold)).foregroundColor(.appTextSecondary)
            }

            if points.isEmpty {
                Text("Pas de valeur de masse grasse sur la période.")
                    .font(.appBody).foregroundColor(.appTextSecondary)
            } else if points.count == 1 {
                Text("Une seule mesure sur cette période.")
                    .font(.appBody).foregroundColor(.appTextSecondary)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Masse grasse", point.value))
                        .foregroundStyle(Color.appTextSecondary)
                    PointMark(x: .value("Date", point.date), y: .value("Masse grasse", point.value))
                        .foregroundStyle(
                            point.id == points.last?.id
                                ? Color.domainAccent(.training)
                                : Color.appTextSecondary
                        )
                        .symbolSize(point.id == points.last?.id ? 55 : 20)
                }
                .chartYAxisLabel("%")
                .frame(height: 150)
                .accessibilityHidden(true)

                let first = points[0].value
                let last = points[points.count - 1].value
                HStack(alignment: .firstTextBaseline) {
                    Text("Première → dernière mesure")
                        .font(.appCaption).foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(formatDelta(last - first))
                        .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func formatDelta(_ value: Double) -> String {
        let magnitude = StatsBodyDetailFormatting.decimal(abs(value))
        let unit = StatsBodyDetailFormatting.isDisplayedAsOne(value) ? "point" : "points"
        if value > 0 { return "+\(magnitude) \(unit)" }
        if value < 0 { return "−\(magnitude) \(unit)" }
        return "0 point"
    }

    private var accessibilityText: String {
        let periodText = StatsBodyDetailFormatting.spokenPeriodLabel(period)
        guard let first = points.first else {
            return "Masse grasse, période \(periodText). Pas de valeur sur cette période."
        }
        guard let last = points.last, points.count > 1 else {
            return "Masse grasse, période \(periodText). Une seule mesure, \(formatPercent(first.value)), \(StatsBodyDetailFormatting.spokenDate(first.date))."
        }
        let delta = last.value - first.value
        return "Masse grasse, période \(periodText). Première mesure \(formatPercent(first.value)) \(StatsBodyDetailFormatting.spokenDate(first.date)). Dernière mesure \(formatPercent(last.value)) \(StatsBodyDetailFormatting.spokenDate(last.date)). Variation de la première à la dernière mesure : \(spokenDelta(delta))."
    }

    private func spokenDelta(_ value: Double) -> String {
        let magnitude = StatsBodyDetailFormatting.decimal(abs(value))
        let unit = StatsBodyDetailFormatting.isDisplayedAsOne(value)
            ? "point de pourcentage"
            : "points de pourcentage"
        if value > 0 { return "plus \(magnitude) \(unit)" }
        if value < 0 { return "moins \(magnitude) \(unit)" }
        return "0 point de pourcentage"
    }

    private func formatPercent(_ value: Double) -> String {
        "\(StatsBodyDetailFormatting.decimal(value)) pour cent"
    }
}

private enum StatsBodyDetailFormatting {
    static func periodLabel(_ period: StatsPeriod) -> String {
        switch period {
        case .month1: return "1 MOIS"
        case .month3: return "3 MOIS"
        case .month6: return "6 MOIS"
        case .all: return "TOUT"
        }
    }

    static func spokenPeriodLabel(_ period: StatsPeriod) -> String {
        periodLabel(period).lowercased()
    }

    static func decimal(_ value: Double) -> String {
        let decimals = value.rounded() == value ? 0 : 1
        return String(format: "%.\(decimals)f", locale: Locale(identifier: "fr_CA"), value)
    }

    static func isDisplayedAsOne(_ value: Double) -> Bool {
        (abs(value) * 10).rounded() / 10 == 1
    }

    static func spokenDate(_ date: Date) -> String {
        let calendar = Calendar.mtl
        if calendar.isDateInToday(date) { return "aujourd’hui" }
        if calendar.isDateInYesterday(date) { return "hier" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return "le \(DateFormatter.shortDateFRCA.string(from: date))"
        }
        return "le \(longDateFormatter.string(from: date))"
    }

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.timeZone = TimeZone(identifier: "America/Montreal") ?? .current
        return formatter
    }()
}

// MARK: - Body measurements history
struct StatsBodyMeasurementsHistoryView: View {
    let entries: [BodyWeightEntry]
    let period: StatsPeriod
    @State private var selectedKind: StatsBodyMeasurementKind?

    private var availableKinds: [StatsBodyMeasurementKind] {
        StatsBodyMeasurementKind.allCases.filter { kind in
            entries.contains { (kind.value(in: $0) ?? 0) > 0 }
        }
    }

    private var effectiveKind: StatsBodyMeasurementKind? {
        guard let selectedKind, availableKinds.contains(selectedKind) else { return availableKinds.first }
        return selectedKind
    }

    private var points: [StatsBodyTrajectoryPoint] {
        guard let kind = effectiveKind else { return [] }
        return entries.reversed().compactMap { entry in
            guard let value = kind.value(in: entry), value > 0,
                  let date = DateFormatter.isoDate.date(from: entry.date) else { return nil }
            return StatsBodyTrajectoryPoint(id: "\(entry.date)-\(kind.id)", date: date, value: value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("MENSURATIONS")
                    .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
                Spacer()
                Text(StatsBodyDetailFormatting.periodLabel(period))
                    .font(.appCaption.weight(.semibold)).foregroundColor(.appTextSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)

            if availableKinds.isEmpty {
                Text("Pas de mensuration disponible sur la période.")
                    .font(.appBody).foregroundColor(.appTextSecondary)
                    .accessibilityHidden(true)
            } else if let kind = effectiveKind {
                Menu {
                    ForEach(availableKinds) { option in
                        Button(option.title) { selectedKind = option }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(kind.title).font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                        Image(systemName: "chevron.down").font(.appMicro).foregroundColor(.appTextSecondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.appSurfaceInset)
                    .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
                }
                .accessibilityLabel("Mensuration sélectionnée : \(kind.title)")
                .accessibilityHint("Choisir la mensuration affichée.")

                if points.count == 1 {
                    Text("Une seule mesure sur cette période.")
                        .font(.appBody).foregroundColor(.appTextSecondary)
                        .accessibilityHidden(true)
                } else if points.count >= 2 {
                    Chart(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value(kind.title, point.value))
                            .foregroundStyle(Color.appTextSecondary)
                        PointMark(x: .value("Date", point.date), y: .value(kind.title, point.value))
                            .foregroundStyle(
                                point.id == points.last?.id
                                    ? Color.domainAccent(.training)
                                    : Color.appTextSecondary
                            )
                            .symbolSize(point.id == points.last?.id ? 55 : 20)
                    }
                    .chartYAxisLabel("cm")
                    .frame(height: 150)
                    .accessibilityHidden(true)

                    let first = points[0].value
                    let last = points[points.count - 1].value
                    HStack(alignment: .firstTextBaseline) {
                        Text("Première → dernière mesure")
                            .font(.appCaption).foregroundColor(.appTextSecondary)
                        Spacer()
                        Text(formatDelta(last - first))
                            .font(.appCaption.weight(.semibold)).foregroundColor(.appTextPrimary)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
    }

    private func formatCentimeters(_ value: Double) -> String {
        "\(StatsBodyDetailFormatting.decimal(value)) cm"
    }

    private func formatDelta(_ value: Double) -> String {
        let magnitude = formatCentimeters(abs(value))
        if value > 0 { return "+\(magnitude)" }
        if value < 0 { return "−\(magnitude)" }
        return formatCentimeters(0)
    }

    private var accessibilityText: String {
        let periodText = StatsBodyDetailFormatting.spokenPeriodLabel(period)
        guard let kind = effectiveKind, let first = points.first else {
            return "Mensurations, période \(periodText). Pas de mensuration disponible sur cette période."
        }
        guard let last = points.last, points.count > 1 else {
            return "Mensurations. \(kind.title). Période \(periodText). Une seule mesure, \(spokenCentimeters(first.value)), \(StatsBodyDetailFormatting.spokenDate(first.date))."
        }
        let delta = last.value - first.value
        return "Mensurations. \(kind.title). Période \(periodText). Première mesure \(spokenCentimeters(first.value)) \(StatsBodyDetailFormatting.spokenDate(first.date)). Dernière mesure \(spokenCentimeters(last.value)) \(StatsBodyDetailFormatting.spokenDate(last.date)). Variation de la première à la dernière mesure : \(spokenDelta(delta))."
    }

    private func spokenCentimeters(_ value: Double) -> String {
        "\(StatsBodyDetailFormatting.decimal(value)) centimètres"
    }

    private func spokenDelta(_ value: Double) -> String {
        let magnitude = spokenCentimeters(abs(value))
        if value > 0 { return "plus \(magnitude)" }
        if value < 0 { return "moins \(magnitude)" }
        return spokenCentimeters(0)
    }
}

private enum StatsBodyMeasurementKind: String, CaseIterable, Identifiable {
    case waist, neck, arms, chest, thighs, hips

    var id: String { rawValue }
    var title: String {
        switch self {
        case .waist: return "Tour de taille"
        case .neck: return "Cou"
        case .arms: return "Bras"
        case .chest: return "Poitrine"
        case .thighs: return "Cuisses"
        case .hips: return "Hanches"
        }
    }

    func value(in entry: BodyWeightEntry) -> Double? {
        switch self {
        case .waist: return entry.waistCm
        case .neck: return entry.neckCm
        case .arms: return entry.armsCm
        case .chest: return entry.chestCm
        case .thighs: return entry.thighsCm
        case .hips: return entry.hipsCm
        }
    }
}

// MARK: - Measurements Trend
// MARK: - Season Comparison Card
struct SeasonComparisonCard: View {
    let data: SeasonComparisonData
    /// Goal en cours (profile.goal). Nil → cellule neutre. Option A : seule la
    /// saison courante est colorée via ce goal ; les précédentes n'ont pas de
    /// snapshot goal, donc toujours neutres (voir weightCell).
    let currentGoal: String?
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(Color.forge).font(.appCaption)
                Text("COMPARAISON SAISONS")
                    .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
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
        let hasBodyFat =
            (current.bodyFatStart != nil && current.bodyFatEnd != nil)
            || (previous?.bodyFatStart != nil && previous?.bodyFatEnd != nil)

        HStack(alignment: .top, spacing: 0) {
            // Labels
            VStack(alignment: .leading, spacing: 12) {
                Text("").frame(height: 16)
                Text("Vol. moy/sem").font(.appCaption).foregroundColor(.gray).frame(height: 18, alignment: .leading)
                Text("Séances").font(.appCaption).foregroundColor(.gray).frame(height: 18, alignment: .leading)
                Text("PSS moy.").font(.appCaption).foregroundColor(.gray).frame(height: 18, alignment: .leading)
                Text("Poids").font(.appCaption).foregroundColor(.gray).frame(height: 40, alignment: .leading)
                if hasBodyFat {
                    Text("Masse grasse").font(.appCaption).foregroundColor(.gray).frame(height: 40, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Current saison
            VStack(alignment: .center, spacing: 12) {
                Text(current.title ?? "En cours")
                    .font(.appCaption.weight(.bold)).foregroundColor(Color.forge)
                    .lineLimit(1).frame(height: 16)
                valCell(current.volumeAvgWeek.map { units.format($0, decimals: 0) })
                valCell(current.sessionsCount.map { "\($0)" })
                valCell(current.pssAvg.map { "\($0)" })
                beforeAfterCell(start: current.weightStartLbs, end: current.weightEndLbs,
                                metric: .weight, goal: currentGoal)
                if hasBodyFat {
                    beforeAfterCell(start: current.bodyFatStart, end: current.bodyFatEnd,
                                    metric: .bodyFat, goal: nil)
                }
            }
            .frame(maxWidth: .infinity)

            if let prev = previous {
                // Middle Δ% arrows — vide pour les lignes Poids / Masse grasse
                VStack(alignment: .center, spacing: 12) {
                    Text("").frame(height: 16)
                    deltaArrow(current.volumeAvgWeek, prev.volumeAvgWeek, higherBetter: true)
                    deltaArrow(current.sessionsCount.map(Double.init), prev.sessionsCount.map(Double.init), higherBetter: true)
                    deltaArrow(current.pssAvg.map(Double.init), prev.pssAvg.map(Double.init), higherBetter: false)
                    Text("").frame(height: 40)
                    if hasBodyFat { Text("").frame(height: 40) }
                }
                .frame(width: 40)

                // Previous saison — passée, toujours neutre (pas de snapshot goal)
                VStack(alignment: .center, spacing: 12) {
                    Text(prev.title ?? "Précédente")
                        .font(.appCaption.weight(.bold)).foregroundColor(.gray)
                        .lineLimit(1).frame(height: 16)
                    valCell(prev.volumeAvgWeek.map { units.format($0, decimals: 0) }, dim: true)
                    valCell(prev.sessionsCount.map { "\($0)" }, dim: true)
                    valCell(prev.pssAvg.map { "\($0)" }, dim: true)
                    beforeAfterCell(start: prev.weightStartLbs, end: prev.weightEndLbs,
                                    metric: .weight, goal: nil, dim: true)
                    if hasBodyFat {
                        beforeAfterCell(start: prev.bodyFatStart, end: prev.bodyFatEnd,
                                        metric: .bodyFat, goal: nil, dim: true)
                    }
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

    /// Cellule "avant → après" pour une métrique Body : affiche `start → end` en
    /// première ligne + delta coloré via BodyProgressionColor en seconde ligne.
    /// Si `start` ou `end` est nil → "—". Pour masse grasse, le bloc n'est
    /// jamais rendu si une des deux valeurs manque (contrôle par `hasBodyFat`
    /// au niveau du tableau, suivant la consigne : "ne s'affiche que si start
    /// ET end sont présents").
    @ViewBuilder private func beforeAfterCell(
        start: Double?, end: Double?,
        metric: BodyProgressionColor.Metric,
        goal: String?,
        dim: Bool = false
    ) -> some View {
        if let s = start, let e = end {
            let delta = e - s
            let color: Color = dim
                ? .appTextSecondary
                : BodyProgressionColor.color(delta: delta, start: s, metric: metric, goal: goal)
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(formatValue(s, metric: metric))
                        .font(.appMicro).foregroundColor(.appTextMuted).monospacedDigit()
                    Text("→").font(.appMicro).foregroundColor(.appTextMuted)
                    Text(formatValue(e, metric: metric))
                        .font(.appLabel.weight(.bold))
                        .foregroundColor(dim ? .appTextSecondary : .appTextPrimary)
                        .monospacedDigit()
                }
                Text(formatDelta(delta, metric: metric))
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(color).monospacedDigit()
            }
            .frame(height: 40)
        } else {
            Text("—").font(.appLabel.weight(.bold))
                .foregroundColor(.appTextSecondary).frame(height: 40)
        }
    }

    private func formatValue(_ v: Double, metric: BodyProgressionColor.Metric) -> String {
        switch metric {
        case .weight:  return units.format(v, decimals: 1)
        case .bodyFat: return "\(seasonDecimal(v)) %"
        case .waist:   return "\(seasonDecimal(v)) cm"
        }
    }

    private func formatDelta(_ delta: Double, metric: BodyProgressionColor.Metric) -> String {
        let sign = delta > 0 ? "+" : (delta < 0 ? "−" : "")
        switch metric {
        case .weight:  return "\(sign)\(units.format(abs(delta), decimals: 1))"
        case .bodyFat: return "\(sign)\(seasonDecimal(abs(delta))) pp"
        case .waist:   return "\(sign)\(seasonDecimal(abs(delta))) cm"
        }
    }

    private func seasonDecimal(_ v: Double) -> String {
        let decimals = v.rounded() == v ? 0 : 1
        return String(format: "%.\(decimals)f", locale: Locale(identifier: "fr_CA"), v)
    }

    @ViewBuilder private func deltaArrow(_ a: Double?, _ b: Double?, higherBetter: Bool) -> some View {
        if let c = a, let p = b, p != 0 {
            let diff = c - p
            let isGood = higherBetter ? diff > 0 : diff < 0
            let pct = Int(round(abs(diff) / abs(p) * 100))
            let sym = diff > 0 ? "↑" : "↓"
            Text("\(sym)\(pct)%")
                .font(.appMicro.weight(.bold))
                .foregroundColor(isGood ? .appSuccess : .appWarning)
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
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)

            if showWarRoom, let wr = warRoomStats {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(wr.totalVictories)")
                        .font(.appTitle.weight(.black))
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
                .cornerRadius(8)
            } else {
                Button { showGate = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "shield.fill")
                            .font(.appBody)
                            .foregroundColor(Color.forge.opacity(0.7))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ton premier jour de victoire t'attend")
                                .font(.appLabel.weight(.semibold))
                                .foregroundColor(.appTextPrimary)
                            Text("Démarre War Room")
                                .font(.appCaption)
                                .foregroundColor(Color.forge.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.appCaption.weight(.semibold))
                            .foregroundColor(Color.forge.opacity(0.4))
                    }
                    .padding(12)
                    .background(Color.forge.opacity(0.06))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16).glassCard()
        .sheet(isPresented: $showGate) { WarRoomGateView() }
    }
}

// MARK: - Force Hero Card
// MARK: - Strength Curve Chart (1RM over time)
struct StrengthCurveChart: View {
    let exerciseName: String
    let history: [WeightHistoryEntry]
    @ObservedObject private var units = UnitSettings.shared
    @State private var metric: ChartMetric = .oneRM

    enum ChartMetric: String, CaseIterable {
        case oneRM = "1RM estimé"
        case weight = "Charge"
    }

    private struct DataPoint: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let isWindowMaximum: Bool
        let isCurrent: Bool
    }

    private var points: [DataPoint] {
        let entries = history.compactMap { e -> (Date, Double)? in
            guard let dateStr = e.date,
                  let date = DateFormatter.isoDate.date(from: dateStr) else { return nil }
            let value: Double
            switch metric {
            case .oneRM:
                guard let stored = e.oneRM, stored > 0 else { return nil }
                value = stored
            case .weight:
                guard let w = e.weight, w > 0 else { return nil }
                value = w
            }
            return (date, units.display(value))
        }.sorted { $0.0 < $1.0 }

        guard !entries.isEmpty else { return [] }
        let maximumValue = entries.map(\.1).max() ?? 0
        return entries.enumerated().map { index, entry in
            DataPoint(
                id: entry.0.description,
                date: entry.0,
                value: entry.1,
                isWindowMaximum: entry.1 >= maximumValue,
                isCurrent: index == entries.count - 1
            )
        }
    }

    private var currentPoint: DataPoint? { points.last }
    private var windowMaximum: DataPoint? { points.last(where: \.isWindowMaximum) }
    private var currentValueLabel: String? {
        guard let currentPoint else { return nil }
        switch metric {
        case .oneRM:
            return "Actuel · 1RM estimé \(formattedDisplayValue(currentPoint.value))"
        case .weight:
            return "Actuel · \(formattedDisplayValue(currentPoint.value))"
        }
    }
    private var lowDataMessage: String {
        if points.count == 1 { return "Encore une valeur nécessaire pour afficher la courbe." }
        switch metric {
        case .oneRM:
            return "La courbe apparaîtra avec au moins deux valeurs de 1RM estimé."
        case .weight:
            return "La courbe apparaîtra avec au moins deux valeurs de charge."
        }
    }
    private var accessibilitySummary: String {
        var parts = [exerciseName, "Évolution sur 180 jours", "Mode \(metric.rawValue)"]
        if let currentPoint {
            parts.append("Valeur actuelle \(formattedDisplayValue(currentPoint.value))")
        }
        if let windowMaximum {
            parts.append("Meilleur sur 180 jours \(formattedDisplayValue(windowMaximum.value))")
        }
        return parts.joined(separator: ". ") + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("ÉVOLUTION DE L’EXERCICE")
                    .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
                Spacer()
                Text("180 JOURS")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.appTextSecondary)
            }

            Picker("Mode", selection: $metric) {
                ForEach(ChartMetric.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            if let currentValueLabel {
                Text(currentValueLabel)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
            }

            if points.count < 2 {
                Text(lowDataMessage)
                    .font(.appLabel).foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("\(accessibilitySummary) \(lowDataMessage)")
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
                        .foregroundStyle(p.isWindowMaximum || p.isCurrent ? Color.forge : Color.forge.opacity(0.4))
                        .symbolSize(p.isCurrent ? 80 : (p.isWindowMaximum ? 55 : 30))
                    }

                    if let maximum = windowMaximum {
                        RuleMark(y: .value("Max. 180 j", maximum.value))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.forge.opacity(0.3))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("Max. 180 j · \(formattedDisplayValue(maximum.value))")
                                    .font(.appMicro.weight(.semibold))
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
            }
        }
        .padding(16).background(Color.appCard).cornerRadius(14)
    }

    private func formattedDisplayValue(_ value: Double) -> String {
        String(format: "%.0f \(units.label)", value)
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
        case "force":        return .forge
        case "hypertrophie": return .forge
        default:             return .forge
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INTENSITÉ RELATIVE — %1RM")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)

            HStack(alignment: .bottom, spacing: 12) {
                if let pct = data.avgPct1rm {
                    Text(String(format: "%.0f%%", pct))
                        .font(.appHero.weight(.black))
                        .foregroundColor(zoneColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(zoneLabel)
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(zoneColor)
                    Text("\(data.setsCount) sets cette semaine")
                        .font(.appCaption).foregroundColor(.gray)
                }
                Spacer()
            }

            GeometryReader { g in
                let w = g.size.width
                // shape inline, radius calibré à la hauteur de la jauge %1RM
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.gray.opacity(0.25)).frame(width: w * 0.65)
                        Rectangle().fill(Color.appSuccess.opacity(0.25)).frame(width: w * 0.15)
                        Rectangle().fill(Color.appDanger.opacity(0.25))
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
                    Text("<65%").font(.appMicro).foregroundColor(.gray)
                    Spacer()
                    Text("65–80%").font(.appMicro).foregroundColor(.appSuccess)
                    Spacer()
                    Text(">80%").font(.appMicro).foregroundColor(.appDanger)
                }
                .offset(y: 16)
            }
            .frame(height: 32)
        }
        .padding(16).glassCard()
    }
}

// MARK: - Deload Status Card
