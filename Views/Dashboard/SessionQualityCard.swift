import SwiftUI

// MARK: - SessionQualityCard

struct SessionQualityCard: View {
    let data: SessionQualityData
    @State private var showDetail = false

    private var trendColor: Color {
        switch data.trend {
        case "improving": return .trendPositive
        case "declining": return .trendNegative
        default:          return .trendNeutral
        }
    }

    private var trendIcon: String {
        switch data.trend {
        case "improving": return "arrow.up.right"
        case "declining": return "arrow.down.right"
        default:          return "arrow.right"
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
                    Text("QUALITÉ SÉANCES")
                        .font(.appMicro.weight(.black)).tracking(1.5)
                        .foregroundColor(.white.opacity(0.35))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: trendIcon).font(.system(size: 9, weight: .semibold))
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
                        Text("MOY. QUALITÉ")
                            .font(.appMicro).tracking(0.8)
                            .foregroundColor(.white.opacity(0.28))
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(data.avgQuality.map { "\(Int($0))" } ?? "—")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(trendColor)
                            Text("/100")
                                .font(.appCaption).foregroundColor(.white.opacity(0.30))
                        }
                    }
                    Spacer()
                    SessionQualitySparkline(weeks: data.weeklyQuality)
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            SessionQualityDetailSheet(data: data)
        }
    }
}

// MARK: - Sparkline

private struct SessionQualitySparkline: View {
    let weeks: [WeeklyQuality]
    private var maxQ: Double { weeks.compactMap(\.avgQuality).max() ?? 100 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(weeks.indices, id: \.self) { i in
                let isLast = i == weeks.count - 1
                let q = weeks[i].avgQuality ?? 0
                let h = maxQ > 0 ? max(4.0, 36.0 * q / maxQ) : 4.0
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLast ? .trendPositive : Color.white.opacity(0.20))
                    .frame(width: 6, height: h)
            }
        }
        .frame(height: 40, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct SessionQualityDetailSheet: View {
    let data: SessionQualityData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SessionQualityBanner(data: data)
                    SessionQualityWeekChart(weeks: data.weeklyQuality)
                    if let best = data.bestSession {
                        SessionQualityBestCard(session: best)
                    }
                    SessionQualityExplainerCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Qualité des Séances")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

private struct SessionQualityBanner: View {
    let data: SessionQualityData

    private var trendColor: Color {
        switch data.trend {
        case "improving": return .trendPositive
        case "declining": return .trendNegative
        default:          return .trendNeutral
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("QUALITÉ DES SÉANCES")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Text(data.message)
                    .font(.appCaption).foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(data.avgQuality.map { "\(Int($0))" } ?? "—")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(trendColor)
        }
        .padding(14)
        .glassCard()
    }
}

private struct SessionQualityWeekChart: View {
    let weeks: [WeeklyQuality]
    private var maxQ: Double { weeks.compactMap(\.avgQuality).max() ?? 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("8 DERNIÈRES SEMAINES")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(weeks.indices, id: \.self) { i in
                    let w = weeks[i]
                    let isLast = i == weeks.count - 1
                    let q = w.avgQuality ?? 0
                    let h = maxQ > 0 ? max(8.0, 60.0 * q / maxQ) : 8.0
                    VStack(spacing: 4) {
                        Text(w.avgQuality.map { "\(Int($0))" } ?? "—")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(isLast ? .white.opacity(0.65) : .white.opacity(0.28))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isLast ? .trendPositive : Color.white.opacity(0.20))
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

private struct SessionQualityBestCard: View {
    let session: BestSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 20))
                .foregroundColor(Color.appWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text("MEILLEURE SÉANCE")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Text(session.date)
                    .font(.appCaption).foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Text("\(Int(session.score))")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(Color.appWarning)
        }
        .padding(14)
        .glassCard()
    }
}

private struct SessionQualityExplainerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Score composé : RPE (40 %), diversité d'exercices (35 %, cible 8 exos = 100 %), volume de sets (25 %, cible 20 sets = 100 %). Agrégé par semaine sur les 8 dernières semaines.")
                .font(.appCaption).foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
