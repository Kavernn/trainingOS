import SwiftUI

struct CardioSettingsView: View {
    @AppStorage("cardio_max_hr")           private var maxHR: Int = 190

    @State private var showMaxHRAlert = false
    @State private var maxHRInput: String = ""

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
                            settingsIcon("heart.fill", color: .statusRed)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("FC max personnelle").font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
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
                .listRowSeparatorTint(Color.appSeparator)
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
