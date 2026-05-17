import SwiftUI
import SwiftData
import UserNotifications

@main
struct TrainingOSApp: App {
    @StateObject private var appState = AppState.shared
    @State private var showSplash = true
    @State private var hkSetupDone = false
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    private let modelContainer: ModelContainer = {
        // iOS 26 beta: SwiftData @Model ObjC runtime registration corrupts the
        // nano-malloc heap. Use an empty schema to skip model registration entirely;
        // SyncManager offline queue and BodyComp history are unavailable until Apple
        // fixes SwiftData on iOS 26.
        if #available(iOS 26, *) {
            let empty = Schema([])
            let cfg   = ModelConfiguration(schema: empty, isStoredInMemoryOnly: true)
            return (try? ModelContainer(for: empty, configurations: cfg))
                ?? { fatalError("Cannot create empty ModelContainer") }()
        }

        let schema     = Schema([PendingMutation.self, BodyCompEntry.self])
        let memConfig  = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let diskConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let container = try? ModelContainer(for: schema, configurations: diskConfig) {
            let ctx = ModelContext(container)
            if (try? ctx.fetch(FetchDescriptor<PendingMutation>())) != nil {
                return container
            }
        }
        return (try? ModelContainer(for: schema, configurations: memConfig))
            ?? { fatalError("Impossible de créer un ModelContainer en mémoire") }()
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.environment["UITEST_MODE"] == "1" {
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
            .onAppear {
                CacheService.invalidateIfVersionChanged()
                if #unavailable(iOS 26) {
                    SyncManager.shared.setup(container: modelContainer)
                }
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { NotificationService.scheduleAll() }
                }
                Task {
                    await appState.loadProfile()
                    await CoachMemoryStore.shared.syncFromServer()
                    guard !hkSetupDone else { return }
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
