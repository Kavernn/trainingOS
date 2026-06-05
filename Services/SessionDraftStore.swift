import Foundation
import OSLog

private let draftLogger = Logger(subsystem: "TrainingOS", category: "session_draft")

struct PersistedSet: Codable {
    let weight: Double
    let reps: String
    let rir: Int
    let rpe: Double?
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

    static func clear(date: String, sessionType: String = "morning") {
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
