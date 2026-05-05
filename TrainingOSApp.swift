import SwiftUI
import SwiftData
import UserNotifications

@main
struct TrainingOSApp: App {
    @ObservedObject private var appState = AppState.shared
    @State private var showSplash = true
    @State private var hkSetupDone = false
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    private let modelContainer: ModelContainer = {
        let schema    = Schema([PendingMutation.self, BodyCompEntry.self])
        let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        // iOS 26 beta: disk-based ModelContainer corrupts the nano-malloc heap
        // during schema migration. Use memory-only; offline mutations won't
        // persist across relaunches on iOS 26 until Apple fixes SwiftData.
        if #available(iOS 26, *) {
            return (try? ModelContainer(for: schema, configurations: memConfig))
                ?? { fatalError("Impossible de créer un ModelContainer en mémoire") }()
        }

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
                SyncManager.shared.setup(container: modelContainer)
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { NotificationService.scheduleAll() }
                }
                Task {
                    await appState.loadProfile()
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
