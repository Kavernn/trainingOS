import SwiftUI

// MARK: - Sleep Staging Bar
struct SleepStagingBar: View {
    let stages: SleepStages

    private var total: Double { max(stages.totalHours, 0.01) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "moon.zzz.fill")
                    .font(.appCaption)
                    .foregroundColor(.blue)
                Text("PHASES DE SOMMEIL")
                    .font(.appMicro.weight(.bold)).tracking(1.5)
                    .foregroundColor(.gray)
                Spacer()
                Text(String(format: "%.1fh total", stages.totalHours))
                    .font(.appCaption.weight(.medium))
                    .foregroundColor(.gray)
            }

            // Proportional bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 0.2, green: 0.3, blue: 0.9))
                        .frame(width: max(0, geo.size.width * CGFloat(stages.deepHours / total)))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.purple)
                        .frame(width: max(0, geo.size.width * CGFloat(stages.remHours / total)))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue.opacity(0.6))
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 10)

            // Legend
            HStack(spacing: 16) {
                StageLegendItem(color: Color(red: 0.2, green: 0.3, blue: 0.9), label: "Profond", hours: stages.deepHours)
                StageLegendItem(color: .purple, label: "REM", hours: stages.remHours)
                StageLegendItem(color: .blue.opacity(0.7), label: "Léger", hours: stages.coreHours)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
    }
}

struct StageLegendItem: View {
    let color: Color
    let label: String
    let hours: Double

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.appCaption)
                .foregroundColor(.gray)
            Text(String(format: "%.0fmin", hours * 60))
                .font(.appCaption.weight(.semibold))
                .foregroundColor(.appTextPrimary)
        }
    }
}

// MARK: - Readiness Score Card
struct ReadinessScoreCard: View {
    let score: Int
    let recovery: RecoveryEntry?

    private var scoreColor: Color {
        switch score {
        case 76...100: return .green
        case 61...75:  return Color(red: 0.85, green: 0.75, blue: 0.1)
        case 41...60:  return .orange
        default:       return .red
        }
    }

    private var scoreLabel: String {
        switch score {
        case 76...100: return "Optimal"
        case 61...75:  return "Bon"
        case 41...60:  return "Modéré"
        default:       return "Repos"
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            // Gauge arc (270° sweep, opens at bottom)
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.08),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: 0.75 * CGFloat(score) / 100)
                    .stroke(scoreColor,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .animation(.easeOut(duration: 0.8), value: score)

                VStack(spacing: 1) {
                    Text("\(score)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                        .contentTransition(.numericText())
                    Text("/ 100")
                        .font(.appCaption.weight(.medium))
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONDITION DU JOUR")
                            .font(.appMicro.weight(.bold)).tracking(1.5)
                            .foregroundColor(.gray)
                        Text(scoreLabel)
                            .font(.appTitle)
                            .foregroundColor(scoreColor)
                    }
                    Spacer(minLength: 4)
                    CardInfoButton(title: "Condition du jour", entries: InfoEntry.readinessEntries)
                }

                VStack(alignment: .leading, spacing: 5) {
                    if let hrv = recovery?.hrv {
                        ReadinessMetricRow(icon: "waveform.path.ecg", label: "HRV", value: "\(Int(hrv)) ms")
                    }
                    if let sleep = recovery?.sleepHours {
                        ReadinessMetricRow(icon: "moon.fill", label: "Sommeil", value: String(format: "%.1fh", sleep))
                    }
                    if let rhr = recovery?.restingHr {
                        ReadinessMetricRow(icon: "heart.fill", label: "RHR", value: "\(Int(rhr)) bpm")
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
}

struct ReadinessMetricRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.appCaption)
                .foregroundColor(.gray)
                .frame(width: 14)
            Text(label)
                .font(.appCaption)
                .foregroundColor(.gray)
            Text(value)
                .font(.appCaption.weight(.semibold))
                .foregroundColor(.appTextPrimary)
        }
    }
}
