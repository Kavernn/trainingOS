import SwiftUI

// MARK: - NutritionPerformanceCard (Dashboard compact)

struct NutritionPerformanceCard: View {
    let data: NutritionPerformanceData
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: { cardContent }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetail) {
                NutritionPerformanceDetailSheet(data: data)
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            comparisonRow
            Text(data.message)
                .font(.appCaption)
                .foregroundColor(.appOnSurface.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
        }
        .padding(14)
        .glassCard()
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("NUTRITION × PERFORMANCE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.appOnSurface.opacity(0.35))
            Spacer()
            ImpactBadge(direction: data.impactDirection)
            Image(systemName: "chevron.right")
                .font(.appMicro)
                .foregroundColor(.appOnSurface.opacity(0.22))
        }
    }

    private var comparisonRow: some View {
        HStack(spacing: 0) {
            RPEStatMini(label: "Avec nutrition J-1", rpe: data.avgRpeWith, count: data.countWith)
            RPEStatMini(label: "Sans nutrition J-1", rpe: data.avgRpeWithout, count: data.countWithout)
            if let diff = data.rpeDiff {
                VStack(spacing: 3) {
                    Text("ΔRPE")
                        .font(.appMicro).tracking(0.8)
                        .foregroundColor(.appOnSurface.opacity(0.28))
                    Text(data.formattedRpeDiff)
                        .font(.appLabel.weight(.bold))
                        .foregroundColor(Color(hex: data.impactDirection.colorHex))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Sub-views

private struct ImpactBadge: View {
    let direction: NutritionPerformanceData.ImpactDirection

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: direction.icon)
                .font(.appMicro.weight(.semibold))
            Text(direction.label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(Color(hex: direction.colorHex).opacity(0.85))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color(hex: direction.colorHex).opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct RPEStatMini: View {
    let label: String
    let rpe: Double?
    let count: Int

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.appMicro).tracking(0.5)
                .foregroundColor(.appOnSurface.opacity(0.28))
                .multilineTextAlignment(.center)
            if let r = rpe {
                Text(String(format: "%.1f", r))
                    .font(.appLabel.weight(.bold))
                    .foregroundColor(.appOnSurface.opacity(0.85))
            } else {
                Text("—")
                    .font(.appLabel)
                    .foregroundColor(.appOnSurface.opacity(0.28))
            }
            Text("\(count) séances")
                .font(.appMicro)
                .foregroundColor(.appOnSurface.opacity(0.28))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Detail Sheet

private struct NutritionPerformanceDetailSheet: View {
    let data: NutritionPerformanceData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ImpactBanner(data: data)
                    BreakdownCard(data: data)
                    ExplainerCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Nutrition × Performance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.appTextPrimary)
                }
            }
        }
    }
}

private struct ImpactBanner: View {
    let data: NutritionPerformanceData
    private var color: Color { Color(hex: data.impactDirection.colorHex) }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("IMPACT NUTRITION J-1")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.appOnSurface.opacity(0.35))
                Text(data.message)
                    .font(.appCaption)
                    .foregroundColor(.appOnSurface.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(data.formattedRpeDiff)
                    .font(.appCardMetric)
                    .foregroundColor(color)
                Text("RPE")
                    .font(.appMicro.weight(.black)).tracking(1)
                    .foregroundColor(color.opacity(0.6))
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct BreakdownCard: View {
    let data: NutritionPerformanceData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DÉTAIL PAR CONDITION")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.appOnSurface.opacity(0.35))

            HStack {
                Text("Condition")
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(.appOnSurface.opacity(0.35))
                Spacer()
                Text("RPE moy.")
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(.appOnSurface.opacity(0.35))
                    .frame(width: 65, alignment: .trailing)
                Text("Séances")
                    .font(.appMicro.weight(.semibold))
                    .foregroundColor(.appOnSurface.opacity(0.35))
                    .frame(width: 55, alignment: .trailing)
            }

            DetailRow(label: "Avec nutrition J-1",
                      icon: "checkmark.circle.fill",
                      iconColor: Color.trendPositive,
                      rpe: data.avgRpeWith,
                      count: data.countWith)

            DetailRow(label: "Sans nutrition J-1",
                      icon: "xmark.circle.fill",
                      iconColor: Color.trendNegative,
                      rpe: data.avgRpeWithout,
                      count: data.countWithout)

            Divider().background(Color.appSeparatorStrong)

            HStack {
                Text("Séances analysées")
                    .font(.appCaption)
                    .foregroundColor(.appOnSurface.opacity(0.50))
                Spacer()
                Text("\(data.sessionsAnalyzed)")
                    .font(.appCaption.weight(.bold))
                    .foregroundColor(.appOnSurface.opacity(0.75))
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct DetailRow: View {
    let label: String
    let icon: String
    let iconColor: Color
    let rpe: Double?
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.appCaption)
                .foregroundColor(iconColor.opacity(0.80))
            Text(label)
                .font(.appCaption)
                .foregroundColor(.appOnSurface.opacity(0.65))
            Spacer()
            Text(rpe.map { String(format: "%.1f", $0) } ?? "—")
                .font(.appCaption.weight(.bold))
                .foregroundColor(.appOnSurface.opacity(0.85))
                .frame(width: 65, alignment: .trailing)
            Text("\(count)")
                .font(.appCaption)
                .foregroundColor(.appOnSurface.opacity(0.38))
                .frame(width: 55, alignment: .trailing)
        }
    }
}

private struct ExplainerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT ÇA FONCTIONNE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.appOnSurface.opacity(0.35))
            Text("On compare ton RPE moyen les jours où tu avais logué ta nutrition la veille, versus les jours sans. Plus l'écart est élevé, plus la nutrition impacte tes performances.")
                .font(.appCaption)
                .foregroundColor(.appOnSurface.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
