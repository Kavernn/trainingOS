import Foundation

struct PersistedExerciseLogResult: Codable {
    let name: String
    let weight: Double
    let reps: String
    let rpe: Double?
    let isSecond: Bool
    let isBonus: Bool
    let equipmentType: String
    let painZone: String
}

enum SessionDraftStore {
    private static func key(date: String, sessionType: String) -> String {
        "session_draft_\(sessionType)_\(date)"
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
    }

    static func hasDraft(date: String, sessionType: String = "morning") -> Bool {
        !load(date: date, sessionType: sessionType).isEmpty
    }
}
