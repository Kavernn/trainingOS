import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject private var units = UnitSettings.shared
    @AppStorage("steps_daily_goal")   private var stepsGoal: Int = 10000
    @AppStorage("hydration_goal_ml")  private var hydrationGoal: Int = 2500

    private let stepsOptions = [5000, 7500, 8000, 10000, 12000, 15000]

    private var hydrationLabel: String {
        if hydrationGoal >= 1000 {
            let l = Double(hydrationGoal) / 1000.0
            return l.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(l)) L"
                : String(format: "%.1f L", l)
        }
        return "\(hydrationGoal) mL"
    }

    var body: some View {
        ZStack {
            AmbientBackground(color: .cyan)

            List {
                Section("Unités de mesure") {
                    HStack(spacing: 12) {
                        settingsIcon("scalemass.fill", color: .cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unité de poids").font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                            Text("Appliqué à tous les exercices et métriques").font(.system(size: 11)).foregroundColor(.gray.opacity(0.55))
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { units.isKg },
                            set: { units.isKg = $0 }
                        )) {
                            Text("kg").tag(true)
                            Text("lbs").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                    }
                    .padding(.vertical, 3)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.white.opacity(0.06))

                Section("Activité") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            settingsIcon("figure.walk", color: .green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Objectif de pas quotidien").font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                                Text("Affiché dans le tableau de bord santé").font(.system(size: 11)).foregroundColor(.gray.opacity(0.55))
                            }
                            Spacer()
                            Text(stepsGoal.formatted())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.green)
                        }

                        Picker("Objectif de pas", selection: $stepsGoal) {
                            ForEach(stepsOptions, id: \.self) { n in
                                Text(n.formatted()).tag(n)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.white.opacity(0.06))

                Section("Nutrition") {
                    HStack(spacing: 12) {
                        settingsIcon("drop.fill", color: .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Objectif d'hydratation").font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                            Text("Non encore connecté au suivi — disponible bientôt").font(.system(size: 11)).foregroundColor(.gray.opacity(0.55))
                        }
                        Spacer()
                        Stepper(
                            value: $hydrationGoal,
                            in: 1000...5000,
                            step: 250
                        ) {
                            Text(hydrationLabel)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.white.opacity(0.06))
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Affichage & Unités")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func settingsIcon(_ icon: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
        }
    }
}
