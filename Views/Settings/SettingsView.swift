import SwiftUI

struct SettingsView: View {
    var body: some View {
        ZStack {
            AmbientBackground(color: .statusPurple)

            List {
                Section("Personnalisation") {
                    MoreRow(icon: "paintpalette.fill", color: .statusCyan,
                            title: "Affichage",
                            subtitle: "Thèmes, atmosphère et unités") { DisplaySettingsView() }
                }
                .listRowBackground(glassRowBG(.statusCyan))
                .listRowSeparatorTint(Color.appSeparator)

                Section("Activité & Santé") {
                    MoreRow(icon: "dumbbell.fill", color: Color.forge,
                            title: "Entraînement",
                            subtitle: "Séances, progression et échauffement") { TrainingSettingsView() }
                    MoreRow(icon: "fork.knife", color: .statusYellow,
                            title: "Nutrition",
                            subtitle: "Macros, cibles et journée nutritionnelle") { NutritionSettingsDestination() }
                    MoreRow(icon: "heart.text.square.fill", color: .statusGreen,
                            title: "Récupération & Sommeil",
                            subtitle: "Objectif sommeil, HRV et horaires") { RecoverySettingsView() }
                    MoreRow(icon: "figure.run", color: .statusCyan,
                            title: "Cardio",
                            subtitle: "FC max, objectif hebdo") { CardioSettingsView() }
                    MoreRow(icon: "alarm.fill", color: .statusPurple,
                            title: "Réveil intelligent",
                            subtitle: "Cycles 90 min, fenêtre personnalisée") { SmartAlarmSettingsView() }
                }
                .listRowBackground(glassRowBG(Color.forge))
                .listRowSeparatorTint(Color.appSeparator)

                Section("Application") {
                    MoreRow(icon: "bell.badge.fill", color: .statusRed,
                            title: "Notifications",
                            subtitle: "Rappels et alertes") { NotificationCenterView() }
                    MoreRow(icon: "externaldrive.fill", color: .statusBlue,
                            title: "Données & Santé",
                            subtitle: "HealthKit et données de l’app") { HealthDataSettingsView() }
                }
                .listRowBackground(glassRowBG(.statusBlue))
                .listRowSeparatorTint(Color.appSeparator)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Paramètres")
        .navigationBarTitleDisplayMode(.large)
    }

    private func glassRowBG(_ color: Color) -> some View {
        Color.appCard
    }
}
