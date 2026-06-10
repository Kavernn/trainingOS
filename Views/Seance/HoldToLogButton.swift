import SwiftUI

struct HoldToLogButton: View {
    let label: String
    let icon: String
    let isEnabled: Bool
    let logFlash: Bool
    let onLog: () -> Void

    @GestureState private var isHolding = false
    @AppStorage("holdToLog_useCount") private var useCount = 0
    @State private var hintPulse = false

    private var showHint: Bool { useCount < 3 && isEnabled && !logFlash }

    var body: some View {
        let holding = isHolding && isEnabled
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(logFlash ? Color.green : holding ? Color.orange.opacity(0.18) : Color.orange.opacity(0.07))
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    showHint ? Color.forge.opacity(hintPulse ? 0.7 : 0.2) : logFlash ? Color.clear : Color.forge.opacity(isEnabled ? 0.35 : 0.1),
                    lineWidth: showHint ? 1.5 : 1
                )
            VStack(spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 20))
                    Text(holding ? "Maintenir..." : label)
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(logFlash ? .black : (isEnabled ? .white : .gray))
                if showHint && !holding {
                    Text("Maintenir appuyé pour logger")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.forge.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity).frame(height: showHint ? 62 : 54)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .scaleEffect(holding ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: holding)
        .animation(.easeInOut(duration: 0.12), value: logFlash)
        .opacity(isEnabled ? 1 : 0.55)
        .onAppear {
            guard showHint else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                hintPulse = true
            }
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.4)
                .updating($isHolding) { _, state, _ in state = true }
                .onEnded { _ in
                    useCount += 1
                    onLog()
                }
        )
    }
}
