import Foundation

final class CacheService {
    static let shared = CacheService()

    private let directory: URL

    /// TTL in seconds per cache key (default: 3600s / 1h)
    private static let ttls: [String: TimeInterval] = [
        "dashboard":       5 * 60,
        "seance_data":     5 * 60,
        "historique_data": 10 * 60,
        "stats_data":      15 * 60,
        "programme_data":  3600,
        "recovery_data":   10 * 60,
        "cardio_data":     10 * 60,
        "nutrition_data":  5 * 60,
        "profil_data":     30 * 60,
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

    func save(_ data: Data, for key: String) {
        try? data.write(to: fileURL(for: key), options: .atomic)
        let ttl = Self.ttls[key] ?? 3600
        let expiry = Date().addingTimeInterval(ttl).timeIntervalSince1970
        let expiryData = withUnsafeBytes(of: expiry) { Data($0) }
        try? expiryData.write(to: expiryURL(for: key), options: .atomic)
    }

    func load(for key: String) -> Data? {
        // Check expiry
        if let expiryData = try? Data(contentsOf: expiryURL(for: key)),
           expiryData.count == MemoryLayout<Double>.size {
            let expiry = expiryData.withUnsafeBytes { $0.load(as: Double.self) }
            if Date().timeIntervalSince1970 > expiry {
                // Expired — evict
                try? FileManager.default.removeItem(at: fileURL(for: key))
                try? FileManager.default.removeItem(at: expiryURL(for: key))
                return nil
            }
        }
        return try? Data(contentsOf: fileURL(for: key))
    }

    func clear(for key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
        try? FileManager.default.removeItem(at: expiryURL(for: key))
    }
}
