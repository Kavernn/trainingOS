import SwiftUI
import SwiftData
import UserNotifications
import UIKit

// MARK: - App Delegate (iOS 26 visual-style pre-init)
// Pre-initializes UIKit appearance proxy before SwiftUI creates the window.
// Without this, iOS 26's new Liquid Glass visual-style system fires during
// UIWindowScene setup with UIKit objects that haven't opted in yet, producing:
//   "Requesting visual style in an implementation that has disabled it" × 2
// followed by a nano-malloc "freed pointer was not the last allocation" crash.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance   = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance       = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance     = navAppearance
        UINavigationBar.appearance().compactAppearance        = navAppearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = navAppearance
        return true
    }
}

@main
struct TrainingOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
