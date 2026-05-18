import SwiftUI

struct MoreView: View {
    @ObservedObject private var api = APIService.shared
    @AppStorage("auto_start_rest_timer") private var autoStartTimer = false
    @AppStorage("show_rir_column") private var showRIRColumn = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .orange)

                List {
                    Section("Rituel & Esprit") {
                        MoreRow(icon: "flame.fill",  color: Color(hex: "FF2D20"), title: "Rituel quotidien") { RitualView() }
                        MoreRow(icon: "wind",        color: Color.moonlight.opacity(0.7), title: "The Void") { SpiritView() }
                        MoreRow(icon: "calendar.badge.clock", color: .teal, title: "Mes chapitres") { SeasonView() }
                    }
                    .listRowBackground(glassRowBG(Color(hex: "FF2D20")))
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Terrain") {
                        MoreRow(icon: "mappin.and.ellipse", color: Color(hex: "F59E0B"), title: "Gym Finder") { GymFinderView() }
                    }
                    .listRowBackground(glassRowBG(Color(hex: "F59E0B")))
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Combat") {
                        MoreRow(icon: "chart.bar.fill",        color: .blue,   title: "Stats")           { StatsView() }
                        MoreRow(icon: "target",                color: .orange, title: "Objectifs")        { ObjectifsView() }
                        MoreRow(icon: "staroflife.fill",       color: .indigo, title: "Workout DNA")      { WorkoutDNASection() }
                        MoreRow(icon: "timer",                 color: .orange, title: "Timer")            { TimerView() }
                        MoreRow(icon: "figure.run",            color: .red,    title: "HIIT")             { HIITHistoriqueView() }
                        MoreRow(icon: "calendar",              color: .teal,   title: "Historique")       { HistoriqueView() }
                        MoreRow(icon: "star.fill",             color: .yellow, title: "XP & Niveau")      { XPView() }
                        MoreRow(icon: "cross.fill",            color: Color(hex: "8B6AFF"), title: "Graveyard") { GraveyardView() }
                    }
                    .listRowBackground(glassRowBG(.blue))
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Corps") {
                        MoreRow(icon: "heart.text.square.fill", color: .cyan,   title: "Tableau santé") { HealthDashboardView() }
                        MoreRow(icon: "scalemass.fill",         color: .green,  title: "Composition")      { BodyCompView() }
                        MoreRow(icon: "ruler.fill",             color: .teal,   title: "Calculateur Navy") { NavyCalculatorView() }
                        MoreRow(icon: "fork.knife",             color: .orange, title: "Nutrition")        { NutritionView() }
                        MoreRow(icon: "figure.run",             color: .teal,   title: "Cardio")           { CardioView() }
                        MoreRow(icon: "bed.double.fill",        color: .purple, title: "Sommeil")          { SleepView() }
                        MoreRow(icon: "moon.zzz.fill",         color: .blue,   title: "Récupération")     { RecoveryView() }
                        MoreRow(icon: "brain.head.profile",    color: .purple, title: "Charge mentale (PSS)") { PSSView() }
                        MoreRow(icon: "face.smiling.fill",     color: .mint,   title: "Santé Mentale")    { MentalHealthView() }
                    }
                    .listRowBackground(glassRowBG(.green))
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Session") {
                        Toggle(isOn: $autoStartTimer) {
                            Label("Timer automatique entre les sets", systemImage: "timer")
                        }
                        .tint(.orange)
                        Toggle(isOn: $showRIRColumn) {
                            Label("Afficher la colonne RIR", systemImage: "gauge.medium")
                        }
                        .tint(.orange)
                    }
                    .listRowBackground(glassRowBG(.orange))
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Réglages") {
                        MoreRow(icon: "shippingbox.fill", color: .gray,   title: "Inventaire") { InventaireView() }
                        MoreRow(icon: "note.text",        color: .blue,   title: "Notes")      { NotesView() }
                        MoreRow(icon: "person.fill",      color: .purple, title: "Profil")     { ProfileView() }
                        MoreRow(icon: "lock.shield.fill", color: Color.forge, title: "War Room")  { WarRoomGateView() }
                        MoreRow(icon: "seal.fill",        color: .black,  title: "Mon serment") { OathGateView() }
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
        Color.appCard
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
