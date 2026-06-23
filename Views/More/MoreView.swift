import SwiftUI
import Combine

struct MoreView: View {
    @ObservedObject private var api      = APIService.shared
    @ObservedObject private var appState = AppState.shared
    @State private var showRitual = false
    @State private var showNutritionDirect = false
    @State private var showRecoveryDirect = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(color: Color.forge)

                List {
                    Section {
                        NavigationLink(destination: ProfileView()) {
                            HStack(spacing: 14) {
                                profileAvatar
                                    .frame(width: 52, height: 52)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(api.dashboard?.profile.name ?? "Profil")
                                        .font(.appBody.weight(.semibold))
                                        .foregroundColor(.appTextPrimary)
                                    Text("Voir le profil")
                                        .font(.appCaption)
                                        .foregroundColor(.gray.opacity(0.6))
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .listRowBackground(glassRowBG(.statusPurple))
                    .listRowSeparatorTint(Color.appSeparator)

                    Section("Apparence") {
                        MoreRow(icon: "slider.horizontal.3", color: .statusCyan, title: "Affichage & Thème",
                                subtitle: "Thème, kg/lbs, objectif de pas") { DisplaySettingsView() }
                    }
                    .listRowBackground(glassRowBG(.statusCyan))
                    .listRowSeparatorTint(Color.appSeparator)

                    Section("Quotidien") {
                        // RitualView a son propre NavigationStack — fullScreenCover évite la collision
                        Button {
                            showRitual = true
                        } label: {
                            moreRowLabel(icon: "flame.fill", color: Color.appDanger,
                                         title: "Engagements", subtitle: nil,
                                         badge: appState.ritualTodayNotDone)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .fullScreenCover(isPresented: $showRitual) {
                            RitualView()
                        }
                        MoreRow(icon: "fork.knife",      color: Color.forge, title: "Nutrition")    { NutritionView() }
                        MoreRow(icon: "bolt.heart.fill", color: Color.forge, title: "Énergie & Récupération") { EnergyRecoveryView() }
                    }
                    .listRowBackground(glassRowBG(Color.appDanger))
                    .listRowSeparatorTint(Color.appSeparator)

                    Section("Entraînement") {
                        MoreRow(icon: "shippingbox.fill", color: .gray,   title: "Catalogue")    { CatalogueView() }
                        MoreRow(icon: "calendar",              color: .statusCyan,              title: "Historique") { HistoriqueView() }
                        MoreRow(icon: "chart.bar.fill",        color: .statusBlue,              title: "Stats")      { StatsView() }
                        MoreRow(icon: "note.text",             color: .statusBlue,              title: "Notes")      { NotesView() }
                        MoreRow(icon: "timer",                 color: Color.forge,                  title: "Timer")      { TimerView() }
                        MoreRow(icon: "mappin.and.ellipse",    color: Color.appWarning,     title: "Gym Finder") { GymFinderView() }
                    }
                    .listRowBackground(glassRowBG(.statusBlue))
                    .listRowSeparatorTint(Color.appSeparator)

                    Section("Corps & Santé") {
                        MoreRow(icon: "heart.text.square.fill", color: .statusCyan,    title: "Tableau santé")         { HealthDashboardView() }
                        MoreRow(icon: "scalemass.fill",         color: .appSuccess,    title: "Composition")           { BodyCompView() }
                        MoreRow(icon: "figure.run",             color: .statusCyan,    title: "Cardio")                { CardioView() }
                        MoreRow(icon: "brain.fill",            color: .statusCyan,    title: "Mental & Âme",
                                subtitle: "Mesures · Pratique · The Void")                { MentalAmeView() }
                    }
                    .listRowBackground(glassRowBG(.appSuccess))
                    .listRowSeparatorTint(Color.appSeparator)

                    Section("Esprit & Identité") {
                        MoreRow(icon: "lock.shield.fill",     color: Color.forge,                   title: "War Room",   subtitle: "Résistance aux habitudes difficiles") { WarRoomGateView() }
                        MoreRow(icon: "staroflife.fill",      color: .statusPurple,                 title: "Workout DNA")   { WorkoutDNASection() }
                        MoreRow(icon: "star.fill",            color: .statusYellow,                 title: "XP & Niveau")   { XPView() }
                    }
                    .listRowBackground(glassRowBG(.statusPurple))
                    .listRowSeparatorTint(Color.appSeparator)

                    Section("Réglages") {
                        MoreRow(icon: "gearshape.fill",   color: .statusPurple, title: "Paramètres",
                                subtitle: "Entraînement, nutrition, récupération…") { SettingsView() }
                    }
                    .listRowBackground(glassRowBG(.gray))
                    .listRowSeparatorTint(Color.appSeparator)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Plus")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(isPresented: $showNutritionDirect) { NutritionView() }
            .fullScreenCover(isPresented: $showRecoveryDirect)  { EnergyRecoveryView() }
            .onReceive(appState.$openRecoveryView.filter { $0 }) { _ in
                showRecoveryDirect = true
                appState.openRecoveryView = false
            }
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        let p = api.dashboard?.profile
        if let urlStr = p?.photoUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill().clipShape(Circle())
                default:
                    profileInitialsCircle
                }
            }
        } else if let b64 = p?.photoB64,
                  let data = Data(base64Encoded: b64.components(separatedBy: ",").last ?? ""),
                  let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill().clipShape(Circle())
        } else {
            profileInitialsCircle
        }
    }

    private var profileInitialsCircle: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color.statusPurple.opacity(0.35), Color.forge.opacity(0.25)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(api.dashboard?.profile.name?.prefix(1).uppercased() ?? "?")
                .font(.system(size: 22, weight: .black))
                .foregroundColor(.white)
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
                    .font(.appBody.weight(.semibold))
                    .foregroundColor(color)
                if badge {
                    Circle().fill(Color.forge).frame(width: 9, height: 9).offset(x: 3, y: -3)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.appBody.weight(.medium)).foregroundColor(.appTextPrimary)
                if let sub = subtitle {
                    Text(sub).font(.appCaption).foregroundColor(.gray.opacity(0.6))
                }
            }
            if badge {
                Spacer()
                Text("À faire")
                    .font(.appCaption.weight(.semibold)).foregroundColor(Color.forge)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.forge.opacity(0.12)).clipShape(Capsule())
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
                        .font(.appBody.weight(.semibold))
                        .foregroundColor(color)
                    if badge {
                        Circle()
                            .fill(Color.forge)
                            .frame(width: 9, height: 9)
                            .offset(x: 3, y: -3)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.appBody.weight(.medium))
                        .foregroundColor(.appTextPrimary)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.appCaption)
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
                if badge {
                    Spacer()
                    Text("À faire")
                        .font(.appCaption.weight(.semibold))
                        .foregroundColor(Color.forge)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.forge.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 5)
        }
    }
}
