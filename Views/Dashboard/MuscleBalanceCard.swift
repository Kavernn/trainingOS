import SwiftUI

// MARK: - MuscleBalanceCard (Dashboard compact)

struct MuscleBalanceCard: View {
    let data: MuscleBalanceData
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: { cardContent }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetail) {
                MuscleBalanceDetailSheet(data: data)
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if let ratios = data.ratios {
                ratioBar(ratios)
            }
            if !data.imbalances.isEmpty {
                imbalanceChips
            }
        }
        .padding(14)
        .glassCard()
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("ÉQUILIBRE MUSCULAIRE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            if let top = data.topCategory {
                TopCatBadge(icon: data.topCategoryIcon, label: data.topCategoryLabel)
            }
            Image(systemName: "chevron.right")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.22))
        }
    }

    private func ratioBar(_ r: MuscleRatios) -> some View {
        let segments: [(Int, Color)] = [
            (r.push,    Color(hex: "FF9500")),
            (r.pull,    Color(hex: "34C759")),
            (r.legs,    Color(hex: "5AC8FA")),
            (r.core,    Color(hex: "BF5AF2")),
            (r.cardio,  Color(hex: "FF6B6B")),
        ]
        let total = segments.reduce(0) { $0 + $1.0 }
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments.indices, id: \.self) { i in
                    let seg = segments[i]
                    if seg.0 > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(seg.1)
                            .frame(width: total > 0 ? geo.size.width * CGFloat(seg.0) / CGFloat(total) : 0)
                    }
                }
            }
        }
        .frame(height: 6)
    }

    private var imbalanceChips: some View {
        HStack(spacing: 6) {
            ForEach(data.imbalances.prefix(2), id: \.key) { imb in
                HStack(spacing: 3) {
                    Image(systemName: imb.icon)
                        .font(.system(size: 8, weight: .semibold))
                    Text(imb.label)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(Color(hex: "FF9500").opacity(0.85))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color(hex: "FF9500").opacity(0.10))
                .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Sub-views

private struct TopCatBadge: View {
    let icon: String
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(Color(hex: "5AC8FA").opacity(0.85))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color(hex: "5AC8FA").opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Detail Sheet

private struct MuscleBalanceDetailSheet: View {
    let data: MuscleBalanceData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let ratios = data.ratios {
                        RatioBreakdownCard(ratios: ratios, totalAnalyzed: data.totalAnalyzed)
                    }
                    if !data.imbalances.isEmpty {
                        ImbalancesCard(imbalances: data.imbalances)
                    }
                    BalanceLegendCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Équilibre Musculaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

private struct RatioBreakdownCard: View {
    let ratios: MuscleRatios
    let totalAnalyzed: Int

    private var rows: [(String, String, Color, Int)] {
        [
            ("arrow.up.circle.fill",   "Push",    Color(hex: "FF9500"), ratios.push),
            ("arrow.down.circle.fill", "Pull",    Color(hex: "34C759"), ratios.pull),
            ("figure.run",             "Jambes",  Color(hex: "5AC8FA"), ratios.legs),
            ("tornado",                "Core",    Color(hex: "BF5AF2"), ratios.core),
            ("heart.fill",             "Cardio",  Color(hex: "FF6B6B"), ratios.cardio),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RÉPARTITION")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                Text("\(totalAnalyzed) exercices analysés")
                    .font(.appMicro)
                    .foregroundColor(.white.opacity(0.28))
            }
            ForEach(rows, id: \.1) { icon, label, color, pct in
                MuscleCatRow(icon: icon, label: label, color: color, pct: pct)
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct MuscleCatRow: View {
    let icon: String
    let label: String
    let color: Color
    let pct: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color.opacity(0.80))
                .frame(width: 16)
            Text(label)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.65))
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.70))
                        .frame(width: geo.size.width * CGFloat(pct) / 100)
                }
                .frame(height: 5)
            }
            .frame(width: 80, height: 5)
            Text("\(pct)%")
                .font(.appCaption.weight(.bold))
                .foregroundColor(color)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct ImbalancesCard: View {
    let imbalances: [MuscleImbalance]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DÉSÉQUILIBRES DÉTECTÉS")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            ForEach(imbalances, id: \.key) { imb in
                HStack(spacing: 10) {
                    Image(systemName: imb.icon)
                        .font(.appLabel)
                        .foregroundColor(Color(hex: "FF9500").opacity(0.80))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(imb.label)
                            .font(.appLabel.weight(.medium))
                            .foregroundColor(.white.opacity(0.75))
                        Text(imb.detail)
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

private struct BalanceLegendCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ÉQUILIBRE IDÉAL")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Un programme équilibré vise un ratio push/pull proche de 1:1, avec au moins 15% de volume legs. Le core et le cardio complètent selon tes objectifs.")
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
