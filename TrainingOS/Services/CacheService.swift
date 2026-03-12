import Foundation

final class CacheService {
    static let shared = CacheService()

    private let directory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("APICache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    private func fileURL(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
                      .replacingOccurrences(of: "?", with: "_")
        return directory.appendingPathComponent("\(safe).cache")
    }

    func save(_ data: Data, for key: String) {
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func load(for key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    func clear(for key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }
}
