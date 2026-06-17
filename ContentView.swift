import SwiftUI
import Combine
import UIKit

struct ContentView: View {
    let themeToken: UUID
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var sync    = SyncManager.shared
    @State private var selectedTab   = 1

    init(themeToken: UUID = UUID()) {
        self.themeToken = themeToken
        // iOS 26+: skip UIKit appearance — Liquid Glass manages bar styling natively.
        // Setting UITabBarAppearance/UINavigationBarAppearance via UIKit proxy on iOS 26
        // conflicts with the Liquid Glass visual style system.
        guard #unavailable(iOS 26) else { return }

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance   = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance          = nav
        UINavigationBar.appearance().scrollEdgeAppearance        = nav
        UINavigationBar.appearance().compactAppearance           = nav
        UINavigationBar.appearance().compactScrollEdgeAppearance = nav
    }

    var body: some View {
#if targetEnvironment(macCatalyst)
        MacContentView(network: network, sync: sync)
#else
        iOSContentView(network: network, sync: sync, selectedTab: $selectedTab)
            .id(themeToken)
#endif
    }
}

// MARK: - iOS layout (TabView)

private struct iOSContentView: View {
    @ObservedObject var network: NetworkMonitor
    @ObservedObject var sync: SyncManager
    @ObservedObject private var api      = APIService.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var theme    = AppTheme.shared
    @Binding var selectedTab: Int

    private var seanceBadge: Int {
        guard let dash = api.dashboard else { return 0 }
        let low = dash.today.lowercased()
        let isRest = low.contains("repos") || low.contains("rest") || low.contains("recovery")
        return (!dash.alreadyLoggedToday && !isRest) ? 1 : 0
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            IntelligenceView(onOpenSession: { selectedTab = 2 })
                .tag(0)
                .tabItem { Label("Coach", systemImage: "brain.head.profile") }
            DashboardView(onOpenSession: { selectedTab = 2 })
                .tag(1)
                .tabItem { Label("Aujourd'hui", systemImage: "sun.horizon.fill") }
                .badge(sync.pendingCount > 0 ? sync.pendingCount : 0)
            SeanceView()
                .tag(2)
                .tabItem { Label("Séance", systemImage: "dumbbell.fill") }
                .badge(seanceBadge)
            ProgrammeView()
                .tag(3)
                .tabItem { Label("Programme", systemImage: "list.bullet.clipboard") }
            MoreView()
                .tag(4)
                .tabItem { Label("Plus", systemImage: "ellipsis.circle.fill") }
                .badge(appState.ritualTodayNotDone ? 1 : 0)
        }
        .overlay(alignment: .top) { offlineBanner }
        .overlay(alignment: .bottom) { offlineToast }
        .tint(theme.accent)
        .task { await appState.checkDNAEvolution() }
        .fullScreenCover(item: $appState.pendingDNAEvolution) { event in
            DNAEvolutionSheet(event: event, onDismiss: appState.acknowledgeDNAEvolution)
        }
        .globalActionFeedback()
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sync.offlineToast)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToIntelligence)) { _ in
            selectedTab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToRecovery)) { _ in
            selectedTab = 4
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToNutrition)) { _ in
            selectedTab = 4
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSeance)) { _ in
            selectedTab = 2
        }
        .onReceive(appState.$pendingDeepLink.compactMap { $0 }) { link in
            switch link {
            case "intelligence": selectedTab = 0
            case "warroom":      selectedTab = 0  // War Room is inside IntelligenceView
            case "dashboard":    selectedTab = 1
            case "seance":       selectedTab = 2
            case "more":         selectedTab = 4
            default: break
            }
            appState.pendingDeepLink = nil
        }
    }

    @ViewBuilder private var offlineBanner: some View {
        if !network.isOnline {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash").font(.appCaption.weight(.semibold))
                Text("Hors-ligne — données en cache").font(.appCaption.weight(.medium))
            }
            .foregroundColor(.appTextPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.appCard)
                    .overlay(Capsule().stroke(Color.orange.opacity(0.55), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .safeAreaPadding(.top)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: network.isOnline)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var offlineToast: some View {
        if let msg = sync.offlineToast {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.appLabel.weight(.semibold))
                Text(msg).font(.appLabel).multilineTextAlignment(.leading)
            }
            .foregroundColor(.appTextPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.15).opacity(0.95))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .safeAreaPadding(.bottom)
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
    case dashboard, seance, nutrition
    // IA
    case intelligence
    // Entraînement
    case programme, stats, timer, hiit, historique, xp
    // Corps & Santé
    case healthDashboard, bodyComp, cardio, recovery, pss, mentalHealth
    // Divers
    case notes, inventaire, profil

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:      return "Aujourd'hui"
        case .seance:         return "Séance"
        case .programme:      return "Programme"
        case .timer:          return "Timer"
        case .intelligence:   return "Intelligence"
        case .stats:          return "Stats"
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
        case .inventaire:     return "Catalogue"
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
    MacSidebarSection(title: "Principal",      pages: [.intelligence, .dashboard, .seance, .nutrition]),
    MacSidebarSection(title: "Entraînement",   pages: [.programme, .stats, .timer, .hiit, .historique, .xp]),
    MacSidebarSection(title: "Corps & Santé",  pages: [.healthDashboard, .bodyComp, .cardio, .recovery, .pss, .mentalHealth]),
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
                            .font(.appMicro.weight(.semibold))
                            .tracking(1.5)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 4)

                        ForEach(section.pages) { page in
                            Button { selected = page } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: page.icon)
                                        .font(.appLabel)
                                        .foregroundColor(selected == page ? page.color : .gray)
                                        .frame(width: 20)
                                    Text(page.label)
                                        .font(.appLabel.weight(selected == page ? .semibold : .regular))
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
                            Image(systemName: "wifi.slash").font(.appCaption.weight(.semibold))
                            Text("Hors-ligne — données en cache").font(.appCaption.weight(.medium))
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
        case .hiit:            HIITHistoriqueView()
        case .historique:      HistoriqueView()
        case .xp:              XPView()
        case .healthDashboard: HealthDashboardView()
        case .bodyComp:        BodyCompView()
        case .nutrition:       NutritionView()
        case .cardio:          CardioView()
        case .recovery:        RecoveryView()
        case .pss:             PSSView()
        case .mentalHealth:    MentalAmeView()
        case .notes:           NotesView()
        case .inventaire:      CatalogueView()
        case .profil:          ProfileView()
        }
    }
}
#endif
