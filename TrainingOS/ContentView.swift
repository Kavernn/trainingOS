import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var api     = APIService.shared
    @StateObject private var network = NetworkMonitor.shared
    @State private var selectedTab   = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tag(0)
                .tabItem {
                    Label("Accueil", systemImage: "house.fill")
                }

            SeanceView()
                .tag(1)
                .tabItem {
                    Label("Séance", systemImage: "dumbbell.fill")
                }

            HistoriqueView()
                .tag(2)
                .tabItem {
                    Label("Historique", systemImage: "calendar")
                }

            TimerView()
                .tag(3)
                .tabItem {
                    Label("Timer", systemImage: "timer")
                }

            MoreView()
                .tag(4)
                .tabItem {
                    Label("Plus", systemImage: "ellipsis.circle.fill")
                }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .keyboardDismissable()
        .onAppear { configureTabBarAppearance() }
        // Offline banner
        .overlay(alignment: .top) {
            if !network.isOnline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Hors-ligne — données en cache")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.9))
                .allowsHitTesting(false)
            }
        }
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
