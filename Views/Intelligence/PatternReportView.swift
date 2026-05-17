import SwiftUI

struct PatternReportView: View {
    @ObservedObject var vm: WarRoomViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if vm.patterns == nil {
                    ProgressView().tint(Color.forge).padding(.top, 60)
                } else if let p = vm.patterns {
                    if !p.enoughData {
                        insufficientDataView(p.totalTriggers)
                    } else {
                        insightsList(p)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.appBg)
        .task { await vm.loadPatterns() }
    }

    private func insufficientDataView(_ count: Int) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 36))
                .foregroundStyle(Color.secondary)
            Text("Données insuffisantes.")
                .font(.system(size: 15, weight: .semibold))
            Text("Il faut au moins 3 entrées dans les 90 derniers jours.\n\(count) enregistrée(s) pour l'instant.")
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func insightsList(_ p: WarRoomPatterns) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("PATTERNS — \(p.totalTriggers) entrées")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .tracking(2)
                Spacer()
            }

            ForEach(p.insights) { insight in
                insightCard(insight)
            }
        }
    }

    private func insightCard(_ insight: WarRoomInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconFor(insight.type))
                    .foregroundStyle(Color.forge)
                    .font(.system(size: 14))
                Text(insight.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.forge)
                    .tracking(2)
            }

            Text(insight.body)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary)

            if let detail = insight.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.forge.opacity(0.12), lineWidth: 1)
        )
    }

    private func iconFor(_ type: String) -> String {
        switch type {
        case "context_dominant":    return "chart.pie.fill"
        case "workout_correlation": return "figure.strengthtraining.traditional"
        case "pss_correlation":     return "brain.head.profile"
        case "time_pattern":        return "clock.fill"
        case "intensity":           return "flame.fill"
        default:                    return "waveform.path.ecg"
        }
    }
}
