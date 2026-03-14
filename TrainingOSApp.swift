import SwiftUI
import SwiftData

@main
struct TrainingOSApp: App {
    @State private var showSplash = true

    private let modelContainer: ModelContainer = {
        let schema = Schema([PendingMutation.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: config)
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
            }
        }
        .modelContainer(modelContainer)
    }
}
