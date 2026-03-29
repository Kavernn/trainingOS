import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var sync    = SyncManager.shared
    @State private var selectedTab   = 0

    var body: some View {
#if targetEnvironment(macCatalyst)
        MacContentView(network: network, sync: sync)
#else
        iOSContentView(network: network, sync: sync, selectedTab: $selectedTab)
#endif
    }
}

// MARK: - iOS layout (TabView)

private struct iOSContentView: View {
    @ObservedObject var network: NetworkMonitor
    @ObservedObject var sync: SyncManager
    @Binding var selectedTab: Int

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tag(0)
                .tabItem { Label("Accueil", systemImage: "house.fill") }
            SeanceView()
                .tag(1)
                .tabItem { Label("Séance", systemImage: "dumbbell.fill") }
            ProgrammeView()
                .tag(2)
                .tabItem { Label("Programme", systemImage: "list.bullet.clipboard") }
            TimerView()
                .tag(3)
                .tabItem { Label("Timer", systemImage: "timer") }
            MoreView()
                .tag(4)
                .tabItem { Label("Plus", systemImage: "ellipsis.circle.fill") }
        }
        .overlay(alignment: .top) { offlineBanner }
        .overlay(alignment: .bottom) { offlineToast }
        .tint(.orange)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sync.offlineToast)
    }

    @ViewBuilder private var offlineBanner: some View {
        if !network.isOnline {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash").font(.system(size: 11, weight: .semibold))
                Text("Hors-ligne — données en cache").font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(hex: "1c1c1e"))
                    .overlay(Capsule().stroke(Color.orange.opacity(0.55), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .padding(.top, 52)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: network.isOnline)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var offlineToast: some View {
        if let msg = sync.offlineToast {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13, weight: .semibold))
                Text(msg).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.leading)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.15).opacity(0.95))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .padding(.bottom, 90)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: msg)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Mac layout (NavigationSplitView)

#if targetEnvironment(macCatalyst)
private enum MacPage: String, Identifiable {
    // Principal
    case dashboard, seance, programme, timer
    // IA
    case intelligence
    // Entraînement
    case stats, objectifs, hiit, historique, xp
    // Corps & Santé
    case healthDashboard, bodyComp, nutrition, cardio, recovery, pss, mentalHealth
    // Divers
    case notes, inventaire, profil

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:      return "Accueil"
        case .seance:         return "Séance"
        case .programme:      return "Programme"
        case .timer:          return "Timer"
        case .intelligence:   return "Intelligence"
        case .stats:          return "Stats"
        case .objectifs:      return "Objectifs"
        case .hiit:           return "HIIT"
        case .historique:     return "Historique"
        case .xp:             return "XP & Niveau"
        case .healthDashboard:return "Health Dashboard"
        case .bodyComp:       return "Body Comp"
        case .nutrition:      return "Nutrition"
        case .cardio:         return "Cardio"
        case .recovery:       return "Récupération"
        case .pss:            return "Stress (PSS)"
        case .mentalHealth:   return "Santé Mentale"
        case .notes:          return "Notes"
        case .inventaire:     return "Inventaire"
        case .profil:         return "Profil"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:      return "house.fill"
        case .seance:         return "dumbbell.fill"
        case .programme:      return "list.bullet.clipboard"
        case .timer:          return "timer"
        case .intelligence:   return "brain.head.profile"
        case .stats:          return "chart.bar.fill"
        case .objectifs:      return "target"
        case .hiit:           return "figure.run"
        case .historique:     return "calendar"
        case .xp:             return "star.fill"
        case .healthDashboard:return "heart.text.square.fill"
        case .bodyComp:       return "scalemass.fill"
        case .nutrition:      return "fork.knife"
        case .cardio:         return "figure.run"
        case .recovery:       return "moon.zzz.fill"
        case .pss:            return "brain.head.profile"
        case .mentalHealth:   return "face.smiling.fill"
        case .notes:          return "note.text"
        case .inventaire:     return "shippingbox.fill"
        case .profil:         return "person.fill"
        }
    }

    var color: Color {
        switch self {
        case .dashboard:      return .orange
        case .seance:         return .orange
        case .programme:      return .orange
        case .timer:          return .orange
        case .intelligence:   return .purple
        case .stats:          return .blue
        case .objectifs:      return .orange
        case .hiit:           return .red
        case .historique:     return .teal
        case .xp:             return .yellow
        case .healthDashboard:return .cyan
        case .bodyComp:       return .green
        case .nutrition:      return .orange
        case .cardio:         return .teal
        case .recovery:       return .indigo
        case .pss:            return .purple
        case .mentalHealth:   return .mint
        case .notes:          return .blue
        case .inventaire:     return .gray
        case .profil:         return .purple
        }
    }
}

private struct MacSidebarSection {
    let title: String
    let pages: [MacPage]
}

private let macSections: [MacSidebarSection] = [
    MacSidebarSection(title: "Principal",      pages: [.dashboard, .seance, .programme, .timer]),
    MacSidebarSection(title: "IA",             pages: [.intelligence]),
    MacSidebarSection(title: "Entraînement",   pages: [.stats, .objectifs, .hiit, .historique, .xp]),
    MacSidebarSection(title: "Corps & Santé",  pages: [.healthDashboard, .bodyComp, .nutrition, .cardio, .recovery, .pss, .mentalHealth]),
    MacSidebarSection(title: "Divers",         pages: [.notes, .inventaire, .profil]),
]

private struct MacContentView: View {
    @ObservedObject var network: NetworkMonitor
    @ObservedObject var sync: SyncManager
    @State private var selected: MacPage = .dashboard

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(macSections, id: \.title) { section in
                        Text(section.title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 4)

                        ForEach(section.pages) { page in
                            Button { selected = page } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: page.icon)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(selected == page ? page.color : .gray)
                                        .frame(width: 20)
                                    Text(page.label)
                                        .font(.system(size: 14, weight: selected == page ? .semibold : .regular))
                                        .foregroundColor(selected == page ? .white : Color(white: 0.75))
                                    Spacer()
                                }
                                .padding(.vertical, 7)
                                .padding(.horizontal, 12)
                                .background(selected == page ? page.color.opacity(0.15) : Color.clear)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                        }
                    }
                    Spacer(minLength: 16)
                }
            }
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if !network.isOnline {
                        HStack(spacing: 6) {
                            Image(systemName: "wifi.slash").font(.system(size: 12, weight: .semibold))
                            Text("Hors-ligne — données en cache").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.9))
                        .allowsHitTesting(false)
                    }
                }
        }
    }

    @ViewBuilder private var detailView: some View {
        switch selected {
        case .dashboard:       DashboardView()
        case .seance:          SeanceView()
        case .programme:       ProgrammeView()
        case .timer:           TimerView()
        case .intelligence:    IntelligenceView()
        case .stats:           StatsView()
        case .objectifs:       ObjectifsView()
        case .hiit:            HIITHistoriqueView()
        case .historique:      HistoriqueView()
        case .xp:              XPView()
        case .healthDashboard: HealthDashboardView()
        case .bodyComp:        BodyCompView()
        case .nutrition:       NutritionView()
        case .cardio:          CardioView()
        case .recovery:        RecoveryView()
        case .pss:             PSSView()
        case .mentalHealth:    MentalHealthView()
        case .notes:           NotesView()
        case .inventaire:      InventaireView()
        case .profil:          ProfileView()
        }
    }
}
#endif
