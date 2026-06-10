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
                        .font(.system(size: 9, weight: .bold)).tracking(2)
                        .foregroundColor(.gray)
                    HStack(spacing: 6) {
                        Text(beaten ? "Battu ! 🔥" : "\(UnitSettings.shared.display(ghost.volume), specifier: "%.0f") \(UnitSettings.shared.label)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(beaten ? .orange : .white)
                        if let rpe = ghost.rpe {
                            Text("RPE \(String(format: "%.1f", rpe))")
                                .font(.system(size: 11)).foregroundColor(.gray)
                        }
                        if let sets = ghost.sets {
                            Text("\(sets) sets")
                                .font(.system(size: 11)).foregroundColor(.gray)
                        }
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.gray)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 5)
                    Capsule()
                        .fill(beaten
                            ? LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.purple.opacity(0.8), .blue.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
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
                    .foregroundColor(beaten ? .orange : .purple)
            }
        }
        .padding(12)
        .background(Color.appBg)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            beaten ? Color.orange.opacity(0.5) : Color.purple.opacity(0.25), lineWidth: 1
        ))
    }
}
