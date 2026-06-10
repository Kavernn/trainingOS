import SwiftUI

struct CardioSettingsView: View {
    @AppStorage("cardio_max_hr")           private var maxHR: Int = 190
    @AppStorage("cardio_weekly_goal_min")  private var weeklyGoalMin: Int = 150

    @State private var showMaxHRAlert = false
    @State private var maxHRInput: String = ""

    private var weeklyGoalLabel: String {
        let h = weeklyGoalMin / 60
        let m = weeklyGoalMin % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    private let weeklyGoalOptions = [60, 90, 120, 150, 180, 210, 240, 300]

    var body: some View {
        ZStack {
            AmbientBackground(color: .teal)

            List {
                Section("Fréquence cardiaque") {
                    Button {
                        maxHRInput = "\(maxHR)"
                        showMaxHRAlert = true
                    } label: {
                        HStack(spacing: 12) {
                            settingsIcon("heart.fill", color: .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("FC max personnelle").font(.appBody.weight(.medium)).foregroundColor(.white)
                                Text("Utilisée pour calculer vos zones cardio").font(.appCaption).foregroundColor(.gray.opacity(0.55))
                            }
                            Spacer()
                            Text("\(maxHR) bpm")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.forge)
                            Image(systemName: "chevron.right")
                                .font(.appCaption)
                                .foregroundColor(.gray.opacity(0.4))
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        settingsIcon("info.circle.fill", color: .gray)
                        Text("Mesurée en sprint max ou test d'effort.\nFormule 220 − âge = estimation seulement.")
                            .font(.system(size: 12))
                            .foregroundColor(.gray.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Color.clear)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.white.opacity(0.06))

                Section("Objectif hebdomadaire") {
                    HStack(spacing: 12) {
                        settingsIcon("calendar.badge.checkmark", color: .teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Minutes de cardio par semaine").font(.appBody.weight(.medium)).foregroundColor(.white)
                            Text("Recommandation ACSM : 150 min/semaine").font(.appCaption).foregroundColor(.gray.opacity(0.55))
                        }
                    }

                    Picker("Objectif cardio", selection: $weeklyGoalMin) {
                        ForEach(weeklyGoalOptions, id: \.self) { mins in
                            let h = mins / 60
                            let m = mins % 60
                            let label = h == 0 ? "\(m) min" : (m == 0 ? "\(h)h" : "\(h)h \(m)m")
                            Text(label).tag(mins)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    .colorScheme(.dark)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.white.opacity(0.06))
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Cardio")
        .navigationBarTitleDisplayMode(.large)
        .alert("FC max personnelle", isPresented: $showMaxHRAlert) {
            TextField("bpm", text: $maxHRInput)
                .keyboardType(.numberPad)
            Button("Annuler", role: .cancel) {}
            Button("Enregistrer") {
                if let v = Int(maxHRInput), v >= 100, v <= 250 { maxHR = v }
            }
        } message: {
            Text("Entrez votre fréquence cardiaque maximale mesurée (bpm).")
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
}
