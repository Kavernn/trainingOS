import Foundation
import Combine
import OSLog

/// Watches network state and flushes pending mutations to the server
/// whenever connectivity is restored.
@MainActor
final class SyncManager: ObservableObject {

    static let shared = SyncManager()

    private let baseURL = APIConfig.base
    private let maxRetries = 5

    var urlSession: URLSession = .shared
    var isOnlineProvider: () -> Bool = { NetworkMonitor.shared.isOnline }

    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isSyncing = false
    @Published var offlineToast: String? = nil
    @Published private(set) var zombieDropCount: Int = 0

    private let queue = UserDefaultsSyncQueue()
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "TrainingOS", category: "sync")

    private enum SendResult { case success, retryable, discarded(Int) }

    init() {}

    // MARK: - Setup

    /// Call once from TrainingOSApp. No ModelContainer needed — queue is UserDefaults-backed.
    func setup() {
        refreshPendingCount()

        if isOnlineProvider() {
            Task { await flushQueue() }
        }

        NetworkMonitor.shared.$isOnline
            .filter { $0 }
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.flushQueue() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Enqueue

    /// Persist a mutation for later delivery. Triggers an immediate flush if already online
    /// (covers momentary flakiness where network state never changed).
    func enqueue(endpoint: String, method: String = "POST", payload: [String: Any]) {
        let mutation = PendingMutation(endpoint: endpoint, method: method, payload: payload)
        queue.append(mutation)
        pendingCount += 1
        showOfflineToast()
        if isOnlineProvider() {
            Task { await flushQueue() }
        }
    }

    private func showOfflineToast() {
        offlineToast = "Enregistré — sera synchronisé quand le réseau sera disponible"
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            self?.offlineToast = nil
        }
    }

    private func showZombieToast(count: Int) {
        let n = count == 1 ? "1 action" : "\(count) actions"
        offlineToast = "⚠️ \(n) non synchronisée(s) après \(maxRetries) tentatives — supprimée(s)."
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.offlineToast = nil
        }
    }

    private func showDiscardedToast(code: Int) {
        offlineToast = "⚠️ Séance rejetée par le serveur (\(code)) — non sauvegardée."
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.offlineToast = nil
        }
    }

    // MARK: - Flush

    /// Send all pending mutations in FIFO order. Safe to call multiple times.
    func flushQueue() async {
        guard !isSyncing else { return }
        guard isOnlineProvider() else { return }

        isSyncing = true
        defer { isSyncing = false }

        let cap = maxRetries

        // Zombie purge runs first — even when nothing else is pending.
        // Without this, zombies would never be cleaned up if they are the only items in the queue
        // (the guard below would short-circuit before reaching the old purge block).
        let zombies = queue.load().filter { !$0.isSynced && $0.retryCount >= cap }
        if !zombies.isEmpty {
            zombies.forEach {
                logger.warning("Dropping zombie mutation — \($0.method, privacy: .public) \($0.endpoint, privacy: .public) (retries: \($0.retryCount))")
            }
            queue.removeAll { !$0.isSynced && $0.retryCount >= cap }
            zombieDropCount += zombies.count
            showZombieToast(count: zombies.count)
        }

        let now = Date()
        var pending = queue.load().filter {
            !$0.isSynced && $0.retryCount < cap && ($0.nextRetryAt.map { $0 <= now } ?? true)
        }
        pending.sort { $0.createdAt < $1.createdAt }

        guard !pending.isEmpty else {
            refreshPendingCount()
            return
        }

        let sessionEndpoints: Set<String> = ["/api/log", "/api/log_session", "/api/log_hiit"]
        var syncedSessionMutation = false

        for var mutation in pending {
            switch await send(mutation: mutation) {
            case .success:
                mutation.isSynced   = true
                mutation.retryCount = 0
                if sessionEndpoints.contains(mutation.endpoint) { syncedSessionMutation = true }
            case .retryable:
                mutation.retryCount += 1
                // Exponential backoff: 2m, 4m, 8m, 16m, 32m
                let delaySeconds = min(pow(2.0, Double(mutation.retryCount)) * 120, 32 * 60)
                mutation.nextRetryAt = Date().addingTimeInterval(delaySeconds)
            case .discarded(let code):
                logger.warning("Discarding non-recoverable mutation — \(mutation.method, privacy: .public) \(mutation.endpoint, privacy: .public) status \(code)")
                mutation.isSynced = true
                if sessionEndpoints.contains(mutation.endpoint) {
                    showDiscardedToast(code: code)
                }
            }
            queue.update(mutation)
        }

        if syncedSessionMutation {
            CacheInvalidation.dashboardInvalidated.invalidate()
            await APIService.shared.fetchDashboard()
        }

        // Purge synced mutations older than 7 days
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        queue.removeAll { $0.isSynced && $0.createdAt < cutoff }

        refreshPendingCount()
    }

    // MARK: - Private

    private func send(mutation: PendingMutation) async -> SendResult {
        guard let url = URL(string: baseURL + mutation.endpoint) else { return .discarded(0) }
        var req = URLRequest(url: url)
        req.httpMethod      = mutation.method
        req.httpBody        = mutation.method == "DELETE" ? nil : mutation.payloadData
        req.timeoutInterval = 15
        if mutation.method != "DELETE" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (_, response) = try await URLSession.authed.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (400...499).contains(code) && code != 429 {
                return .discarded(code)
            }
            return (200...299).contains(code) || code == 409 ? .success : .retryable
        } catch {
            return .retryable
        }
    }

    private func refreshPendingCount() {
        pendingCount = queue.pendingCount(maxRetries: maxRetries)
    }
}
