import SwiftUI

struct RecoverySettingsView: View {
    @AppStorage("sleep_goal_hours") private var sleepGoalHours: Double = 8.0
    @AppStorage("hrv_sensitivity")  private var hrvSensitivity: String = "standard"

    @State private var saveError: String? = nil
    @State private var isRevertingSleepGoal = false

    private let sensitivityOptions: [(id: String, label: String, subtitle: String)] = [
        ("conservative", "Conservateur", "Zones 85% / 115% — moins d'alertes"),
        ("standard",     "Standard",     "Zones 90% / 110% — défaut Whoop/Oura"),
        ("aggressive",   "Agressif",     "Zones 80% / 120% — plus sensible"),
    ]

    private var sleepGoalLabel: String {
        let h = Int(sleepGoalHours)
        let m = Int((sleepGoalHours - Double(h)) * 60)
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    var body: some View {
        ZStack {
            AmbientBackground(color: .indigo)

            List {
                Section("Sommeil") {
                    HStack(spacing: 12) {
                        settingsIcon("moon.zzz.fill", color: .indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Objectif de sommeil").font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
                            Text("Score 100% quand atteint").font(.appCaption).foregroundColor(.gray.opacity(0.55))
                        }
                        Spacer()
                        Stepper(
                            value: $sleepGoalHours,
                            in: 5.0...12.0,
                            step: 0.5
                        ) {
                            Text(sleepGoalLabel)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.appTextPrimary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)

                Section("Sensibilité HRV") {
                    ForEach(sensitivityOptions, id: \.id) { option in
                        Button {
                            let old = hrvSensitivity
                            hrvSensitivity = option.id
                            Task {
                                do {
                                    try await APIService.shared.updateProfileSettings(hrvSensitivity: option.id)
                                } catch {
                                    await MainActor.run {
                                        hrvSensitivity = old
                                        saveError = "Réglage HRV non sauvegardé — réessaie"
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                settingsIcon(
                                    option.id == "conservative" ? "tortoise.fill" :
                                    option.id == "standard"     ? "waveform.path.ecg" : "hare.fill",
                                    color: option.id == "aggressive" ? .statusRed :
                                           option.id == "standard"   ? .statusCyan : .statusGreen
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label).font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
                                    Text(option.subtitle).font(.appCaption).foregroundColor(.gray.opacity(0.55))
                                }
                                Spacer()
                                if hrvSensitivity == option.id {
                                    Image(systemName: "checkmark")
                                        .font(.appLabel.weight(.semibold))
                                        .foregroundColor(Color.forge)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Influence les alertes HRV (vert / orange / rouge) dans le tableau de bord.")
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.6))
                        .listRowBackground(Color.clear)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Récupération & Sommeil")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: sleepGoalHours) { oldValue, newValue in
            if isRevertingSleepGoal { isRevertingSleepGoal = false; return }
            Task {
                do {
                    try await APIService.shared.updateProfileSettings(sleepGoalHours: newValue)
                } catch {
                    await MainActor.run {
                        isRevertingSleepGoal = true
                        sleepGoalHours = oldValue
                        saveError = "Objectif de sommeil non sauvegardé — réessaie"
                    }
                }
            }
        }
        .alert("Note", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    @ViewBuilder
    private func settingsIcon(_ icon: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
            Image(systemName: icon)
                .font(.appLabel.weight(.semibold))
                .foregroundColor(color)
        }
    }
}
