import SwiftUI

struct InsightsCard: View {
    let data: CorrelationsData
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Corrélations · \(data.periodDays)j", systemImage: "chart.dots.scatter")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.blue)
                Spacer()
                Text("\(data.dataPoints) pts")
                    .font(.appCaption)
                    .foregroundColor(.gray)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }

            if data.dataPoints < 10 || data.insights.isEmpty {
                Text("Pas assez de données pour détecter des corrélations (min. 10 séances).")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            } else {
                ForEach(data.insights) { insight in
                    CorrelationRow(insight: insight)
                    if insight.id != data.insights.last?.id {
                        Divider().background(Color.appSeparator)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appBg)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.25), lineWidth: 1))
        .cornerRadius(12)
    }
}

struct CorrelationRow: View {
    let insight: CorrelationInsight

    var accentColor: Color {
        switch insight.color {
        case "blue":   return .blue
        case "indigo": return .blue
        case "green":  return .green
        case "teal":   return .teal
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        default:       return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: insight.icon)
                    .font(.system(size: 14))
                    .foregroundColor(accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(insight.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.appTextPrimary)
                        Spacer()
                        Text(insight.strength)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(accentColor.opacity(0.15))
                            .cornerRadius(4)
                    }
                    Text(insight.insightDesc)
                        .font(.appCaption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
            }

            GeometryReader { geo in
                let mid  = geo.size.width / 2
                let barW = abs(insight.correlation) * mid
                let offX = insight.correlation >= 0 ? mid : mid - barW

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor)
                        .frame(width: barW, height: 4)
                        .offset(x: offX)

                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 1, height: 8)
                        .offset(x: mid - 0.5, y: -2)
                }
            }
            .frame(height: 8)
            .padding(.leading, 28)

            HStack {
                Spacer()
                Text("n=\(insight.nPoints)")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.25))
            }
            .padding(.leading, 28)
        }
        .padding(.vertical, 4)
    }
}
