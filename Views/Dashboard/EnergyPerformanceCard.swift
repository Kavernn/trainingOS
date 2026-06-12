import SwiftUI

// MARK: - EnergyPerformanceCard

struct EnergyPerformanceCard: View {
    let data: EnergyPerformanceData
    @State private var showDetail = false

    private var bestLabel: String {
        switch data.bestEnergy {
        case "low":    return "Bas"
        case "medium": return "Moyen"
        case "high":   return "Élevé"
        default:       return "—"
        }
    }

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("ÉNERGIE × PERFORMANCE")
                        .font(.appMicro.weight(.black)).tracking(1.5)
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    if data.hasData {
                        Text("Meilleur: \(bestLabel)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.trendPositive.opacity(0.85))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.trendPositive.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.appMicro).foregroundColor(.white.opacity(0.22))
                }

                if data.hasData {
                    EnergyBucketBars(buckets: data.buckets, best: data.bestEnergy)
                } else {
                    Text("Pas assez de données")
                        .font(.appCaption).foregroundColor(.white.opacity(0.35))
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            EnergyPerformanceDetailSheet(data: data)
        }
    }
}

// MARK: - Bucket bars

private struct EnergyBucketBars: View {
    let buckets: [EnergyBucket]
    let best: String?

    private var maxRpe: Double { buckets.compactMap(\.avgRpe).max() ?? 10 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(buckets, id: \.bucket) { b in
                let isBest = b.bucket == best
                let rpe    = b.avgRpe ?? 0
                let h      = maxRpe > 0 ? max(4.0, 36.0 * rpe / maxRpe) : 4.0
                VStack(spacing: 4) {
                    if let rpe = b.avgRpe {
                        Text(String(format: "%.1f", rpe))
                            .font(.appMicro.weight(.semibold))
                            .foregroundColor(isBest ? .white.opacity(0.80) : .white.opacity(0.35))
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isBest ? Color.trendPositive : Color.white.opacity(0.20))
                        .frame(height: h)
                    Text(b.bucket == "low" ? "Bas" : b.bucket == "medium" ? "Moyen" : "Élevé")
                        .font(.system(size: 8))
                        .foregroundColor(isBest ? .white.opacity(0.55) : .white.opacity(0.25))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 60, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct EnergyPerformanceDetailSheet: View {
    let data: EnergyPerformanceData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    EnergyPerfBanner(data: data)
                    EnergyPerfDetailChart(data: data)
                    EnergyPerfExplainerCard(analyzed: data.sessionsAnalyzed)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Énergie × Performance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.appTextPrimary)
                }
            }
        }
    }
}

private struct EnergyPerfBanner: View {
    let data: EnergyPerformanceData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ÉNERGIE PRÉ-SÉANCE VS RPE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text(data.message)
                .font(.appCaption).foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            if let diff = data.rpeDiff {
                Text("Écart Élevé vs Bas : \(String(format: "%.1f", diff)) RPE")
                    .font(.appCaption).foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct EnergyPerfDetailChart: View {
    let data: EnergyPerformanceData

    private var maxRpe: Double { data.buckets.compactMap(\.avgRpe).max() ?? 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RPE MOYEN PAR NIVEAU D'ÉNERGIE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(data.buckets, id: \.bucket) { b in
                    let isBest = b.bucket == data.bestEnergy
                    let rpe    = b.avgRpe ?? 0
                    let h      = maxRpe > 0 ? max(12.0, 72.0 * rpe / maxRpe) : 12.0
                    VStack(spacing: 5) {
                        if let rpe = b.avgRpe {
                            Text(String(format: "%.1f", rpe))
                                .font(.appCaption.weight(.semibold))
                                .foregroundColor(isBest ? .white.opacity(0.85) : .white.opacity(0.40))
                        } else {
                            Text("—").font(.appCaption).foregroundColor(.white.opacity(0.25))
                        }
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isBest ? Color.trendPositive : Color.white.opacity(0.20))
                            .frame(height: h)
                        Text(b.label)
                            .font(.appMicro.weight(.medium))
                            .foregroundColor(isBest ? .white.opacity(0.65) : .white.opacity(0.30))
                            .multilineTextAlignment(.center)
                        Text("\(b.count) séances")
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.22))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120, alignment: .bottom)
        }
        .padding(14)
        .glassCard()
    }
}

private struct EnergyPerfExplainerCard: View {
    let analyzed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Les séances sont groupées par niveau d'énergie pré-séance (1–3, 4–6, 7–10). Le RPE moyen de chaque groupe révèle si ton niveau d'énergie influence ton effort perçu. \(analyzed) séances analysées.")
                .font(.appCaption).foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
