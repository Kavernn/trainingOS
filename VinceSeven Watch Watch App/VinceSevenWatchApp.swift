import SwiftUI

@main
struct VinceSevenWatchApp: App {
    @StateObject private var sessionManager = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(sessionManager)
        }
    }
}
