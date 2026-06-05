import Foundation
import Combine
import WatchConnectivity
import OSLog

private let watchLog = Logger(subsystem: "VinceSevenWatch", category: "session")

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var isReachable: Bool      = false
    @Published var activeSession: WatchActiveSession?
    @Published var unitIsKg: Bool         = false
    @Published var weightIncrement: Double = 2.5

    private let queueKey = "pendingWatchLogs_v1"

    private var pendingQueue: [PendingWatchLog] {
        get {
            guard let data = UserDefaults.standard.data(forKey: queueKey),
                  let logs = try? JSONDecoder().decode([PendingWatchLog].self, from: data)
            else { return [] }
            return logs
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: queueKey)
        }
    }

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - API publique

    func sendSetLog(_ log: WatchSetLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        enqueue(PendingWatchLog(id: UUID(), type: "set", payload: data, timestamp: Date(), synced: false))
        flush()
    }

    func sendRecoveryLog(_ log: WatchRecoveryLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        enqueue(PendingWatchLog(id: UUID(), type: "recovery", payload: data, timestamp: Date(), synced: false))
        flush()
    }

    // MARK: - Queue

    private func enqueue(_ log: PendingWatchLog) {
        var q = pendingQueue
        q.append(log)
        pendingQueue = q
    }

    func flush() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let toSend = pendingQueue.filter { !$0.synced }
        guard !toSend.isEmpty else { return }

        for pending in toSend {
            let key = pending.type == "set" ? "setLog" : "recoveryLog"
            let message: [String: Any] = [key: pending.payload]

            if session.isReachable {
                session.sendMessage(message, replyHandler: { [weak self] reply in
                    guard (reply["status"] as? String) == "ok" else { return }
                    Task { @MainActor in self?.markSynced(id: pending.id) }
                }, errorHandler: { error in
                    watchLog.warning("sendMessage échoué, en queue : \(error)")
                })
            } else {
                // transferUserInfo garantit la livraison même si l'iPhone est hors portée.
                session.transferUserInfo(message)
                markSynced(id: pending.id)
            }
        }
    }

    private func markSynced(id: UUID) {
        var q = pendingQueue
        for i in q.indices where q[i].id == id { q[i].synced = true }
        pendingQueue = q.filter { !$0.synced }
    }

    // MARK: - Réception depuis iPhone

    private func applyContext(_ context: [String: Any]) {
        if let data = context["activeSession"] as? Data, !data.isEmpty,
           let s = try? JSONDecoder().decode(WatchActiveSession.self, from: data) {
            activeSession = s
        } else if context["activeSession"] != nil {
            activeSession = nil
        }
        if let v = context["unit_is_kg"] as? Bool   { unitIsKg = v }
        if let v = context["weight_increment"] as? Double { weightIncrement = v }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.applyContext(session.applicationContext)
            self.flush()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if session.isReachable { self.flush() }
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.applyContext(context) }
    }
}
