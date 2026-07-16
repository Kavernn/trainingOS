import SwiftUI

// Placeholders partagés — les 4 cartes affichent loading/empty/error dans le même style.
// Le try? silencieux des appels URLSession directs (crime L1266-1291 IntelligenceView)
// a été remplacé par un état explicite : jamais indistinguable d'une absence de données.

private struct AnalyticsPlaceholder: View {
    enum Kind { case loading, empty, error }
    let kind: Kind
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.system(size: 14))
            Text(message)
                .font(.appCaption)
                .foregroundColor(Color.appOnSurface.opacity(0.7))
            Spacer()
        }
        .padding(10)
        .background(bgColor)
        .cornerRadius(8)
    }

    private var iconName: String {
        switch kind {
        case .loading: return "hourglass"
        case .empty:   return "tray"
        case .error:   return "exclamationmark.triangle"
        }
    }
    private var iconColor: Color {
        switch kind {
        case .loading: return .gray
        case .empty:   return .gray
        case .error:   return .statusRed
        }
    }
    private var bgColor: Color {
        switch kind {
        case .error: return Color.statusRed.opacity(0.08)
        default:     return Color.appSurfaceInset
        }
    }
}

// MARK: - Overtraining Risk Card

struct OvertrainingRiskCard: View {
    let risk: OvertrainingRisk?
    let error: String?

    private var riskColor: Color {
        switch risk?.level {
        case "high":     return .statusRed
        case "moderate": return .statusOrange
        default:         return .statusGreen
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(riskColor)
                Text("RISQUE SURMENAGE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let risk = risk, !risk.isInsufficient, error == nil {
                    Text(risk.level.uppercased())
                        .font(.appCaption.weight(.black))
                        .foregroundColor(riskColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(riskColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if let error = error {
                AnalyticsPlaceholder(kind: .error, message: error)
            } else if let risk = risk {
                if risk.isInsufficient {
                    AnalyticsPlaceholder(kind: .empty, message: "Pas assez de données pour évaluer aujourd'hui.")
                } else {
                    loadedBody(risk)
                }
            } else {
                AnalyticsPlaceholder(kind: .loading, message: "Chargement…")
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    @ViewBuilder
    private func loadedBody(_ risk: OvertrainingRisk) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.appSurfaceInset).frame(height: 6)
                RoundedRectangle(cornerRadius: 3).fill(riskColor)
                    .frame(width: geo.size.width * CGFloat(min(risk.riskScore, 6)) / 6, height: 6)
            }
        }
        .frame(height: 6)

        if !risk.flags.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(risk.flags, id: \.self) { flag in
                    HStack(spacing: 6) {
                        Circle().fill(riskColor).frame(width: 5, height: 5)
                        Text(flag).font(.system(size: 12)).foregroundColor(Color.appOnSurface.opacity(0.8))
                    }
                }
            }
        }

        Text(risk.recommendation)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(riskColor.opacity(0.9))
            .padding(8)
            .background(riskColor.opacity(0.08))
            .cornerRadius(8)
    }
}

// MARK: - Mesocycle Status Card

struct MesocycleStatusCard: View {
    let status: MesocycleStatus?
    let error: String?

    private var phaseColor: Color {
        switch status?.phase {
        case "accumulation":    return .statusBlue
        case "intensification": return .statusOrange
        case "realization":     return .statusRed
        default:                return .gray
        }
    }

    private var reasonMessage: String {
        // Backend contract : phase == nil garantit reason présent (no_cycle_start | error).
        switch status?.reason {
        case "no_cycle_start": return "Aucun cycle démarré — commence un programme pour activer la phase."
        case "error":          return "Erreur de calcul du cycle — réessaie plus tard."
        default:               return "Aucun cycle actif."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(status?.icon ?? "🌀")
                Text("MÉSOCYCLE")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let label = status?.phaseLabel, error == nil {
                    Text(label.uppercased())
                        .font(.appCaption.weight(.black))
                        .foregroundColor(phaseColor)
                }
            }

            if let error = error {
                AnalyticsPlaceholder(kind: .error, message: error)
            } else if let status = status {
                if status.hasCycle {
                    loadedBody(status)
                } else {
                    AnalyticsPlaceholder(kind: .empty, message: reasonMessage)
                }
            } else {
                AnalyticsPlaceholder(kind: .loading, message: "Chargement…")
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    @ViewBuilder
    private func loadedBody(_ status: MesocycleStatus) -> some View {
        if let description = status.description {
            Text(description)
                .font(.appLabel).foregroundColor(Color.appOnSurface.opacity(0.85))
        }

        HStack(spacing: 16) {
            if let rpe = status.rpeTarget {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RPE CIBLE").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                    Text(rpe).font(.system(size: 14, weight: .black)).foregroundColor(phaseColor)
                }
            }
            if let wk = status.weekInCycle {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SEMAINE CYCLE").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                    Text("S\(wk + 1) / 8").font(.system(size: 14, weight: .black)).foregroundColor(.appTextPrimary)
                }
            }
            if let next = status.nextDeloadInWeeks {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DÉCHARGE DANS").font(.appMicro.weight(.bold)).tracking(1).foregroundColor(.gray)
                    Text("\(next) sem").font(.system(size: 14, weight: .black)).foregroundColor(.statusCyan)
                }
            }
            Spacer()
        }

