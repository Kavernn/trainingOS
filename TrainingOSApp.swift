import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Notification delegate (deep links from notification taps)

private final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        DispatchQueue.main.async {
            if id.hasPrefix("event.phoenix") || id.hasPrefix("event.dna") {
                AppState.shared.pendingDeepLink = "intelligence"
            } else if id.hasPrefix("event.season") || id.hasPrefix("event.capsule") {
                AppState.shared.pendingDeepLink = "intelligence"
            } else if id.hasPrefix("war_room") {
                AppState.shared.pendingDeepLink = "warroom"
            } else if id.hasPrefix("event.graveyard") {
                AppState.shared.pendingDeepLink = "intelligence"
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@main
struct TrainingOSApp: App {
    @StateObject private var appState = AppState.shared
    @State private var showSplash = true
    @State private var hkSetupDone = false
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    private let modelContainer: ModelContainer = {
        // SyncManager uses UserDefaults — no SwiftData needed for the offline queue.
        // BodyCompEntry still uses SwiftData for local history (iOS < 26 only;
        // iOS 26 beta SwiftData @Model ObjC registration corrupts the nano-malloc heap).
        if #available(iOS 26, *) {
            let empty = Schema([])
            let cfg   = ModelConfiguration(schema: empty, isStoredInMemoryOnly: true)
            return (try? ModelContainer(for: empty, configurations: cfg))
                ?? { fatalError("Cannot create empty ModelContainer") }()
        }

        let schema     = Schema([BodyCompEntry.self])
        let memConfig  = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let diskConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return (try? ModelContainer(for: schema, configurations: diskConfig))
            ?? (try? ModelContainer(for: schema, configurations: memConfig))
            ?? { fatalError("Impossible de créer un ModelContainer") }()
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
                SyncManager.shared.setup()
                UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared
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
