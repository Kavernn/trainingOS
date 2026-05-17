import SwiftUI

struct WarRoomSettingsView: View {
    @ObservedObject var vm: WarRoomViewModel
    @State private var config: WarRoomConfig?
    @State private var loading = true

    var body: some View {
        Form {
            if loading {
                ProgressView().tint(Color.forge)
            } else if let c = config {
                Section("Intégrations") {
                    Toggle("Phoenix Score", isOn: binding(\.integrationPhoenix))
                        .tint(Color.forge)
                    Toggle("Readiness", isOn: binding(\.integrationReadiness))
                        .tint(Color.forge)
                    Toggle("Coach IA", isOn: binding(\.integrationAiCoach))
                        .tint(Color.forge)
                }
                .listRowBackground(Color.appCard)

                let _ = c // silence unused warning
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBg)
        .navigationTitle("Paramètres")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        config  = try? await APIService.shared.getWarRoomConfig()
        loading = false
    }

    private func binding(_ kp: WritableKeyPath<WarRoomConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { config?[keyPath: kp] ?? false },
            set: { newVal in
                config?[keyPath: kp] = newVal
                let key: String
                switch kp {
                case \.integrationPhoenix:  key = "integration_phoenix"
                case \.integrationReadiness: key = "integration_readiness"
                case \.integrationAiCoach:  key = "integration_ai_coach"
                default:                    return
                }
                Task { try? await APIService.shared.updateWarRoomConfig([key: newVal]) }
            }
        )
    }
}
