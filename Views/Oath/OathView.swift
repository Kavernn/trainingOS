import SwiftUI
import Combine
import LocalAuthentication

// MARK: - Gate

struct OathGateView: View {
    @State private var unlocked = false
    @State private var authFailed = false
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if unlocked {
                OathContentView()
                    .transition(.opacity)
            } else {
                lockScreen
            }
        }
        .animation(.easeInOut(duration: 0.4), value: unlocked)
        .onAppear { authenticate() }
    }

    private var lockScreen: some View {
        VStack(spacing: 40) {
            Spacer()
            Image(systemName: "seal.fill")
                .font(.system(size: 60, weight: .ultraLight))
                .foregroundStyle(.white.opacity(pulsing ? 0.7 : 0.3))
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: pulsing)
                .onAppear { pulsing = true }

            VStack(spacing: 8) {
                Text("MON SERMENT")
                    .font(.system(size: 11, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(6)
                if authFailed {
                    Text("Authentification requise")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            Spacer()

            Button {
                authenticate()
            } label: {
                Text("Déverrouiller")
                    .font(.system(size: 14, weight: .light, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(2)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    )
            }
            .padding(.bottom, 60)
        }
    }

    private func authenticate() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            unlocked = true
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Accéder à ton serment") { ok, _ in
            DispatchQueue.main.async {
                if ok { unlocked = true } else { authFailed = true }
            }
        }
    }
}

// MARK: - Content

struct OathContentView: View {
    @StateObject private var vm = OathViewModel()
    @State private var showWrite = false
    @State private var showArchive = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if vm.isLoading {
                    ProgressView().tint(.white).padding(.top, 60)
                } else if let oath = vm.currentOath {
                    oathDisplay(oath)
                } else {
                    emptyState
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("MON SERMENT")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(6)
                }
                if vm.currentOath != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showArchive = true } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.white.opacity(0.4))
                                .font(.system(size: 14))
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showWrite, onDismiss: {
            Task { await vm.load() }
        }) {
            OathWriteView(existingOath: vm.currentOath) {
                showWrite = false
                Task { await vm.load() }
            }
        }
        .sheet(isPresented: $showArchive) {
            OathArchiveView(versions: vm.versions)
        }
        .task { await vm.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 48) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "seal")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.2))
                Text("Tu n'as pas encore écrit ton serment.")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
            Button { showWrite = true } label: {
                Text("ÉCRIRE MON SERMENT")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.black)
                    .tracking(2)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 2))
            }
            .padding(.bottom, 60)
        }
    }

    private func oathDisplay(_ oath: OathModel) -> some View {
        ScrollView {
            VStack(spacing: 48) {
                Spacer(minLength: 40)

                Text("\u{201C}\(oath.text)\u{201D}")
                    .font(.system(size: 20, weight: .light, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 32)

                VStack(spacing: 6) {
                    Text("Version \(oath.version)")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(2)
                    Text(oath.formattedDate)
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .tracking(1)
                }

                Button { showWrite = true } label: {
                    Text("RÉÉCRIRE")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(4)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                        )
                }

                Spacer(minLength: 40)
            }
        }
    }
}

// MARK: - Archive sheet

struct OathArchiveView: View {
    let versions: [OathModel]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if versions.isEmpty {
                    Text("Aucune version archivée.")
                        .foregroundStyle(.white.opacity(0.4))
                        .font(.system(size: 14))
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(versions) { v in
                                archiveRow(v)
                            }
                        }
                        .padding(.top, 16)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("VERSIONS")
                        .font(.system(size: 11, weight: .light, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(6)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func archiveRow(_ v: OathModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("V\(v.version)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(v.isActive ? .white : .white.opacity(0.3))
                    .tracking(2)
                Spacer()
                Text(v.formattedDate)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                if v.isActive {
                    Text("ACTIF")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                        )
                }
            }
            Text(v.text)
                .font(.system(size: 14, weight: .light, design: .serif))
                .foregroundStyle(v.isActive ? .white.opacity(0.85) : .white.opacity(0.3))
                .lineSpacing(4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.white.opacity(v.isActive ? 0.04 : 0.0))
    }
}

// MARK: - ViewModel

@MainActor
class OathViewModel: ObservableObject {
    @Published var currentOath: OathModel?
    @Published var versions:    [OathModel] = []
    @Published var isLoading = false

    func load() async {
        isLoading = true
        currentOath = try? await APIService.shared.getCurrentOath()
        versions    = (try? await APIService.shared.getOathVersions()) ?? []
        isLoading   = false
    }
}
