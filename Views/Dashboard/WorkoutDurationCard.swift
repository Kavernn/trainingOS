import SwiftUI

// MARK: - WorkoutDurationCard

struct WorkoutDurationCard: View {
    let data: WorkoutDurationData
    @State private var showDetail = false

    private var trendColor: Color {
        switch data.trend {
        case "increasing": return Color(hex: "FF9500")
        case "decreasing": return Color(hex: "34C759")
        default:           return Color(hex: "8E8E93")
        }
    }

    private var trendLabel: String {
        switch data.trend {
        case "increasing": return "En hausse"
        case "decreasing": return "En baisse"
        default:           return "Stable"
        }
    }

    private var trendIcon: String {
        switch data.trend {
        case "increasing": return "arrow.up.right"
        case "decreasing": return "arrow.down.right"
        default:           return "arrow.right"
        }
    }

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("DURÉE SÉANCES")
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
                        Text("MOY. PAR SÉANCE")
                            .font(.appMicro).tracking(0.8)
                            .foregroundColor(.white.opacity(0.28))
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(data.avgDuration.map { "\(Int($0))" } ?? "—")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(trendColor)
                            Text("min")
                                .font(.appCaption).foregroundColor(.white.opacity(0.30))
                        }
                    }
                    Spacer()
                    DurationSparkline(weeks: data.weeklyAvgs)
                }
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            WorkoutDurationDetailSheet(data: data)
        }
    }
}

private struct DurationSparkline: View {
    let weeks: [WeeklyDurationAvg]
    private var maxVal: Double { weeks.compactMap(\.avgMin).max() ?? 1 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(weeks.indices, id: \.self) { i in
                let isLast = i == weeks.count - 1
                let v = weeks[i].avgMin ?? 0
                let h = maxVal > 0 ? max(4.0, 36.0 * v / maxVal) : 4.0
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLast ? Color(hex: "34C759") : Color.white.opacity(0.20))
                    .frame(width: 5, height: h)
            }
        }
        .frame(height: 40, alignment: .bottom)
    }
}

// MARK: - Detail Sheet

private struct WorkoutDurationDetailSheet: View {
    let data: WorkoutDurationData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    DurationBanner(data: data)
                    DurationWeeklyChart(weeks: data.weeklyAvgs)
                    DurationByLengthCard(buckets: data.byLength)
                    DurationExplainerCard(analyzed: data.sessionsAnalyzed)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("Durée des Séances")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
}

private struct DurationBanner: View {
    let data: WorkoutDurationData

    private var color: Color {
        switch data.trend {
        case "increasing": return Color(hex: "FF9500")
        case "decreasing": return Color(hex: "34C759")
        default:           return Color(hex: "8E8E93")
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DURÉE DES SÉANCES")
                    .font(.appMicro.weight(.black)).tracking(1.5)
                    .foregroundColor(.white.opacity(0.35))
                Text(data.message)
                    .font(.appCaption).foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(data.sessionsAnalyzed) séances analysées")
                    .font(.appCaption).foregroundColor(.white.opacity(0.30))
            }
            Spacer()
            Text(data.avgDuration.map { "\(Int($0))m" } ?? "—")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(color)
        }
        .padding(14)
        .glassCard()
    }
}

private struct DurationWeeklyChart: View {
    let weeks: [WeeklyDurationAvg]
    private var maxVal: Double { weeks.compactMap(\.avgMin).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("12 DERNIÈRES SEMAINES (MIN)")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(weeks.indices, id: \.self) { i in
                    let isLast = i == weeks.count - 1
                    let v = weeks[i].avgMin ?? 0
                    let h = maxVal > 0 ? max(8.0, 60.0 * v / maxVal) : 8.0
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isLast ? Color(hex: "34C759") : Color.white.opacity(0.20))
                        .frame(maxWidth: .infinity).frame(height: h)
                }
            }
            .frame(height: 68, alignment: .bottom)
        }
        .padding(14)
        .glassCard()
    }
}

private struct DurationByLengthCard: View {
    let buckets: [DurationBucket]
    private var maxRpe: Double { buckets.compactMap(\.avgRpe).max() ?? 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RPE MOYEN PAR DURÉE")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(buckets, id: \.bucket) { b in
                    let rpe = b.avgRpe ?? 0
                    let h   = maxRpe > 0 ? max(10.0, 64.0 * rpe / maxRpe) : 10.0
                    VStack(spacing: 5) {
                        Text(b.avgRpe.map { String(format: "%.1f", $0) } ?? "—")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(b.count > 0 ? 0.75 : 0.25))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(b.count > 0 ? Color(hex: "34C759") : Color.white.opacity(0.10))
                            .frame(height: h)
                        Text(b.label)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white.opacity(0.35))
                            .multilineTextAlignment(.center)
                        Text("\(b.count) séances")
                            .font(.system(size: 7))
                            .foregroundColor(.white.opacity(0.22))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100, alignment: .bottom)
        }
        .padding(14)
        .glassCard()
    }
}

private struct DurationExplainerCard: View {
    let analyzed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMMENT C'EST CALCULÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))
            Text("Durée moyenne hebdomadaire des séances complétées avec duration_min renseigné. La corrélation durée/RPE montre si les séances longues sont plus ou moins intenses. \(analyzed) séances analysées.")
                .font(.appCaption).foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .glassCard()
    }
}
