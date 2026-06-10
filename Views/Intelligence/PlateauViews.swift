import SwiftUI

// ── Section ───────────────────────────────────────────────────────────────────

struct PlateauSection: View {
    @State private var alerts: [PlateauAlert] = []
    @State private var isLoading              = false
    @State private var selected: PlateauAlert?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            if isLoading {
                plateauSkeleton
            } else if alerts.isEmpty {
                emptyState
            } else {
                ForEach(alerts, id: \.stableId) { alert in
                    PlateauAlertRow(alert: alert) {
                        selected = alert
                    }
                    if alert.stableId != alerts.last?.stableId {
                        Divider()
                            .background(Color(white: 0.2))
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
        .sheet(item: $selected) { alert in
            PlateauDetailSheet(alert: alert) {
                Task { await reload() }
            }
        }
        .task { await load() }
    }

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.appCaption.weight(.bold))
                .foregroundColor(.orange)
            Text("DÉTECTION DE PLATEAU")
                .font(.appCaption.weight(.bold))
                .foregroundColor(Color(white: 0.45))
            Spacer()
            if !alerts.isEmpty {
                Text("\(alerts.count)")
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green.opacity(0.7))
                .font(.appLabel)
            Text("Aucun adversaire actif. Tu progresses.")
                .font(.appLabel)
                .foregroundColor(Color(white: 0.45))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var plateauSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.15))
                    .frame(height: 56)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
        .padding(.bottom, 6)
        .redacted(reason: .placeholder)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await APIService.shared.fetchPlateauAlerts()
            alerts = response.alerts.filter { $0.status != "dismissed" && $0.status != "completed" }
        } catch {}
    }

    private func reload() async {
        do {
            let response = try await APIService.shared.fetchPlateauAlerts(force: true)
            alerts = response.alerts.filter { $0.status != "dismissed" && $0.status != "completed" }
        } catch {}
    }
}

// ── Alert Row ────────────────────────────────────────────────────────────────

struct PlateauAlertRow: View {
    let alert: PlateauAlert
    let onTap: () -> Void
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        let scoreText   = "\(alert.plateauScore)/100"
        let weeksText   = alert.plateauWeeks == 1
            ? "1 semaine"
            : "\(alert.plateauWeeks) semaines"

        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: alert.rootCauseIcon)
                    .font(.system(size: 18))
                    .foregroundColor(alert.severityColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.exerciseName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("\(alert.rootCauseLabel) · \(weeksText)")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.5))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(alert.severityLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(alert.severityColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(alert.severityColor.opacity(0.15))
                        .cornerRadius(4)
                    Text(scoreText)
                        .font(.appCaption)
                        .foregroundColor(Color(white: 0.4))
                }

                Image(systemName: "chevron.right")
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(Color(white: 0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// ── Detail Sheet ─────────────────────────────────────────────────────────────

struct PlateauDetailSheet: View {
    let alert: PlateauAlert
    let onStatusChanged: () -> Void

    @State private var showDeloadPlan = false
    @State private var isDismissing   = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    sparklineSection
                    contextChipsSection
                    if alert.deloadType != nil {
                        solutionSection
                    }
                    actionButtons
                }
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle(alert.exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .foregroundColor(Color(white: 0.6))
                }
            }
        }
        .sheet(isPresented: $showDeloadPlan) {
            if let plan = alert.deloadPlan {
                DeloadPlanSheet(alert: alert, plan: plan, onActivate: {
                    onStatusChanged()
                    dismiss()
                })
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: alert.rootCauseIcon)
                    .font(.system(size: 22))
                    .foregroundColor(alert.severityColor)
                Text(alert.severityLabel)
                    .font(.appLabel.weight(.bold))
                    .foregroundColor(alert.severityColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(alert.severityColor.opacity(0.15))
                    .cornerRadius(6)
            }
            Text(alert.rootCauseLabel)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            let weeksText = alert.plateauWeeks == 1
                ? "Tu n'as pas progressé depuis 1 semaine."
                : "Tu n'as pas progressé depuis \(alert.plateauWeeks) semaines."
            Text(weeksText)
                .font(.system(size: 14))
                .foregroundColor(Color(white: 0.5))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var sparklineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROGRESSION e1RM")
                .font(.appCaption.weight(.bold))
                .foregroundColor(Color(white: 0.4))
            E1RMSparkline(series: alert.e1rmSeries, accentColor: alert.severityColor)
                .frame(height: 70)
            let latestE1rm = alert.e1rmSeries.last?.e1rmLbs ?? alert.workingWeightLbs
            HStack {
                Text("Dernier working set")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.45))
                Spacer()
                Text("\(units.format(alert.workingWeightLbs, decimals: 0)) × \(alert.workingReps) reps")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text("→ e1RM \(units.format(latestE1rm, decimals: 0))")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.45))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(white: 0.07))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    private var contextChipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FACTEURS DÉTECTÉS")
                .font(.appCaption.weight(.bold))
                .foregroundColor(Color(white: 0.4))
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ContextChip(
                        icon: "clock",
                        label: "\(alert.plateauWeeks) sem. de stagnation",
                        color: alert.severityColor
                    )
                    if let pss = alert.pssContext {
                        if pss.isHigh || pss.isRising {
                            let pssLabel = pss.isRising ? "Stress ↑" : "Stress élevé"
                            ContextChip(icon: "bolt.heart.fill", label: pssLabel, color: .red)
                        }
                    }
                    if let nut = alert.nutritionContext, nut.deficitFlag {
                        let defText = nut.caloricDeficit.map { "Déficit −\($0) kcal" } ?? "Déficit calorique"
                        ContextChip(icon: "fork.knife", label: defText, color: .yellow)
                    }
                    let scoreLabel = "Score plateau: \(alert.plateauScore)/100"
                    ContextChip(icon: "chart.bar.fill", label: scoreLabel, color: Color(white: 0.5))
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var solutionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LA DÉCISION")
                .font(.appCaption.weight(.bold))
                .foregroundColor(Color(white: 0.4))
            HStack(spacing: 12) {
                Image(systemName: alert.deloadTypeIcon)
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(alert.deloadTypeLabel)
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(.white)
                    if let instruction = alert.deloadPlan?.instruction {
                        Text(instruction)
                            .font(.appLabel)
                            .foregroundColor(Color(white: 0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.2), lineWidth: 1))
        }
        .padding(.horizontal, 20)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if alert.deloadPlan != nil {
                Button(action: { showDeloadPlan = true }) {
                    Label("Voir le plan de deload", systemImage: "arrow.right.circle.fill")
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .cornerRadius(12)
                }
            }
            Button(action: snooze) {
                Text("Ignorer — rappeler dans 7 jours")
                    .font(.appLabel)
                    .foregroundColor(Color(white: 0.4))
            }
            .disabled(isDismissing)
        }
        .padding(.horizontal, 20)
    }

    private func snooze() {
        guard let id = alert.id else { dismiss(); return }
        isDismissing = true
        Task {
            try? await APIService.shared.updatePlateauStatus(id: id, status: "dismissed")
            onStatusChanged()
            dismiss()
        }
    }
}
// ── Deload Plan Sheet ─────────────────────────────────────────────────────────

