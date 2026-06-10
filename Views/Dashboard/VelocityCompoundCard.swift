import SwiftUI

// MARK: - VelocityCompoundCard

struct VelocityCompoundCard: View {
    let velocity: VelocityData
    let compound: CompoundScore

    var body: some View {
        HStack(spacing: 0) {
            VelocityPanel(data: velocity)
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            CompoundPanel(data: compound)
        }
        .glassCard()
    }
}

// MARK: - Velocity Panel

private struct VelocityPanel: View {
    let data: VelocityData

    private var accentColor: Color {
        switch data.label {
        case "accélération": return .forge
        case "stable":       return Color.white.opacity(0.70)
        case "décélération": return .orange
        default:             return .appDanger
        }
    }

    private var labelIcon: String {
        switch data.label {
        case "accélération": return "arrow.up.forward"
        case "stable":       return "minus"
        case "décélération": return "arrow.down.forward"
        default:             return "arrow.down"
        }
    }

    // Reverse weekly_scores so left = oldest, right = most recent
    private var orderedScores: [Double?] {
        Array(data.weeklyScores.reversed())
    }

    private var velocityText: String {
        guard let v = data.velocity else { return "—" }
        let sign = v >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", v))%"
    }

    private var trendText: String {
        guard let t = data.trendPct else { return "" }
        let sign = t >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f", t))% / 4 sem."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VÉLOCITÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))

            HStack(spacing: 4) {
                Image(systemName: labelIcon)
                    .font(.system(size: 10, weight: .bold))
                Text(data.velocityLabel)
                    .font(.appLabel.weight(.bold))
            }
            .foregroundColor(accentColor)

            Text(velocityText)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(accentColor)
                .contentTransition(.numericText())

            SparklineBars(scores: orderedScores, accent: accentColor)

            if !trendText.isEmpty {
                Text(trendText)
                    .font(.appCaption)
                    .foregroundColor(.white.opacity(0.38))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

// MARK: - Compound Panel

private struct CompoundPanel: View {
    let data: CompoundScore

    private var trendColor: Color {
        switch data.trend {
        case "hausse": return .forge
        case "baisse": return .appDanger
        default:       return Color.white.opacity(0.55)
        }
    }

    private var trendIcon: String {
        switch data.trend {
        case "hausse": return "arrow.up.right"
        case "baisse": return "arrow.down.right"
        default:       return "minus"
        }
    }

    private var consistencyWidth: CGFloat {
        CGFloat(max(0, min(100, data.baseConsistency)) / 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COMPOSÉ")
                .font(.appMicro.weight(.black)).tracking(1.5)
                .foregroundColor(.white.opacity(0.35))

            HStack(spacing: 4) {
                Image(systemName: trendIcon)
                    .font(.system(size: 10, weight: .bold))
                Text(data.trendLabel)
                    .font(.appLabel.weight(.bold))
            }
            .foregroundColor(trendColor)

            Text(data.formattedScore)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(data.isAboveBaseline ? .forge : .white.opacity(0.75))
                .contentTransition(.numericText())

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 4)
                    Capsule()
                        .fill(trendColor.opacity(0.70))
                        .frame(width: geo.size.width * consistencyWidth, height: 4)
                }
            }
            .frame(height: 4)

            Text("\(String(format: "%.0f", data.baseConsistency))% actif · \(data.currentStreak)j streak")
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.38))

            Text(data.formattedDelta + " vs 30j")
                .font(.appCaption)
                .foregroundColor(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

// MARK: - Sparkline Bars

private struct SparklineBars: View {
    let scores: [Double?]
    let accent: Color

    var body: some View {
        let capped = Array(scores.prefix(4))
        let maxVal = capped.compactMap { $0 }.max() ?? 1.0

        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<capped.count, id: \.self) { i in
                let val = capped[i] ?? 0.0
                let ratio = maxVal > 0 ? val / maxVal : 0
                let isLatest = (i == capped.count - 1)
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLatest ? accent : accent.opacity(0.30))
                    .frame(width: 8, height: max(4, 22 * ratio))
            }
        }
        .frame(height: 22, alignment: .bottom)
    }
}
