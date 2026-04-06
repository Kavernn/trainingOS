import SwiftUI
import SwiftData
import UserNotifications

@main
struct TrainingOSApp: App {
    @StateObject private var appState = AppState.shared
    @State private var showSplash = true
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    private let modelContainer: ModelContainer = {
        let schema = Schema([PendingMutation.self])
        let memConfig  = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let diskConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        // Essaie sur disque + validation par fetch — fallback mémoire si le store est corrompu
        if let container = try? ModelContainer(for: schema, configurations: diskConfig) {
            let ctx = ModelContext(container)
            if (try? ctx.fetch(FetchDescriptor<PendingMutation>())) != nil {
                return container   // store lisible, on l'utilise
            }
        }
        // Store corrompu ou illisible → mémoire (mutations offline perdues, mais l'app ne crashe plus)
        return (try? ModelContainer(for: schema, configurations: memConfig))
            ?? { fatalError("Impossible de créer un ModelContainer en mémoire") }()
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
                } else if !onboardingCompleted {
                    OnboardingView { onboardingCompleted = true }
                } else {
                    ContentView()
                }
            }
            .environmentObject(appState)
            .preferredColorScheme(.dark)
            .onAppear {
                SyncManager.shared.setup(container: modelContainer)
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { NotificationService.scheduleAll() }
                }
                Task {
                    await HealthKitService.shared.requestAuthorization()
                    await WatchSyncService.shared.syncIfNeeded()
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
