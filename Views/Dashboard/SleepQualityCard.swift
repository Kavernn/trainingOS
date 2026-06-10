import SwiftUI

// MARK: - SleepQualityCard

struct SleepQualityCard: View {
    let data: SleepQualityData
    @State private var showDetail = false

    private var scoreColor: Color {
        guard let s = data.currentScore else { return .gray }
        if s >= 75 { return Color.trendPositive }
        if s >= 50 { return Color.trendNeutral }
        return Color.trendNegative
    }

    private var trendIcon: String {
        switch data.trend {
        case "improving": return "arrow.up.right"
        case "declining": return "arrow.down.right"
        default:          return "arrow.right"
        }
    }

    private var trendColor: Color {
        switch data.trend {
        case "improving": return Color.trendPositive
        case "declining": return Color.trendNegative
        default:          return Color.trendNeutral
        }
    }

    private var trendLabel: String {
        switch data.trend {
        case "improving": return "En hausse"
        case "declining": return "En baisse"
        default:          return "Stable"
        }
    }

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("QUALITÉ SOMMEIL")
                        .font(.appMicro.weight(.black)).tracking(1.5)
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: trendIcon).font(.appMicro.weight(.semibold))
                        Text(trendLabel).font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(trendColor.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(trendColor.opacity(0.12))
                    .clipShape(Capsule())
                    Image(systemName: "chevron.right")
                        .font(.appMicro).foregroundColor(.white.opacity(0.22))
                }

                HStack(alignment: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SCORE NUIT ACTUELLE")
                            .font(.appMicro).tracking(0.8)
                            .foregroundColor(.white.opacity(0.28))
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(data.currentScore.map { "\(Int($0))" } ?? "—")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(scoreColor)
                            Text("/100")
                                .font(.appCaption).foregroundColor(.white.opacity(0.30))
                        }
                    }
                    Spacer()
                    SleepQualitySparkline(weeks: data.weeklyScores)
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            SleepQualityDetailSheet(data: data)
        }
    }
}

private struct SleepQualitySparkline: View {
    let weeks: [WeeklySleepScore]
    private var maxVal: Double { weeks.compactMap(\.score).max() ?? 100 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(weeks.indices, id: \.self) { i in
                let isLast = i == weeks.count - 1
                let v = weeks[i].score ?? 0
                let h = maxVal > 0 ? max(4.0, 36.0 * v / maxVal) : 4.0
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLast ? Color.trendPositive : Color.white.opacity(0.20))
                    .frame(width: 6, height: h)
            }
        }
        .frame(height: 40, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct SleepQualityDetailSheet: View {
    let data: SleepQualityData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SleepQualityBanner(data: data)
                    SleepQualityWeekChart(weeks: data.weeklyScores)
                    SleepQualityExplainerCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Qualité du Sommeil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

private struct SleepQualityBanner: View {
    let data: SleepQualityData

    private var scoreColor: Color {
        guard let s = data.avgScore else { return .gray }
        if s >= 75 { return Color.trendPositive }
        if s >= 50 { return Color.trendNeutral }
        return Color.trendNegative
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SCORE QUALITÉ SOMMEIL")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Text(data.message)
                    .font(.appCaption).foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(data.avgScore.map { "\(Int($0))" } ?? "—")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(scoreColor)
        }
        .padding(14)
        .glassCard()
    }
}

private struct SleepQualityWeekChart: View {
    let weeks: [WeeklySleepScore]
    private var maxVal: Double { weeks.compactMap(\.score).max() ?? 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("8 DERNIÈRES SEMAINES")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(weeks.indices, id: \.self) { i in
                    let w = weeks[i]
                    let isLast = i == weeks.count - 1
                    let v = w.score ?? 0
                    let h = maxVal > 0 ? max(8.0, 60.0 * v / maxVal) : 8.0
                    VStack(spacing: 4) {
                        Text(w.score.map { "\(Int($0))" } ?? "—")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(isLast ? .white.opacity(0.65) : .white.opacity(0.28))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isLast ? Color.trendPositive : Color.white.opacity(0.20))
                            .frame(height: h)
                        Text("S\(i + 1)")
                            .font(.system(size: 7))
                            .foregroundColor(isLast ? .white.opacity(0.50) : .white.opacity(0.22))
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

private struct SleepQualityExplainerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Score composite : durée (50 %, pénalité hors 7–9 h) + qualité auto-évaluée (50 %, échelle 1–10 × 10). Agrégé par semaine sur 8 semaines.")
                .font(.appCaption).foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
