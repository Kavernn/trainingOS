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

    private let queue: UserDefaultsSyncQueue
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "TrainingOS", category: "sync")

    private enum SendResult { case success, retryable, discarded(Int) }
    enum CorrelatedDisposition { case delivered(Int), retryable(Int), discarded(Int) }
    private var activeCorrelated = Set<UUID>()

    init(queue: UserDefaultsSyncQueue = UserDefaultsSyncQueue()) {
        self.queue = queue
    }

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

    func status(for operationKey: OfflineOperationKey) -> OfflineMutationStatus {
        queue.status(for: operationKey)
    }

    /// Additive API: persists the exact bytes supplied by the caller.
    @discardableResult
    func enqueue(endpoint: String, method: String = "POST", payloadData: Data,
                 operationKey: OfflineOperationKey) throws -> OfflineMutationReceipt {
        let receipt = try queue.enqueue(endpoint: endpoint, method: method,
                                        payloadData: payloadData, operationKey: operationKey)
        refreshPendingCount()
        if isOnlineProvider() { Task { await flushQueue() } }
        return receipt
    }

    /// Uses the SAME attempt journal for immediate transport and later replay.
    /// An online caller receives bytes, not a queue receipt or a business ACK.
    func postCorrelated(endpoint: String, method: String, payloadData: Data,
                        operationKey: OfflineOperationKey,
                        transport: ((URLRequest) async throws -> (Data, URLResponse))? = nil) async throws -> CorrelatedOfflinePostOutcome {
        let isNew = queue.status(for: operationKey) == .notFound
        let receipt = try queue.enqueue(endpoint: endpoint, method: method,
                                        payloadData: payloadData, operationKey: operationKey)
        refreshPendingCount()
        // Existing pending may be backing off. Do not bypass its retry policy.
        guard isNew, isOnlineProvider() else { return .queued(receipt) }
        guard let mutation = queue.load().first(where: { $0.id == receipt.mutationID }) else {
            throw OfflineCorrelationError.corruptStorage
        }
        return try await performCorrelated(mutation, transport: transport)
    }

    /// Historical e41b584 contract: every non-429 4xx, INCLUDING 409, is discarded.
    /// delivered classifies HTTP transport only, never response-body semantics.
    static func correlatedDisposition(statusCode: Int) -> CorrelatedDisposition {
        if (200...299).contains(statusCode) { return .delivered(statusCode) }
        if (400...499).contains(statusCode), statusCode != 429 { return .discarded(statusCode) }
        return .retryable(statusCode)
    }

    private func request(for mutation: PendingMutation) throws -> URLRequest {
        guard let url = URL(string: baseURL + mutation.endpoint) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = mutation.method
        request.httpBody = mutation.method == "DELETE" ? nil : mutation.payloadData
        request.timeoutInterval = 15
        request.setValue("Bearer \(APIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        if mutation.method != "DELETE" { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    private func performCorrelated(_ original: PendingMutation,
        transport: ((URLRequest) async throws -> (Data, URLResponse))? = nil) async throws -> CorrelatedOfflinePostOutcome {
        guard let receipt = original.receipt else { throw OfflineCorrelationError.corruptStorage }
        let request: URLRequest
        do { request = try self.request(for: original) }
        catch {
            try queue.finishAttempt(original, state: .discarded, statusCode: 0, reason: "invalidURL")
            throw error
        }
        try queue.beginAttempt(original)
        activeCorrelated.insert(original.id)
        defer { activeCorrelated.remove(original.id); refreshPendingCount() }
        let response: (Data, URLResponse)
        do {
            if let transport { response = try await transport(request) }
            else { response = try await urlSession.data(for: request) }
        } catch {
            if (error as? URLError)?.code == .notConnectedToInternet {
                try scheduleCorrelatedRetry(original)
                return .queued(receipt)
            }
            // Timeout/connection loss/cancellation cannot prove that the server
            // didn't receive the request. Never auto-replay that ambiguity.
            try queue.finishAttempt(original, state: .uncertain, reason: "ambiguousTransportFailure")
            throw OfflineCorrelationError.existing(queue.status(for: receipt.operationKey))
        }
        guard let http = response.1 as? HTTPURLResponse else {
            try queue.finishAttempt(original, state: .uncertain, reason: "nonHTTPResponse")
            throw OfflineCorrelationError.existing(queue.status(for: receipt.operationKey))
        }
        switch Self.correlatedDisposition(statusCode: http.statusCode) {
        case .delivered(let code):
            try queue.finishAttempt(original, state: .delivered, statusCode: code)
            return .response(response.0)
        case .discarded(let code):
            try queue.finishAttempt(original, state: .discarded, statusCode: code)
            throw APIError.serverError(code, "HTTP \(code)")
        case .retryable:
            try scheduleCorrelatedRetry(original)
            return .queued(receipt)
        }
    }

    private func scheduleCorrelatedRetry(_ original: PendingMutation) throws {
        var mutation = original
        mutation.retryCount += 1
        mutation.nextRetryAt = Date().addingTimeInterval(min(pow(2, Double(mutation.retryCount)) * 120, 32 * 60))
        try queue.retryAttempt(mutation)
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
        do {
            try queue.reconcile(excluding: activeCorrelated)
            try queue.pruneTerminalHistory()
        } catch {
            // Corrupt journals block correlated replay, not a proof of delivery.
            logger.error("Correlation reconciliation refused: \(error)")
        }

        // Zombie purge runs first — even when nothing else is pending.
        // Without this, zombies would never be cleaned up if they are the only items in the queue
        // (the guard below would short-circuit before reaching the old purge block).
        let zombies = queue.load().filter { !$0.isSynced && $0.retryCount >= cap }
        if !zombies.isEmpty {
            zombies.forEach {
                logger.warning("Dropping zombie mutation — \($0.method, privacy: .public) \($0.endpoint, privacy: .public) (retries: \($0.retryCount))")
            }
            queue.removeAll { !$0.isSynced && $0.retryCount >= cap }
            let retainedIDs = Set(queue.load().map(\.id))
            let removedCount = zombies.filter { !retainedIDs.contains($0.id) }.count
            if removedCount > 0 {
                zombieDropCount += removedCount
                showZombieToast(count: removedCount)
            }
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
            if let key = mutation.operationKey {
                guard !activeCorrelated.contains(mutation.id),
                      case .pending(let receipt) = queue.status(for: key),
                      receipt.mutationID == mutation.id else { continue }
                do {
                    _ = try await performCorrelated(mutation)
                } catch {
                    logger.error("Correlated replay stopped: \(error)")
                }
                // Generic infrastructure deliberately triggers no workout effects.
                continue
            }
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
        req.setValue("Bearer \(APIConfig.apiKey)", forHTTPHeaderField: "Authorization")
        if mutation.method != "DELETE" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (_, response) = try await urlSession.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (400...499).contains(code) && code != 429 {
                return .discarded(code)
            }
            return (200...299).contains(code) ? .success : .retryable
        } catch {
            return .retryable
        }
    }

    private func refreshPendingCount() {
        pendingCount = queue.pendingCount(maxRetries: maxRetries)
    }
}
