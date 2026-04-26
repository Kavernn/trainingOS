import Foundation

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
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key(date: date, sessionType: sessionType))
    }

    static func load(date: String, sessionType: String = "morning") -> [PersistedExerciseLogResult] {
        guard let data = UserDefaults.standard.data(forKey: key(date: date, sessionType: sessionType)),
              let decoded = try? JSONDecoder().decode([PersistedExerciseLogResult].self, from: data) else {
            return []
        }
        return decoded
    }

    static func clear(date: String, sessionType: String = "morning") {
        UserDefaults.standard.removeObject(forKey: key(date: date, sessionType: sessionType))
        UserDefaults.standard.removeObject(forKey: startedAtKey(date: date, sessionType: sessionType))
    }

    static func hasDraft(date: String, sessionType: String = "morning") -> Bool {
        !load(date: date, sessionType: sessionType).isEmpty
    }

    static func saveStartedAt(date: String, sessionType: String = "morning", startedAt: Date) {
        UserDefaults.standard.set(startedAt.timeIntervalSince1970, forKey: startedAtKey(date: date, sessionType: sessionType))
    }

    static func loadStartedAt(date: String, sessionType: String = "morning") -> Date? {
        let ts = UserDefaults.standard.double(forKey: startedAtKey(date: date, sessionType: sessionType))
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
}
