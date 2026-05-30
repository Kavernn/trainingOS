import SwiftUI

struct MoreView: View {
    @ObservedObject private var api      = APIService.shared
    @ObservedObject private var appState = AppState.shared
    @AppStorage("auto_start_rest_timer") private var autoStartTimer = false
    @AppStorage("show_rir_column") private var showRIRColumn = false
    @State private var phoenixStreak: Int = 0
    @State private var showRitual = false
    @State private var showNutritionDirect = false
    @State private var showRecoveryDirect = false

    private var ritualSubtitle: String? {
        if phoenixStreak >= 2 { return "🔥 \(phoenixStreak) jours consécutifs" }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: .orange)

                List {
                    Section("Quotidien") {
                        // RitualView a son propre NavigationStack — fullScreenCover évite la collision
                        Button {
                            showRitual = true
                        } label: {
                            moreRowLabel(icon: "flame.fill", color: Color(hex: "FF2D20"),
                                         title: "Rituel quotidien", subtitle: ritualSubtitle,
                                         badge: appState.ritualTodayNotDone)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .fullScreenCover(isPresented: $showRitual, onDismiss: {
                            phoenixStreak = 0
                            Task { phoenixStreak = (try? await APIService.shared.fetchPhoenixStats())?.phoenixStreak ?? 0 }
                        }) {
                            RitualView()
                        }
                        MoreRow(icon: "fork.knife",      color: .orange, title: "Nutrition")    { NutritionView() }
                        MoreRow(icon: "bed.double.fill", color: .purple, title: "Sommeil")      { SleepView() }
                        MoreRow(icon: "moon.zzz.fill",  color: .blue,   title: "Récupération") { RecoveryView() }
                        MoreRow(icon: "wind",            color: Color.moonlight.opacity(0.7),
                                title: "The Void", subtitle: "Respiration, méditation & journal") { SpiritView() }
                    }
                    .listRowBackground(glassRowBG(Color(hex: "FF2D20")))
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Entraînement") {
                        MoreRow(icon: "calendar",              color: .teal,                    title: "Historique") { HistoriqueView() }
                        MoreRow(icon: "target",                color: .orange,                  title: "Objectifs")  { ObjectifsView() }
                        MoreRow(icon: "chart.bar.fill",        color: .blue,                    title: "Stats")      { StatsView() }
                        MoreRow(icon: "timer",                 color: .orange,                  title: "Timer")      { TimerView() }
                        MoreRow(icon: "mappin.and.ellipse",    color: Color(hex: "F59E0B"),     title: "Gym Finder") { GymFinderView() }
                    }
                    .listRowBackground(glassRowBG(.blue))
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Corps & Santé") {
                        MoreRow(icon: "heart.text.square.fill", color: .cyan,   title: "Tableau santé")         { HealthDashboardView() }
                        MoreRow(icon: "scalemass.fill",         color: .green,  title: "Composition")           { BodyCompView() }
                        MoreRow(icon: "figure.run",             color: .teal,   title: "Cardio")                { CardioView() }
                        MoreRow(icon: "brain.head.profile",    color: .purple, title: "Charge mentale (PSS)")  { PSSView() }
                        MoreRow(icon: "face.smiling.fill",     color: .mint,   title: "Santé Mentale")         { MentalHealthView() }
                    }
                    .listRowBackground(glassRowBG(.green))
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Esprit & Identité") {
                        MoreRow(icon: "lock.shield.fill",     color: Color.forge,                   title: "War Room",   subtitle: "Résistance aux habitudes difficiles") { WarRoomGateView() }
                        MoreRow(icon: "staroflife.fill",      color: .indigo,                       title: "Workout DNA")   { WorkoutDNASection() }
                        MoreRow(icon: "star.fill",            color: .yellow,                       title: "XP & Niveau")   { XPView() }
                        MoreRow(icon: "book.pages.fill",      color: Color(hex: "FF2D20").opacity(0.7), title: "Biographie", subtitle: "Timeline de tes intentions") { RitualBiographyView() }
                        MoreRow(icon: "calendar.badge.clock", color: .teal,                         title: "Mes chapitres") { SeasonView() }
                        MoreRow(icon: "seal.fill",            color: .black,                        title: "Mon serment")   { OathGateView() }
                    }
                    .listRowBackground(glassRowBG(.indigo))
                    .listRowSeparatorTint(Color.white.opacity(0.06))

                    Section("Réglages") {
                        MoreRow(icon: "person.fill",      color: .purple, title: "Profil")        { ProfileView() }
                        MoreRow(icon: "bell.badge.fill",  color: .purple, title: "Notifications", subtitle: "Gérer tous les rappels") { NotificationCenterView() }
                        Toggle(isOn: $autoStartTimer) {
                            Label("Timer automatique entre les sets", systemImage: "timer")
                        }
                        .tint(.orange)
                        Toggle(isOn: $showRIRColumn) {
                            Label("Afficher la colonne RIR", systemImage: "gauge.medium")
                        }
                        .tint(.orange)
                        MoreRow(icon: "shippingbox.fill", color: .gray, title: "Inventaire") { InventaireView() }
                        MoreRow(icon: "note.text",        color: .blue, title: "Notes")      { NotesView() }
                    }
                    .listRowBackground(glassRowBG(.gray))
                    .listRowSeparatorTint(Color.white.opacity(0.06))
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Plus")
            .navigationBarTitleDisplayMode(.large)
            .task {
                phoenixStreak = (try? await APIService.shared.fetchPhoenixStats())?.phoenixStreak ?? 0
            }
            .fullScreenCover(isPresented: $showNutritionDirect) { NutritionView() }
            .fullScreenCover(isPresented: $showRecoveryDirect)  { RecoveryView() }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToNutrition)) { _ in
                showNutritionDirect = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToRecovery)) { _ in
                showRecoveryDirect = true
            }
        }
    }

    private func glassRowBG(_ color: Color) -> some View {
        Color.appCard
    }

    // Label identique à MoreRow mais sans NavigationLink (pour les vues avec NavigationStack propre)
    @ViewBuilder
    private func moreRowLabel(icon: String, color: Color, title: String, subtitle: String?, badge: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                    .shadow(color: color.opacity(0.2), radius: 4, y: 2)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
                if badge {
                    Circle().fill(Color.orange).frame(width: 9, height: 9).offset(x: 3, y: -3)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 16, weight: .medium)).foregroundColor(.white)
                if let sub = subtitle {
                    Text(sub).font(.system(size: 11)).foregroundColor(.gray.opacity(0.6))
                }
            }
            if badge {
                Spacer()
                Text("À faire")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12)).clipShape(Capsule())
            }
        }
        .padding(.vertical, 5)
    }
}

struct MoreRow<Destination: View>: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String? = nil
    var badge: Bool = false
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
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
                    if badge {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 9, height: 9)
                            .offset(x: 3, y: -3)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
                if badge {
                    Spacer()
                    Text("À faire")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 5)
        }
    }
}
