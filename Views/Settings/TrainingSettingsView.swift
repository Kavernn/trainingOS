import SwiftUI

struct TrainingSettingsView: View {
    @AppStorage("auto_start_rest_timer") private var autoStartTimer = false
    @AppStorage("show_rir_column")       private var showRIRColumn  = false
    @AppStorage("increment_upper_kg")    private var upperKg: Double = 1.25
    @AppStorage("increment_lower_kg")    private var lowerKg: Double = 2.5
    @AppStorage("increment_upper_lbs")   private var upperLbs: Double = 2.5
    @AppStorage("increment_lower_lbs")   private var lowerLbs: Double = 5.0
    @AppStorage("warmup_pct_1")          private var warmupPct1: Int = 40
    @AppStorage("warmup_pct_2")          private var warmupPct2: Int = 60
    @AppStorage("warmup_pct_3")          private var warmupPct3: Int = 80
    @ObservedObject private var units = UnitSettings.shared

    var body: some View {
        ZStack {
            AmbientBackground(color: Color.forge)

            List {
                Section("Séances") {
                    Toggle(isOn: $autoStartTimer) {
                        settingsLabel(icon: "timer", color: Color.forge,
                                      title: "Timer automatique entre les sets",
                                      subtitle: "Lance le chrono dès qu'un set est loggé")
                    }
                    .tint(Color.forge)
                    Toggle(isOn: $showRIRColumn) {
                        settingsLabel(icon: "gauge.medium", color: Color.forge,
                                      title: "Afficher la colonne RIR",
                                      subtitle: "Reps In Reserve dans la carte d'exercice")
                    }
                    .tint(Color.forge)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.white.opacity(0.06))

                Section("Progression") {
                    if units.isKg {
                        stepperRow(icon: "arrow.up", color: .blue,
                                   title: "Incrément upper body",
                                   subtitle: "Épaules, pecs, dos, bras",
                                   value: $upperKg,
                                   step: 0.25, range: 0.25...5.0,
                                   unit: "kg")
                        stepperRow(icon: "arrow.up.circle", color: .teal,
                                   title: "Incrément lower body",
                                   subtitle: "Squat, soulevé de terre, leg press",
                                   value: $lowerKg,
                                   step: 0.5, range: 0.5...10.0,
                                   unit: "kg")
                    } else {
                        stepperRow(icon: "arrow.up", color: .blue,
                                   title: "Incrément upper body",
                                   subtitle: "Épaules, pecs, dos, bras",
                                   value: $upperLbs,
                                   step: 0.5, range: 0.5...10.0,
                                   unit: "lbs")
                        stepperRow(icon: "arrow.up.circle", color: .teal,
                                   title: "Incrément lower body",
                                   subtitle: "Squat, soulevé de terre, leg press",
                                   value: $lowerLbs,
                                   step: 1.0, range: 1.0...20.0,
                                   unit: "lbs")
                    }
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.white.opacity(0.06))

                Section("Échauffement") {
                    warmupRow(label: "Set 1", pct: $warmupPct1, range: 10...70)
                    warmupRow(label: "Set 2", pct: $warmupPct2, range: 20...85)
                    warmupRow(label: "Set 3", pct: $warmupPct3, range: 40...95)
                    Text("Appliqués sur le poids de travail actuel pour générer les sets d'échauffement.")
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.6))
                        .listRowBackground(Color.clear)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.white.opacity(0.06))
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Entraînement")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func settingsLabel(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.12)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.appBody.weight(.medium)).foregroundColor(.white)
                Text(subtitle).font(.appCaption).foregroundColor(.gray.opacity(0.55))
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func stepperRow(icon: String, color: Color, title: String, subtitle: String,
                             value: Binding<Double>, step: Double, range: ClosedRange<Double>, unit: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.12)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.appBody.weight(.medium)).foregroundColor(.white)
                Text(subtitle).font(.appCaption).foregroundColor(.gray.opacity(0.55))
            }
            Spacer()
            Stepper(
                value: value,
                in: range,
                step: step
            ) {
                Text(value.wrappedValue.truncatingRemainder(dividingBy: 1) == 0
                     ? "\(Int(value.wrappedValue)) \(unit)"
                     : String(format: "%.2g \(unit)", value.wrappedValue))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func warmupRow(label: String, pct: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label)
                .font(.appBody.weight(.medium))
                .foregroundColor(.white)
                .frame(width: 40, alignment: .leading)
            Slider(value: Binding(
                get: { Double(pct.wrappedValue) },
                set: { pct.wrappedValue = Int($0) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 5)
            .tint(Color.forge)
            Text("\(pct.wrappedValue)%")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.forge)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }
}
