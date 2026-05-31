import SwiftUI

struct HoldToLogButton: View {
    let label: String
    let icon: String
    let isEnabled: Bool
    let logFlash: Bool
    let onLog: () -> Void

    @GestureState private var isHolding = false

    var body: some View {
        let holding = isHolding && isEnabled
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(logFlash ? Color.green : holding ? Color.orange.opacity(0.18) : Color.orange.opacity(0.07))
            RoundedRectangle(cornerRadius: 14)
                .stroke(logFlash ? Color.clear : Color.orange.opacity(isEnabled ? 0.35 : 0.1), lineWidth: 1)
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 20))
                Text(holding ? "Maintenir..." : label)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(logFlash ? .black : (isEnabled ? .white : .gray))
        }
        .frame(maxWidth: .infinity).frame(height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .scaleEffect(holding ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: holding)
        .animation(.easeInOut(duration: 0.12), value: logFlash)
        .opacity(isEnabled ? 1 : 0.55)
        .gesture(
            LongPressGesture(minimumDuration: 0.4)
                .updating($isHolding) { _, state, _ in state = true }
                .onEnded { _ in onLog() }
        )
    }
}
