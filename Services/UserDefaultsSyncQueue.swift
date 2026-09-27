import Foundation
import OSLog

private let syncQueueLogger = Logger(subsystem: "TrainingOS", category: "sync_queue")

/// UserDefaults-backed queue for offline mutations.
/// Replaces SwiftData so SyncManager works on all iOS versions.
final class UserDefaultsSyncQueue {

    private static let key = "sync_queue_v2"
    private static let historyKey = "sync_correlation_v1"
    // Serializes read/modify/write across store instances in this process.
    // UserDefaults is the existing persistence contract, not a filesystem fsync guarantee.
    private static let lock = NSRecursiveLock()
    static let terminalRetention: TimeInterval = 30 * 86_400
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [PendingMutation] {
        locked { (try? readQueue()) ?? [] }
    }

    func append(_ mutation: PendingMutation) {
        legacyWrite {
            var all = try readQueue()
            all.append(mutation)
            try write(all, key: Self.key)
        }
    }

    func update(_ mutation: PendingMutation) {
        legacyWrite {
            var all = try readQueue()
            if let idx = all.firstIndex(where: { $0.id == mutation.id }) {
                if all[idx].operationKey != nil || mutation.operationKey != nil {
                    guard sameRequest(all[idx], mutation) else { throw OfflineCorrelationError.payloadConflict }
                }
                all[idx] = mutation
            }
            try write(all, key: Self.key)
        }
    }

    func removeAll(where predicate: (PendingMutation) -> Bool) {
        legacyWrite {
            var all = try readQueue()
            var removals = Set(all.filter { predicate($0) && $0.operationKey == nil }.map(\.id))
            // No correlated deletion without first recording its outcome.
            for mutation in all.filter(predicate) where mutation.operationKey != nil {
                guard let key = mutation.operationKey else { continue }
                guard all.filter({ $0.operationKey == key }).count == 1 else { continue }
                var history = try readHistory()
                if let existing = history[key.rawValue] {
                    guard existing.receipt?.mutationID == mutation.id else { continue }
                } else {
                    history[key.rawValue] = record(mutation, state: .uncertain, reason: "removedWithoutDelivery")
                    try write(history, key: Self.historyKey)
                }
                removals.insert(mutation.id)
            }
            all.removeAll { removals.contains($0.id) }
            try write(all, key: Self.key)
        }
    }

    func pendingCount(maxRetries: Int) -> Int {
        load().filter {
            guard !$0.isSynced && $0.retryCount < maxRetries else { return false }
            guard let key = $0.operationKey else { return true }
            if case .pending = status(for: key) { return true }
            return false
        }.count
    }

