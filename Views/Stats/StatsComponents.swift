import SwiftUI
import Charts

// MARK: - Current body measurements
struct StatsCurrentBodyMeasurements: View {
    let entries: [BodyWeightEntry]
    @ObservedObject private var units = UnitSettings.shared

    private var measurements: [StatsBodyMeasurementPresentation] {
        var result: [StatsBodyMeasurementPresentation] = []
        if let entry = entries.first(where: { $0.weight > 0 }) {
            result.append(StatsBodyMeasurementPresentation(label: "Poids", value: units.format(entry.weight, decimals: 1), date: entry.date))
        }
        if let entry = entries.first(where: { ($0.bodyFat ?? 0) > 0 }), let value = entry.bodyFat {
            result.append(StatsBodyMeasurementPresentation(label: "Masse grasse", value: formatted(value) + " %", date: entry.date))
        }
        appendMeasurement("Tour de taille", keyPath: \.waistCm, to: &result)
        appendMeasurement("Cou", keyPath: \.neckCm, to: &result)
        appendMeasurement("Bras", keyPath: \.armsCm, to: &result)
        appendMeasurement("Poitrine", keyPath: \.chestCm, to: &result)
        appendMeasurement("Cuisses", keyPath: \.thighsCm, to: &result)
        appendMeasurement("Hanches", keyPath: \.hipsCm, to: &result)
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MESURES ACTUELLES")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
            if measurements.isEmpty {
                Text("Pas encore de mesure corporelle disponible.")
                    .font(.appBody).foregroundColor(.appTextSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(measurements.enumerated()), id: \.offset) { index, measurement in
                        StatsBodyMeasurementRow(measurement: measurement)
                        if index < measurements.count - 1 {
                            Rectangle().fill(Color.appSeparator).frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(.appCardInsetV).background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
        .accessibilityElement(children: .contain)
    }

    private func appendMeasurement(
        _ label: String,
        keyPath: KeyPath<BodyWeightEntry, Double?>,
        to result: inout [StatsBodyMeasurementPresentation]
    ) {
        guard let entry = entries.first(where: { ($0[keyPath: keyPath] ?? 0) > 0 }),
              let value = entry[keyPath: keyPath] else { return }
        result.append(StatsBodyMeasurementPresentation(label: label, value: "\(formatted(value)) cm", date: entry.date))
    }

    private func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

private struct StatsBodyMeasurementPresentation {
    let label: String
    let value: String
    let date: String
}

private struct StatsBodyMeasurementRow: View {
    let measurement: StatsBodyMeasurementPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(measurement.label)
                .font(.appCaption.weight(.medium)).foregroundColor(.appTextPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(measurement.value)
                    .font(.appHeadline.weight(.semibold)).foregroundColor(.appTextPrimary)
                Spacer()
                Text("Dernière mesure · \(measurement.date)")
                    .font(.appMicro).foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(measurement.label) : \(measurement.value). Dernière mesure : \(measurement.date).")
    }
}

// MARK: - Activity streaks
struct StatsActivityStreakSummary: View {
    let currentStreak: Int
    let bestStreak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SÉRIES D’ACTIVITÉ")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
            HStack(spacing: 12) {
                metric(value: "\(currentStreak) \(dayLabel(currentStreak))", title: "Série actuelle")
                metric(value: "\(bestStreak) \(dayLabel(bestStreak))", title: "Meilleure série")
            }
            Text("Basé sur les jours d’activité enregistrée")
                .font(.appMicro).foregroundColor(.appTextSecondary)
        }
        .padding(.appCardInsetV).background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
        .accessibilityElement(children: .contain)
    }

    private func metric(value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.appHeadline.weight(.semibold)).foregroundColor(.appTextPrimary)
            Text(title).font(.appCaption).foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func dayLabel(_ value: Int) -> String { value == 1 ? "jour" : "jours" }
}

// MARK: - Canonical regularity
struct StatsRegularitySummary: View {
    let trainingLoad: StatsCockpitTrainingLoad

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIVITÉ RÉCENTE")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
            HStack(spacing: 12) {
                metric(value: "\(trainingLoad.summary.activeDayCount)", label: "Jours actifs")
                metric(value: "\(trainingLoad.summary.sessionCount)", label: "Séances avec activité")
            }
        }
        .padding(.appCardInsetV).background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
        .accessibilityElement(children: .contain)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.appHeadline.weight(.semibold)).foregroundColor(.appTextPrimary)
            Text(label).font(.appCaption).foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct StatsWeeklyRegularityChart: View {
    let weekly: [StatsWeeklyTrainingLoad]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RYTHME HEBDOMADAIRE")
                .font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.appTextMuted)
            Text("Historique récent")
                .font(.appCaption).foregroundColor(.appTextSecondary)
            if weekly.isEmpty {
                Text("Pas encore de rythme hebdomadaire disponible.")
                    .font(.appBody).foregroundColor(.appTextSecondary)
            } else {
                GeometryReader { geometry in
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(weekly, id: \.weekStart) { bucket in
                            bar(bucket, height: geometry.size.height)
                        }
                    }
                }
                .frame(height: 110)
            }
        }
        .padding(.appCardInsetV).background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
    }

    private var maxDays: Int { max(weekly.map(\.activeDayCount).max() ?? 0, 1) }

    @ViewBuilder
    private func bar(_ bucket: StatsWeeklyTrainingLoad, height: CGFloat) -> some View {
        VStack(spacing: 4) {
            if bucket.activeDayCount > 0 {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.domainAccent(.training))
                    .frame(height: CGFloat(bucket.activeDayCount) / CGFloat(maxDays) * (height - 24))
                    .accessibilityLabel(accessibilityLabel(for: bucket))
            } else {
                Circle()
                    .fill(Color.appTextMuted)
                    .frame(width: 4, height: 4)
                    .accessibilityLabel(accessibilityLabel(for: bucket))
            }
            Text(String(bucket.weekStart.prefix(7)))
                .font(.appMicro).foregroundColor(.appTextMuted).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func accessibilityLabel(for bucket: StatsWeeklyTrainingLoad) -> String {
        let partial = bucket.isPartial ? " Semaine partielle." : ""
        return "Semaine du \(bucket.weekStart). \(bucket.activeDayCount) jours actifs. \(bucket.sessionCount) séances avec activité.\(partial)"
    }
}

// MARK: - Charge summary and muscle comparison
struct StatsChargeHeroCard: View {
    let trainingLoad: StatsCockpitTrainingLoad

    private var weeklySetDelta: Int? {
        let completeWeeks = trainingLoad.weekly
            .filter { !$0.isPartial }
            .sorted { $0.weekStart < $1.weekStart }
        guard completeWeeks.count >= 2 else { return nil }
        return completeWeeks[completeWeeks.count - 1].validRepsSetCount
            - completeWeeks[completeWeeks.count - 2].validRepsSetCount
    }

    private var weeklyDeltaLabel: String? {
        guard let weeklySetDelta else { return nil }
        guard weeklySetDelta != 0 else {
            return "Même nombre de séries que la semaine précédente"
        }
        let sign = weeklySetDelta > 0 ? "+" : "−"
        let count = abs(weeklySetDelta)
        let unit = count == 1 ? "série" : "séries"
        return "\(sign)\(count) \(unit) vs semaine précédente"
    }

