import SwiftUI
import Combine
import UIKit

struct ContentView: View {
    let themeToken: UUID
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var sync    = SyncManager.shared
    @State private var selectedTab   = 0

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
            DashboardView(onOpenSession: { selectedTab = 1 })
                .tag(0)
                .tabItem { Label("Aujourd'hui", systemImage: "sun.horizon.fill") }
                .badge(sync.pendingCount > 0 ? sync.pendingCount : 0)
            SeanceView()
                .tag(1)
                .tabItem { Label("Séance", systemImage: "dumbbell.fill") }
                .badge(seanceBadge)
            ProgrammeView()
                .tag(2)
                .tabItem { Label("Programme", systemImage: "list.bullet.clipboard") }
            MoreView()
                .tag(3)
                .tabItem { Label("Plus", systemImage: "ellipsis.circle.fill") }
        }
        .overlay(alignment: .top) { offlineBanner }
        .overlay(alignment: .bottom) { offlineToast }
        .tint(theme.accent)
        .buttonStyle(ScaleButtonStyle())
        .task { await appState.checkDNAEvolution() }
        .task { await appState.checkYesterdayNutrition() }
        .fullScreenCover(item: $appState.pendingDNAEvolution) { event in
            DNAEvolutionSheet(event: event, onDismiss: appState.acknowledgeDNAEvolution)
        }
        .sheet(item: $appState.pendingNutritionCatchup) { prompt in
            NutritionCatchupSheet(prompt: prompt)
        }
        .globalActionFeedback()
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sync.offlineToast)
        .onReceive(appState.$pendingDeepLink.compactMap { $0 }) { link in
            switch link {
            case "warroom":   selectedTab = 3
            case "dashboard": selectedTab = 0
            case "seance":    selectedTab = 1
            case "more":      selectedTab = 3
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

// MARK: - Nutrition Catchup Sheet (estimation rétroactive de la veille)

private struct NutritionCatchupSheet: View {
    let prompt: NutritionCatchupPrompt
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pctCalories:  Double = 100
    @State private var pctProteines: Double = 100
    @State private var isCommitting = false
    @State private var errorMessage: String? = nil

    private var estimatedCalories: Int {
        Int((prompt.targetCalories * pctCalories / 100).rounded())
    }
    private var estimatedProteines: Int {
        Int((prompt.targetProteines * pctProteines / 100).rounded())
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Hier, tu as loggué \(prompt.entriesCount) entrée(s) totalisant \(Int(prompt.currentCalories)) kcal / \(Int(prompt.currentProteines)) g prot.")
                    .font(.appBody).foregroundColor(.gray)

                VStack(alignment: .leading, spacing: 8) {
                    Text("% des calories cibles (\(Int(prompt.targetCalories)) kcal)")
                        .font(.appCaption.weight(.bold)).tracking(1).foregroundColor(.gray)
                    HStack {
                        Slider(value: $pctCalories, in: 0...200, step: 5)
                        Text("\(Int(pctCalories))%")
                            .font(.appHeadline).frame(width: 60, alignment: .trailing)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("% des protéines cibles (\(Int(prompt.targetProteines)) g)")
                        .font(.appCaption.weight(.bold)).tracking(1).foregroundColor(.gray)
                    HStack {
                        Slider(value: $pctProteines, in: 0...200, step: 5)
                        Text("\(Int(pctProteines))%")
                            .font(.appHeadline).frame(width: 60, alignment: .trailing)
                    }
                }

                Divider()

                Text("Estimation : \(estimatedCalories) kcal · \(estimatedProteines) g prot")
                    .font(.appHeadline).foregroundColor(Color.forge)

                Text("Cette estimation remplace les \(prompt.entriesCount) entrée(s) actuelles de la veille.")
                    .font(.appCaption).foregroundColor(.gray.opacity(0.7))

                if let msg = errorMessage {
                    Text(msg).font(.appCaption).foregroundColor(Color.appDanger)
                }

                Spacer()

                Button {
                    Task { await commit() }
                } label: {
                    HStack {
                        if isCommitting { ProgressView().tint(.white) }
                        Text(isCommitting ? "Écriture…" : "Confirmer l'estimation")
                            .font(.appHeadline)
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.forge).foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isCommitting)

                Button("Non, hier était complet") {
                    appState.dismissNutritionCatchup(ackForToday: true)
                }
                .font(.appBody).foregroundColor(.gray)
                .frame(maxWidth: .infinity)
                .disabled(isCommitting)
            }
            .padding()
            .navigationTitle("Rattrapage nutrition")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func commit() async {
        errorMessage = nil
        isCommitting = true
        do {
            try await appState.commitYesterdayEstimate(pctCal: pctCalories, pctProt: pctProteines)
        } catch {
            errorMessage = "Écriture échouée — réessaie. \(error.localizedDescription)"
        }
        isCommitting = false
    }
}

// MARK: - Mac layout (NavigationSplitView)

#if targetEnvironment(macCatalyst)
private enum MacPage: String, Identifiable {
    // Principal
    case dashboard, seance, nutrition
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
    MacSidebarSection(title: "Principal",      pages: [.dashboard, .seance, .nutrition]),
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
