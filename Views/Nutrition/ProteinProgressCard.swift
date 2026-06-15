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
        if isOver { return Color.appDanger }
        if isReached { return Color.appSuccess }
        return Color.statusBlue
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("PROTÉINES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.appTextSecondary)
                Spacer()
                Text("Cible : \(Int(target))g")
                    .font(.appCaption)
                    .foregroundColor(.appTextSecondary)
            }

            HStack(spacing: 28) {
                // Grand anneau
                ZStack {
                    Circle()
                        .stroke(Color.appSurfaceInset, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: pct)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: pct)
                    VStack(spacing: 0) {
                        Text("\(Int(current))")
                            .font(.system(size: 30, weight: .black))
                            .foregroundColor(.appTextPrimary)
                        Text("g")
                            .font(.system(size: 12))
                            .foregroundColor(.appTextSecondary)
                    }
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 12) {
                    // Message statut
                    if isOver {
                        Label("+\(Int(current - target))g au-delà de la cible.", systemImage: "exclamationmark.triangle.fill")
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(Color.appDanger)
                    } else if isReached {
                        Label("Cible atteinte.", systemImage: "checkmark.circle.fill")
                            .font(.appLabel.weight(.semibold))
                            .foregroundColor(Color.appSuccess)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Encore")
                                .font(.appCaption)
                                .foregroundColor(.appTextSecondary)
                            Text("\(Int(remaining))g")
                                .font(.system(size: 32, weight: .black))
                                .foregroundColor(Color.statusBlue)
                            Text("restants")
                                .font(.appCaption)
                                .foregroundColor(.appTextSecondary)
                        }
                    }

                    // Barre de progression
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.appSurfaceInset).frame(height: 6)
                                Capsule()
                                    .fill(ringColor)
                                    .frame(width: geo.size.width * pct, height: 6)
                                    .animation(.easeOut(duration: 0.6), value: pct)
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int(pct * 100))% de l'objectif")
                            .font(.system(size: 10))
                            .foregroundColor(.appTextSecondary)
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
