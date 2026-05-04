import Foundation

final class CacheService {
    static let shared = CacheService()

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
        "programme_data":     3600,
        // Health
        "recovery_data":      10 * 60,
        "cardio_data":        10 * 60,
        "acwr":               30 * 60,
        "deload_data":        30 * 60,
        // Nutrition
        "nutrition_data":     5 * 60,
        // Analytics — computed server-side, changes rarely
        "insights":           30 * 60,
        "life_stress":        30 * 60,
        "morning_brief_data": 5 * 60,
        "smart_day":          30 * 60,
        "weekly_report":      3600,
        // Profile
        "profil_data":        30 * 60,
        // Coach tip: valid all day — keyed by date so auto-rotates at midnight
        "coach_tip":          24 * 3600,
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
        let expiry = Date().addingTimeInterval(ttl).timeIntervalSince1970
        let expiryData = withUnsafeBytes(of: expiry) { Data($0) }
        try? expiryData.write(to: expiryURL(for: key), options: .atomic)
    }

    func load(for key: String) -> Data? {
        // L1: memory hit — no disk I/O
        if let hit = mem.object(forKey: key as NSString) { return hit as Data }

        // L2: disk — check expiry first
        if let expiryData = try? Data(contentsOf: expiryURL(for: key)),
           expiryData.count == MemoryLayout<Double>.size {
            let expiry = expiryData.withUnsafeBytes { $0.load(as: Double.self) }
            if Date().timeIntervalSince1970 > expiry {
                try? FileManager.default.removeItem(at: fileURL(for: key))
                try? FileManager.default.removeItem(at: expiryURL(for: key))
                return nil
            }
        }
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        mem.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        return data
    }

    func clear(for key: String) {
        mem.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: fileURL(for: key))
        try? FileManager.default.removeItem(at: expiryURL(for: key))
    }
}
