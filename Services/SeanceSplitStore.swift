import Foundation
import OSLog

private let splitLogger = Logger(subsystem: "TrainingOS", category: "seance_split")

extension Notification.Name {
    static let seanceSplitStoreDidChange = Notification.Name("seanceSplitStoreDidChange")
}

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
        notifyChange()
    }

    static func remove(date: String, exercise: String) {
        var current = load(date: date)
        current.remove(exercise)
        if current.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(date: date))
        } else {
            persist(date: date, set: current)
        }
        notifyChange()
    }

    static func contains(date: String, exercise: String) -> Bool {
        load(date: date).contains(exercise)
    }

    static func clear(date: String) {
        UserDefaults.standard.removeObject(forKey: key(date: date))
        notifyChange()
    }

    /// Self-healing : retire du Set les exos déjà loggés (utile si un log a été fait
    /// avant l'instauration du remove dans finish(), ou via un path qui ne décrémente pas).
    static func reconcile(date: String, loggedNames: Set<String>) {
        let current = load(date: date)
        let cleaned = current.subtracting(loggedNames)
        guard cleaned.count != current.count else { return }
        if cleaned.isEmpty {
            UserDefaults.standard.removeObject(forKey: key(date: date))
        } else {
            persist(date: date, set: cleaned)
        }
        notifyChange()
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

    private static func notifyChange() {
        NotificationCenter.default.post(name: .seanceSplitStoreDidChange, object: nil)
    }
}
