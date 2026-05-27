import Foundation

final class CacheService {
    static let shared = CacheService()

    // Bump this when any API response schema changes to auto-clear stale disk cache.
    private static let schemaVersion = "v6"

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

    /// TTL in seconds per cache key (default: 3600s / 1h)
    private static let ttls: [String: TimeInterval] = [
        // Core
        "dashboard":          5 * 60,
        "seance_data":        5 * 60,
        "seance_soir_data":   5 * 60,
        "historique_data":    10 * 60,
        "stats_data":         15 * 60,
        "programme_data":     24 * 3600,
        // Health
        "recovery_data":      3600,
        "cardio_data":        10 * 60,
        "acwr":               30 * 60,
        // Nutrition
        "nutrition_data":     5 * 60,
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
    ]

    init(directory: URL? = nil) {
        let dir = directory ?? {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return docs.appendingPathComponent("APICache", isDirectory: true)
        }()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
    }

    private func fileURL(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
                      .replacingOccurrences(of: "?", with: "_")
        return directory.appendingPathComponent("\(safe).cache")
    }

    private func expiryURL(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
                      .replacingOccurrences(of: "?", with: "_")
        return directory.appendingPathComponent("\(safe).expiry")
    }

    private func savedAtURL(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
                      .replacingOccurrences(of: "?", with: "_")
        return directory.appendingPathComponent("\(safe).savedAt")
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
        try? data.write(to: fileURL(for: key), options: .atomic)
        let ttl = ttl(for: key)
        let now = Date().timeIntervalSince1970
        let expiry = now + ttl
        let expiryData = withUnsafeBytes(of: expiry) { Data($0) }
        try? expiryData.write(to: expiryURL(for: key), options: .atomic)
        let savedAtData = withUnsafeBytes(of: now) { Data($0) }
        try? savedAtData.write(to: savedAtURL(for: key), options: .atomic)
    }

    func load(for key: String) -> Data? {
        // L1: memory hit — no disk I/O
        if let hit = mem.object(forKey: key as NSString) { return hit as Data }

        // L2: disk — check expiry first; expired files kept for stale-while-revalidate
        if let expiryData = try? Data(contentsOf: expiryURL(for: key)),
           expiryData.count == MemoryLayout<Double>.size {
            let expiry = expiryData.withUnsafeBytes { $0.load(as: Double.self) }
            if Date().timeIntervalSince1970 > expiry { return nil }
        }
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        mem.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        return data
    }

    func clear(for key: String) {
        mem.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: fileURL(for: key))
        try? FileManager.default.removeItem(at: expiryURL(for: key))
        try? FileManager.default.removeItem(at: savedAtURL(for: key))
    }

    /// Returns the timestamp when this key was last saved, or nil if never.
    func savedAt(for key: String) -> Date? {
        guard let data = try? Data(contentsOf: savedAtURL(for: key)),
              data.count == MemoryLayout<Double>.size else { return nil }
        let epoch = data.withUnsafeBytes { $0.load(as: Double.self) }
        return Date(timeIntervalSince1970: epoch)
    }

    /// Reads disk cache regardless of expiry — never promotes stale data to mem cache.
    /// Use in stale-while-revalidate paths: show old value while background refresh runs.
    func loadIncludingStale(for key: String) -> (data: Data?, isExpired: Bool, savedAt: Date?) {
        var isExpired = true
        if let expiryData = try? Data(contentsOf: expiryURL(for: key)),
           expiryData.count == MemoryLayout<Double>.size {
            let expiry = expiryData.withUnsafeBytes { $0.load(as: Double.self) }
            isExpired = Date().timeIntervalSince1970 > expiry
        }
        guard let data = try? Data(contentsOf: fileURL(for: key)) else {
            return (nil, true, nil)
        }
        return (data, isExpired, savedAt(for: key))
    }
}
