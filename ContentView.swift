import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var api     = APIService.shared
    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var sync    = SyncManager.shared
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

            ProgrammeView()
                .tag(2)
                .tabItem {
                    Label("Programme", systemImage: "list.bullet.clipboard")
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
        .onAppear { configureTabBarAppearance() }
        // Offline banner (top)
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
        // Offline queued toast (bottom)
        .overlay(alignment: .bottom) {
            if let msg = sync.offlineToast {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.leading)
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
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sync.offlineToast)
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
