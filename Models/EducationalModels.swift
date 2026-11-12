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
    private static let seenAtKey    = "lessonOfDay.seenAt"      // [String(id): unixTimestamp]
    private static let todayIdKey   = "lessonOfDay.todayId"
    private static let todayDateKey = "lessonOfDay.todayDate"
    private static let todayRevKey  = "lessonOfDay.todayIsRevision"

    struct DailyPick: Equatable {
        let capsule: EducationalCapsule
        let isRevision: Bool
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.capsule.id == rhs.capsule.id && lhs.isRevision == rhs.isRevision
        }
    }

    /// Présentation canonique de la carte "Leçon du jour". Garantit qu'aucun
    /// état de la vue ne produit de carte invisible : pas de pick + pas d'échec
    /// réseau = pool live réellement vide (DB sans aucune capsule).
    enum Presentation: Equatable {
        case present(DailyPick)
        case refreshFailed
        case absent     // pool live vide (cas limite, DB sans capsules)
    }

    static func presentation(pick: DailyPick?, refreshFailedToday: Bool) -> Presentation {
        if let pick { return .present(pick) }
        if refreshFailedToday { return .refreshFailed }
        return .absent
    }

    static func seenIds() -> Set<Int> {
        let raw = UserDefaults.standard.array(forKey: seenKey) as? [Int] ?? []
        return Set(raw)
    }

    private static func seenAt() -> [Int: Double] {
        let raw = UserDefaults.standard.dictionary(forKey: seenAtKey) as? [String: Double] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
    }

    /// Purge de seenIds les IDs absents du pool live (capsules soft-deleted côté DB).
    /// Appelée avant `todayPick` lors d'un refresh live pour éviter que des IDs
    /// zombie gonflent artificiellement la couverture.
    static func reconcileSeen(against liveIds: Set<Int>) {
        let seen = seenIds()
        let cleaned = seen.intersection(liveIds)
        if cleaned != seen {
            UserDefaults.standard.set(Array(cleaned), forKey: seenKey)
            let at = seenAt().filter { liveIds.contains($0.key) }
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: at.map { (String($0.key), $0.value) }), forKey: seenAtKey)
        }
    }

    /// Choix du jour. `isRevision=false` si une capsule non-vue existe,
    /// `isRevision=true` si le pool est épuisé (reprend la plus anciennement vue).
    /// Retourne nil UNIQUEMENT si le pool live est vide (jamais en temps normal).
    static func todayPick(from all: [EducationalCapsule], todayStr: String) -> DailyPick? {
        guard !all.isEmpty else { return nil }
        let defaults = UserDefaults.standard

        if defaults.string(forKey: todayDateKey) == todayStr,
           let savedId = defaults.object(forKey: todayIdKey) as? Int,
           let pinned = all.first(where: { $0.id == savedId }) {
            return DailyPick(capsule: pinned, isRevision: defaults.bool(forKey: todayRevKey))
        }

        let seen = seenIds()
        let unseen = all.filter { !seen.contains($0.id) }

        if let pick = unseen.randomElement() {
            markPicked(pick.id, todayStr: todayStr, isRevision: false)
            return DailyPick(capsule: pick, isRevision: false)
        }

        // Pool épuisé → révision. La plus anciennement vue d'abord ;
        // capsules sans timestamp (vues avant l'ajout du suivi) → .distantPast.
        let at = seenAt()
        let oldest = all.min { (at[$0.id] ?? 0) < (at[$1.id] ?? 0) }
        guard let pick = oldest else { return nil }
        markPicked(pick.id, todayStr: todayStr, isRevision: true)
        return DailyPick(capsule: pick, isRevision: true)
    }

    /// Si la capsule du jour est en révision ET qu'au moins une capsule non-vue
    /// existe dans `all`, remplace la révision par la nouveauté (priorité aux
    /// nouvelles capsules). Appelée après un refresh live réussi.
    @discardableResult
    static func supersedeRevisionIfPossible(from all: [EducationalCapsule], todayStr: String) -> DailyPick? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: todayDateKey) == todayStr,
              defaults.bool(forKey: todayRevKey) else { return nil }
        let seen = seenIds()
        let unseen = all.filter { !seen.contains($0.id) }
        guard let pick = unseen.randomElement() else { return nil }
        markPicked(pick.id, todayStr: todayStr, isRevision: false)
        return DailyPick(capsule: pick, isRevision: false)
    }

    private static func markPicked(_ id: Int, todayStr: String, isRevision: Bool) {
        let d = UserDefaults.standard
        var seen = seenIds(); seen.insert(id)
        d.set(Array(seen), forKey: seenKey)
        var at = d.dictionary(forKey: seenAtKey) as? [String: Double] ?? [:]
        at[String(id)] = Date().timeIntervalSince1970
        d.set(at, forKey: seenAtKey)
        d.set(id, forKey: todayIdKey)
        d.set(todayStr, forKey: todayDateKey)
        d.set(isRevision, forKey: todayRevKey)
    }
}
