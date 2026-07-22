import Foundation

final class CacheService {
    static let shared = CacheService()

    // Bump this when any API response schema changes to auto-clear stale disk cache.
    // v7: merged expiry+savedAt into 16-byte header in .cache file (eliminates .expiry/.savedAt)
    // v8: seance_data.weights.history entries now carry exercise_volume (progressive overload target)
    private static let schemaVersion = "v8"

    /// Call once at app launch. Wipes all cache files if schema version changed.
    static func invalidateIfVersionChanged() {
        let key = "cache_schema_version"
        guard UserDefaults.standard.string(forKey: key) != schemaVersion else { return }
        let c = CacheService.shared
        if let files = try? FileManager.default.contentsOfDirectory(
            at: c.directory, includingPropertiesForKeys: nil
        ) {
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        c.mem.removeAllObjects()
        UserDefaults.standard.set(schemaVersion, forKey: key)
    }

    private let directory: URL
    private let mem: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.countLimit = 60
        c.totalCostLimit = 20 * 1024 * 1024  // 20 MB
        return c
    }()
    private var memoryKeys = Set<String>()
    private let keysLock   = NSLock()

    /// TTL in seconds per cache key (default: 3600s / 1h)
    private static let ttls: [String: TimeInterval] = [
        // Core — invalidated explicitly after each workout log / session complete
        "dashboard":          30 * 60,
        "seance_data":        30 * 60,
        "seance_soir_data":   30 * 60,
        "historique_data":    60 * 60,
        "stats_data":         60 * 60,
        "programme_data":     24 * 3600,
        // Health
        "recovery_data":      3600,
        // Readiness score + history 14j — matches backend readiness cache TTL 1800s (readiness.py:736)
        "readiness":          30 * 60,
        "readiness_history":  30 * 60,
        "cardio_data":        30 * 60,
        "acwr":               60 * 60,
        // Streak — invalidated on session logged
        "streak_data":        5 * 60,
        // Nutrition — invalidated explicitly on food log
        "nutrition_data":     30 * 60,
        // Coach memory — local UserDefaults, but registered for consistency
        "coach_memory":       60 * 60,
        // Analytics — computed server-side, changes rarely
        "insights":           30 * 60,
        "life_stress":        30 * 60,
        "smart_day":          30 * 60,
        "weekly_report":      3600,
        // Profile
        "profil_data":        30 * 60,
        // Coach tip: valid all day — keyed by date so auto-rotates at midnight
        "coach_tip":          24 * 3600,
        // Ritual — force-cleared on write but still registered for consistency
        "ritual_today": 5 * 60,
        "ritual_streak": 5 * 60,
        // Morning brief — generated once per morning, valid 1 h
        "morning_brief": 3600,
        // Weather — Open-Meteo, refreshed every 30 min
        "weather_data":  1800,
        // Coach analytics (cartes bilan) — data physio du jour + agrégations lentes
        "overtraining_risk":   30 * 60,    // dépend des logs du jour, même famille que readiness
        "one_rm_programming":  30 * 60,    // change à chaque /api/log via weights.history
        "mesocycle_status":    60 * 60,    // active_program.cycle_start_date change rare
        "pain_journal":        60 * 60,    // agrégat exercise_logs.pain_zone, change lent
        // Coach page — 7 clés autrefois sur défaut implicite 3600s, désormais explicites.
        // Filet vs mécanisme principal : quand une invalidation existe (plateau/patterns),
        // TTL long OK ; sinon TTL = seul rempart contre le stale, aligné readiness (30 min).
        "plateau_alerts":       60 * 60,        // invalidé par plateauDismissed → filet
        "patterns_daily":       30 * 60,        // invalidé par patternsPinMutated → filet quotidien
        "workout_dna_90":       6 * 3600,       // agrégation 90j, une séance bouge peu
        "insights_correlations": 6 * 3600,      // corrélations historique long
        "educational":          24 * 3600,      // contenu éditorial statique (préfixe match: educational_all / educational_<cat>)
        "daily_insight":        30 * 60,        // dérivé readiness/sessions sans invalidation, TTL = seul filet
        "proactive_insights":   30 * 60,        // recalculé selon état du jour, famille readiness
        // Progression suggestions — clef par date+sessionType+sessionName (préfixe match).
        // Invalidé par sessionLogged (nouveaux logs = nouvelles suggestions) et programmeMutated.
        "progression_suggestions": 30 * 60,
    ]

