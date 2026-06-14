import SwiftUI

struct SettingsView: View {
    var body: some View {
        ZStack {
            AmbientBackground(color: .purple)

            List {
                Section("Identité") {
                    MoreRow(icon: "person.fill", color: .purple,
                            title: "Mon profil",
                            subtitle: "Nom, âge, objectif, photo") { ProfileView() }
                }
                .listRowBackground(glassRowBG(.purple))
                .listRowSeparatorTint(Color.appSeparator)

                Section("Entraînement") {
                    MoreRow(icon: "dumbbell.fill", color: Color.forge,
                            title: "Entraînement",
                            subtitle: "Incréments, échauffement, RIR, timer") { TrainingSettingsView() }
                    MoreRow(icon: "fork.knife", color: .green,
                            title: "Nutrition",
                            subtitle: "Cibles calories, macros, fenêtre") { NutritionView() }
                    MoreRow(icon: "figure.run", color: .teal,
                            title: "Cardio",
                            subtitle: "FC max, objectif hebdo") { CardioSettingsView() }
                }
                .listRowBackground(glassRowBG(Color.forge))
                .listRowSeparatorTint(Color.appSeparator)

                Section("Récupération") {
                    MoreRow(icon: "bed.double.fill", color: .indigo,
                            title: "Récupération & Sommeil",
                            subtitle: "Objectif sommeil, HRV, horaires") { RecoverySettingsView() }
                    MoreRow(icon: "alarm.fill", color: .indigo,
                            title: "Réveil intelligent",
                            subtitle: "Cycles 90 min, fenêtre personnalisée") { SmartAlarmSettingsView() }
                }
                .listRowBackground(glassRowBG(.indigo))
                .listRowSeparatorTint(Color.appSeparator)

                Section("Préférences") {
                    MoreRow(icon: "bell.badge.fill", color: .red,
                            title: "Notifications",
                            subtitle: "Rappels, horaires, toggles") { NotificationCenterView() }
                    MoreRow(icon: "heart.text.square.fill", color: .pink,
                            title: "Données & Santé",
                            subtitle: "HealthKit, export") { HealthDataSettingsView() }
                }
                .listRowBackground(glassRowBG(.cyan))
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
