import SwiftUI

// MARK: - PerformanceConditionsCard (Dashboard compact)

struct PerformanceConditionsCard: View {
    let data: PerformanceConditionsData
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            PerformanceConditionsDetailSheet(data: data)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            conditionRows
            Text(data.message)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.50))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
        }
        .padding(14)
        .glassCard()
    }

    private var scoreColor: Color {
        guard let s = data.alignmentScore else { return .white.opacity(0.35) }
        if s >= 80 { return .forge }
        if s >= 50 { return Color.trendNeutral }
        return Color.trendNegative
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("RECETTE DU SUCCÈS")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            if let score = data.alignmentScore {
                Text("\(score)%")
                    .font(.appLabel.weight(.black))
                    .foregroundColor(scoreColor)
            }
            Image(systemName: "chevron.right")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.22))
        }
    }

    private var conditionRows: some View {
        VStack(spacing: 5) {
            ForEach(data.conditions.prefix(4), id: \.key) { cond in
                ConditionRowCompact(condition: cond)
            }
        }
    }
}

// MARK: - Compact condition row

private struct ConditionRowCompact: View {
    let condition: PerformanceCondition

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: condition.matchToday ? "checkmark.circle.fill" : "circle")
                .font(.appLabel)
                .foregroundColor(condition.matchToday ? .forge : .white.opacity(0.22))

            Image(systemName: condition.icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.38))
                .frame(width: 14)

            Text(condition.label)
                .font(.appCaption)
                .foregroundColor(condition.matchToday ? .white.opacity(0.80) : .white.opacity(0.42))
                .lineLimit(1)

            Spacer()

            Text("\(condition.frequency)%")
                .font(.appMicro.weight(.semibold))
                .foregroundColor(.white.opacity(0.28))
        }
    }
}

// MARK: - Detail Sheet

private struct PerformanceConditionsDetailSheet: View {
    let data: PerformanceConditionsData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    AlignmentScoreBanner(data: data)
                    ConditionsFullList(data: data)
                    HowItWorksCard(topN: data.total)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Recette du Succès")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Alignment Score Banner

private struct AlignmentScoreBanner: View {
    let data: PerformanceConditionsData

    private var scoreColor: Color {
        guard let s = data.alignmentScore else { return .white.opacity(0.40) }
        if s >= 80 { return .forge }
        if s >= 50 { return Color.trendNeutral }
        return Color.trendNegative
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ALIGNEMENT AUJOURD'HUI")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Text("\(data.matched)/\(data.total) conditions réunies")
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(.white.opacity(0.80))
                Text(data.message)
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.50))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let score = data.alignmentScore {
                Text("\(score)%")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(scoreColor)
            }
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - Full Conditions List

private struct ConditionsFullList: View {
    let data: PerformanceConditionsData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONDITIONS IDENTIFIÉES")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))

            ForEach(data.conditions, id: \.key) { cond in
                ConditionDetailRow(condition: cond)
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct ConditionDetailRow: View {
    let condition: PerformanceCondition

    private var matchColor: Color { condition.matchToday ? .forge : .white.opacity(0.28) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: condition.matchToday ? "checkmark.circle.fill" : "circle")
                .font(.appLabel)
                .foregroundColor(matchColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(condition.label)
                    .font(.appLabel.weight(.medium))
                    .foregroundColor(condition.matchToday ? .white.opacity(0.88) : .white.opacity(0.50))
                Text("Présente dans \(condition.frequency)% de tes meilleures séances")
                    .font(.appMicro)
                    .foregroundColor(.white.opacity(0.30))
            }

            Spacer()

            Image(systemName: condition.icon)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.28))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - How It Works Card

private struct HowItWorksCard: View {
    let topN: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Basé sur le contexte des 20% de tes séances les plus intenses (RPE le plus élevé). Les conditions présentes dans ≥55% de ces séances forment ta recette personnelle.")
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
