import SwiftUI

struct ReadinessCard: View {
    let entry: RecoveryEntry
    var backendScore: Double? = nil

    private var score: Double? {
        backendScore.map { $0 / 10.0 }
    }

    private var scoreColor: Color {
        guard let s = score else { return .gray }
        return s >= 7 ? .statusGreen : (s >= 5 ? .statusOrange : .statusRed)
    }

    private var scoreLabel: String {
        guard let s = score else { return "—" }
        return s >= 7 ? "Prêt" : (s >= 5 ? "Modéré" : "Fatigué")
    }

    private var presentCount: Int {
        [entry.hrv.map { _ in () }, entry.restingHr.map { _ in () },
         entry.sleepHours.map { _ in () }, entry.soreness.map { _ in () },
         entry.sleepQuality.map { _ in () }, entry.fatigue.map { _ in () },
         entry.energyPre.map { _ in () }]
            .compactMap { $0 }.count
    }

    private var missingMetrics: [String] {
        var m: [String] = []
        if entry.hrv == nil        { m.append("HRV") }
        if entry.restingHr == nil  { m.append("Fréq. cardiaque") }
        if entry.sleepHours == nil { m.append("Sommeil") }
        if entry.soreness == nil   { m.append("Courbatures") }
        return m
    }

    private var reliabilityLabel: String {
        switch presentCount {
        case 6...: return "Fiabilité élevée"
        case 4...: return "Fiabilité partielle"
        case 2...: return "Données limitées"
        default:   return "Données insuffisantes"
        }
    }

    private var reliabilityColor: Color {
        switch presentCount {
        case 6...: return .statusGreen
        case 4...: return .statusOrange
        default:   return .statusRed
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.15), lineWidth: 6)
                    .frame(width: 62, height: 62)
                if let s = score {
                    Circle()
                        .trim(from: 0, to: CGFloat(s / 10))
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 62, height: 62)
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 1) {
                    Text(score.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.appTextPrimary)
                    Text("/10")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("READINESS DU JOUR")
                        .font(.system(size: 10, weight: .bold)).tracking(2)
                        .foregroundColor(.gray)
                    Text(scoreLabel)
                        .font(.appMicro.weight(.bold))
                        .foregroundColor(scoreColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(scoreColor.opacity(0.15))
                        .cornerRadius(4)
                }
                HStack(spacing: 12) {
                    if let hrv = entry.hrv {
                        metricPill("HRV", String(format: "%.0f ms", hrv),
                                   hrv >= 50 ? .statusGreen : (hrv >= 30 ? .statusOrange : .statusRed))
                    }
                    if let hr = entry.restingHr {
                        metricPill("RHR", String(format: "%.0f bpm", hr),
                                   hr <= 55 ? .statusGreen : (hr <= 65 ? .statusOrange : .statusRed))
                    }
                    if let s = entry.soreness {
                        metricPill("Courbatures", String(format: "%.0f/10", s),
                                   s <= 3 ? .statusGreen : (s <= 6 ? .statusOrange : .statusRed))
                    }
                }
                if !missingMetrics.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.appMicro)
                            .foregroundColor(reliabilityColor)
                        Text("\(reliabilityLabel) · manque : \(missingMetrics.joined(separator: ", "))")
                            .font(.appMicro)
                            .foregroundColor(.gray)
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .glassCard(color: scoreColor, intensity: 0.06)
        .cornerRadius(14)
    }

    private func metricPill(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.appCaption.weight(.bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.gray)
        }
    }
}
