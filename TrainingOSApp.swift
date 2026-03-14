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

    var body: some Scene {
        WindowGroup {
            if showSplash {
                SplashView { showSplash = false }
                    .preferredColorScheme(.dark)
            } else {
                ContentView()
                    .preferredColorScheme(.dark)
            }
        }
        .modelContainer(modelContainer)
        .task {
            SyncManager.shared.setup(container: modelContainer)
        }
    }
}
