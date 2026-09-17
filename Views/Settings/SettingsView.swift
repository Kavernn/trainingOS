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
                            title: "Santé & récupération",
                            subtitle: "Sommeil, HRV, cardio et réveil") { HealthRecoverySettingsView() }
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

struct HealthRecoverySettingsView: View {
    @AppStorage("steps_daily_goal") private var stepsGoal: Int = 10000

    private let stepsOptions = [5000, 7500, 8000, 10000, 12000, 15000]

    var body: some View {
        ZStack {
            AmbientBackground(color: .statusGreen)

            List {
                Section("Récupération") {
                    MoreRow(icon: "moon.zzz.fill", color: .statusPurple,
                            title: "Sommeil & HRV",
                            subtitle: "Objectif sommeil, sensibilité HRV et horaires") {
                        RecoverySettingsView()
                    }
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)

                Section("Cardio") {
                    MoreRow(icon: "figure.run", color: .statusCyan,
                            title: "Cardio & objectifs",
                            subtitle: "FC max et objectifs cardio") {
                        CardioSettingsView()
                    }
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)

                Section("Sommeil") {
                    MoreRow(icon: "alarm.fill", color: .statusPurple,
                            title: "Réveil intelligent",
                            subtitle: "Fenêtre de réveil et activation") {
                        SmartAlarmSettingsView()
                    }
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)

                Section("Activité") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.walk")
                                .font(.appBody.weight(.semibold))
                                .foregroundColor(.statusGreen)
                                .frame(width: 36, height: 36)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Objectif quotidien de pas")
                                    .font(.appBody.weight(.medium))
                                    .foregroundColor(.appTextPrimary)
                                Text("Affiché dans le tableau de bord santé")
                                    .font(.appCaption)
                                    .foregroundColor(.gray.opacity(0.6))
                            }

                            Spacer()

                            Text(stepsGoal.formatted())
                                .font(.appLabel.weight(.semibold))
                                .foregroundColor(.statusGreen)
                        }

                        Picker("Objectif de pas", selection: $stepsGoal) {
                            ForEach(stepsOptions, id: \.self) { steps in
                                Text(steps.formatted()).tag(steps)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Santé & récupération")
        .navigationBarTitleDisplayMode(.large)
    }
}
