import SwiftUI

struct PostSeanceCard: View {
    let data: PostSessionData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.green)
                Text("Séance terminée".uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.5)
                    .foregroundColor(.green)
                Spacer()
                if let name = data.sessionName, !name.isEmpty {
                    Text(name)
                        .font(.appCaption.weight(.medium))
                        .foregroundColor(.white.opacity(0.45))
                }
            }

            Divider().background(Color.white.opacity(0.08))

            // Metrics
            HStack(alignment: .top, spacing: 20) {
                if let rpe = data.avgRpe {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RPE")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.40))
                        Text(String(format: "%.1f", rpe))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text(shortInterpretation(data.rpeInterpretation))
                            .font(.appCaption)
                            .foregroundColor(.white.opacity(0.50))
                            .lineLimit(1)
                    }
                }
                if let delta = data.volumeDeltaPct {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Effort vs baseline")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.40))
                        Text(delta > 0 ? "+\(delta)%" : "\(delta)%")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(delta > 10 ? .orange : delta < -10 ? .green : .white)
                        Text("même type de séance")
                            .font(.appCaption)
                            .foregroundColor(.white.opacity(0.50))
                    }
                }
            }

            // Nutrition advice
            if !data.nutritionAdvice.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.appCaption)
                        .foregroundColor(.green.opacity(0.75))
                        .padding(.top, 1)
                    Text(data.nutritionAdvice)
                        .font(.appLabel)
                        .foregroundColor(.white.opacity(0.78))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.green.opacity(0.22), lineWidth: 1)
        )
        .cornerRadius(14)
    }

    // Extract the short label after " — " in interpretation strings like "Intensité correcte — dans la zone cible"
    private func shortInterpretation(_ text: String) -> String {
        text.components(separatedBy: " — ").last ?? text
    }
}
