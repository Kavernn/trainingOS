import SwiftUI

struct TodayMetricsRow: View {
    let dash: DashboardData
    let recovery: RecoveryEntry?
    let cardioData: [CardioEntry]

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var calories: Double { dash.nutritionTotals.calories ?? 0 }
    private var calGoal: Double { dash.nutritionSettings?.calories ?? 2000 }
    private var protein: Double { dash.nutritionTotals.proteines ?? 0 }
    private var protGoal: Double { dash.nutritionSettings?.proteines ?? 150 }

    private var weeklyCardioKm: Double {
        guard !cardioData.isEmpty else { return 0 }
        guard let todayMid = Self.isoFmt.date(from: dash.todayDate) else { return 0 }
        let cutoff = Self.isoFmt.string(from: Date(timeIntervalSince1970: todayMid.timeIntervalSince1970 - 6 * 86400))
        return cardioData.filter { ($0.date ?? "") >= cutoff }.compactMap { $0.distanceKm }.reduce(0, +)
    }

    var body: some View {
        HStack(spacing: 8) {
            MetricMiniCard(
                icon: "flame.fill",
                iconColor: Color.forge,
                value: "\(Int(calories))",
                label: "/ \(Int(calGoal)) kcal",
                fill: calGoal > 0 ? min(calories / calGoal, 1.0) : 0,
                fillColor: Color.forge,
                compact: weeklyCardioKm > 0
            )

            MetricMiniCard(
                icon: "circle.hexagongrid.fill",
                iconColor: .cyan,
                value: "\(Int(protein))g",
                label: "/ \(Int(protGoal))g prot.",
                fill: protGoal > 0 ? min(protein / protGoal, 1.0) : 0,
                fillColor: .cyan,
                compact: weeklyCardioKm > 0
            )

            if weeklyCardioKm > 0 {
                MetricMiniCard(
                    icon: "figure.run",
                    iconColor: .green,
                    value: String(format: "%.1f", weeklyCardioKm),
                    label: "km · 7 jours",
                    fill: min(weeklyCardioKm / 20.0, 1.0),
                    fillColor: .green,
                    compact: true
                )
            } else if let sleep = recovery?.sleepHours {
                MetricMiniCard(
                    icon: "moon.zzz.fill",
                    iconColor: .blue,
                    value: String(format: "%.1fh", sleep),
                    label: "sommeil",
                    fill: min(sleep / 8.0, 1.0),
                    fillColor: .blue,
                    compact: false
                )
            }
        }
    }
}

struct MetricMiniCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String
    let fill: Double
    let fillColor: Color
    var compact: Bool = false

    private var valueSize: CGFloat { compact ? 16 : 20 }
    private var labelSize: CGFloat { compact ? 10 : 11 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(value)
                    .font(.system(size: valueSize, weight: .black))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            Text(label)
                .font(.system(size: labelSize))
                .foregroundColor(Color.white.opacity(0.4))
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(fill), height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