        if let guidance = status.volGuidance {
            Text(guidance)
                .font(.appCaption).foregroundColor(.gray)
        }
    }
}

// MARK: - Pain Journal Card

struct PainJournalCard: View {
    let data: PainJournalResponse?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bandage.fill").foregroundColor(.statusRed)
                Text("JOURNAL BLESSURES")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
                Spacer()
                if let data = data, error == nil, !data.byExercise.isEmpty {
                    Text("\(data.byExercise.count) exercices")
                        .font(.appCaption).foregroundColor(.gray)
                }
            }

            if let error = error {
                AnalyticsPlaceholder(kind: .error, message: error)
            } else if let data = data {
                if data.byExercise.isEmpty {
                    AnalyticsPlaceholder(kind: .empty, message: "Aucune zone de douleur signalée.")
                } else {
                    loadedBody(data)
                }
            } else {
                AnalyticsPlaceholder(kind: .loading, message: "Chargement…")
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
    }

    @ViewBuilder
    private func loadedBody(_ data: PainJournalResponse) -> some View {
        ForEach(data.byExercise.prefix(5)) { ex in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.exercise)
                        .font(.appLabel.weight(.semibold)).foregroundColor(.appTextPrimary)
                    Text(ex.zones.joined(separator: " · "))
                        .font(.appCaption).foregroundColor(Color.statusRed.opacity(0.8))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(ex.count)×")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(Color.forge)
                    if let d = ex.lastDate {
                        Text(String(d.prefix(10)))
                            .font(.system(size: 10)).foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color.statusRed.opacity(0.05))
            .cornerRadius(8)
        }
    }
}

// MARK: - 1RM Programming Card

struct OneRMProgrammingCard: View {
    let data: OneRMResponse?
    let error: String?
    @State private var selected: String? = nil
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "percent").foregroundColor(.statusPurple)
                Text("PROGRAMMATION % 1RM")
                    .font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.gray)
            }

            if let error = error {
                AnalyticsPlaceholder(kind: .error, message: error)
            } else if let data = data {
                if data.exercises.isEmpty {
                    AnalyticsPlaceholder(kind: .empty, message: "Pas encore de compound tracké avec assez d'historique.")
                } else {
                    loadedBody(data)
                }
            } else {
                AnalyticsPlaceholder(kind: .loading, message: "Chargement…")
            }
        }
        .padding(14)
        .background(Color.appCard)
        .cornerRadius(14)
        .animation(.easeInOut(duration: 0.2), value: selected)
    }

    @ViewBuilder
    private func loadedBody(_ data: OneRMResponse) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(data.exercises) { ex in
                    Button {
                        withAnimation { selected = selected == ex.exercise ? nil : ex.exercise }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ex.exercise)
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.appTextPrimary)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text("1RM \(units.format(ex.estimated1rm, decimals: 0))")
                                    .font(.system(size: 10)).foregroundColor(.statusPurple)
                                if let pct = ex.pctOf1rm {
                                    Text(String(format: "· %.0f%%", pct))
                                        .font(.system(size: 10)).foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(10)
                        .background(selected == ex.exercise ? Color.statusPurple.opacity(0.15) : Color.appSurfaceInset)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected == ex.exercise ? Color.statusPurple.opacity(0.4) : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }

        if let selEx = data.exercises.first(where: { $0.exercise == selected }) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(selEx.table) { entry in
                    VStack(spacing: 2) {
                        Text("\(entry.pct)%")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(.statusPurple)
                        Text(units.format(entry.weight, decimals: 0))
                            .font(.appLabel.weight(.black)).foregroundColor(.appTextPrimary)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.statusPurple.opacity(0.07))
                    .cornerRadius(8)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}
