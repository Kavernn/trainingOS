import SwiftUI
import SwiftData
import UserNotifications
import AppIntents
import OSLog

// MARK: - E10: App Shortcuts — Morning Ritual quick access

@available(iOS 16, *)
struct OpenMorningRitualIntent: AppIntent {
    static var title: LocalizedStringResource = "Rituel du matin"
    static var description = IntentDescription("Ouvre le rituel du matin pour déclarer ton intention.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppState.shared.pendingDeepLink = "intelligence" }
        return .result()
    }
}

@available(iOS 16, *)
struct TrainingOSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenMorningRitualIntent(),
            phrases: [
                "Rituel du matin sur \(.applicationName)",
                "Déclare ma guerre sur \(.applicationName)",
                "Mon intention du jour sur \(.applicationName)"
            ],
            shortTitle: "Rituel du matin",
            systemImageName: "flame.fill"
        )
    }
}

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
            if id.hasPrefix("event.phoenix") || id.hasPrefix("event.dna")
                || id.hasPrefix("event.season") || id.hasPrefix("event.capsule")
                || id.hasPrefix("event.graveyard")
                || id == "ritual.morning.reminder" || id == "ritual.streak.risk"
                || id == "ritual.demon.haunting" || id == "ritual.evening.reminder"
                || id == "weekly.recap.sunday" {
                AppState.shared.pendingDeepLink = "intelligence"
            } else if id.hasPrefix("war_room") {
                AppState.shared.pendingDeepLink = "warroom"
            } else if id == "nutrition.daily.reminder" {
                AppState.shared.pendingDeepLink = "more"
            } else if id == "hrv.morning.reminder" || id == "selfcare.daily.reminder"
                        || id == "pss.weekly.test" {
                AppState.shared.pendingDeepLink = "more"
            } else if id == "inactivity.reminder" || id == "weekly.friday.fullbody" {
                AppState.shared.pendingDeepLink = "seance"
            } else if id == "streak.milestone" {
                AppState.shared.pendingDeepLink = "dashboard"
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

    private static let swiftDataLog = Logger(subsystem: "TrainingOS", category: "SwiftData")

    // Optional so the app never crashes if SwiftData is broken at the OS level.
    // Views using @Query will see empty results rather than crashing.
    private let modelContainer: ModelContainer? = {
        // SyncManager uses UserDefaults — no SwiftData needed for the offline queue.
        // BodyCompEntry still uses SwiftData for local history (iOS < 26 only;
        // iOS 26 beta SwiftData @Model ObjC registration corrupts the nano-malloc heap).
        if #available(iOS 26, *) {
            let empty = Schema([])
            let cfg   = ModelConfiguration(schema: empty, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: empty, configurations: cfg)
            } catch {
                swiftDataLog.critical("iOS 26 empty ModelContainer failed: \(error) — retrying without configuration")
                do {
                    return try ModelContainer(for: Schema([]))
                } catch let e2 {
                    swiftDataLog.critical("SwiftData unavailable on iOS 26: \(e2)")
                    return nil
                }
            }
        }

        let schema     = Schema([BodyCompEntry.self])
        let diskConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let memConfig  = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: diskConfig)
        } catch {
            swiftDataLog.error("SwiftData disk init failed: \(error)")
        }

        do {
            return try ModelContainer(for: schema, configurations: memConfig)
        } catch {
            swiftDataLog.critical("SwiftData in-memory init failed: \(error) — BodyComp data unavailable, trying empty container")
        }

        do {
            return try ModelContainer(for: Schema([]))
        } catch let e {
            swiftDataLog.critical("SwiftData completely unavailable: \(e)")
            return nil
        }
    }()

    @ViewBuilder
    private var rootView: some View {
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
            _ = WatchConnectivityManager.shared  // active WCSession au lancement
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

    var body: some Scene {
        WindowGroup {
            if let container = modelContainer {
                rootView.modelContainer(container)
            } else {
                rootView
            }
        }
    }
}