struct DeloadPlanSheet: View {
    let alert: PlateauAlert
    let plan: DeloadPlan
    let onActivate: () -> Void

    @State private var isActivating = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    planHeader
                    if let exercises = plan.exercises, !exercises.isEmpty {
                        exerciseTable(exercises)
                    }
                    if let nutrition = plan.nutritionPrescription {
                        nutritionCard(nutrition)
                    }
                    if let min = alert.reboundDaysMin, let max = alert.reboundDaysMax {
                        reboundCard(min: min, max: max)
                    }
                    activateButton
                }
                .padding(.bottom, 40)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle(alert.deloadTypeLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Retour") { dismiss() }
                        .foregroundColor(Color(white: 0.6))
                }
            }
        }
    }

    private var planHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: alert.deloadTypeIcon)
                    .font(.system(size: 28))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.deloadTypeLabel)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    let duration = deloadDuration
                    Text(duration)
                        .font(.appLabel)
                        .foregroundColor(Color(white: 0.45))
                }
            }
            Text(plan.instruction)
                .font(.system(size: 14))
                .foregroundColor(Color(white: 0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var deloadDuration: String {
        switch alert.deloadType {
        case "rest":            return "4-5 jours"
        case "light_week":      return "1 semaine"
        case "rep_range":       return "1-2 semaines"
        case "nutrition_first": return "10 jours"
        default:                return "1 semaine"
        }
    }

    private func exerciseTable(_ exercises: [DeloadExercise]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRESCRIPTIONS")
                .font(.appCaption.weight(.bold))
                .foregroundColor(Color(white: 0.4))
            VStack(spacing: 0) {
                ForEach(Array(exercises.enumerated()), id: \.offset) { idx, ex in
                    DeloadExerciseRow(exercise: ex, deloadType: alert.deloadType ?? "light_week")
                    if idx < exercises.count - 1 {
                        Divider().background(Color(white: 0.15)).padding(.horizontal, 16)
                    }
                }
            }
            .background(Color(white: 0.07))
            .cornerRadius(12)
        }
        .padding(.horizontal, 20)
    }

    private func nutritionCard(_ nutrition: NutritionPrescription) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRESCRIPTION NUTRITION")
                .font(.appCaption.weight(.bold))
                .foregroundColor(Color(white: 0.4))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("+\(nutrition.caloricIncreaseKcal) kcal/jour", systemImage: "flame.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.yellow)
                    Spacer()
                    Text("\(nutrition.durationDays) jours")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.45))
                }
                Text(nutrition.proteinTargetNote)
                    .font(.appLabel)
                    .foregroundColor(Color(white: 0.5))
            }
            .padding(14)
            .background(Color.yellow.opacity(0.08))
            .cornerRadius(12)
        }
        .padding(.horizontal, 20)
    }

    private func reboundCard(min: Int, max: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRÉDICTION")
                .font(.appCaption.weight(.bold))
                .foregroundColor(Color(white: 0.4))
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Retour à la progression en \(min)-\(max) jours")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    if let msg = alert.reboundMessage {
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(Color.green.opacity(0.08))
            .cornerRadius(12)
        }
        .padding(.horizontal, 20)
    }

    private var activateButton: some View {
        VStack(spacing: 10) {
            Button(action: activate) {
                HStack(spacing: 8) {
                    if isActivating {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text("Activer le deload")
                        .font(.appBody.weight(.semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.orange)
                .cornerRadius(12)
            }
            .disabled(isActivating)
            .padding(.horizontal, 20)
            Text("Le plan sera actif pour la durée indiquée. Tu peux le compléter après ta semaine de deload.")
                .font(.appCaption)
                .foregroundColor(Color(white: 0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    private func activate() {
        guard let id = alert.id else { onActivate(); dismiss(); return }
        isActivating = true
        Task {
            try? await APIService.shared.updatePlateauStatus(id: id, status: "active")
            onActivate()
            dismiss()
        }
    }
}

// ── Exercise Row ──────────────────────────────────────────────────────────────

private struct DeloadExerciseRow: View {
    let exercise: DeloadExercise
    let deloadType: String
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name)
                .font(.appLabel.weight(.semibold))
                .foregroundColor(.white)

            if deloadType == "rep_range" {
                repRangeOptions
            } else {
                standardRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var standardRow: some View {
        let from = exercise.fromLbs.map { units.format($0, decimals: 0) } ?? "—"
        let to   = exercise.toLbs.map   { units.format($0, decimals: 0) } ?? "—"
        let sets = exercise.sets.map    { "\($0) sets" }     ?? ""
        let reps = exercise.reps.map    { "× \($0) reps" }   ?? ""

        return HStack(spacing: 6) {
            Text(from)
                .font(.appLabel)
                .foregroundColor(Color(white: 0.5))
            Image(systemName: "arrow.right")
                .font(.appCaption)
                .foregroundColor(Color(white: 0.35))
            Text(to)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.orange)
            Spacer()
            Text("\(sets) \(reps)")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.45))
        }
    }

    private var repRangeOptions: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let force = exercise.forceOption {
                let forceText = "\(units.format(force.weightLbs, decimals: 0)) × \(force.reps) reps"
                HStack(spacing: 6) {
                    Text("Option Force:")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.45))
                    Text(forceText)
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.orange)
                }
            }
            if let volume = exercise.volumeOption {
                let volText = "\(units.format(volume.weightLbs, decimals: 0)) × \(volume.reps) reps"
                HStack(spacing: 6) {
                    Text("Option Volume:")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.45))
                    Text(volText)
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.blue.opacity(0.8))
                }
            }
        }
    }
}

