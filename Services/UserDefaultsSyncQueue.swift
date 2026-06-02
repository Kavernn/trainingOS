import Foundation
import OSLog

private let syncQueueLogger = Logger(subsystem: "TrainingOS", category: "sync_queue")

/// UserDefaults-backed queue for offline mutations.
/// Replaces SwiftData so SyncManager works on all iOS versions.
final class UserDefaultsSyncQueue {

    private static let key = "sync_queue_v2"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [PendingMutation] {
        guard let data = defaults.data(forKey: Self.key),
              let mutations = try? JSONDecoder().decode([PendingMutation].self, from: data)
        else { return [] }
        return mutations
    }

    func append(_ mutation: PendingMutation) {
        var all = load()
        all.append(mutation)
        persist(all)
    }

    func update(_ mutation: PendingMutation) {
        var all = load()
        if let idx = all.firstIndex(where: { $0.id == mutation.id }) {
            all[idx] = mutation
        }
        persist(all)
    }

    func removeAll(where predicate: (PendingMutation) -> Bool) {
        persist(load().filter { !predicate($0) })
    }

    func pendingCount(maxRetries: Int) -> Int {
        load().filter { !$0.isSynced && $0.retryCount < maxRetries }.count
    }

    private func persist(_ mutations: [PendingMutation]) {
        do {
            defaults.set(try JSONEncoder().encode(mutations), forKey: Self.key)
        } catch {
            syncQueueLogger.error("SyncQueue persist failed: \(error)")
        }
    }
}
