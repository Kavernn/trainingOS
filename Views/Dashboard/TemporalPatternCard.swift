import SwiftUI

// MARK: - SessionProgressionCard (Dashboard compact)

struct SessionProgressionCard: View {
    let data: SessionProgressionData
    @State private var showDetail = false

    private var topSessions: [SessionProgressionEntry] {
        Array(data.sessions.prefix(3))
    }

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("PROGRESSION PAR SÉANCE")
                        .font(.appMicro.weight(.black)).tracking(1.5)
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appMicro)
                        .foregroundColor(.white.opacity(0.22))
                }

                VStack(spacing: 6) {
                    ForEach(topSessions, id: \.sessionName) { entry in
                        SessionProgressionRow(entry: entry, compact: true)
                    }
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            SessionProgressionDetailSheet(data: data)
        }
    }
}

// MARK: - Compact row

private struct SessionProgressionRow: View {
    let entry: SessionProgressionEntry
    let compact: Bool

    private var trendColor: Color {
        switch entry.trend {
        case "up":   return Color.trendPositive
        case "down": return Color.trendNegative
        default:     return .white.opacity(0.38)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.trendIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(trendColor)
                .frame(width: 14)

            Text(entry.sessionName)
                .font(.appLabel.weight(.medium))
                .foregroundColor(.white.opacity(0.80))
                .lineLimit(1)

            Spacer()

            if let delta = entry.volumeDeltaPct {
                let sign = delta >= 0 ? "+" : ""
                Text("\(sign)\(Int(delta))% vol")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(trendColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(trendColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(entry.relativeDate)
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.28))
        }
    }
}

// MARK: - Detail Sheet

private struct SessionProgressionDetailSheet: View {
    let data: SessionProgressionData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    SessionProgressionExplainer()

                    ForEach(data.sessions, id: \.sessionName) { entry in
                        SessionProgressionDetailCard(entry: entry)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Progression par Séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Detail Card (per session type)

private struct SessionProgressionDetailCard: View {
    let entry: SessionProgressionEntry

    private var trendColor: Color {
        switch entry.trend {
        case "up":   return Color.trendPositive
        case "down": return Color.trendNegative
        default:     return Color.forge
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.sessionName)
                    .font(.appLabel.weight(.bold))
                    .foregroundColor(.white.opacity(0.88))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: entry.trendIcon)
                        .font(.system(size: 10, weight: .black))
                    Text(entry.trend == "up" ? "Progression" : entry.trend == "down" ? "Régression" : "Stable")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(trendColor)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(trendColor.opacity(0.12))
                .clipShape(Capsule())
            }

            Text(entry.relativeDate)
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.30))

            Divider().background(Color.white.opacity(0.08))

            HStack(spacing: 0) {
                MetricBlock(
                    label: "Volume",
                    value: entry.lastVolume.map { "\(Int($0)) kg" } ?? "—",
                    baseline: entry.baselineVolume.map { "moy. \(Int($0)) kg" },
                    delta: entry.volumeDeltaPct
                )
                MetricBlock(
                    label: "Durée",
                    value: entry.lastDuration.map { "\($0) min" } ?? "—",
                    baseline: entry.baselineDuration.map { "moy. \(Int($0)) min" },
                    delta: entry.durationDeltaPct
                )
                MetricBlock(
                    label: "RPE",
                    value: entry.lastRpe.map { "\(String(format: "%.1f", $0))/10" } ?? "—",
                    baseline: nil,
                    delta: nil
                )
            }

            Text("\(entry.occurrences) occurrences analysées")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.22))
        }
        .padding(14)
        .glassCard()
    }
}

private struct MetricBlock: View {
    let label: String
    let value: String
    let baseline: String?
    let delta: Double?

    private var deltaColor: Color {
        guard let d = delta else { return .white.opacity(0.38) }
        return d > 0 ? Color.trendPositive : (d < 0 ? Color.trendNegative : .white.opacity(0.38))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.30))
            Text(value)
                .font(.appLabel.weight(.semibold))
                .foregroundColor(.white.opacity(0.85))
            if let b = baseline {
                Text(b)
                    .font(.appMicro)
                    .foregroundColor(.white.opacity(0.28))
            }
            if let d = delta {
                let sign = d >= 0 ? "+" : ""
                Text("\(sign)\(Int(d))%")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(deltaColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SessionProgressionExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Chaque séance est comparée à ses 4 occurrences précédentes du même type. Le volume (kg×reps total) et la durée sont les métriques de base. La tendance est haussière si le dernier volume dépasse la moyenne de +5% ou plus.")
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.50))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
