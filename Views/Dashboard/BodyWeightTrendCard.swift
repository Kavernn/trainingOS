import SwiftUI

// MARK: - BodyWeightTrendCard

struct BodyWeightTrendCard: View {
    let data: BodyWeightTrendData
    @State private var showDetail = false

    private var trendColor: Color {
        switch data.trend {
        case "gaining": return Color.trendNeutral
        case "losing":  return Color.trendPositive
        default:        return .gray
        }
    }

    private var trendIcon: String {
        switch data.trend {
        case "gaining": return "arrow.up.right"
        case "losing":  return "arrow.down.right"
        default:        return "arrow.right"
        }
    }

    private var trendLabel: String {
        switch data.trend {
        case "gaining": return "En hausse"
        case "losing":  return "En baisse"
        default:        return "Stable"
        }
    }

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("POIDS")
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
                        Text("ACTUEL (LBS)")
                            .font(.appMicro).tracking(0.8)
                            .foregroundColor(.white.opacity(0.28))
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(data.currentWeight.map { String(format: "%.1f", $0) } ?? "—")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(trendColor)
                            if let pct = data.changePct {
                                let sign = pct >= 0 ? "+" : ""
                                Text("\(sign)\(String(format: "%.1f", pct))%")
                                    .font(.appCaption).foregroundColor(.white.opacity(0.35))
                            }
                        }
                    }
                    Spacer()
                    BodyWeightSparkline(avgs: data.weeklyAvgs)
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            BodyWeightDetailSheet(data: data)
        }
    }
}

// MARK: - Sparkline

private struct BodyWeightSparkline: View {
    let avgs: [WeeklyWeightAvg]

    private var minVal: Double { avgs.compactMap(\.avg).min() ?? 0 }
    private var maxVal: Double { avgs.compactMap(\.avg).max() ?? 1 }
    private var range: Double  { max(maxVal - minVal, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(avgs.indices, id: \.self) { i in
                let isLast = i == avgs.count - 1
                let v = avgs[i].avg ?? minVal
                let h = max(4.0, 36.0 * (v - minVal) / range)
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLast ? Color.trendPositive : Color.white.opacity(0.20))
                    .frame(width: 5, height: h)
            }
        }
        .frame(height: 40, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct BodyWeightDetailSheet: View {
    let data: BodyWeightTrendData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    BodyWeightBanner(data: data)
                    BodyWeightWeeklyChart(avgs: data.weeklyAvgs)
                    BodyWeightRangeCard(data: data)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Tendance du Poids")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

private struct BodyWeightBanner: View {
    let data: BodyWeightTrendData

    private var trendColor: Color {
        switch data.trend {
        case "gaining": return Color.trendNeutral
        case "losing":  return Color.trendPositive
        default:        return .gray
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TENDANCE DU POIDS")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Text(data.message)
                    .font(.appCaption).foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(data.currentWeight.map { String(format: "%.1f", $0) } ?? "—")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(trendColor)
        }
        .padding(14)
        .glassCard()
    }
}

private struct BodyWeightWeeklyChart: View {
    let avgs: [WeeklyWeightAvg]

    private var minVal: Double { avgs.compactMap(\.avg).min() ?? 0 }
    private var maxVal: Double { avgs.compactMap(\.avg).max() ?? 1 }
    private var range: Double  { max(maxVal - minVal, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("12 DERNIÈRES SEMAINES")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(avgs.indices, id: \.self) { i in
                    let isLast = i == avgs.count - 1
                    let v  = avgs[i].avg ?? minVal
                    let h  = max(8.0, 60.0 * (v - minVal) / range)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isLast ? Color.trendPositive : Color.white.opacity(0.20))
                        .frame(maxWidth: .infinity)
                        .frame(height: h)
                }
            }
            .frame(height: 68, alignment: .bottom)
            HStack {
                Text(String(format: "%.1f lbs", minVal))
                    .font(.system(size: 8)).foregroundColor(.white.opacity(0.25))
                Spacer()
                Text(String(format: "%.1f lbs", maxVal))
                    .font(.system(size: 8)).foregroundColor(.white.opacity(0.25))
            }
        }
        .padding(14)
        .glassCard()
    }
}

private struct BodyWeightRangeCard: View {
    let data: BodyWeightTrendData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RANGE 90 JOURS")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BAS").font(.appMicro).foregroundColor(.white.opacity(0.28))
                    Text(data.rangeLow.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Color.trendPositive)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("HAUT").font(.appMicro).foregroundColor(.white.opacity(0.28))
                    Text(data.rangeHigh.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Color.trendNeutral)
                }
                if let pct = data.currentPctOfRange {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("POSITION").font(.appMicro).foregroundColor(.white.opacity(0.28))
                        Text("\(pct)%")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.70))
                    }
                }
            }
        }
        .padding(14)
        .glassCard()
    }
}
