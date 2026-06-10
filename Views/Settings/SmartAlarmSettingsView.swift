import SwiftUI

struct SmartAlarmSettingsView: View {
    @ObservedObject private var service = SmartAlarmService.shared

    @State private var windowStartDate: Date = Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: Date()) ?? Date()
    @State private var windowEndDate: Date   = Calendar.current.date(bySettingHour: 7, minute: 0,  second: 0, of: Date()) ?? Date()

    var body: some View {
        ZStack {
            AmbientBackground(color: .indigo)

            List {
                Section("Alarme") {
                    toggleRow
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.white.opacity(0.06))

                if service.isEnabled {
                    Section("Fenêtre de réveil") {
                        DatePicker("Début", selection: $windowStartDate, displayedComponents: .hourAndMinute)
                            .colorScheme(.dark)
                            .foregroundColor(.white)
                            .onChange(of: windowStartDate) { _, _ in commitWindowChange() }

                        DatePicker("Fin", selection: $windowEndDate, displayedComponents: .hourAndMinute)
                            .colorScheme(.dark)
                            .foregroundColor(.white)
                            .onChange(of: windowEndDate) { _, _ in commitWindowChange() }
                    }
                    .listRowBackground(Color.appCard)
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Comment ça fonctionne") {
                        howItWorksView
                    }
                    .listRowBackground(Color.appCard)
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Statut") {
                        alarmStateRow
                    }
                    .listRowBackground(Color.appCard)
                    .listRowSeparatorTint(Color.white.opacity(0.06))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Réveil intelligent")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { syncPickersFromService() }
    }

    // MARK: - Rows

    private var toggleRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .foregroundColor(.indigo)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Réveil intelligent")
                    .font(.appBody.weight(.medium))
                    .foregroundColor(.white)
                Text("Alarme sur le plus proche point de cycle (90 min)")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.45))
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { service.isEnabled },
                set: { newVal in Task { if newVal { await service.enable() } else { await service.disable() } } }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var alarmStateRow: some View {
        HStack(spacing: 10) {
            Image(systemName: stateIcon)
                .font(.system(size: 14))
                .foregroundColor(stateColor)
                .frame(width: 20)
            Text(stateLabel)
                .font(.system(size: 14))
                .foregroundColor(stateColor)
        }
    }

    // MARK: - State display

    private var stateIcon: String {
        switch service.state {
        case .armed:               return "alarm.fill"
        case .notArmed:            return "moon.zzz"
        case .authorizationDenied: return "exclamationmark.triangle.fill"
        case .disabled:            return "slash.circle"
        }
    }

    private var stateColor: Color {
        switch service.state {
        case .armed:               return .green
        case .notArmed:            return Color(white: 0.5)
        case .authorizationDenied: return .orange
        case .disabled:            return Color(white: 0.3)
        }
    }

    private var stateLabel: String {
        switch service.state {
        case .armed(let at):
            let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
            return "Armé — \(fmt.string(from: at))"
        case .notArmed:
            return "Non armé — tapez « Armer réveil cyclique » sur le tableau de bord au moment du coucher (dès 20h)"
        case .authorizationDenied:
            return "Permission refusée — activer dans Réglages > VinceSeven"
        case .disabled:
            return "Désactivé"
        }
    }

    // MARK: - Mode d'emploi

    private var howItWorksView: some View {
        VStack(alignment: .leading, spacing: 10) {
            howStep("1", "Réglez la fenêtre de réveil ci-dessus (ex. 6h30–7h00).")
            howStep("2", "Au coucher, tapez « Armer réveil cyclique » sur le tableau de bord — visible de 20h à 3h.")
            howStep("3", "L'alarme se place à la fin d'un cycle de 90 min dans votre fenêtre. Si aucun cycle n'y tombe, elle sonne à la borne de fin.")
            howStep("4", "Une fois armée, l'alarme sonne quoi qu'il arrive — app fermée, mode silencieux, Focus.")

            Text("Pas de tap au coucher = pas d'alarme.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(white: 0.4))
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func howStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.appCaption.weight(.bold))
                .foregroundColor(AppTheme.shared.accent)
                .frame(width: 14, alignment: .center)
            Text(text)
                .font(.appLabel)
                .foregroundColor(Color(white: 0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func syncPickersFromService() {
        let cal = Calendar.current
        windowStartDate = cal.date(bySettingHour: service.windowStartHour,
                                   minute: service.windowStartMinute,
                                   second: 0, of: Date()) ?? windowStartDate
        windowEndDate   = cal.date(bySettingHour: service.windowEndHour,
                                   minute: service.windowEndMinute,
                                   second: 0, of: Date()) ?? windowEndDate
    }

    private func commitWindowChange() {
        let cal = Calendar.current
        Task {
            await service.updateWindow(
                startHour:   cal.component(.hour,   from: windowStartDate),
                startMinute: cal.component(.minute, from: windowStartDate),
                endHour:     cal.component(.hour,   from: windowEndDate),
                endMinute:   cal.component(.minute, from: windowEndDate)
            )
        }
    }
}
