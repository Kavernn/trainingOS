import SwiftUI

// MARK: - VolumeProgressionCard

struct VolumeProgressionCard: View {
    let data: VolumeProgressionData
    @State private var showDetail = false

    private var trendColor: Color {
        switch data.trend {
        case "building":  return Color(hex: "34C759")
        case "declining": return Color(hex: "FF6B6B")
        default:          return Color(hex: "FF9500")
        }
    }

    private var trendIcon: String {
        switch data.trend {
        case "building":  return "arrow.up.right"
        case "declining": return "arrow.down.right"
        default:          return "arrow.right"
        }
    }

    private var trendLabel: String {
        switch data.trend {
        case "building":  return "En hausse"
        case "declining": return "En baisse"
        default:          return "Stable"
        }
    }

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("VOLUME")
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
                        Text("CHARGE PEAK")
                            .font(.appMicro).tracking(0.8)
                            .foregroundColor(.white.opacity(0.28))
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(data.currentPctOfPeak.map { "\($0)" } ?? "—")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(trendColor)
                            Text("%")
                                .font(.appCaption).foregroundColor(.white.opacity(0.30))
                        }
                    }
                    Spacer()
                    VolumeSparkline(loads: data.weeklyLoads)
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            VolumeProgressionDetailSheet(data: data)
        }
    }
}

// MARK: - Sparkline

private struct VolumeSparkline: View {
    let loads: [WeeklyLoad]
    private var maxLoad: Double { loads.map(\.load).max() ?? 1 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(loads.indices, id: \.self) { i in
                let isLast = i == loads.count - 1
                let h = maxLoad > 0 ? max(4.0, 36.0 * loads[i].load / maxLoad) : 4.0
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLast ? Color(hex: "34C759") : Color.white.opacity(0.20))
                    .frame(width: 5, height: h)
            }
        }
        .frame(height: 40, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct VolumeProgressionDetailSheet: View {
    let data: VolumeProgressionData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VolumeSummaryBanner(data: data)
                    VolumeWeeklyChart(loads: data.weeklyLoads)
                    VolumeExplainerCard()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Progression du Volume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

private struct VolumeSummaryBanner: View {
    let data: VolumeProgressionData

    private var trendColor: Color {
        switch data.trend {
        case "building":  return Color(hex: "34C759")
        case "declining": return Color(hex: "FF6B6B")
        default:          return Color(hex: "FF9500")
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROGRESSION DU VOLUME")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                if let peak = data.peakLoad {
                    Text("Peak semaine : \(Int(peak)) RPE cumulé")
                        .font(.appCaption).foregroundColor(.white.opacity(0.50))
                }
                Text(data.message)
                    .font(.appCaption).foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(data.currentPctOfPeak.map { "\($0)%" } ?? "—")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundColor(trendColor)
        }
        .padding(14)
        .glassCard()
    }
}

private struct VolumeWeeklyChart: View {
    let loads: [WeeklyLoad]
    private var maxLoad: Double { loads.map(\.load).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("13 DERNIÈRES SEMAINES")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(loads.indices, id: \.self) { i in
                    let isLast = i == loads.count - 1
                    let h = maxLoad > 0 ? max(8.0, 60.0 * loads[i].load / maxLoad) : 8.0
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isLast ? Color(hex: "34C759") : Color.white.opacity(0.20))
                        .frame(maxWidth: .infinity)
                        .frame(height: h)
                }
            }
            .frame(height: 68, alignment: .bottom)
        }
        .padding(14)
        .glassCard()
    }
}

private struct VolumeExplainerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("La charge hebdomadaire est la somme des RPE de toutes les séances complétées. La tendance compare la moyenne des 3 dernières semaines aux 3 semaines précédentes (±10 %).")
                .font(.appCaption).foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
