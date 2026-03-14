import Foundation
import SwiftData
import Combine

/// Watches network state and flushes pending mutations to the server
/// whenever connectivity is restored.
@MainActor
final class SyncManager: ObservableObject {

    static let shared = SyncManager()

    private let baseURL = "https://training-os-rho.vercel.app"
    private let maxRetries = 5

    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isSyncing = false

    private var container: ModelContainer?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Setup

    /// Call once from TrainingOSApp with the shared ModelContainer.
    func setup(container: ModelContainer) {
        self.container = container
        refreshPendingCount()

        // Auto-sync when coming back online
        NetworkMonitor.shared.$isOnline
            .filter { $0 }                         // only when transitioning to online
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.flushQueue() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Enqueue

    /// Persist a mutation for later delivery.
    func enqueue(endpoint: String, payload: [String: Any]) {
        guard let container else { return }
        let context = ModelContext(container)
        let mutation = PendingMutation(endpoint: endpoint, payload: payload)
        context.insert(mutation)
        try? context.save()
        pendingCount += 1
    }

    // MARK: - Flush

    /// Send all pending mutations in FIFO order. Safe to call multiple times.
    func flushQueue() async {
        guard let container, !isSyncing else { return }
        guard NetworkMonitor.shared.isOnline else { return }

        isSyncing = true
        defer { isSyncing = false }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate { !$0.isSynced && $0.retryCount < 5 },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else {
            refreshPendingCount()
            return
        }

        for mutation in pending {
            let success = await send(mutation: mutation)
            if success {
                mutation.isSynced   = true
                mutation.retryCount = 0
            } else {
                mutation.retryCount += 1
            }
            try? context.save()
        }

        // Purge synced mutations older than 7 days to keep storage clean
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let purgeDescriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.isSynced && $0.createdAt < cutoff }
        )
        if let toDelete = try? context.fetch(purgeDescriptor) {
            toDelete.forEach { context.delete($0) }
            try? context.save()
        }

        refreshPendingCount()
    }

    // MARK: - Private

    private func send(mutation: PendingMutation) async -> Bool {
        guard let url = URL(string: baseURL + mutation.endpoint) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod      = mutation.method
        req.httpBody        = mutation.payloadData
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 2xx = success; 409 (already_logged) = treat as success (idempotent)
            return (200...299).contains(code) || code == 409
        } catch {
            return false
        }
    }

    private func refreshPendingCount() {
        guard let container else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PendingMutation>(
            predicate: #Predicate { !$0.isSynced && $0.retryCount < 5 }
        )
        pendingCount = (try? context.fetchCount(descriptor)) ?? 0
    }
}