    /// One synchronous transaction: operationKey lives in the queue itself.
    func enqueue(endpoint: String, method: String, payloadData: Data,
                 operationKey: OfflineOperationKey) throws -> OfflineMutationReceipt {
        try locked {
            guard !operationKey.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OfflineCorrelationError.invalidKey
            }
            var all = try readQueue()
            _ = try readHistory() // Never overwrite an unreadable journal.
            switch status(for: operationKey) {
            case .notFound: break
            case .pending(let receipt):
                guard let old = all.first(where: { $0.id == receipt.mutationID }),
                      old.endpoint == endpoint, old.method == method,
                      equivalentJSON(old.payloadData, payloadData) else {
                    throw OfflineCorrelationError.payloadConflict
                }
                return receipt
            case let existing: throw OfflineCorrelationError.existing(existing)
            }
            let mutation = PendingMutation(endpoint: endpoint, method: method,
                                           payloadData: payloadData, operationKey: operationKey)
            all.append(mutation)
            try write(all, key: Self.key)
            guard let receipt = mutation.receipt else { throw OfflineCorrelationError.persistenceFailed }
            return receipt
        }
    }

    func status(for key: OfflineOperationKey) -> OfflineMutationStatus {
        locked {
            let queueResult = Result { try readQueue() }
            let historyResult = Result { try readHistory() }
            let matching = (try? queueResult.get())?.filter { $0.operationKey == key } ?? []
            if matching.count > 1 {
                return .uncertain(unknown(key, reason: "duplicateOperationKey"))
            }
            guard let history = try? historyResult.get() else {
                return .uncertain(unknown(key, reason: "corruptHistory"))
            }
            if var record = history[key.rawValue] {
                if let mutation = matching.first, record.receipt?.mutationID != mutation.id {
                    return .uncertain(unknown(key, reason: "receiptMismatch"))
                }
                switch record.state {
                case .delivered: return .delivered(record)
                case .discarded: return .discarded(record)
                case .attempting:
                    record.state = .uncertain
                    record.reason = "attemptWithoutDurableOutcome"
                    return .uncertain(record)
                case .uncertain: return .uncertain(record)
                }
            }
            guard (try? queueResult.get()) != nil else {
                return .uncertain(unknown(key, reason: "corruptQueue"))
            }
            guard let mutation = matching.first else { return .notFound }
            guard !mutation.isSynced, let receipt = mutation.receipt else {
                return .uncertain(record(mutation, state: .uncertain, reason: "legacySyncedIsNotDelivery"))
            }
            return .pending(receipt)
        }
    }

    /// Must finish durably before the caller sends any bytes.
    func beginAttempt(_ mutation: PendingMutation) throws {
        try locked {
            guard let key = mutation.operationKey, case .pending(let receipt) = status(for: key),
                  receipt.mutationID == mutation.id,
                  try readQueue().contains(where: { $0.id == mutation.id && sameRequest($0, mutation) }) else {
                throw OfflineCorrelationError.corruptStorage
            }
            var history = try readHistory()
            history[key.rawValue] = record(mutation, state: .attempting)
            try write(history, key: Self.historyKey)
        }
    }

    /// Terminal-first. A crash before removal is reconciled without sending again.
    func finishAttempt(_ mutation: PendingMutation, state: OfflineMutationRecord.State,
                       statusCode: Int? = nil, reason: String? = nil) throws {
        try locked {
            guard state != .attempting, let key = mutation.operationKey else {
                throw OfflineCorrelationError.corruptStorage
            }
            var all = try readQueue()
            guard all.filter({ $0.operationKey == key }).count == 1,
                  all.contains(where: { $0.id == mutation.id && sameRequest($0, mutation) }) else {
                throw OfflineCorrelationError.corruptStorage
            }
            var history = try readHistory()
            if let existing = history[key.rawValue] {
                guard existing.state == .attempting, existing.receipt == mutation.receipt else {
                    throw OfflineCorrelationError.existing(status(for: key))
                }
            }
            history[key.rawValue] = record(mutation, state: state, code: statusCode, reason: reason)
            try write(history, key: Self.historyKey)
            all.removeAll { $0.id == mutation.id }
            try write(all, key: Self.key)
        }
    }

    /// Explicit retryable result: persist retry/backoff before removing the attempt marker.
    func retryAttempt(_ mutation: PendingMutation) throws {
        try locked {
            guard let key = mutation.operationKey else { throw OfflineCorrelationError.corruptStorage }
            var history = try readHistory()
            guard history[key.rawValue]?.state == .attempting,
                  history[key.rawValue]?.receipt?.mutationID == mutation.id else {
                throw OfflineCorrelationError.corruptStorage
            }
            var all = try readQueue()
            guard all.filter({ $0.operationKey == key }).count == 1,
                  let index = all.firstIndex(where: { $0.id == mutation.id && sameRequest($0, mutation) }) else {
                throw OfflineCorrelationError.corruptStorage
            }
            all[index] = mutation
            try write(all, key: Self.key)
            history.removeValue(forKey: key.rawValue)
            try write(history, key: Self.historyKey)
        }
    }

    /// Before replay, seal abandoned attempts and reconcile terminal/stale queue pairs.
    /// Active requests in the current manager are excluded; they aren't crashes.
    func reconcile(excluding active: Set<UUID> = []) throws {
        try locked {
            var all = try readQueue()
            var history = try readHistory()
            var removals = Set<UUID>()
            for (key, var existing) in history where existing.state == .attempting {
                if let id = existing.receipt?.mutationID, active.contains(id) { continue }
                if !all.contains(where: { $0.operationKey?.rawValue == key }) {
                    existing.state = .uncertain
                    existing.reason = "attemptWithoutQueueEntry"
                    existing.updatedAt = Date()
                    history[key] = existing
                }
            }
            for key in Set(all.compactMap(\.operationKey)) {
                let matches = all.filter { $0.operationKey == key }
                if matches.count > 1 {
                    history[key.rawValue] = unknown(key, reason: "duplicateOperationKey")
                    continue // Preserve BOTH payloads for explicit diagnosis.
                }
                guard let mutation = matches.first, !active.contains(mutation.id) else { continue }
                if var existing = history[key.rawValue] {
                    guard existing.receipt?.mutationID == mutation.id else { continue }
                    if existing.state == .attempting {
                        existing.state = .uncertain
                        existing.reason = "interruptedAttempt"
                        existing.updatedAt = Date()
                        history[key.rawValue] = existing
                    } else if existing.state == .delivered || existing.state == .discarded {
                        removals.insert(mutation.id)
                    }
                } else if mutation.isSynced {
                    history[key.rawValue] = record(mutation, state: .uncertain, reason: "legacySyncedIsNotDelivery")
                }
            }
            try write(history, key: Self.historyKey)
            all.removeAll { removals.contains($0.id) }
            try write(all, key: Self.key)
        }
    }

    /// Dedupe history is guaranteed for 30 days. Never expire a key still in queue.
    /// After expiry status is notFound, NOT delivery; callers must never recycle keys.
    func pruneTerminalHistory(now: Date = Date()) throws {
        try locked {
            let keys = Set(try readQueue().compactMap(\.operationKey))
            var history = try readHistory()
            history = history.filter { _, record in
                keys.contains(record.operationKey) || record.state == .attempting
                    || now.timeIntervalSince(record.updatedAt) < Self.terminalRetention
            }
            try write(history, key: Self.historyKey)
        }
    }

    private func readQueue() throws -> [PendingMutation] { try read([PendingMutation].self, key: Self.key, empty: []) }
    private func readHistory() throws -> [String: OfflineMutationRecord] {
        let records = try read([String: OfflineMutationRecord].self, key: Self.historyKey, empty: [:])
        guard records.allSatisfy({ key, value in
            key == value.operationKey.rawValue
                && (value.receipt == nil || value.receipt?.operationKey == value.operationKey)
                && (value.state == .uncertain || value.receipt != nil)
        }) else { throw OfflineCorrelationError.corruptStorage }
        return records
    }
    private func read<T: Decodable>(_ type: T.Type, key: String, empty: T) throws -> T {
        guard let object = defaults.object(forKey: key) else { return empty }
        guard let data = object as? Data, let decoded = try? JSONDecoder().decode(type, from: data) else {
            throw OfflineCorrelationError.corruptStorage
        }
        return decoded
    }
    private func write<T: Encodable>(_ value: T, key: String) throws {
        let bytes = try JSONEncoder().encode(value)
        defaults.set(bytes, forKey: key)
        // A correlated sender must not start transport while its attempt is only
        // buffered in memory. Failure is conservative; it never authorizes a send.
        guard defaults.synchronize(), defaults.data(forKey: key) == bytes else {
            throw OfflineCorrelationError.persistenceFailed
        }
    }
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return try body()
    }
    private func legacyWrite(_ body: () throws -> Void) {
        locked {
            do { try body() }
            catch { syncQueueLogger.error("SyncQueue write refused: \(error)") }
        }
    }
    private func record(_ mutation: PendingMutation, state: OfflineMutationRecord.State,
                        code: Int? = nil, reason: String? = nil) -> OfflineMutationRecord {
        .init(operationKey: mutation.operationKey!, receipt: mutation.receipt, state: state,
              createdAt: mutation.createdAt, updatedAt: Date(), statusCode: code, reason: reason)
    }
    private func unknown(_ key: OfflineOperationKey, reason: String) -> OfflineMutationRecord {
        .init(operationKey: key, receipt: nil, state: .uncertain, createdAt: Date(),
              updatedAt: Date(), reason: reason)
    }
    private func equivalentJSON(_ lhs: Data, _ rhs: Data) -> Bool {
        if lhs == rhs { return true }
        guard let a = try? JSONSerialization.jsonObject(with: lhs, options: [.fragmentsAllowed]),
              let b = try? JSONSerialization.jsonObject(with: rhs, options: [.fragmentsAllowed]),
              let ca = try? JSONSerialization.data(withJSONObject: a, options: [.sortedKeys, .fragmentsAllowed]),
              let cb = try? JSONSerialization.data(withJSONObject: b, options: [.sortedKeys, .fragmentsAllowed]) else { return false }
        return ca == cb // Original bytes remain untouched in the stored mutation.
    }

    private func sameRequest(_ lhs: PendingMutation, _ rhs: PendingMutation) -> Bool {
        lhs.id == rhs.id && lhs.operationKey == rhs.operationKey && lhs.endpoint == rhs.endpoint
            && lhs.method == rhs.method && lhs.payloadData == rhs.payloadData && lhs.createdAt == rhs.createdAt
    }
}
