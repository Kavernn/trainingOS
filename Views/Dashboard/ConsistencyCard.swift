import SwiftUI

// MARK: - ConsistencyCard (Dashboard compact)

struct ConsistencyCard: View {
    let data: ConsistencyData
    @State private var showDetail = false

    private var scoreColor: Color { Color(hex: data.scoreColor) }

    var body: some View {
        Button { showDetail = true } label: { cardContent }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetail) {
                ConsistencyDetailSheet(data: data)
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            metricsRow
        }
        .padding(14)
        .glassCard()
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("CONSISTANCE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.appOnSurface.opacity(0.35))
            Spacer()
            ConsistencyTrendBadge(trend: data.trend, icon: data.trendIcon, colorHex: data.trendColor)
            Image(systemName: "chevron.right")
                .font(.appMicro)
                .foregroundColor(.appOnSurface.opacity(0.22))
        }
    }

    private var metricsRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RÉGULARITÉ")
                    .font(.appMicro).tracking(0.8)
                    .foregroundColor(.appOnSurface.opacity(0.28))
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(data.score.map { "\($0)" } ?? "—")
                        .font(.appCardMetric)
                        .foregroundColor(scoreColor)
                    Text("/100")
                        .font(.appCaption)
                        .foregroundColor(.appOnSurface.opacity(0.30))
                }
            }
            Spacer()
            ConsistencySparkline(counts: data.weeklyCounts)
        }
    }
}

// MARK: - Sub-views

private struct ConsistencyTrendBadge: View {
    let trend: String
    let icon: String
    let colorHex: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.appMicro.weight(.semibold))
            Text(trend == "improving" ? "En hausse" : trend == "declining" ? "En baisse" : "Stable")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(Color(hex: colorHex).opacity(0.85))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color(hex: colorHex).opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct ConsistencySparkline: View {
    let counts: [WeeklyCount]

    private var maxCount: Int { counts.map(\.count).max() ?? 1 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(counts.indices, id: \.self) { i in
                let c = counts[i].count
                let isLast = i == counts.count - 1
                let h = maxCount > 0 ? max(4.0, 36.0 * Double(c) / Double(maxCount)) : 4.0
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLast ? Color.trendPositive : Color.appOnSurface.opacity(0.20))
                    .frame(width: 8, height: h)
            }
        }
        .frame(height: 40, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct ConsistencyDetailSheet: View {
    let data: ConsistencyData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ConsistencyScoreBanner(data: data)
                    ConsistencyWeeklyCard(counts: data.weeklyCounts)
                    ConsistencyExplainerCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Consistance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.appTextPrimary)
                }
            }
        }
    }
}

private struct ConsistencyScoreBanner: View {
    let data: ConsistencyData
    private var scoreColor: Color { Color(hex: data.scoreColor) }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SCORE DE RÉGULARITÉ")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.appOnSurface.opacity(0.35))
                if let avg = data.avgSessionsPerWeek {
                    Text("Moy. \(String(format: "%.1f", avg)) séances/semaine")
                        .font(.appCaption)
                        .foregroundColor(.appOnSurface.opacity(0.50))
                }
                Text(data.message)
                    .font(.appCaption)
                    .foregroundColor(.appOnSurface.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(data.score.map { "\($0)" } ?? "—")
                .font(.appCardHero)
                .foregroundColor(scoreColor)
        }
        .padding(14)
        .glassCard()
    }
}

private struct ConsistencyWeeklyCard: View {
    let counts: [WeeklyCount]

    private var maxCount: Int { counts.map(\.count).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("8 DERNIÈRES SEMAINES")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.appOnSurface.opacity(0.35))

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(counts.indices, id: \.self) { i in
                    let w = counts[i]
                    let isLast = i == counts.count - 1
                    let h = maxCount > 0 ? max(8.0, 60.0 * Double(w.count) / Double(maxCount)) : 8.0
                    VStack(spacing: 4) {
                        Text("\(w.count)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(isLast ? .appOnSurface.opacity(0.65) : .appOnSurface.opacity(0.28))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isLast ? Color.trendPositive : Color.appOnSurface.opacity(0.20))
                            .frame(height: h)
                        Text("S\(i + 1)")
                            .font(.system(size: 7))
                            .foregroundColor(isLast ? .appOnSurface.opacity(0.50) : .appOnSurface.opacity(0.22))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 84, alignment: .bottom)
        }
        .padding(14)
        .glassCard()
    }
}

private struct ConsistencyExplainerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.appOnSurface.opacity(0.35))
            Text("Le score mesure l'écart-type de tes séances sur 8 semaines. Plus tu t'entraînes le même nombre de fois chaque semaine, plus ton score est élevé — indépendamment du streak.")
                .font(.appCaption)
                .foregroundColor(.appOnSurface.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
