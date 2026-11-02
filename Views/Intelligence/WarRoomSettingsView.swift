import SwiftUI

struct WarRoomSettingsView: View {
    @ObservedObject var vm: WarRoomViewModel
    @State private var config: WarRoomConfig?
    @State private var loading = true
    @State private var pendingKeys: Set<String> = []
    @State private var queuedKeys:  Set<String> = []
    @State private var settingsError: String?

    var body: some View {
        Form {
            if loading {
                ProgressView().tint(Color.forge)
            } else if config != nil {
                Section("Intégrations") {
                    Toggle("Phoenix Score", isOn: binding(\.integrationPhoenix))
                        .tint(Color.forge)
                        .disabled(pendingKeys.contains("integration_phoenix"))
                    Toggle("Readiness", isOn: binding(\.integrationReadiness))
                        .tint(Color.forge)
                        .disabled(pendingKeys.contains("integration_readiness"))
                    Toggle("Coach IA", isOn: binding(\.integrationAiCoach))
                        .tint(Color.forge)
                        .disabled(pendingKeys.contains("integration_ai_coach"))
                }
                .listRowBackground(Color.appCard)

                if !queuedKeys.isEmpty {
                    Section {
                        Text("\(queuedKeys.count) changement\(queuedKeys.count > 1 ? "s" : "") en attente — hors ligne")
                            .font(.appCaption)
                            .foregroundColor(.appTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.appCard)
                }
                if let msg = settingsError {
                    Section {
                        Text(msg)
                            .font(.appCaption)
                            .foregroundColor(.appDanger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.appCard)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBg)
        .navigationTitle("Paramètres")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onReceive(SyncManager.shared.$pendingCount) { count in
            if count == 0 && !queuedKeys.isEmpty {
                queuedKeys.removeAll()
                Task { await load() }
            }
        }
    }

    private func load() async {
        config  = try? await APIService.shared.getWarRoomConfig()
        loading = false
    }

    private func keyName(for kp: WritableKeyPath<WarRoomConfig, Bool>) -> String? {
        switch kp {
        case \.integrationPhoenix:   return "integration_phoenix"
        case \.integrationReadiness: return "integration_readiness"
        case \.integrationAiCoach:   return "integration_ai_coach"
        default:                     return nil
        }
    }

    private func binding(_ kp: WritableKeyPath<WarRoomConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { config?[keyPath: kp] ?? false },
            set: { newVal in
                guard let key = keyName(for: kp) else { return }
                pendingKeys.insert(key)
                settingsError = nil
                Task {
                    defer { pendingKeys.remove(key) }
                    do {
                        try await APIService.shared.updateWarRoomConfig([key: newVal])
                        // Succès serveur UNIQUEMENT : commit local (anti-optimiste).
                        config?[keyPath: kp] = newVal
                    } catch APIError.queuedOffline {
                        queuedKeys.insert(key)
                        // Toggle visuellement non flip jusqu'au rejeu SyncManager.
                    } catch APIError.serverError(_, let msg) {
                        settingsError = msg.isEmpty ? "Erreur serveur" : msg
                    } catch {
                        settingsError = "Erreur réseau — réessaie"
                    }
                }
            }
        )
    }
}
