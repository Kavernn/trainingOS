import SwiftUI

// MARK: - RuptureRiskCard (Dashboard compact)

struct RuptureRiskCard: View {
    let data: RuptureRisk
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            RuptureDetailSheet(data: data)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if !data.signals.isEmpty {
                signalChips
            }
            Text(data.message)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }

    private var riskColor: Color { Color(hex: data.riskColorHex) }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.appCaption)
                .foregroundColor(riskColor)
            Text("RISQUE DE RUPTURE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            Text("\(data.score)")
                .font(.appLabel.weight(.black))
                .foregroundColor(riskColor)
            Text("/100")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.30))
            Image(systemName: "chevron.right")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.22))
        }
    }

    private var signalChips: some View {
        HStack(spacing: 6) {
            ForEach(data.signals, id: \.self) { signal in
                HStack(spacing: 4) {
                    Image(systemName: data.signalIcon(signal))
                        .font(.appMicro.weight(.semibold))
                    Text(data.signalLabel(signal))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(riskColor.opacity(0.85))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(riskColor.opacity(0.10))
                .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Detail Sheet

private struct RuptureDetailSheet: View {
    let data: RuptureRisk
    @Environment(\.dismiss) private var dismiss

    private var riskColor: Color { Color(hex: data.riskColorHex) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    RuptureScoreBanner(data: data)

                    if !data.signals.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SIGNAUX ACTIFS")
                                .font(.appMicro.weight(.black)).tracking(1.5)
                                .foregroundColor(.white.opacity(0.35))
                            ForEach(data.signals, id: \.self) { signal in
                                RuptureSignalRow(signal: signal, data: data, color: riskColor)
                            }
                        }
                        .padding(14)
                        .glassCard()
                    }

                    if data.totalEpisodes > 0 {
                        RuptureHistoryCard(data: data)
                    }

                    if let ctx = data.context {
                        RuptureContextCard(ctx: ctx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Risque de Rupture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.appTextPrimary)
                }
            }
        }
    }
}

// MARK: - Score Banner

private struct RuptureScoreBanner: View {
    let data: RuptureRisk

    private var riskColor: Color { Color(hex: data.riskColorHex) }

    private var levelLabel: String {
        switch data.riskLevel {
        case .nominal:   return "Nominal"
        case .vigilance: return "Vigilance"
        case .elevated:  return "Élevé"
        case .critical:  return "Critique"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SCORE DE RISQUE")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Text(levelLabel)
                    .font(.appBody.weight(.bold))
                    .foregroundColor(riskColor)
                Text(data.message)
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("\(data.score)")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(riskColor)
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - Signal Row

private struct RuptureSignalRow: View {
    let signal: String
    let data: RuptureRisk
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: data.signalIcon(signal))
                .font(.appLabel)
                .foregroundColor(color.opacity(0.80))
                .frame(width: 20)
            Text(data.signalLabel(signal))
                .font(.appLabel)
                .foregroundColor(.white.opacity(0.78))
        }
    }
}

// MARK: - History Card

private struct RuptureHistoryCard: View {
    let data: RuptureRisk

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HISTORIQUE DE DÉRAPAGE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(data.totalEpisodes)")
                        .font(.appHeadline.weight(.bold))
                        .foregroundColor(.white.opacity(0.80))
                    Text("épisodes détectés")
                        .font(.appMicro)
                        .foregroundColor(.white.opacity(0.32))
                }
                if data.similarEpisodes > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(data.similarEpisodes)")
                            .font(.appHeadline.weight(.bold))
                            .foregroundColor(Color(hex: data.riskColorHex))
                        Text("similaires au contexte actuel")
                            .font(.appMicro)
                            .foregroundColor(.white.opacity(0.32))
                    }
                }
            }
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - Context Card

private struct RuptureContextCard: View {
    let ctx: RuptureContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTEXTE 7 DERNIERS JOURS")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))

            HStack(spacing: 0) {
                RuptureContextStat(
                    icon: "figure.strengthtraining.traditional",
                    label: "Séances",
                    value: "\(ctx.workoutCount)"
                )
                if let sleep = ctx.avgSleep {
                    Divider().background(Color.white.opacity(0.10)).frame(height: 36)
                    RuptureContextStat(
                        icon: "moon.zzz.fill",
                        label: "Sommeil moy.",
                        value: String(format: "%.1fh", sleep)
                    )
                }
                if let pss = ctx.avgPss {
                    Divider().background(Color.white.opacity(0.10)).frame(height: 36)
                    RuptureContextStat(
                        icon: "brain.head.profile",
                        label: "PSS moy.",
                        value: String(format: "%.0f/40", pss)
                    )
                }
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct RuptureContextStat: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.42))
            Text(value)
                .font(.appLabel.weight(.bold))
                .foregroundColor(.white.opacity(0.80))
            Text(label)
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.30))
        }
        .frame(maxWidth: .infinity)
    }
}
