import SwiftUI

struct MoreView: View {
    @StateObject private var api = APIService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .purple)

                List {
                    Section("IA") {
                        MoreRow(icon: "brain.head.profile", color: .purple, title: "Intelligence") { IntelligenceView() }
                    }
                    .listRowBackground(glassRowBG(.purple))
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Entraînement") {
                        MoreRow(icon: "chart.bar.fill",        color: .blue,   title: "Stats")        { StatsView() }
                        MoreRow(icon: "target",                color: .orange, title: "Objectifs")    { ObjectifsView() }
                        MoreRow(icon: "figure.run",            color: .red,    title: "HIIT")         { HIITHistoriqueView() }
                        MoreRow(icon: "list.bullet.clipboard", color: .teal,   title: "Programme")    { ProgrammeView() }
                        MoreRow(icon: "star.fill",             color: .yellow, title: "XP & Niveau")  { XPView() }
                    }
                    .listRowBackground(glassRowBG(.blue))
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Corps & Santé") {
                        MoreRow(icon: "heart.text.square.fill", color: .cyan,   title: "Health Dashboard") { HealthDashboardView() }
                        MoreRow(icon: "scalemass.fill",         color: .green,  title: "Body Comp")        { BodyCompView() }
                        MoreRow(icon: "fork.knife",             color: .orange, title: "Nutrition")        { NutritionView() }
                        MoreRow(icon: "figure.run",             color: .teal,   title: "Cardio")           { CardioView() }
                        MoreRow(icon: "moon.zzz.fill",         color: .indigo, title: "Récupération")     { RecoveryView() }
                        MoreRow(icon: "brain.head.profile",    color: .purple, title: "Stress (PSS)")     { PSSView() }
                        MoreRow(icon: "face.smiling.fill",     color: .mint,   title: "Santé Mentale")    { MentalHealthView() }
                    }
                    .listRowBackground(glassRowBG(.green))
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Divers") {
                        MoreRow(icon: "note.text",        color: .blue,   title: "Notes")      { NotesView() }
                        MoreRow(icon: "shippingbox.fill", color: .gray,   title: "Inventaire") { InventaireView() }
                        MoreRow(icon: "person.fill",      color: .purple, title: "Profil")     { ProfileView() }
                    }
                    .listRowBackground(glassRowBG(.gray))
                    .listRowSeparatorTint(Color.white.opacity(0.06))
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Plus")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func glassRowBG(_ color: Color) -> some View {
        ZStack {
            Color(hex: "11111c")
            LinearGradient(
                colors: [color.opacity(0.04), .clear],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }
}

struct MoreRow<Destination: View>: View {
    let icon: String
    let color: Color
    let title: String
    @ViewBuilder let destination: () -> Destination
    @State private var pressed = false

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.25), color.opacity(0.12)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .shadow(color: color.opacity(0.2), radius: 4, y: 2)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 5)
        }
    }
}
