import SwiftUI

struct RecoverySettingsView: View {
    @AppStorage("sleep_goal_hours") private var sleepGoalHours: Double = 8.0
    @AppStorage("wake_time_target") private var wakeTimeTarget: String = "07:00"
    @AppStorage("bedtime_target")   private var bedtimeTarget: String  = "23:00"
    @AppStorage("hrv_sensitivity")  private var hrvSensitivity: String = "standard"

    @State private var wakeDate: Date = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @State private var bedDate:  Date = Calendar.current.date(from: DateComponents(hour: 23, minute: 0)) ?? Date()

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

                    HStack(spacing: 12) {
                        settingsIcon("sunrise.fill", color: .statusYellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Heure de lever cible").font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
                            Text("Utilisé pour les rappels").font(.appCaption).foregroundColor(.gray.opacity(0.55))
                        }
                        Spacer()
                        DatePicker("", selection: $wakeDate, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .onChange(of: wakeDate) { _, d in
                                wakeTimeTarget = timeString(from: d)
                            }
                    }
                    .padding(.vertical, 3)

                    HStack(spacing: 12) {
                        settingsIcon("moon.fill", color: .statusBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Heure de coucher cible").font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
                            Text("Utilisé pour les rappels").font(.appCaption).foregroundColor(.gray.opacity(0.55))
                        }
                        Spacer()
                        DatePicker("", selection: $bedDate, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .onChange(of: bedDate) { _, d in
                                bedtimeTarget = timeString(from: d)
                            }
                    }
                    .padding(.vertical, 3)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)

                Section("Sensibilité HRV") {
                    ForEach(sensitivityOptions, id: \.id) { option in
                        Button {
                            hrvSensitivity = option.id
                            Task { try? await APIService.shared.updateProfileSettings(hrvSensitivity: option.id) }
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
        .onAppear { loadStoredTimes() }
        .onChange(of: sleepGoalHours) { _, newValue in
            Task { try? await APIService.shared.updateProfileSettings(sleepGoalHours: newValue) }
        }
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

    private func timeString(from date: Date) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return String(format: "%02d:%02d", h, m)
    }

    private func loadStoredTimes() {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        if let d = fmt.date(from: wakeTimeTarget) { wakeDate = d }
        if let d = fmt.date(from: bedtimeTarget)  { bedDate  = d }
    }
}
