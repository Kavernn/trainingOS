import Foundation
import OSLog

private let splitLogger = Logger(subsystem: "TrainingOS", category: "seance_split")

enum SeanceSplitStore {
    private static let keyPrefix = "seance2_assignments_"

    static func key(date: String) -> String {
        "\(keyPrefix)\(date)"
    }

    static func load(date: String) -> Set<String> {
        guard let arr = UserDefaults.standard.array(forKey: key(date: date)) as? [String] else {
            return []
        }
        return Set(arr)
    }

    static func add(date: String, exercise: String) {
        var current = load(date: date)
        current.insert(exercise)
        persist(date: date, set: current)
    }

    static func remove(date: String, exercise: String) {
        var current = load(date: date)
        current.remove(exercise)
        if current.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(date: date))
        } else {
            persist(date: date, set: current)
        }
    }

    static func contains(date: String, exercise: String) -> Bool {
        load(date: date).contains(exercise)
    }

    static func clear(date: String) {
        UserDefaults.standard.removeObject(forKey: key(date: date))
    }

    static func purgeOldEntries(currentDate: String) {
        let currentKey = key(date: currentDate)
        let defaults = UserDefaults.standard
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(keyPrefix) && k != currentKey {
            defaults.removeObject(forKey: k)
        }
    }

    private static func persist(date: String, set: Set<String>) {
        let sorted = set.sorted()
        UserDefaults.standard.set(sorted, forKey: key(date: date))
    }
}
