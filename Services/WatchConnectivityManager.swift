import Foundation
import WatchConnectivity
import OSLog

private let wcLog = Logger(subsystem: "TrainingOS", category: "watch_connectivity")

// Types du contrat Watch ↔ iOS (dupliqués dans VinceSevenWatch/WatchTypes.swift)
struct WatchActiveSession: Codable {
    let sessionName: String
    let exercises: [WatchExercise]
}

struct WatchExercise: Codable, Identifiable {
    let id: String
    let name: String
    let targetSets: Int
    let targetReps: String
    let defaultWeightLbs: Double
    let restSeconds: Int
}

struct WatchSetLog: Codable {
    let exerciseId: String
    let exerciseName: String
    let weightLbs: Double
    let reps: Int
    let rpe: Double?
    let timestamp: Date
}

struct WatchRecoveryLog: Codable {
    let energy: Int     // 1–10
    let soreness: Int   // 1–10
    let mood: String    // "low" | "neutral" | "good" | "great"
    let date: String    // yyyy-MM-dd
}

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var isReachable = false
    @Published var isPaired    = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Push context to Watch

    /// Appeler quand l'utilisateur démarre une séance.
    func pushActiveSession(_ active: WatchActiveSession) {
        guard WCSession.default.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(active) else { return }
        try? WCSession.default.updateApplicationContext(["activeSession": data])
    }

    /// Appeler quand les settings d'unité changent.
    func pushSettings() {
        guard WCSession.default.activationState == .activated else { return }
        let ctx: [String: Any] = [
            "unit_is_kg": UserDefaults.standard.bool(forKey: "unit_is_kg"),
            "weight_increment": UserDefaults.standard.double(forKey: "weight_increment_kg")
        ]
        try? WCSession.default.updateApplicationContext(ctx)
    }

    /// Efface la séance active sur la Watch quand la séance est terminée.
    func clearActiveSession() {
        guard WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(["activeSession": Data()])
    }

    // MARK: - Handlers

    private func handle(message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        if let data = message["setLog"] as? Data,
           let log = try? JSONDecoder().decode(WatchSetLog.self, from: data) {
            handleSetLog(log, reply: replyHandler)
        } else if let data = message["recoveryLog"] as? Data,
                  let log = try? JSONDecoder().decode(WatchRecoveryLog.self, from: data) {
            handleRecoveryLog(log, reply: replyHandler)
        } else {
            replyHandler?(["status": "unknown"])
        }
    }

    private func handleSetLog(_ log: WatchSetLog, reply: (([String: Any]) -> Void)?) {
        Task {
            do {
                _ = try await APIService.shared.logExercise(
                    exercise: log.exerciseName,
                    weight: log.weightLbs,
                    reps: String(log.reps),
                    rpe: log.rpe
                )
                wcLog.info("✅ Watch set loggé : \(log.exerciseName) \(log.weightLbs, format: .fixed(precision: 1))lbs × \(log.reps)")
                reply?(["status": "ok"])
            } catch {
                wcLog.error("Watch set log échoué : \(error)")
                reply?(["status": "error"])
            }
        }
    }

    private func handleRecoveryLog(_ log: WatchRecoveryLog, reply: (([String: Any]) -> Void)?) {
        Task {
            do {
                try await APIService.shared.logRecovery(
                    sleepHours: nil, sleepQuality: nil, restingHr: nil, hrv: nil, steps: nil,
                    soreness: Double(log.soreness),
                    energyPre: Double(log.energy),
                    notes: "Humeur: \(log.mood) [Watch]",
                    date: log.date
                )
                wcLog.info("✅ Watch recovery loggé")
                reply?(["status": "ok"])
            } catch {
                wcLog.error("Watch recovery log échoué : \(error)")
                reply?(["status": "error"])
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.isPaired      = session.isPaired
            self.isReachable   = session.isReachable
            if state == .activated { self.pushSettings() }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in self.handle(message: message, replyHandler: replyHandler) }
    }

    // Réception offline (transferUserInfo — Watch sans iPhone à portée)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.handle(message: userInfo, replyHandler: nil) }
    }
}
