import Foundation
import OSLog

private let draftLogger = Logger(subsystem: "TrainingOS", category: "session_draft")

struct PersistedSet: Codable {
    let weight: Double
    let reps: String?
    let rir: Int?
    let rpe: Double?
    var distanceM: Int? = nil
    var intensity: Double? = nil
    var leftTime: Int? = nil
    var rightTime: Int? = nil

    // Validated log payloads, not raw UI rows. Protocol's weight-only set means "done".
    static func preserving(_ payload: [String: Any], trackingType: String) -> PersistedSet? {
        guard let weight = (payload["weight"] as? NSNumber)?.doubleValue else { return nil }
        let reps = payload.repsString()
        let distance = payload["distance_m"] as? Int
        let meaningful: Bool
        switch trackingType {
        case "carry": meaningful = (distance ?? 0) > 0
        case "protocol": meaningful = payload.count == 1 && weight == 0
        default: meaningful = reps != nil && reps != ""
        }
        guard meaningful else { return nil }
        return PersistedSet(weight: weight, reps: reps, rir: payload["rir"] as? Int,
                            rpe: payload["rpe"] as? Double,
                            distanceM: distance, intensity: payload["intensity"] as? Double,
                            leftTime: (payload["left"] as? [String: Any])?["time"] as? Int,
                            rightTime: (payload["right"] as? [String: Any])?["time"] as? Int)
    }

    var payload: [String: Any] {
        var result: [String: Any] = ["weight": weight]
        if let reps { result["reps"] = reps }
        if let rir { result["rir"] = rir }
        if let rpe { result["rpe"] = rpe }
        if let distanceM { result["distance_m"] = distanceM }
        if let intensity { result["intensity"] = intensity }
        if let leftTime { result["left"] = ["time": leftTime] }
        if let rightTime { result["right"] = ["time": rightTime] }
        return result
    }
}

struct PersistedExerciseLogResult: Codable {
    let name: String
    let weight: Double
    let reps: String
    let rpe: Double?
    let isSecond: Bool
    let isBonus: Bool
    let equipmentType: String
    let painZone: String
    var sets: [PersistedSet]
    var trackingType: String? = nil
    var notes: String? = nil
}

enum SessionDraftStore {
    private static func key(date: String, sessionType: String) -> String {
        "session_draft_\(sessionType)_\(date)"
    }
    private static func startedAtKey(date: String, sessionType: String) -> String {
        "session_started_at_\(sessionType)_\(date)"
    }

    static func save(date: String, sessionType: String = "morning", values: [PersistedExerciseLogResult]) {
        do {
            let data = try APIService.encoder.encode(values)
            UserDefaults.standard.set(data, forKey: key(date: date, sessionType: sessionType))
        } catch {
            draftLogger.error("SessionDraftStore save failed [\(sessionType)/\(date)]: \(error)")
        }
    }

    static func load(date: String, sessionType: String = "morning") -> [PersistedExerciseLogResult] {
        guard let data = UserDefaults.standard.data(forKey: key(date: date, sessionType: sessionType)),
              let decoded = try? APIService.decoder.decode([PersistedExerciseLogResult].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func commentKey(date: String, sessionType: String) -> String {
        "session_comment_\(sessionType)_\(date)"
    }

    static func saveComment(_ comment: String, date: String, sessionType: String) {
        UserDefaults.standard.set(comment, forKey: commentKey(date: date, sessionType: sessionType))
    }

    static func loadComment(date: String, sessionType: String) -> String? {
        UserDefaults.standard.string(forKey: commentKey(date: date, sessionType: sessionType))
    }

    static func clear(date: String, sessionType: String = "morning") {
        clearLogs(date: date, sessionType: sessionType)
        UserDefaults.standard.removeObject(forKey: commentKey(date: date, sessionType: sessionType))
    }

    /// Intermediate empty logs must not discard a still-legitimate session comment.
    static func clearLogs(date: String, sessionType: String) {
        UserDefaults.standard.removeObject(forKey: key(date: date, sessionType: sessionType))
        UserDefaults.standard.removeObject(forKey: startedAtKey(date: date, sessionType: sessionType))
        UserDefaults.standard.removeObject(forKey: chronoPausedDurationKey(date: date, sessionType: sessionType))
        UserDefaults.standard.removeObject(forKey: chronoIsPausedKey(date: date, sessionType: sessionType))
        UserDefaults.standard.removeObject(forKey: chronoPausedAtKey(date: date, sessionType: sessionType))
    }

    static func hasDraft(date: String, sessionType: String = "morning") -> Bool {
        !load(date: date, sessionType: sessionType).isEmpty
    }

    static func hasAnyDraft(date: String) -> Bool {
        ["morning", "evening", "bonus"].contains(where: { !load(date: date, sessionType: $0).isEmpty })
    }

    static func saveStartedAt(date: String, sessionType: String = "morning", startedAt: Date) {
        UserDefaults.standard.set(startedAt.timeIntervalSince1970, forKey: startedAtKey(date: date, sessionType: sessionType))
    }

    static func loadStartedAt(date: String, sessionType: String = "morning") -> Date? {
        let ts = UserDefaults.standard.double(forKey: startedAtKey(date: date, sessionType: sessionType))
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    // MARK: - Chrono persistence (pause/resume state)

    private static func chronoPausedDurationKey(date: String, sessionType: String) -> String {
        "session_chrono_paused_\(sessionType)_\(date)"
    }
    private static func chronoIsPausedKey(date: String, sessionType: String) -> String {
        "session_chrono_is_paused_\(sessionType)_\(date)"
    }
    private static func chronoPausedAtKey(date: String, sessionType: String) -> String {
        "session_chrono_paused_at_\(sessionType)_\(date)"
    }

    static func saveChronoPausedDuration(date: String, sessionType: String, duration: TimeInterval) {
        UserDefaults.standard.set(duration, forKey: chronoPausedDurationKey(date: date, sessionType: sessionType))
    }
    static func loadChronoPausedDuration(date: String, sessionType: String) -> TimeInterval {
        UserDefaults.standard.double(forKey: chronoPausedDurationKey(date: date, sessionType: sessionType))
    }
    static func saveChronoIsPaused(date: String, sessionType: String, isPaused: Bool) {
        UserDefaults.standard.set(isPaused, forKey: chronoIsPausedKey(date: date, sessionType: sessionType))
    }
    static func loadChronoIsPaused(date: String, sessionType: String) -> Bool {
        UserDefaults.standard.bool(forKey: chronoIsPausedKey(date: date, sessionType: sessionType))
    }
    static func saveChronoPausedAt(date: String, sessionType: String, pausedAt: Date?) {
        if let pa = pausedAt {
            UserDefaults.standard.set(pa.timeIntervalSince1970, forKey: chronoPausedAtKey(date: date, sessionType: sessionType))
        } else {
            UserDefaults.standard.removeObject(forKey: chronoPausedAtKey(date: date, sessionType: sessionType))
        }
    }
    static func loadChronoPausedAt(date: String, sessionType: String) -> Date? {
        let ts = UserDefaults.standard.double(forKey: chronoPausedAtKey(date: date, sessionType: sessionType))
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
}
