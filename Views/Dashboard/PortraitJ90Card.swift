import SwiftUI

// MARK: - PortraitJ90Card (Dashboard compact)

struct PortraitJ90Card: View {
    let data: PortraitData
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            PortraitDetailSheet(data: data)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            dimensionRows
            footerRow
        }
        .padding(14)
        .glassCard()
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("PORTRAIT J-90")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            if let score = data.transformationScore {
                let scoreColor: Color = score >= 50 ? .forge : Color.trendNegative
                Text("\(score)%")
                    .font(.appLabel.weight(.black))
                    .foregroundColor(scoreColor)
            }
            Image(systemName: "chevron.right")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.22))
        }
    }

    private var dimensionRows: some View {
        let active = data.dimensions.filter { $0.hasBaseline }
        return VStack(spacing: 5) {
            ForEach(active.prefix(5), id: \.name) { dim in
                DimRowCompact(dim: dim)
            }
        }
    }

    private var footerRow: some View {
        Text("\(data.improvingCount)/\(data.totalWithBaseline) dimensions en progression vs il y a \(data.referenceOffsetDays)J")
            .font(.appMicro)
            .foregroundColor(.white.opacity(0.32))
    }
}

// MARK: - Compact dimension row

private struct DimRowCompact: View {
    let dim: PortraitDimension

    private var improving: Bool { dim.improving ?? false }
    private var deltaColor: Color { improving ? .forge : Color.trendNegative }
    private var arrowName: String { improving ? "arrow.up" : "arrow.down" }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: dim.icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.40))
                .frame(width: 14)
            Text(dim.label)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.62))
            Spacer()
            Text(dim.formattedDelta)
                .font(.appCaption.weight(.semibold))
                .foregroundColor(deltaColor)
            Image(systemName: arrowName)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(deltaColor)
        }
    }
}

// MARK: - Detail Sheet

private struct PortraitDetailSheet: View {
    let data: PortraitData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let score = data.transformationScore {
                        TransformationScoreBanner(score: score,
                                                  improving: data.improvingCount,
                                                  total: data.totalWithBaseline)
                    }
                    DimensionDetailTable(dimensions: data.dimensions,
                                        referenceOffset: data.referenceOffsetDays)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Portrait J-90")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Transformation score banner

private struct TransformationScoreBanner: View {
    let score: Int
    let improving: Int
    let total: Int

    private var scoreColor: Color { score >= 50 ? .forge : Color.trendNegative }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SCORE DE TRANSFORMATION")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Text("\(improving)/\(total) dimensions en progression")
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Text("\(score)%")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(scoreColor)
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - Dimension detail table

private struct DimensionDetailTable: View {
    let dimensions: [PortraitDimension]
    let referenceOffset: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DIMENSION")
                    .font(.appMicro.weight(.black)).tracking(1.2)
                    .foregroundColor(.white.opacity(0.30))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("MAINTENANT")
                    .font(.appMicro.weight(.black)).tracking(1.2)
                    .foregroundColor(.white.opacity(0.30))
                    .frame(width: 70, alignment: .trailing)
                Text("J-\(referenceOffset)")
                    .font(.appMicro.weight(.black)).tracking(1.2)
                    .foregroundColor(.white.opacity(0.30))
                    .frame(width: 50, alignment: .trailing)
                Text("DELTA")
                    .font(.appMicro.weight(.black)).tracking(1.2)
                    .foregroundColor(.white.opacity(0.30))
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            ForEach(dimensions.filter { $0.hasBaseline }, id: \.name) { dim in
                DimDetailRow(dim: dim)
            }

            if dimensions.contains(where: { !$0.hasBaseline }) {
                Text("Données insuffisantes pour certaines dimensions (< 90J d'historique)")
                    .font(.appMicro)
                    .foregroundColor(.white.opacity(0.28))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .glassCard()
        .padding(.bottom, 0)
        .clipped()
    }
}

private struct DimDetailRow: View {
    let dim: PortraitDimension

    private var improving: Bool { dim.improving ?? false }
    private var deltaColor: Color { improving ? .forge : Color.trendNegative }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.1f", v)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: dim.icon)
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.42))
                    .frame(width: 16)
                Text(dim.label)
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(fmt(dim.recent))
                .font(.appCaption.weight(.medium))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 70, alignment: .trailing)

            Text(fmt(dim.ref))
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.38))
                .frame(width: 50, alignment: .trailing)

            HStack(spacing: 3) {
                Text(dim.formattedDelta)
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(deltaColor)
                Image(systemName: improving ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(deltaColor)
            }
            .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.03))
    }
}