    private var accessibilitySummary: String {
        let summary = "Activité sur 12 semaines. \(trainingLoad.summary.sessionCount) séances, \(trainingLoad.summary.activeDayCount) jours actifs et \(trainingLoad.summary.validRepsSetCount) séries valides."
        guard let weeklyDeltaLabel else { return summary }
        return "\(summary) Dernière semaine complète : \(weeklyDeltaLabel)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("ACTIVITÉ")
                    .font(.appMicro.weight(.bold))
                    .tracking(2)
                    .foregroundColor(.appTextMuted)
                Spacer()
                Text("12 SEMAINES")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.appTextSecondary)
            }

            HStack(spacing: 12) {
                metric(value: "\(trainingLoad.summary.sessionCount)", label: "Séances")
                metric(value: "\(trainingLoad.summary.activeDayCount)", label: "Jours actifs")
                metric(value: "\(trainingLoad.summary.validRepsSetCount)", label: "Séries valides")
            }

            if let weeklyDeltaLabel {
                Divider().overlay(Color.appSeparatorSubtle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DERNIÈRE SEMAINE COMPLÈTE")
                        .font(.appMicro.weight(.bold))
                        .tracking(1)
                        .foregroundColor(.appTextMuted)
                    Text(weeklyDeltaLabel)
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding(.appCardInsetV)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.appHeadline.weight(.semibold))
                .foregroundColor(.appTextPrimary)
            Text(label)
                .font(.appMicro)
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatsMuscleWorkloadComparisonChart: View {
    let muscles: StatsCockpitMuscles

    private var solicitedWorkloads: [StatsMuscleWorkload] {
        muscles.workloads.filter {
            $0.directExposureCount > 0 || $0.indirectExposureCount > 0
        }
    }

    private var solicitedMuscleCount: Int { solicitedWorkloads.count }

    private var directlyTargetedCount: Int {
        solicitedWorkloads.filter { $0.directExposureCount > 0 }.count
    }

    private var indirectOnlyCount: Int {
        solicitedWorkloads.filter {
            $0.directExposureCount == 0 && $0.indirectExposureCount > 0
        }.count
    }

    private var topWorkloads: [StatsMuscleWorkload] {
        let direct = muscles.workloads
            .filter { $0.directSetCount > 0 }
            .sorted {
                if $0.directSetCount != $1.directSetCount { return $0.directSetCount > $1.directSetCount }
                if $0.indirectSetCount != $1.indirectSetCount { return $0.indirectSetCount > $1.indirectSetCount }
                return $0.muscle.localizedCaseInsensitiveCompare($1.muscle) == .orderedAscending
            }
            .prefix(4)
        let indirect = muscles.workloads
            .filter { $0.indirectSetCount > 0 }
            .sorted {
                if $0.indirectSetCount != $1.indirectSetCount { return $0.indirectSetCount > $1.indirectSetCount }
                if $0.directSetCount != $1.directSetCount { return $0.directSetCount > $1.directSetCount }
                return $0.muscle.localizedCaseInsensitiveCompare($1.muscle) == .orderedAscending
            }
            .prefix(4)

        var selectedByMuscle: [String: StatsMuscleWorkload] = [:]
        for workload in direct { selectedByMuscle[workload.muscle] = workload }
        for workload in indirect { selectedByMuscle[workload.muscle] = workload }

        return selectedByMuscle.values.sorted {
            let dominant0 = max($0.directSetCount, $0.indirectSetCount)
            let dominant1 = max($1.directSetCount, $1.indirectSetCount)
            if dominant0 != dominant1 { return dominant0 > dominant1 }
            let combined0 = $0.directSetCount + $0.indirectSetCount
            let combined1 = $1.directSetCount + $1.indirectSetCount
            if combined0 != combined1 { return combined0 > combined1 }
            if $0.directSetCount != $1.directSetCount { return $0.directSetCount > $1.directSetCount }
            return $0.muscle.localizedCaseInsensitiveCompare($1.muscle) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("MUSCLES")
                    .font(.appMicro.weight(.bold))
                    .tracking(2)
                    .foregroundColor(.appTextMuted)
                Spacer()
                Text("30 JOURS")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.appTextSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(solicitedMuscleCount)")
                    .font(.appTitle.weight(.bold))
                    .foregroundColor(.appTextPrimary)
                Text("Muscles sollicités")
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
            }
            Text("\(directlyTargetedCount) ciblés directement · \(indirectOnlyCount) uniquement indirectement")
                .font(.appCaption)
                .foregroundColor(.appTextSecondary)

            Divider().overlay(Color.appSeparatorSubtle)

            Text("MUSCLES LES PLUS SOLLICITÉS")
                .font(.appMicro.weight(.bold))
                .tracking(1.5)
                .foregroundColor(.appTextMuted)

            if topWorkloads.isEmpty {
                Text(emptyChartMessage)
                    .font(.appBody)
                    .foregroundColor(.appTextSecondary)
            } else {
                Text("Jusqu’à 8 muscles, sélectionnés selon le travail direct et indirect")
                    .font(.appMicro)
                    .foregroundColor(.appTextMuted)

                HStack(spacing: 14) {
                    legend(color: AppTheme.shared.chartColor(0), label: "Direct")
                    legend(color: AppTheme.shared.chartColor(1), label: "Indirect")
                    Spacer()
                }
                Text("Direct : muscle principal · Indirect : muscle secondaire")
                    .font(.appMicro)
                    .foregroundColor(.appTextSecondary)

                Chart {
                    ForEach(topWorkloads, id: \.muscle) { workload in
                        BarMark(x: .value("Séries", workload.directSetCount), y: .value("Muscle", displayLabel(workload.muscle)))
                            .foregroundStyle(AppTheme.shared.chartColor(0))
                            .position(by: .value("Type", "Direct"))
                        BarMark(x: .value("Séries", workload.indirectSetCount), y: .value("Muscle", displayLabel(workload.muscle)))
                            .foregroundStyle(AppTheme.shared.chartColor(1))
                            .position(by: .value("Type", "Indirect"))
                    }
                }
                .chartXAxis { AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appSeparatorSubtle)
                    AxisValueLabel().foregroundStyle(Color.appTextMuted)
                } }
                .chartYAxis { AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.appSeparatorSubtle)
                    AxisValueLabel().foregroundStyle(Color.appTextMuted)
                } }
                .chartLegend(.hidden)
                .frame(height: CGFloat(topWorkloads.count * 34 + 34))
            }
        }
        .padding(.appCardInsetV)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var emptyChartMessage: String {
        if solicitedMuscleCount > 0 {
            return "Des muscles ont été enregistrés, mais aucune série exploitable n’est disponible sur les 30 derniers jours."
        }
        return "Aucun muscle sollicité sur les 30 derniers jours."
    }

    private var accessibilitySummary: String {
        let summary = "Muscles sur 30 jours. \(solicitedMuscleCount) muscles sollicités : \(directlyTargetedCount) ciblés directement et \(indirectOnlyCount) uniquement indirectement."
        guard !topWorkloads.isEmpty else { return "\(summary) \(emptyChartMessage)" }
        return "\(summary) Direct signifie muscle principal. Indirect signifie muscle secondaire. Le graphique présente jusqu’à 8 muscles."
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.appMicro.weight(.semibold)).foregroundColor(.appTextSecondary)
        }
    }

    private func displayLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private func statsMuscleDisplayName(_ rawValue: String) -> String {
    let known: [String: String] = [
        "rear_delts": "Deltoïdes postérieurs",
        "rotator_cuff": "Coiffe des rotateurs",
        "scalenes": "Scalènes",
        "semispinalis_capitis": "Semi-épineux de la tête",
        "longus_capitis": "Long de la tête",
        "rhomboids": "Rhomboïdes",
        "mid_traps": "Trapèzes moyens"
    ]
    if let label = known[rawValue.lowercased()] { return label }
    return rawValue
        .replacingOccurrences(of: "_", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .capitalized
}

private func statsMuscleRecency(_ rawDate: String) -> String {
    guard let date = DateFormatter.isoDate.date(from: rawDate) else { return rawDate }
    let calendar = Calendar.mtl
    let today = calendar.startOfDay(for: Date())
    let day = calendar.startOfDay(for: date)
    let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
    if days < 0 { return rawDate }
    if days == 0 { return "Aujourd’hui" }
    if days == 1 { return "Hier" }
    return "Il y a \(days) j"
}

// MARK: - Canonical muscle workload
struct StatsMuscleWorkloadSection: View {
    let muscles: StatsCockpitMuscles
    @State private var isExpanded = false

    private var sortedWorkloads: [StatsMuscleWorkload] {
        muscles.workloads.sorted {
            let dominant0 = max($0.directSetCount, $0.indirectSetCount)
            let dominant1 = max($1.directSetCount, $1.indirectSetCount)
            if dominant0 != dominant1 { return dominant0 > dominant1 }
            if $0.directSetCount != $1.directSetCount { return $0.directSetCount > $1.directSetCount }
            if $0.indirectSetCount != $1.indirectSetCount { return $0.indirectSetCount > $1.indirectSetCount }
            return $0.muscle.localizedCaseInsensitiveCompare($1.muscle) == .orderedAscending
        }
    }

    private var visibleWorkloads: ArraySlice<StatsMuscleWorkload> {
        isExpanded ? sortedWorkloads[...] : sortedWorkloads.prefix(6)
    }

    private var remainingWorkloadCount: Int {
        max(sortedWorkloads.count - 6, 0)
    }

    private var bicepsFemoralHasSets: Bool {
        guard let workload = muscles.workloads.first(where: { $0.muscle == "Biceps fémoral" }) else {
            return false
        }
        return workload.directSetCount > 0 || workload.indirectSetCount > 0
    }

    private var expandLabel: String {
        if remainingWorkloadCount == 1 { return "Voir 1 autre muscle" }
        return "Voir les \(remainingWorkloadCount) autres muscles"
    }

    private var coverageMessage: String? {
        let coverage = muscles.coverage
        guard coverage.unmappedExposureCount > 0 else { return nil }
        return "Mapping partiel · \(coverage.mappedExposureCount) / \(coverage.totalExposureCount) expositions mappées"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("DÉTAIL MUSCULAIRE")
                    .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
                Spacer()
                Text("30 JOURS")
                    .font(.appCaption.weight(.semibold)).foregroundColor(.appTextSecondary)
            }
            Text("Séries directes et indirectes · séances et récence")
                .font(.appCaption).foregroundColor(.appTextSecondary)

            if let coverageMessage {
                Text(coverageMessage)
                    .font(.appMicro.weight(.semibold)).foregroundColor(.appTextMuted)
            }

            if muscles.workloads.isEmpty {
                Text("Pas encore de travail musculaire mesurable.")
                    .font(.appBody).foregroundColor(.appTextSecondary)
            } else {
                ForEach(visibleWorkloads, id: \.muscle) { workload in
                    StatsMuscleWorkloadRow(
                        workload: workload,
                        bicepsFemoralHasSets: bicepsFemoralHasSets
                    )
                    if workload.muscle != visibleWorkloads.last?.muscle {
                        Divider().overlay(Color.appSeparatorSubtle)
                    }
                }

                if remainingWorkloadCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                    } label: {
                        HStack {
                            Text(isExpanded ? "Réduire la liste" : expandLabel)
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(.appTextPrimary)
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(.appTextSecondary)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Réduire la liste des détails musculaires" : expandLabel)
                }
            }
        }
        .padding(.appCardInsetV)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
    }
}

