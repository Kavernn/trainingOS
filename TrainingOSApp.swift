import SwiftUI
import SwiftData
import UserNotifications

@main
struct TrainingOSApp: App {
    @StateObject private var appState = AppState.shared
    @State private var showSplash = true
    @State private var hkSetupDone = false   // ROB-9: prevent re-registration on every onAppear
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    private let modelContainer: ModelContainer = {
        let schema = Schema([PendingMutation.self, BodyCompEntry.self])
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
                if ProcessInfo.processInfo.environment["UITEST_MODE"] == "1" {
                    // Skip splash + onboarding in UITest mode — go straight to ContentView
                    ContentView()
                } else if showSplash {
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
                    await appState.loadProfile()    // ARCH-8: load user profile at startup
                    guard !hkSetupDone else { return } // ROB-9: register HK observers once only
                    hkSetupDone = true
                    await HealthKitService.shared.requestAuthorization()
                    await WatchSyncService.shared.syncIfNeeded()
                    await WatchSyncService.shared.enableBackgroundDelivery()
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