    init(directory: URL? = nil) {
        let dir = directory ?? {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return docs.appendingPathComponent("APICache", isDirectory: true)
        }()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
    }

    // File layout: [expiry: Double 8B][savedAt: Double 8B][payload]
    private static let headerSize = MemoryLayout<Double>.size * 2

    private func fileURL(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
                      .replacingOccurrences(of: "?", with: "_")
        return directory.appendingPathComponent("\(safe).cache")
    }

    private func ttl(for key: String) -> TimeInterval {
        if let exact = Self.ttls[key] { return exact }
        // Prefix match: "coach_tip_2026-04-16" → "coach_tip"
        for (prefix, value) in Self.ttls where key.hasPrefix(prefix + "_") {
            return value
        }
        return 3600
    }

    func save(_ data: Data, for key: String) {
        mem.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        keysLock.withLock { memoryKeys.insert(key) }
        let now    = Date().timeIntervalSince1970
        let expiry = now + ttl(for: key)
        var file   = Data(capacity: Self.headerSize + data.count)
        withUnsafeBytes(of: expiry) { file.append(contentsOf: $0) }
        withUnsafeBytes(of: now)    { file.append(contentsOf: $0) }
        file.append(data)
        try? file.write(to: fileURL(for: key), options: .atomic)
    }

    func load(for key: String) -> Data? {
        // L1: memory hit — no disk I/O
        if let hit = mem.object(forKey: key as NSString) { return hit as Data }

        // L2: single disk read — header contains expiry, rest is payload
        guard let file = try? Data(contentsOf: fileURL(for: key)),
              file.count > Self.headerSize else { return nil }
        let expiry = file.withUnsafeBytes { $0.load(as: Double.self) }
        if Date().timeIntervalSince1970 > expiry { return nil }
        let payload = file.subdata(in: Self.headerSize..<file.count)
        mem.setObject(payload as NSData, forKey: key as NSString, cost: payload.count)
        return payload
    }

    func clear(for key: String) {
        mem.removeObject(forKey: key as NSString)
        keysLock.withLock { memoryKeys.remove(key) }
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    func clear(prefix: String) {
        let safe = prefix.replacingOccurrences(of: "/", with: "_")
                         .replacingOccurrences(of: "?", with: "_")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for url in files where url.lastPathComponent.hasPrefix(safe) {
            try? FileManager.default.removeItem(at: url)
        }
        keysLock.withLock {
            for key in memoryKeys where key.hasPrefix(prefix) {
                mem.removeObject(forKey: key as NSString)
            }
            memoryKeys = memoryKeys.filter { !$0.hasPrefix(prefix) }
        }
    }

    /// Reads disk cache regardless of expiry — never promotes stale data to mem cache.
    /// Use in stale-while-revalidate paths: show old value while background refresh runs.
    func loadIncludingStale(for key: String) -> (data: Data?, isExpired: Bool, savedAt: Date?) {
        guard let file = try? Data(contentsOf: fileURL(for: key)),
              file.count > Self.headerSize else { return (nil, true, nil) }
        let expiry  = file.withUnsafeBytes { $0.load(as: Double.self) }
        let savedAt = file.withUnsafeBytes { $0.load(fromByteOffset: MemoryLayout<Double>.size, as: Double.self) }
        let payload = file.subdata(in: Self.headerSize..<file.count)
        let isExpired = Date().timeIntervalSince1970 > expiry
        return (payload, isExpired, Date(timeIntervalSince1970: savedAt))
    }
}
