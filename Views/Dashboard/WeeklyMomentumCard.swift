import SwiftUI

// MARK: - WeeklyMomentumCard (Dashboard compact)

struct WeeklyMomentumCard: View {
    let data: WeeklyMomentumData
    @State private var showDetail = false

    private var scoreColor: Color { Color(hex: data.scoreColor) }

    var body: some View {
        Button { showDetail = true } label: { cardContent }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetail) {
                WeeklyMomentumDetailSheet(data: data)
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
            Text("MOMENTUM HEBDO")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            if let t = data.trendPct {
                TrendBadge(trendPct: t, icon: data.trendIcon)
            }
            Image(systemName: "chevron.right")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.22))
        }
    }

    private var metricsRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SCORE")
                    .font(.appMicro).tracking(0.8)
                    .foregroundColor(.white.opacity(0.28))
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(data.score.map { "\($0)" } ?? "—")
                        .font(.appCardMetric)
                        .foregroundColor(scoreColor)
                    Text("/100")
                        .font(.appCaption)
                        .foregroundColor(.white.opacity(0.30))
                }
            }
            Spacer()
            if let pillars = data.pillars {
                PillarMiniGrid(pillars: pillars)
            }
        }
    }
}

// MARK: - Sub-views

private struct TrendBadge: View {
    let trendPct: Int
    let icon: String

    private var color: Color {
        if trendPct >= 5  { return Color.trendPositive }
        if trendPct <= -5 { return Color.trendNegative }
        return Color.trendNeutral
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.appMicro.weight(.semibold))
            let sign = trendPct >= 0 ? "+" : ""
            Text("\(sign)\(trendPct)%")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color.opacity(0.85))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct PillarMiniGrid: View {
    let pillars: MomentumPillars

    private var items: [(String, Int, String)] {
        [
            ("figure.strengthtraining.traditional", pillars.training, "Séances"),
            ("moon.zzz.fill",                       pillars.sleep,    "Sommeil"),
            ("fork.knife.circle.fill",              pillars.nutrition, "Nutrition"),
            ("brain.head.profile",                  pillars.stress,   "Stress"),
        ]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.0) { item in
                PillarDot(icon: item.0, score: item.1)
            }
        }
    }
}

private struct PillarDot: View {
    let icon: String
    let score: Int

    private var color: Color {
        if score >= 75 { return Color.trendPositive }
        if score >= 50 { return Color.trendNeutral }
        return Color.trendNegative
    }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.38))
            Text("\(score)")
                .font(.appMicro.weight(.bold))
                .foregroundColor(color)
        }
    }
}

// MARK: - Detail Sheet

private struct WeeklyMomentumDetailSheet: View {
    let data: WeeklyMomentumData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ScoreBanner(data: data)
                    if let pillars = data.pillars {
                        PillarBreakdownCard(pillars: pillars)
                    }
                    if !data.history.isEmpty {
                        HistoryCard(history: data.history, currentScore: data.score)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Momentum Hebdo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.appTextPrimary)
                }
            }
        }
    }
}

private struct ScoreBanner: View {
    let data: WeeklyMomentumData
    private var scoreColor: Color { Color(hex: data.scoreColor) }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CETTE SEMAINE")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                if let prev = data.prevAvg {
                    Text("Moy. 4 sem. : \(prev)/100")
                        .font(.appCaption)
                        .foregroundColor(.white.opacity(0.50))
                }
                Text(data.message)
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.55))
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

private struct PillarBreakdownCard: View {
    let pillars: MomentumPillars

    private var rows: [(String, String, Int, Double)] {
        [
            ("figure.strengthtraining.traditional", "Entraînement", pillars.training, 0.35),
            ("moon.zzz.fill",                       "Sommeil",      pillars.sleep,    0.25),
            ("fork.knife.circle.fill",              "Nutrition",    pillars.nutrition, 0.25),
            ("brain.head.profile",                  "Stress",       pillars.stress,   0.15),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DÉTAIL PAR PILIER")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            ForEach(rows, id: \.1) { row in
                MomentumPillarRow(icon: row.0, label: row.1, score: row.2, weight: row.3)
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct MomentumPillarRow: View {
    let icon: String
    let label: String
    let score: Int
    let weight: Double

    private var color: Color {
        if score >= 75 { return Color.trendPositive }
        if score >= 50 { return Color.trendNeutral }
        return Color.trendNegative
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.38))
                .frame(width: 16)
            Text(label)
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.65))
            Text("×\(Int(weight * 100))%")
                .font(.appMicro)
                .foregroundColor(.white.opacity(0.28))
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(score) / 100)
                }
                .frame(height: 5)
            }
            .frame(width: 80, height: 5)
            Text("\(score)")
                .font(.appCaption.weight(.bold))
                .foregroundColor(color)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

private struct HistoryCard: View {
    let history: [MomentumWeekHistory]
    let currentScore: Int?

    private var maxScore: Int {
        max((history.map(\.score).max() ?? 50), currentScore ?? 50, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HISTORIQUE 4 SEMAINES")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(history.indices, id: \.self) { i in
                    let h = history[i]
                    let barH = maxScore > 0 ? max(8.0, 60.0 * Double(h.score) / Double(maxScore)) : 8.0
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.22))
                            .frame(height: barH)
                        Text("S-\(history.count - i)")
                            .font(.system(size: 7))
                            .foregroundColor(.white.opacity(0.28))
                    }
                    .frame(maxWidth: .infinity)
                }
                if let cur = currentScore {
                    let barH = maxScore > 0 ? max(8.0, 60.0 * Double(cur) / Double(maxScore)) : 8.0
                    let color: Color = {
                        if cur >= 75 { return Color.trendPositive }
                        if cur >= 50 { return Color.trendNeutral }
                        return Color.trendNegative
                    }()
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(height: barH)
                        Text("Cette sem.")
                            .font(.system(size: 7))
                            .foregroundColor(.white.opacity(0.50))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 72, alignment: .bottom)
        }
        .padding(14)
        .glassCard()
    }
}
