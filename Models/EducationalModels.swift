import Foundation

struct EducationalCapsule: Codable, Identifiable {
    let id: Int
    let category: String
    let title: String
    let body: String
    let movementPattern: String?
    let muscleSpecific: String?
    let tags: [String]?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, category, title, body, tags
        case movementPattern = "movement_pattern"
        case muscleSpecific  = "muscle_specific"
        case createdAt       = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(Int.self, forKey: .id)
        category        = try c.decode(String.self, forKey: .category)
        title           = try c.decode(String.self, forKey: .title)
        body            = try c.decode(String.self, forKey: .body)
        movementPattern = try c.decodeIfPresent(String.self, forKey: .movementPattern)
        muscleSpecific  = try c.decodeIfPresent(String.self, forKey: .muscleSpecific)
        tags            = try c.decodeIfPresent([String].self, forKey: .tags)
        createdAt       = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

// MARK: - Lesson of Day (UserDefaults, local-only, mono-device)
//
// Une capsule par jour, figée par date. Tirage random parmi les non-vues.
// Pas de markRead — la carte reste consultable toute la journée (décision A).

enum LessonOfDayStore {
    private static let seenKey      = "lessonOfDay.seenIds"
    private static let todayIdKey   = "lessonOfDay.todayId"
    private static let todayDateKey = "lessonOfDay.todayDate"

    static func seenIds() -> Set<Int> {
        let raw = UserDefaults.standard.array(forKey: seenKey) as? [Int] ?? []
        return Set(raw)
    }

    /// Renvoie la capsule du jour, ou nil si toutes vues (état "épuisé").
    /// - Si une capsule est déjà figée pour `todayStr` et toujours présente
    ///   dans `all` → la retourne (stable sur la journée).
    /// - Sinon : tire au hasard parmi les non-vues, persiste, ajoute à seenIds.
    static func todayLesson(from all: [EducationalCapsule], todayStr: String) -> EducationalCapsule? {
        let defaults = UserDefaults.standard

        if defaults.string(forKey: todayDateKey) == todayStr,
           let savedId = defaults.object(forKey: todayIdKey) as? Int,
           let pinned = all.first(where: { $0.id == savedId }) {
            return pinned
        }

        let seen = seenIds()
        let pool = all.filter { !seen.contains($0.id) }
        guard let pick = pool.randomElement() else { return nil }

        var newSeen = seen
        newSeen.insert(pick.id)
        defaults.set(Array(newSeen), forKey: seenKey)
        defaults.set(pick.id, forKey: todayIdKey)
        defaults.set(todayStr, forKey: todayDateKey)
        return pick
    }
}
