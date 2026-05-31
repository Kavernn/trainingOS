import SwiftUI

// MARK: - Protein Progress Card

struct ProteinProgressCard: View {
    let current: Double
    let target: Double

    private var pct: Double { min(current / max(target, 1), 1.0) }
    private var remaining: Double { max(target - current, 0) }
    private var isReached: Bool { current >= target }
    private var isOver: Bool { current > target }

    private var ringColor: Color {
        if isOver { return .red }
        if isReached { return .green }
        return .blue
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("PROTÉINES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.gray)
                Spacer()
                Text("Cible : \(Int(target))g")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            HStack(spacing: 28) {
                // Grand anneau
                ZStack {
                    Circle()
                        .stroke(Color(hex: "191926"), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: pct)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: pct)
                    VStack(spacing: 0) {
                        Text("\(Int(current))")
                            .font(.system(size: 30, weight: .black))
                            .foregroundColor(.white)
                        Text("g")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 12) {
                    // Message statut
                    if isOver {
                        Label("+\(Int(current - target))g au-delà de la cible.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.red)
                    } else if isReached {
                        Label("Cible atteinte.", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Encore")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            Text("\(Int(remaining))g")
                                .font(.system(size: 32, weight: .black))
                                .foregroundColor(.blue)
                            Text("restants")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                    }

                    // Barre de progression
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(hex: "191926")).frame(height: 6)
                                Capsule()
                                    .fill(ringColor)
                                    .frame(width: geo.size.width * pct, height: 6)
                                    .animation(.easeOut(duration: 0.6), value: pct)
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int(pct * 100))% de l'objectif")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}
