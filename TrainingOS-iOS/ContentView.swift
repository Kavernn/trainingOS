import SwiftUI

struct ContentView: View {
    @StateObject private var api = APIService.shared

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Accueil", systemImage: "house.fill")
                }

            SeanceView()
                .tabItem {
                    Label("Séance", systemImage: "dumbbell.fill")
                }

            HistoriqueView()
                .tabItem {
                    Label("Historique", systemImage: "calendar")
                }

            TimerView()
                .tabItem {
                    Label("Timer", systemImage: "timer")
                }

            ProfileView()
                .tabItem {
                    Label("Profil", systemImage: "person.fill")
                }
        }
        .tint(Color.orange)
    }
}
