import SwiftUI

struct GhostData {
    let date: String
    let volume: Double
    let rpe: Double?
    let sets: Int?
}

// MARK: - Ghost Banner
struct GhostBanner: View {
    let ghost: GhostData
    let currentVolume: Double
    let beaten: Bool
    var onDismiss: () -> Void

    private var progress: Double {
        guard ghost.volume > 0 else { return 0 }
        return min(currentVolume / ghost.volume, 1.0)
    }

    private func shortDate(_ s: String) -> String {
        String(s.suffix(5))  // MM-DD
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("👻")
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text("GHOST · \(shortDate(ghost.date))")
                        .font(.appMicro.weight(.bold)).tracking(2)
                        .foregroundColor(.gray)
                    HStack(spacing: 6) {
                        Text(beaten ? "Battu ! 🔥" : "\(UnitSettings.shared.display(ghost.volume), specifier: "%.0f") \(UnitSettings.shared.label)")
                            .font(.appLabel.weight(.bold))
                            .foregroundColor(beaten ? Color.forge : .white)
                        if let rpe = ghost.rpe {
                            Text("RPE \(String(format: "%.1f", rpe))")
                                .font(.appCaption).foregroundColor(.gray)
                        }
                        if let sets = ghost.sets {
                            Text("\(sets) sets")
                                .font(.appCaption).foregroundColor(.gray)
                        }
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.appCaption).foregroundColor(.gray)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 5)
                    Capsule()
                        .fill(beaten
                            ? LinearGradient(colors: [Color.forge, Color.forgeDeep], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.statusPurple.opacity(0.8), .statusBlue.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * progress, height: 5)
                        .animation(.spring(response: 0.5), value: progress)
                }
            }
            .frame(height: 5)

            HStack {
                Text(currentVolume > 0
                    ? "\(UnitSettings.shared.display(currentVolume), specifier: "%.0f") / \(UnitSettings.shared.display(ghost.volume), specifier: "%.0f") \(UnitSettings.shared.label)"
                    : "Commence à logger pour suivre ta progression")
                    .font(.system(size: 10)).foregroundColor(.gray)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(beaten ? Color.forge : .statusPurple)
            }
        }
        .padding(12)
        .background(Color.appBg)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            beaten ? Color.forge.opacity(0.5) : Color.statusPurple.opacity(0.25), lineWidth: 1
        ))
    }
}
