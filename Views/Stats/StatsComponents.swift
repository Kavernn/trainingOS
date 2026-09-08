import SwiftUI

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

// MARK: - Canonical muscle workload
struct StatsMuscleWorkloadSection: View {
    let muscles: StatsCockpitMuscles

    private var coverageMessage: String? {
        let coverage = muscles.coverage
        guard coverage.unmappedExposureCount > 0 else { return nil }
        return "Mapping partiel · \(coverage.mappedExposureCount) / \(coverage.totalExposureCount) expositions mappées"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TRAVAIL PAR MUSCLE")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
            Text("Répartition du travail mesurable")
                .font(.appCaption).foregroundColor(.appTextSecondary)

            if let coverageMessage {
                Text(coverageMessage)
                    .font(.appMicro.weight(.semibold)).foregroundColor(.appTextMuted)
            }

            if muscles.workloads.isEmpty {
                Text("Pas encore de travail musculaire mesurable.")
                    .font(.appBody).foregroundColor(.appTextSecondary)
            } else {
                ForEach(muscles.workloads, id: \.muscle) { workload in
                    StatsMuscleWorkloadRow(workload: workload)
                    if workload.muscle != muscles.workloads.last?.muscle {
                        Divider().overlay(Color.appSeparator)
                    }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(workload.muscle)
                .font(.appBody.weight(.semibold)).foregroundColor(.appTextPrimary)
                .lineLimit(1)
            HStack(spacing: 10) {
                Text("\(workload.directSetCount) séries directes")
                Text("\(workload.indirectSetCount) séries indirectes")
            }
            .font(.appCaption).foregroundColor(.appTextSecondary)
            Text("\(workload.sessionCount) séances · \(workload.activeDayCount) jours actifs")
                .font(.appMicro).foregroundColor(.appTextMuted)
            Text("Dernière exposition · \(workload.lastExposureDate)")
                .font(.appMicro).foregroundColor(.appTextMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workload.muscle). \(workload.directSetCount) séries directes. \(workload.indirectSetCount) séries indirectes. \(workload.sessionCount) séances. \(workload.activeDayCount) jours actifs. Dernière exposition le \(workload.lastExposureDate).")
    }
}

// MARK: - Canonical external load
struct StatsExternalLoadSection: View {
    let trainingLoad: StatsCockpitTrainingLoad

    private var tonnageLabel: String {
        trainingLoad.summary.tonnage.value.map { UnitSettings.shared.format($0, decimals: 0) } ?? "—"
    }

    private var coverageLabel: String {
        let tonnage = trainingLoad.summary.tonnage
        switch tonnage.coverage {
        case .complete: return "Complet"
        case .partial:
            return tonnage.applicableExposureCount > 0
                ? "Partiel · \(tonnage.calculableExposureCount)/\(tonnage.applicableExposureCount) expositions calculables"
                : "Partiel"
        case .unavailable: return "Indisponible"
        case .unknown: return "Données partielles"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CHARGE EXTERNE")
                .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
            Text("Tonnage reps sur la période")
                .font(.appCaption).foregroundColor(.appTextSecondary)

            HStack(spacing: 12) {
                metric(value: tonnageLabel, label: "Tonnage reps", detail: coverageLabel)
                metric(value: "\(trainingLoad.summary.validRepsSetCount)", label: "Séries valides", detail: nil)
                metric(
                    value: "\(trainingLoad.summary.tonnage.calculableExposureCount) / \(trainingLoad.summary.tonnage.applicableExposureCount)",
                    label: "Expositions calculables",
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
        .accessibilityLabel("Charge externe. Tonnage reps \(tonnageLabel). \(coverageLabel). \(trainingLoad.summary.validRepsSetCount) séries valides.")
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
            Text("TONNAGE REPS / SEMAINE")
                .font(.appMicro.weight(.bold)).tracking(1.5).foregroundColor(.appTextMuted)
            if weekly.isEmpty {
                Text("Pas encore de trajectoire hebdomadaire disponible.")
                    .font(.appCaption).foregroundColor(.appTextSecondary)
            } else {
                GeometryReader { geometry in
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(weekly, id: \.weekStart) { bucket in
                            weeklyBar(bucket, maxValue: maxValue, height: geometry.size.height)
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
    private func weeklyBar(_ bucket: StatsWeeklyTrainingLoad, maxValue: Double, height: CGFloat) -> some View {
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
            Text(String(bucket.weekStart.prefix(7)))
                .font(.appMicro).foregroundColor(.appTextMuted).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func weeklyAccessibilityLabel(_ bucket: StatsWeeklyTrainingLoad, tonnage: Double?) -> String {
        let value = tonnage.map { UnitSettings.shared.format($0, decimals: 0) } ?? "indisponible"
        let partial = bucket.isPartial ? ", semaine partielle" : ""
        return "Semaine du \(bucket.weekStart). Tonnage reps \(value)\(partial)."
    }
}

// MARK: - Canonical Force progression
struct StatsStrengthProgressionSection: View {
    let comparisons: [StatsProgressionComparison]
    var onSelectExercise: ((String) -> Void)? = nil
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PROGRESSION PAR EXERCICE").font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.appTextMuted)
            Text("Comparaison des meilleures performances sur les deux périodes").font(.appCaption).foregroundColor(.appTextSecondary)
            if comparisons.isEmpty {
                Text("Pas encore assez de données comparables.").font(.appBody).foregroundColor(.appTextSecondary)
            } else {
                group("EN HAUSSE", comparisons: improving)
                group("STABLE", comparisons: stable)
                group("EN BAISSE", comparisons: declining)
                group("DONNÉES INSUFFISANTES", comparisons: insufficient)
                group("DONNÉES DISPONIBLES", comparisons: other)
            }
        }
        .padding(.appCardInsetV).background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius)).padding(.horizontal, .appPagePadding)
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
    var body: some View {
        Button(action: { onSelect?() }) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { Text(comparison.exerciseName).font(.appBody.weight(.semibold)).foregroundColor(.appTextPrimary).lineLimit(1); Spacer(minLength: 6); Text(statusLabel).font(.appCaption.weight(.semibold)).foregroundColor(statusColor) }
                HStack(spacing: 8) {
                    if let recent = comparison.recentBestE1RM { Text(UnitSettings.shared.format(recent, decimals: 0)).font(.appLabel.weight(.semibold)).foregroundColor(.appTextPrimary) }
                    if let delta = comparison.relativeDelta { Text(String(format: "%+.1f", delta * 100).replacingOccurrences(of: ".", with: ",") + " %").font(.appCaption.weight(.semibold)).foregroundColor(statusColor) }
                    Spacer(minLength: 0)
                }
                if let baseline = comparison.baselineBestE1RM, let recent = comparison.recentBestE1RM { Text("\(UnitSettings.shared.format(baseline, decimals: 0)) → \(UnitSettings.shared.format(recent, decimals: 0))").font(.appMicro).foregroundColor(.appTextSecondary) }
                else if let reason { Text(reason).font(.appMicro).foregroundColor(.appTextSecondary) }
                Text("\(comparison.baselineExposureCount) réf. · \(comparison.recentExposureCount) récentes").font(.appMicro).foregroundColor(.appTextMuted)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
    }
}

// MARK: - Cockpit Overview
struct StatsProgressionHero: View {
    let progression: StatsCockpitProgression

    private var improving: Int { progression.statusCounts.improving }
    private var stable: Int { progression.statusCounts.stable }
    private var declining: Int { progression.statusCounts.declining }
    private var comparable: Int { improving + stable + declining }

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
        VStack(alignment: .leading, spacing: 16) {
            Text(presentation.eyebrow)
                .font(.appMicro.weight(.bold))
                .tracking(2)
                .foregroundColor(Color.domainAccent(.training))

            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.headline)
                    .font(.appTitle.weight(.bold))
                    .foregroundColor(.appTextPrimary)
                Text(presentation.support)
                    .font(.appBody)
                    .foregroundColor(.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if comparable > 0 {
                HStack(spacing: 8) {
                    if improving > 0 { StatusChip(label: "\(improving) en hausse", color: .appSuccess) }
                    if stable > 0 { StatusChip(label: "\(stable) stable\(stable == 1 ? "" : "s")", color: .appTextSecondary) }
                    if declining > 0 { StatusChip(label: "\(declining) en baisse", color: .appDanger) }
                }
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
        .padding(.horizontal, .appPagePadding)
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

struct StatsOverviewMetric: View {
    let value: String
    let label: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.appHeadline.weight(.semibold))
                .foregroundColor(.appTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.appCaption)
                .foregroundColor(.appTextSecondary)
            if let detail {
                Text(detail)
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(.appTextMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct StatsTopMoversCard: View {
    let movers: [StatsProgressionComparison]
    var onSelectExercise: ((String) -> Void)? = nil

    private var visibleMovers: [StatsProgressionComparison] {
        Array(movers.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOP MOVERS")
                .font(.appMicro.weight(.bold))
                .tracking(2)
                .foregroundColor(.appTextMuted)

            ForEach(visibleMovers, id: \.exerciseName) { mover in
                Button {
                    onSelectExercise?(mover.exerciseName)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mover.exerciseName)
                                .font(.appBody.weight(.semibold))
                                .foregroundColor(.appTextPrimary)
                                .lineLimit(1)
                            if let baseline = mover.baselineBestE1RM,
                               let recent = mover.recentBestE1RM {
                                Text("\(UnitSettings.shared.format(baseline, decimals: 0)) → \(UnitSettings.shared.format(recent, decimals: 0)) e1RM")
                                    .font(.appMicro)
                                    .foregroundColor(.appTextSecondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(formatRelativeDelta(mover.relativeDelta))
                            .font(.appBody.weight(.bold))
                            .foregroundColor(.appSuccess)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: mover))

                if mover.exerciseName != visibleMovers.last?.exerciseName {
                    Divider().overlay(Color.appSeparator)
                }
            }
        }
        .padding(.appCardInsetV)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
    }

    private func formatRelativeDelta(_ value: Double?) -> String {
        guard let value else { return "—" }
        let formatted = String(format: "%+.1f", value * 100)
            .replacingOccurrences(of: ".", with: ",")
        return "\(formatted) %"
    }

    private func accessibilityLabel(for mover: StatsProgressionComparison) -> String {
        guard let delta = mover.relativeDelta else {
            return "\(mover.exerciseName), progression disponible"
        }
        let formatted = String(format: "%.1f", abs(delta * 100))
            .replacingOccurrences(of: ".", with: ",")
        return "\(mover.exerciseName), en hausse de \(formatted) pour cent"
    }
}

struct StatsAttentionCard: View {
    let attention: [StatsAttentionObservation]

    private var visibleAttention: [StatsAttentionObservation] {
        Array(attention.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("À REVOIR")
                .font(.appMicro.weight(.bold))
                .tracking(2)
                .foregroundColor(.appTextMuted)

            ForEach(visibleAttention, id: \.exerciseName) { observation in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.dotted")
                        .font(.appLabel)
                        .foregroundColor(.appWarning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(observation.exerciseName)
                            .font(.appBody.weight(.semibold))
                            .foregroundColor(.appTextPrimary)
                        Text(detail(for: observation))
                            .font(.appCaption)
                            .foregroundColor(.appTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                if observation.exerciseName != visibleAttention.last?.exerciseName {
                    Divider().overlay(Color.appSeparator)
                }
            }
        }
        .padding(.appCardInsetV)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: .appCardRadius))
        .padding(.horizontal, .appPagePadding)
    }

    private func detail(for observation: StatsAttentionObservation) -> String {
        switch observation.kind {
        case .noRecentImprovement:
            return "Aucun nouveau meilleur e1RM sur les dernières expositions comparables."
        case .unknown:
            return "Observation disponible"
        }
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
struct SmartInsightsBanner: View {
    let insights: [(icon: String, text: String, color: Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill").foregroundColor(.gray).font(.appMicro)
                Text("INSIGHTS").font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(insights.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        Image(systemName: insights[i].icon)
                            .foregroundColor(insights[i].color)
                            .font(.appLabel)
                            .frame(width: 18)
                        Text(insights[i].text)
                            .font(.appLabel)
                            .foregroundColor(Color.appOnSurface.opacity(0.9))
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Adherence Rings Card
struct AdherenceRingsCard: View {
    let data: AdherenceData

    private var daysInMonth: Int {
        let parts = data.period.split(separator: "-")
        guard parts.count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]),
              let d = Calendar.mtl.date(from: DateComponents(year: y, month: m, day: 1)),
              let range = Calendar.mtl.range(of: .day, in: .month, for: d)
        else { return 30 } // ponytail: fallback si period malformé
        return range.count
    }

    private struct Pillar {
        let label:   String
        let pct:     Int
        let color:   Color
        let rawDays: Int?
    }

    private var pillars: [Pillar] {
        [
            Pillar(label: "Body",        pct: data.bodyPct,   color: .forge, rawDays: nil),
            Pillar(label: "Mind",        pct: data.mindPct,   color: .gray, rawDays: nil),
            Pillar(label: "Consistance", pct: data.fuelPct,   color: .gray, rawDays: data.fuelDays),
            Pillar(label: "Spirit",      pct: data.spiritPct, color: .gray, rawDays: nil),
        ]
    }

    @State private var showFuelInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // collage titre/sous-titre, micro-optique volontaire
            VStack(alignment: .leading, spacing: 2) {
                Text("CONSTANCE CE MOIS")
                    .font(.appMicro.weight(.bold)).tracking(2).foregroundColor(.gray)
                Text("\(data.daysElapsed) / \(daysInMonth) j écoulés")
                    .font(.appCaption).foregroundColor(.gray.opacity(0.7))
            }

            HStack(spacing: 24) {
                ZStack {
                    ForEach(pillars.indices.reversed(), id: \.self) { i in
                        AdherenceArc(
                            pct: Double(pillars[i].pct) / 100.0,
                            color: pillars[i].color,
                            radius: CGFloat(40 - i * 8),
                            lineWidth: 6
                        )
                    }
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pillars.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(pillars[i].color)
                                .frame(width: 8, height: 8)
                            Text(pillars[i].label)
                                .font(.appCaption).foregroundColor(Color.appOnSurface.opacity(0.85))
                            Spacer()
                            if pillars[i].rawDays == .some(0) {
                                Text("—")
                                    .font(.appCaption.weight(.bold)).foregroundColor(.gray)
                            } else {
                                Text("\(pillars[i].pct)%")
                                    .font(.appCaption.weight(.bold))
                                    .foregroundColor(adherenceColor(pillars[i].pct))
                            }
                            if pillars[i].rawDays != nil {
                                Button { showFuelInfo = true } label: {
                                    Image(systemName: "info.circle")
                                        .font(.appCaption).foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(16).glassCard()
        .alert("Consistance", isPresented: $showFuelInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Jours avec au moins un repas loggué ce mois-ci")
        }
    }

    private func adherenceColor(_ pct: Int) -> Color {
        if pct >= 70 { return .appSuccess }
        if pct >= 40 { return .appWarning }
        return .appDanger
    }
}

private struct AdherenceArc: View {
    let pct: Double
    let color: Color
    let radius: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .trim(from: 0, to: CGFloat(min(pct, 1.0)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: radius * 2, height: radius * 2)
                .animation(.easeOut(duration: 0.6), value: pct)
        }
    }
}