// ── e1RM Sparkline ────────────────────────────────────────────────────────────

struct E1RMSparkline: View {
    let series: [E1RMPoint]
    var accentColor: Color = .orange

    var body: some View {
        Canvas { ctx, size in
            guard series.count >= 2 else { return }

            let values = series.map(\.e1rmLbs)
            let minV   = (values.min() ?? 0) * 0.96
            let maxV   = (values.max() ?? 1) * 1.04
            let range  = max(maxV - minV, 1.0)

            func xPos(_ i: Int) -> CGFloat {
                size.width * CGFloat(i) / CGFloat(series.count - 1)
            }
            func yPos(_ v: Double) -> CGFloat {
                size.height * CGFloat(1.0 - (v - minV) / range)
            }

            // Fill area under curve
            var fillPath = Path()
            fillPath.move(to: CGPoint(x: xPos(0), y: size.height))
            fillPath.addLine(to: CGPoint(x: xPos(0), y: yPos(values[0])))
            for i in 1..<values.count {
                fillPath.addLine(to: CGPoint(x: xPos(i), y: yPos(values[i])))
            }
            fillPath.addLine(to: CGPoint(x: xPos(values.count - 1), y: size.height))
            fillPath.closeSubpath()
            ctx.fill(fillPath, with: .color(accentColor.opacity(0.08)))

            // Line
            var linePath = Path()
            linePath.move(to: CGPoint(x: xPos(0), y: yPos(values[0])))
            for i in 1..<values.count {
                linePath.addLine(to: CGPoint(x: xPos(i), y: yPos(values[i])))
            }
            ctx.stroke(linePath, with: .color(accentColor.opacity(0.5)), lineWidth: 1.5)

            // Dots
            for (i, v) in values.enumerated() {
                let cx = xPos(i)
                let cy = yPos(v)
                let r: CGFloat = i == values.count - 1 ? 4 : 2.5
                let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(
                    i == values.count - 1 ? accentColor : accentColor.opacity(0.4)
                ))
            }
        }
    }
}

// ── Context Chip ──────────────────────────────────────────────────────────────

private struct ContextChip: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.appCaption)
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(color.opacity(0.25), lineWidth: 1))
    }
}