struct StatsMuscleWorkloadRow: View {
    let workload: StatsMuscleWorkload
    let bicepsFemoralHasSets: Bool

    private var hasExposureWithoutValidSets: Bool {
        workload.directSetCount == 0
            && workload.indirectSetCount == 0
            && (workload.directExposureCount > 0 || workload.indirectExposureCount > 0)
    }

    private var showsBicepsFemoralContext: Bool {
        workload.muscle == "Ischio-jambiers"
            && hasExposureWithoutValidSets
            && bicepsFemoralHasSets
    }

    private var accessibilitySummary: String {
        let muscle = statsMuscleDisplayName(workload.muscle)
        let sets: String
        if hasExposureWithoutValidSets {
            sets = showsBicepsFemoralContext
                ? "Aucune série exploitable. Séries comptées sous Biceps fémoral."
                : "Aucune série exploitable."
        } else {
            sets = "Direct, \(workload.directSetCount) séries. Indirect, \(workload.indirectSetCount) séries."
        }
        return "\(muscle). \(sets) \(workload.sessionCount) séance\(workload.sessionCount == 1 ? "" : "s"). \(workload.activeDayCount) jour actif\(workload.activeDayCount == 1 ? "" : "s"). Dernière exposition, \(statsMuscleRecency(workload.lastExposureDate))."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(statsMuscleDisplayName(workload.muscle))
                .font(.appBody.weight(.semibold)).foregroundColor(.appTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if hasExposureWithoutValidSets {
                Text("Aucune série exploitable")
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(.appTextSecondary)
                if showsBicepsFemoralContext {
                    Text("Séries comptées sous Biceps fémoral")
                        .font(.appMicro)
                        .foregroundColor(.appTextMuted)
                }
            } else {
                HStack(spacing: 10) {
                    metricBadge(value: workload.directSetCount, label: "Direct", color: AppTheme.shared.chartColor(0))
                    metricBadge(value: workload.indirectSetCount, label: "Indirect", color: AppTheme.shared.chartColor(1))
                }
            }
            HStack {
                Text("\(workload.sessionCount) séance\(workload.sessionCount == 1 ? "" : "s") · \(workload.activeDayCount) jour actif\(workload.activeDayCount == 1 ? "" : "s")")
                Spacer(minLength: 8)
                Text(statsMuscleRecency(workload.lastExposureDate))
            }
                .font(.appMicro).foregroundColor(.appTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private func metricBadge(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(value)")
                .font(.appMicro.weight(.semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.appSurfaceInset)
        .clipShape(Capsule())
    }
}

// MARK: - Canonical external load
struct StatsExternalLoadSection: View {
    let trainingLoad: StatsCockpitTrainingLoad

    private var tonnageLabel: String {
        guard let tonnage = trainingLoad.summary.tonnage.value else { return "—" }
        let displayValue = UnitSettings.shared.display(tonnage)
        let formatted = NumberFormatter.spaceGrouped.string(from: NSNumber(value: displayValue))
            ?? String(format: "%.0f", displayValue)
        return "\(formatted) \(UnitSettings.shared.label)"
    }

    private var coverageLabel: String {
        let tonnage = trainingLoad.summary.tonnage
        switch tonnage.coverage {
        case .complete: return "Complet"
        case .partial: return "Couverture partielle"
        case .unavailable: return "Indisponible"
        case .unknown: return "Données partielles"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("CHARGE EXTERNE")
                    .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
                Spacer()
                Text("12 SEMAINES")
                    .font(.appCaption.weight(.semibold)).foregroundColor(.appTextSecondary)
            }
            Text("Tonnage · poids × reps")
                .font(.appCaption).foregroundColor(.appTextSecondary)

            HStack(spacing: 12) {
                metric(value: tonnageLabel, label: "Tonnage", detail: coverageLabel)
                metric(value: "\(trainingLoad.summary.validRepsSetCount)", label: "Séries valides", detail: nil)
                metric(
                    value: "\(trainingLoad.summary.tonnage.calculableExposureCount) / \(trainingLoad.summary.tonnage.applicableExposureCount)",
                    label: "Expositions avec tonnage",
                    detail: nil
                )
            }

            StatsWeeklyTonnageChart(weekly: trainingLoad.weekly)
        }
        .padding(.appCardInsetV)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Charge externe sur 12 semaines. Tonnage poids fois répétitions, \(tonnageLabel). \(coverageLabel). \(trainingLoad.summary.validRepsSetCount) séries valides.")
    }

    private func metric(value: String, label: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.appHeadline.weight(.semibold)).foregroundColor(.appTextPrimary)
                .lineLimit(1).minimumScaleFactor(0.65)
            Text(label).font(.appMicro).foregroundColor(.appTextSecondary)
            if let detail { Text(detail).font(.appMicro.weight(.semibold)).foregroundColor(.appTextMuted).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct StatsWeeklyTonnageChart: View {
    let weekly: [StatsWeeklyTrainingLoad]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TONNAGE / SEMAINE")
                .font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.appTextMuted)
            if weekly.isEmpty {
                Text("Pas encore de trajectoire hebdomadaire disponible.")
                    .font(.appCaption).foregroundColor(.appTextSecondary)
            } else {
                GeometryReader { geometry in
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(weekly.indices, id: \.self) { index in
                            weeklyBar(
                                weekly[index],
                                maxValue: maxValue,
                                height: geometry.size.height,
                                showLabel: shouldShowLabel(at: index)
                            )
                        }
                    }
                }
                .frame(height: 110)
                HStack(spacing: 12) {
                    Text("— indisponible").font(.appMicro).foregroundColor(.appTextMuted)
                    if weekly.contains(where: { $0.isPartial }) {
                        Text("· semaine partielle").font(.appMicro).foregroundColor(.appTextSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var maxValue: Double {
        max(weekly.compactMap { $0.tonnage.value }.max() ?? 0, 1)
    }

    @ViewBuilder
    private func weeklyBar(
        _ bucket: StatsWeeklyTrainingLoad,
        maxValue: Double,
        height: CGFloat,
        showLabel: Bool
    ) -> some View {
        let tonnage = bucket.tonnage.value
        VStack(spacing: 4) {
            if let tonnage {
                RoundedRectangle(cornerRadius: 3)
                    .fill(bucket.tonnage.coverage == .partial ? Color.appWarning : Color.domainAccent(.training))
                    .frame(height: max(tonnage > 0 ? CGFloat(tonnage / maxValue) * (height - 22) : 2, 2))
                    .accessibilityLabel(weeklyAccessibilityLabel(bucket, tonnage: tonnage))
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.appSurfaceInset)
                    .frame(height: 2)
                    .overlay(Rectangle().fill(Color.appTextMuted).frame(width: 10, height: 1))
                    .accessibilityLabel(weeklyAccessibilityLabel(bucket, tonnage: nil))
            }
            Color.clear
                .frame(height: 12)
                .overlay {
                    if showLabel {
                        Text(weekLabel(bucket.weekStart))
                            .font(.appMicro)
                            .foregroundColor(.appTextMuted)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityHidden(true)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func shouldShowLabel(at index: Int) -> Bool {
        guard weekly.count > 7 else { return true }
        let lastIndex = weekly.count - 1
        return index == lastIndex || (index.isMultiple(of: 2) && index != lastIndex - 1)
    }

    private func weekLabel(_ rawDate: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: rawDate) else { return rawDate }
        return DateFormatter.shortDateFRCA.string(from: date)
    }

    private func weeklyAccessibilityLabel(_ bucket: StatsWeeklyTrainingLoad, tonnage: Double?) -> String {
        let value = tonnage.map { UnitSettings.shared.format($0, decimals: 0) } ?? "indisponible"
        let partial = bucket.isPartial ? ", semaine partielle" : ""
        return "Semaine du \(bucket.weekStart). Tonnage reps \(value)\(partial)."
    }
}

// MARK: - Canonical Force progression
struct StatsForceProgressionHero: View {
    let progression: StatsCockpitProgression

    private var improving: Int { progression.statusCounts.improving }
    private var stable: Int { progression.statusCounts.stable }
    private var declining: Int { progression.statusCounts.declining }
    private var comparable: Int { improving + stable + declining }

    private var comparableLabel: String {
        comparable == 1 ? "1 exercice comparable" : "\(comparable) exercices comparables"
    }

    private var accessibilitySummary: String {
        let stableSummary = stable == 1 ? "1 exercice stable" : "\(stable) exercices stables"
        return "Trajectoire force. Comparaison des \(progression.comparisonWindowDays) derniers jours aux \(progression.comparisonWindowDays) jours précédents. \(improving) exercices en hausse. \(stableSummary). \(declining) en baisse. \(comparableLabel)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TRAJECTOIRE FORCE")
                .font(.appMicro.weight(.bold))
                .tracking(2)
                .foregroundColor(Color.domainAccent(.training))

            Text("\(progression.comparisonWindowDays) derniers jours vs \(progression.comparisonWindowDays) jours précédents")
                .font(.appCaption)
                .foregroundColor(.appTextSecondary)

            HStack(spacing: 12) {
                metric(value: improving, label: "En hausse", color: .appSuccess)
                metric(value: stable, label: "Stables", color: .appTextSecondary)
                metric(value: declining, label: "En baisse", color: .appDanger)
            }

            Text(comparableLabel)
                .font(.appMicro.weight(.semibold))
                .foregroundColor(.appTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.appCardInsetV)
        .background(Color.appCard)
        .overlay(
            RoundedRectangle(cornerRadius: .appCardRadius)
                .stroke(Color.appSeparator, lineWidth: CGFloat.appHairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func metric(value: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.appTitle.weight(.bold))
                .foregroundColor(color)
            Text(label)
                .font(.appCaption.weight(.semibold))
                .foregroundColor(.appTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatsStrengthProgressionSection: View {
    let comparisons: [StatsProgressionComparison]
    let comparisonWindowDays: Int
    var onSelectExercise: ((String) -> Void)? = nil
    @State private var isShowingAllProgressionRows = false
    private let compactRowLimit = 10
    private var improving: [StatsProgressionComparison] { comparisons.filter { $0.status == .improving } }
    private var stable: [StatsProgressionComparison] { comparisons.filter { $0.status == .stable } }
    private var declining: [StatsProgressionComparison] { comparisons.filter { $0.status == .declining } }
    private var insufficient: [StatsProgressionComparison] { comparisons.filter { $0.status == .insufficientData } }
    private var other: [StatsProgressionComparison] {
        comparisons.filter {
            if case .unknown(_) = $0.status { return true }
            return false
        }
    }
    private var totalRowCount: Int {
        improving.count + stable.count + declining.count + insufficient.count + other.count
    }
    private var remainingRowCount: Int { max(totalRowCount - compactRowLimit, 0) }
    private var expansionLabel: String {
        if isShowingAllProgressionRows { return "Réduire la liste" }
        if remainingRowCount == 1 { return "Voir 1 autre exercice" }
        return "Voir les \(remainingRowCount) autres exercices"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PROGRESSION PAR EXERCICE")
                .font(.appMicro.weight(.bold))
                .tracking(2)
                .foregroundColor(.appTextMuted)
            Text("Meilleur 1RM estimé · \(comparisonWindowDays) derniers jours vs \(comparisonWindowDays) jours précédents")
                .font(.appCaption)
                .foregroundColor(.appTextSecondary)

            if comparisons.isEmpty {
                Text("Pas encore assez de données comparables.").font(.appBody).foregroundColor(.appTextSecondary)
            } else {
                group("EN HAUSSE", comparisons: visibleRows(in: improving, after: 0))
                group("STABLE", comparisons: visibleRows(in: stable, after: improving.count))
                group("EN BAISSE", comparisons: visibleRows(in: declining, after: improving.count + stable.count))
                group("DONNÉES INSUFFISANTES", comparisons: visibleRows(in: insufficient, after: improving.count + stable.count + declining.count))
                group("DONNÉES DISPONIBLES", comparisons: visibleRows(in: other, after: improving.count + stable.count + declining.count + insufficient.count))

                if remainingRowCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingAllProgressionRows.toggle()
                        }
                    } label: {
                        HStack {
                            Text(expansionLabel)
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(.appTextSecondary)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isShowingAllProgressionRows
                            ? "Réduire la progression par exercice aux 10 premiers exercices"
                            : "Afficher \(remainingRowCount) exercice\(remainingRowCount == 1 ? "" : "s") supplémentaire\(remainingRowCount == 1 ? "" : "s")"
                    )
                }
            }
        }
        .padding(.appCardInsetV).background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius)).padding(.horizontal, .appPagePadding)
    }

    private func visibleRows(
        in group: [StatsProgressionComparison],
        after precedingRowCount: Int
    ) -> [StatsProgressionComparison] {
        guard !isShowingAllProgressionRows else { return group }
        return Array(group.prefix(max(compactRowLimit - precedingRowCount, 0)))
    }

    @ViewBuilder private func group(_ title: String, comparisons: [StatsProgressionComparison]) -> some View {
        if !comparisons.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.appTextMuted)
                ForEach(comparisons, id: \.exerciseName) { comparison in
                    StatsStrengthComparisonRow(comparison: comparison) { onSelectExercise?(comparison.exerciseName) }
                    if comparison.exerciseName != comparisons.last?.exerciseName { Divider().overlay(Color.appSeparator) }
                }
            }
        }
    }
}

struct StatsStrengthComparisonRow: View {
    let comparison: StatsProgressionComparison
    var onSelect: (() -> Void)? = nil
    private var statusLabel: String {
        switch comparison.status { case .improving: return "En hausse"; case .stable: return "Stable"; case .declining: return "En baisse"; case .insufficientData: return "Données insuffisantes"; case .unknown: return "Données disponibles" }
    }
    private var statusColor: Color {
        switch comparison.status { case .improving: return .appSuccess; case .declining: return .appDanger; case .stable: return .appTextSecondary; case .insufficientData, .unknown: return .appTextMuted }
    }
    private var reason: String? {
        guard case .insufficientData = comparison.status, let reason = comparison.insufficiencyReason else { return nil }
        switch reason { case .nonComparableTrackingType: return "Type de suivi non comparable"; case .noValidExposure: return "Aucune exposition valide"; case .insufficientBaselineExposures: return "Historique de référence insuffisant"; case .insufficientRecentExposures: return "Pas assez d’expositions récentes"; case .insufficientBothWindows: return "Historique insuffisant sur les deux périodes"; case .invalidBaseline: return "Référence non comparable"; case .unknown: return "Historique insuffisant" }
    }
    private var deltaLabel: String? {
        guard let delta = comparison.relativeDelta else { return nil }
        if abs(delta) < 0.0005 { return "0,0 %" }
        return String(format: "%+.1f", delta * 100).replacingOccurrences(of: ".", with: ",") + " %"
    }
    private var exposureLabel: String {
        let previous = comparison.baselineExposureCount == 1 ? "exposition précédente" : "expositions précédentes"
        let recent = comparison.recentExposureCount == 1 ? "récente" : "récentes"
        return "\(comparison.baselineExposureCount) \(previous) · \(comparison.recentExposureCount) \(recent)"
    }
    private var accessibilitySummary: String {
        var parts = [comparison.exerciseName, statusLabel]
        if let baseline = comparison.baselineBestE1RM, let recent = comparison.recentBestE1RM {
            parts.append("1RM estimé, \(UnitSettings.shared.format(baseline, decimals: 0)) précédemment, \(UnitSettings.shared.format(recent, decimals: 0)) récemment")
        } else if let recent = comparison.recentBestE1RM {
            parts.append("1RM estimé récent, \(UnitSettings.shared.format(recent, decimals: 0))")
        } else if let baseline = comparison.baselineBestE1RM {
            parts.append("1RM estimé précédent, \(UnitSettings.shared.format(baseline, decimals: 0))")
        }
        if let delta = comparison.relativeDelta {
            let value = String(format: "%.1f", abs(delta * 100)).replacingOccurrences(of: ".", with: ",")
            if delta > 0 {
                parts.append("Hausse de \(value) pour cent")
            } else if delta < 0 {
                parts.append("Baisse de \(value) pour cent")
            } else {
                parts.append("Aucun écart en pourcentage")
            }
        }
        if let reason { parts.append(reason) }
        parts.append(exposureLabel.replacingOccurrences(of: " · ", with: ", "))
        return parts.joined(separator: ". ") + "."
    }
    var body: some View {
        Button(action: { onSelect?() }) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { Text(comparison.exerciseName).font(.appBody.weight(.semibold)).foregroundColor(.appTextPrimary).lineLimit(1); Spacer(minLength: 6); Text(statusLabel).font(.appCaption.weight(.semibold)).foregroundColor(statusColor) }

                if let baseline = comparison.baselineBestE1RM, let recent = comparison.recentBestE1RM {
                    Text("1RM ESTIMÉ")
                        .font(.appMicro.weight(.semibold))
                        .tracking(1)
                        .foregroundColor(.appTextMuted)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(UnitSettings.shared.format(baseline, decimals: 0)) → \(UnitSettings.shared.format(recent, decimals: 0))")
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(.appTextPrimary)
                        Spacer(minLength: 6)
                        if let deltaLabel {
                            Text(deltaLabel)
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(statusColor)
                        }
                    }
                } else if let recent = comparison.recentBestE1RM {
                    estimatedValue(label: "1RM ESTIMÉ RÉCENT", value: recent)
                } else if let baseline = comparison.baselineBestE1RM {
                    estimatedValue(label: "1RM ESTIMÉ PRÉCÉDENT", value: baseline)
                }

                if let reason { Text(reason).font(.appMicro).foregroundColor(.appTextSecondary) }
                Text(exposureLabel).font(.appMicro).foregroundColor(.appTextMuted)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Ouvre l’historique de l’exercice")
    }

    private func estimatedValue(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.appMicro.weight(.semibold))
                .tracking(1)
                .foregroundColor(.appTextMuted)
            Text(UnitSettings.shared.format(value, decimals: 0))
                .font(.appLabel.weight(.semibold))
                .foregroundColor(.appTextPrimary)
        }
    }
}

// MARK: - Cockpit Overview
struct StatsProgressionHero: View {
    let progression: StatsCockpitProgression
    let onOpen: () -> Void
    @State private var isShowingExplanation = false
    @State private var shouldOpenForceAfterDismiss = false

    private var improving: Int { progression.statusCounts.improving }
    private var stable: Int { progression.statusCounts.stable }
    private var declining: Int { progression.statusCounts.declining }
    private var comparable: Int { improving + stable + declining }

    private var accessibilitySummary: String {
        let improvingLabel = improving == 1 ? "1 exercice en hausse" : "\(improving) exercices en hausse"
        let stableLabel = stable == 1 ? "1 exercice stable" : "\(stable) exercices stables"
        let decliningLabel = declining == 1 ? "1 exercice en baisse" : "\(declining) exercices en baisse"
        return "Trajectoire Force. \(presentation.headline). \(improvingLabel), \(stableLabel), \(decliningLabel). Comparaison des \(progression.comparisonWindowDays) derniers jours aux \(progression.comparisonWindowDays) jours précédents."
    }

    private var presentation: (eyebrow: String, headline: String, support: String) {
        if comparable == 0 {
            return (
                "TRAJECTOIRE",
                "En construction",
                "Pas encore assez d’expositions comparables pour conclure."
            )
        }
        if improving > 0 && stable == 0 && declining == 0 {
            let movement = improving == 1 ? "1 mouvement en progression" : "\(improving) mouvements en progression"
            return (
                "PROGRESSION SUR \(progression.comparisonWindowDays) JOURS",
                movement,
                "\(improving) sur \(comparable) exercices comparables ont amélioré leur meilleur e1RM."
            )
        }
        if improving == 0 && stable > 0 && declining == 0 {
            return (
                "TRAJECTOIRE SUR \(progression.comparisonWindowDays) JOURS",
                "Stable",
                "\(stable) mouvements comparables sans changement matériel détecté."
            )
        }
        if improving == 0 && stable == 0 && declining > 0 {
            let movement = declining == 1
                ? "1 mouvement comparable est en baisse sur la période."
                : "\(declining) mouvements comparables sont en baisse sur la période."
            return (
                "TRAJECTOIRE SUR \(progression.comparisonWindowDays) JOURS",
                "En baisse",
                movement
            )
        }
        return (
            "TRAJECTOIRE SUR \(progression.comparisonWindowDays) JOURS",
            "Progression mixte",
            "\(improving) en hausse · \(stable) stables · \(declining) en baisse"
        )
    }

    var body: some View {
        Button(action: { isShowingExplanation = true }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("TRAJECTOIRE FORCE")
                        .font(.appMicro.weight(.bold))
                        .tracking(2)
                        .foregroundColor(Color.domainAccent(.training))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appMicro.weight(.semibold))
                        .foregroundColor(.appTextMuted)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(presentation.headline)
                        .font(.appTitle.weight(.bold))
                        .foregroundColor(.appTextPrimary)
                    Text("\(progression.comparisonWindowDays) derniers jours vs \(progression.comparisonWindowDays) jours précédents")
                        .font(.appCaption)
                        .foregroundColor(.appTextSecondary)
                }

                if comparable > 0 {
                    ForceDistributionBar(
                        improving: improving,
                        stable: stable,
                        declining: declining
                    )

                    HStack(spacing: 8) {
                        StatusChip(label: "\(improving) en hausse", color: .appSuccess)
                        StatusChip(label: "\(stable) stable\(stable == 1 ? "" : "s")", color: .appTextSecondary)
                        StatusChip(label: "\(declining) en baisse", color: .appDanger)
                    }
                } else {
                    Text(presentation.support)
                        .font(.appBody)
                        .foregroundColor(.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.appCardInsetV)
            .background(Color.appCard)
            .overlay(
                RoundedRectangle(cornerRadius: .appCardRadius)
                    .stroke(Color.appSeparator, lineWidth: CGFloat.appHairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, .appPagePadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Touchez pour comprendre")
        .sheet(isPresented: $isShowingExplanation, onDismiss: {
            guard shouldOpenForceAfterDismiss else { return }
            shouldOpenForceAfterDismiss = false
            onOpen()
        }) {
            ForceTrajectoryExplanationSheet(
                windowDays: progression.comparisonWindowDays,
                improving: improving,
                stable: stable,
                declining: declining,
                isMixed: [improving, stable, declining].filter { $0 > 0 }.count > 1,
                onOpenForce: {
                    shouldOpenForceAfterDismiss = true
                    isShowingExplanation = false
                }
            )
        }
    }

    private struct ForceTrajectoryExplanationSheet: View {
        let windowDays: Int
        let improving: Int
        let stable: Int
        let declining: Int
        let isMixed: Bool
        let onOpenForce: () -> Void

        @Environment(\.dismiss) private var dismiss

        private var comparable: Int { improving + stable + declining }

        private var resultSummary: String {
            guard comparable > 0 else {
                return "Aucun exercice comparable n’est disponible sur ces deux périodes."
            }
            let exerciseLabel = comparable == 1 ? "exercice comparable" : "exercices comparables"
            return "Sur \(comparable) \(exerciseLabel) : \(statusClause(improving, singular: "est en hausse", plural: "sont en hausse", none: "aucun n’est en hausse")), \(statusClause(stable, singular: "est stable", plural: "sont stables", none: "aucun n’est stable")), \(statusClause(declining, singular: "est en baisse", plural: "sont en baisse", none: "aucun n’est en baisse"))."
        }

        private func statusClause(_ count: Int, singular: String, plural: String, none: String) -> String {
            if count == 0 { return none }
            return count == 1 ? "1 \(singular)" : "\(count) \(plural)"
        }

        var body: some View {
            NavigationStack {
                ZStack {
                    Color.appBg.ignoresSafeArea()

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Cette vue compare ton meilleur 1RM estimé pour chaque exercice sur les \(windowDays) derniers jours avec les \(windowDays) jours précédents.")
                                .font(.appBody)
                                .foregroundColor(.appTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(alignment: .leading, spacing: 12) {
                                category(
                                    title: "En hausse",
                                    definition: "Meilleur 1RM estimé en progression de 5 % ou plus."
                                )
                                category(
                                    title: "Stable",
                                    definition: "Variation de moins de 5 % dans un sens ou dans l’autre."
                                )
                                category(
                                    title: "En baisse",
                                    definition: "Meilleur 1RM estimé en recul de 5 % ou plus."
                                )
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("RÉSULTAT ACTUEL")
                                    .font(.appMicro.weight(.bold))
                                    .tracking(1.5)
                                    .foregroundColor(.appTextMuted)
                                Text(resultSummary)
                                    .font(.appBody.weight(.semibold))
                                    .foregroundColor(.appTextPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if isMixed {
                                    Text("Progression mixte signifie que tous tes exercices n’évoluent pas dans la même direction.")
                                        .font(.appCaption)
                                        .foregroundColor(.appTextSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)

                            Text("Le 1RM estimé est une estimation de ta force maximale à partir de tes séries enregistrées. Ce n’est pas nécessairement un vrai essai à 1 répétition.")
                                .font(.appCaption)
                                .foregroundColor(.appTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.appPagePadding)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        Divider()
                        Button(action: onOpenForce) {
                            Text("Voir le détail Force")
                                .font(.appLabel.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.domainAccent(.training))
                        .accessibilityLabel("Voir le détail Force")
                        .padding(.horizontal, .appPagePadding)
                        .padding(.vertical, 12)
                    }
                    .background(Color.appBg)
                }
                .navigationTitle("Trajectoire Force")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Fermer") { dismiss() }
                            .foregroundColor(Color.domainAccent(.training))
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }

        private func category(title: String, definition: String) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
                Text(definition)
                    .font(.appCaption)
                    .foregroundColor(.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private struct ForceDistributionBar: View {
        let improving: Int
        let stable: Int
        let declining: Int

        private var total: Int { improving + stable + declining }
        private var visibleSegmentCount: Int { [improving, stable, declining].filter { $0 > 0 }.count }

        var body: some View {
            GeometryReader { geometry in
                let spacing = CGFloat(max(visibleSegmentCount - 1, 0)) * 3
                let availableWidth = max(geometry.size.width - spacing, 0)
                HStack(spacing: 3) {
                    segment(count: improving, color: .appSuccess, availableWidth: availableWidth)
                    segment(count: stable, color: .appTextSecondary, availableWidth: availableWidth)
                    segment(count: declining, color: .appDanger, availableWidth: availableWidth)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .accessibilityHidden(true)
        }

        @ViewBuilder
        private func segment(count: Int, color: Color, availableWidth: CGFloat) -> some View {
            if count > 0, total > 0 {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: availableWidth * CGFloat(count) / CGFloat(total))
            }
        }
    }

    private struct StatusChip: View {
        let label: String
        let color: Color

        var body: some View {
            Text(label)
                .font(.appMicro.weight(.semibold))
                .foregroundColor(color)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.appSurfaceInset)
                .clipShape(Capsule())
        }
    }
}

struct StatsOverviewActivityCard: View {
    let trainingLoad: StatsCockpitTrainingLoad
    let onOpen: () -> Void
    @EnvironmentObject private var theme: AppTheme

    private var weekly: [StatsWeeklyTrainingLoad] { trainingLoad.weekly }
    private var maxActiveDays: Int { max(weekly.map(\.activeDayCount).max() ?? 0, 1) }
    private var hasPartialWeek: Bool { weekly.last?.isPartial == true }

    private var accessibilitySummary: String {
        let partial = hasPartialWeek ? " La semaine en cours est affichée comme partielle." : ""
        let sessions = trainingLoad.summary.sessionCount == 1 ? "1 séance" : "\(trainingLoad.summary.sessionCount) séances"
        let days = trainingLoad.summary.activeDayCount == 1 ? "1 jour actif" : "\(trainingLoad.summary.activeDayCount) jours actifs"
        return "Activité sur 12 semaines. \(sessions), \(days). Rythme hebdomadaire.\(partial)"
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                overviewHeader(title: "ACTIVITÉ", period: "12 SEMAINES")

                HStack(spacing: 20) {
                    metric(value: trainingLoad.summary.sessionCount, label: "Séances")
                    metric(value: trainingLoad.summary.activeDayCount, label: "Jours actifs")
                }

                if weekly.isEmpty {
                    Text("Pas encore de rythme hebdomadaire disponible.")
                        .font(.appCaption).foregroundColor(.appTextSecondary)
                } else {
                    GeometryReader { geometry in
                        HStack(alignment: .bottom, spacing: 5) {
                            ForEach(weekly, id: \.weekStart) { bucket in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(theme.chartColor(0))
                                    .opacity(bucket.isPartial ? 0.4 : 1)
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 2,
                                        maxHeight: max(
                                            CGFloat(bucket.activeDayCount) / CGFloat(maxActiveDays) * geometry.size.height,
                                            2
                                        )
                                    )
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: 48)
                    .accessibilityHidden(true)
                }

                if hasPartialWeek {
                    Text("Semaine en cours")
                        .font(.appMicro)
                        .foregroundColor(.appTextMuted)
                }
            }
            .overviewCardStyle()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, .appPagePadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Ouvrir Régularité")
    }

    private func overviewHeader(title: String, period: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
            Spacer()
            Text(period)
                .font(.appCaption.weight(.semibold)).foregroundColor(.appTextSecondary)
            Image(systemName: "chevron.right")
                .font(.appMicro.weight(.semibold)).foregroundColor(.appTextMuted)
                .accessibilityHidden(true)
        }
    }

    private func metric(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.appHeadline.weight(.semibold)).foregroundColor(.appTextPrimary)
            Text(label)
                .font(.appCaption).foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatsOverviewExternalLoadCard: View {
    let trainingLoad: StatsCockpitTrainingLoad
    let onOpen: () -> Void
    @EnvironmentObject private var theme: AppTheme

    private var validPoints: [(index: Int, bucket: StatsWeeklyTrainingLoad, value: Double)] {
        trainingLoad.weekly.enumerated().compactMap { index, bucket in
            guard let value = bucket.tonnage.value else { return nil }
            return (index, bucket, value)
        }
    }

    private var completeBuckets: [(index: Int, bucket: StatsWeeklyTrainingLoad)] {
        trainingLoad.weekly.enumerated().compactMap { index, bucket in
            bucket.isPartial ? nil : (index, bucket)
        }
    }

    private var latestComplete: (index: Int, bucket: StatsWeeklyTrainingLoad)? {
        completeBuckets.last
    }

    private var relativeDelta: Double? {
        guard completeBuckets.count >= 2,
              let recent = completeBuckets[completeBuckets.count - 1].bucket.tonnage.value,
              let previous = completeBuckets[completeBuckets.count - 2].bucket.tonnage.value else { return nil }
        guard previous > 0 else { return nil }
        return (recent - previous) / previous
    }

    private var latestTonnageLabel: String {
        guard let value = latestComplete?.bucket.tonnage.value else { return "Indisponible" }
        let displayValue = UnitSettings.shared.display(value)
        let formatted = NumberFormatter.spaceGrouped.string(from: NSNumber(value: displayValue))
            ?? String(format: "%.0f", displayValue)
        return "\(formatted) \(UnitSettings.shared.label)"
    }

    private var deltaLabel: String? {
        guard let relativeDelta else { return nil }
        let value = abs(relativeDelta * 100)
        if relativeDelta == 0 { return "Même niveau que la semaine précédente" }
        let formatted = String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
        return "\(relativeDelta > 0 ? "+" : "−")\(formatted) % vs semaine précédente"
    }

    private var accessibilitySummary: String {
        var summary = "Charge externe sur 12 semaines. Dernière semaine complète : \(latestTonnageLabel)."
        if let relativeDelta {
            let value = String(format: "%.1f", abs(relativeDelta * 100)).replacingOccurrences(of: ".", with: ",")
            if relativeDelta == 0 {
                summary += " Même niveau que la semaine précédente."
            } else if relativeDelta > 0 {
                summary += " Hausse de \(value) pour cent par rapport à la semaine précédente."
            } else {
                summary += " Baisse de \(value) pour cent par rapport à la semaine précédente."
            }
        }
        return summary
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("CHARGE EXTERNE")
                        .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
                    Spacer()
                    Text("12 SEMAINES")
                        .font(.appCaption.weight(.semibold)).foregroundColor(.appTextSecondary)
                    Image(systemName: "chevron.right")
                        .font(.appMicro.weight(.semibold)).foregroundColor(.appTextMuted)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(latestTonnageLabel)
                        .font(.appHeadline.weight(.semibold)).foregroundColor(.appTextPrimary)
                    Text("Dernière semaine complète")
                        .font(.appCaption).foregroundColor(.appTextSecondary)
                    if let deltaLabel {
                        Text(deltaLabel)
                            .font(.appMicro.weight(.semibold)).foregroundColor(.appTextSecondary)
                    }
                }

                if validPoints.isEmpty {
                    Text("Pas encore de trajectoire de charge disponible.")
                        .font(.appCaption).foregroundColor(.appTextSecondary)
                } else {
                    Chart {
                        ForEach(validPoints, id: \.index) { point in
                            LineMark(
                                x: .value("Semaine", point.index),
                                y: .value("Tonnage", UnitSettings.shared.display(point.value))
                            )
                            .foregroundStyle(theme.chartColor(1))
                            .interpolationMethod(.catmullRom)

                            if point.index == validPoints.last?.index {
                                PointMark(
                                    x: .value("Semaine", point.index),
                                    y: .value("Tonnage", UnitSettings.shared.display(point.value))
                                )
                                .foregroundStyle(theme.chartColor(1))
                                .symbolSize(42)
                            }
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 54)
                    .accessibilityHidden(true)
                }
            }
            .overviewCardStyle()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, .appPagePadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Ouvrir Charge")
    }
}

private extension View {
    func overviewCardStyle() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.appCardInsetV)
            .background(Color.appCard)
            .overlay(
                RoundedRectangle(cornerRadius: .appCardRadius)
                    .stroke(Color.appSeparator, lineWidth: CGFloat.appHairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
    }
}

struct StatsOverviewNotableCard: View {
    let recentPRs: [RecentPR]
    let movers: [StatsProgressionComparison]
    let attention: [StatsAttentionObservation]
    let onSelectExercise: (String) -> Void
    @ObservedObject private var units = UnitSettings.shared

    private enum Fact: Identifiable {
        case recentPR(RecentPR)
        case mover(StatsProgressionComparison)
        case attention(StatsAttentionObservation)

        var exerciseName: String {
            switch self {
            case .recentPR(let record): return record.name
            case .mover(let mover): return mover.exerciseName
            case .attention(let observation): return observation.exerciseName
            }
        }

        var id: String {
            switch self {
            case .recentPR: return "pr-\(exerciseName)"
            case .mover: return "mover-\(exerciseName)"
            case .attention: return "attention-\(exerciseName)"
            }
        }
    }

    private var facts: [Fact] {
        let prFacts = recentPRs
            .sorted { $0.date > $1.date }
            .map(Fact.recentPR)
        let moverFacts = movers.compactMap { mover -> Fact? in
            guard mover.baselineBestE1RM != nil,
                  mover.recentBestE1RM != nil,
                  mover.relativeDelta != nil else { return nil }
            return .mover(mover)
        }
        let attentionFacts = attention.compactMap { observation -> Fact? in
            guard observation.kind == .noRecentImprovement else { return nil }
            return .attention(observation)
        }

        var selected: [Fact] = []
        var seenExercises = Set<String>()

        func appendFirstAvailable(from candidates: [Fact]) {
            guard selected.count < 3 else { return }
            for candidate in candidates {
                let key = normalizedExerciseName(candidate.exerciseName)
                if seenExercises.insert(key).inserted {
                    selected.append(candidate)
                    return
                }
            }
        }

        appendFirstAvailable(from: prFacts)
        appendFirstAvailable(from: moverFacts)
        appendFirstAvailable(from: attentionFacts)

        if selected.count < 3 {
            for candidates in [prFacts, moverFacts, attentionFacts] {
                for candidate in candidates where selected.count < 3 {
                    let key = normalizedExerciseName(candidate.exerciseName)
                    if seenExercises.insert(key).inserted {
                        selected.append(candidate)
                    }
                }
            }
        }

        return selected
    }

    var body: some View {
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("À NOTER")
                    .font(.appMicro.weight(.bold))
                    .tracking(2)
                    .foregroundColor(.appTextMuted)

                ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                    Button {
                        onSelectExercise(fact.exerciseName)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fact.exerciseName)
                                    .font(.appBody.weight(.semibold))
                                    .foregroundColor(.appTextPrimary)
                                    .lineLimit(1)
                                Text(detail(for: fact))
                                    .font(.appCaption)
                                    .foregroundColor(.appTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.appMicro.weight(.semibold))
                                .foregroundColor(.appTextMuted)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: fact))

                    if index < facts.count - 1 {
                        Divider().overlay(Color.appSeparator)
                    }
                }
            }
            .overviewCardStyle()
            .padding(.horizontal, .appPagePadding)
        }
    }

    private func normalizedExerciseName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_CA"))
    }

    private func detail(for fact: Fact) -> String {
        switch fact {
        case .recentPR(let record):
            return "Record récent · 1RM estimé \(units.format(record.est1RM, decimals: 0)) · \(formattedDate(record.date))"
        case .mover(let mover):
            guard let baseline = mover.baselineBestE1RM,
                  let recent = mover.recentBestE1RM,
                  let delta = mover.relativeDelta else { return "Hausse du meilleur 1RM estimé" }
            return "Meilleur 1RM estimé : \(units.format(baseline, decimals: 0)) → \(units.format(recent, decimals: 0)) · \(formattedPercent(delta))"
        case .attention:
            return "Aucun nouveau meilleur 1RM estimé sur les expositions comparables"
        }
    }

    private func accessibilityLabel(for fact: Fact) -> String {
        switch fact {
        case .recentPR(let record):
            return "\(record.name). Record récent. 1RM estimé \(units.format(record.est1RM, decimals: 0)). \(formattedDate(record.date))."
        case .mover(let mover):
            guard let baseline = mover.baselineBestE1RM,
                  let recent = mover.recentBestE1RM,
                  let delta = mover.relativeDelta else {
                return "\(mover.exerciseName). Hausse du meilleur 1RM estimé."
            }
            let percentage = String(format: "%.1f", abs(delta * 100)).replacingOccurrences(of: ".", with: ",")
            return "\(mover.exerciseName). Meilleur 1RM estimé de \(units.format(baseline, decimals: 0)) à \(units.format(recent, decimals: 0)). Hausse de \(percentage) pour cent."
        case .attention(let observation):
            return "\(observation.exerciseName). Aucun nouveau meilleur 1RM estimé sur les expositions comparables."
        }
    }

    private func formattedDate(_ rawDate: String) -> String {
        guard let date = DateFormatter.isoDate.date(from: rawDate) else { return rawDate }
        let calendar = Calendar.mtl
        if calendar.isDateInToday(date) { return "Aujourd’hui" }
        if calendar.isDateInYesterday(date) { return "Hier" }
        return DateFormatter.shortDateFRCA.string(from: date)
    }

    private func formattedPercent(_ value: Double) -> String {
        let formatted = String(format: "%+.1f", value * 100).replacingOccurrences(of: ".", with: ",")
        return "\(formatted) %"
    }
}

// MARK: - Stats Tab Bar
struct StatsTabBar: View {
    @Binding var selectedTab: StatsTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(StatsTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.3)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.appLabel.weight(selectedTab == tab ? .bold : .regular))
                        Text(tab.title)
                            .font(.appMicro.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(selectedTab == tab ? Color.domainAccent(.training) : Color.appTextSecondary)
                    .background(selectedTab == tab ? Color.appSurfaceInset : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: .appCardRadius / 2))
                }
                .accessibilityLabel(tab.accessibilityLabel)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
    }
}

// MARK: - Period Picker
struct PeriodPicker: View {
    @Binding var selected: StatsPeriod

    var body: some View {
        HStack(spacing: 8) {
            ForEach(StatsPeriod.allCases, id: \.self) { p in
                Button {
                    withAnimation(.spring(response: 0.25)) { selected = p }
                } label: {
                    Text(p.rawValue)
                        .font(.appCaption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(selected == p ? Color.forge : Color.appSurfaceInset)
                        .foregroundColor(selected == p ? Color.onAccent : .gray)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
    }
}

// MARK: - Smart Insights Banner
// MARK: - Adherence Rings Card
