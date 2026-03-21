import SwiftUI
import SwiftData
import UserNotifications

@main
struct TrainingOSApp: App {
    @State private var showSplash = true

    private let modelContainer: ModelContainer = {
        let schema = Schema([PendingMutation.self])
        // Essaie sur disque d'abord, fallback mémoire si le store est corrompu (ex: migration iOS)
        if let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)) {
            return container
        }
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }()

    init() {
        // ModelContainer must be created before init() returns,
        // so we call setup after the lazy initializer runs.
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showSplash {
                    SplashView { showSplash = false }
                } else {
                    ContentView()
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                SyncManager.shared.setup(container: modelContainer)
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
        .modelContainer(modelContainer)
    }
}
