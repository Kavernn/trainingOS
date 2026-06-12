import SwiftUI

struct HealthDataSettingsView: View {
    var body: some View {
        ZStack {
            AmbientBackground(color: .pink)

            List {
                Section("HealthKit") {
                    HStack(spacing: 12) {
                        settingsIcon("heart.text.square.fill", color: .pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Permissions HealthKit").font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
                            Text("Gérer depuis les Réglages iOS > Santé > Accès aux apps").font(.appCaption).foregroundColor(.gray.opacity(0.55))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14))
                            .foregroundColor(.gray.opacity(0.5))
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)

                Section("Données") {
                    HStack(spacing: 12) {
                        settingsIcon("square.and.arrow.up.fill", color: .gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exporter mes données").font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
                            Text("Bientôt disponible").font(.appCaption).foregroundColor(.gray.opacity(0.55))
                        }
                        Spacer()
                        Text("Bientôt")
                            .font(.appCaption.weight(.medium))
                            .foregroundColor(.gray.opacity(0.5))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 3)
                }
                .listRowBackground(Color.appCard)
                .listRowSeparatorTint(Color.appSeparator)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Données & Santé")
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
                .font(.appLabel.weight(.semibold))
                .foregroundColor(color)
        }
    }
}
