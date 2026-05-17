import SwiftUI
import LocalAuthentication

struct WarRoomGateView: View {
    @State private var unlocked      = false
    @State private var authFailed    = false
    @State private var pulse         = false
    @State private var showOathSetup = false

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            if unlocked {
                WarRoomView()
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                lockScreen
            }
        }
        .animation(.easeInOut(duration: 0.35), value: unlocked)
        .onAppear { authenticate() }
        .fullScreenCover(isPresented: $showOathSetup) {
            OathWriteView(existingOath: nil) {
                showOathSetup = false
            }
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.forge.opacity(pulse ? 0.15 : 0.05))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulse ? 1.12 : 1.0)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulse)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.forge)
            }

            VStack(spacing: 10) {
                Text("ZONE SÉCURISÉE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.forge)
                    .tracking(3)

                Text("Accès biométrique requis")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.secondary)
            }

            if authFailed {
                Button("Réessayer") { authenticate() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.forge)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color.forge.opacity(0.12), in: Capsule())
            }

            Spacer()
        }
        .onAppear { pulse = true }
    }

    private func authenticate() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlocked = true
            checkOath()
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Accès War Room") { success, _ in
            DispatchQueue.main.async {
                if success {
                    unlocked = true
                    self.checkOath()
                } else {
                    authFailed = true
                }
            }
        }
    }

    private func checkOath() {
        Task {
            let oath = try? await APIService.shared.getCurrentOath()
            await MainActor.run {
                if oath == nil { showOathSetup = true }
            }
        }
    }
}
