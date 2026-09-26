import Foundation
import CryptoKit

enum DayComposerSourceAdmission: Equatable {
    enum Denial: Error, Equatable {
        case legacyWithoutProvenance, contextMismatch, invalidated, interruptedWrite
        case corrupt, unsupportedVersion, sourceMismatch, integrityMismatch, storageUnavailable
    }
    case fresh
    case validated(executionID: UUID, revision: Int)
    case denied(Denial)
}

struct DayComposerRecoveryProvenance: Codable, Equatable {
    struct SourceState: Codable, Equatable {
        enum Validity: String, Codable { case valid, invalidated }
        var validity: Validity = .valid
        var revision: Int = 0
        // Non-nil is a durable, fail-closed in-progress marker, never an ACK.
        var pendingMutation: UUID?
        var integrity: String
    }
    let schemaVersion: Int
    let executionID: UUID
    let context: DayComposerExecutionContext
    var morning: SourceState
    var evening: SourceState

    subscript(source: DayComposerSource) -> SourceState {
        get { source == .morning ? morning : evening }
        set {
            if source == .morning { morning = newValue } else { evening = newValue }
        }
    }
}

/// Attribution only. Recovery values remain in their existing stores/keys.
/// One authoritative file per date, NOT one record per program.
/// Atomic file replacement precedes recovery writes. A pending marker, an I/O
/// error or a mismatch with UserDefaults after relaunch always denies admission.
/// This is not a transaction across files/UserDefaults, nor a power-loss guarantee.
final class DayComposerProvenanceStore {
    static let shared = DayComposerProvenanceStore()
    private static let lock = NSRecursiveLock()

    struct Authorization {
        let context: DayComposerExecutionContext
        let source: DayComposerSource
        let executionID: UUID
        fileprivate init(context: DayComposerExecutionContext, source: DayComposerSource, executionID: UUID) {
            self.context = context
            self.source = source
            self.executionID = executionID
        }
    }
    struct Mutation {
        fileprivate let authorization: Authorization
        fileprivate let id: UUID
        fileprivate let revision: Int
    }
    struct Inventory: Equatable {
        let hasState: Bool
        let integrity: String
    }

    let defaults: UserDefaults
    let directory: URL
    private let writeRecord: (Data, URL) throws -> Void

    init(defaults: UserDefaults = .standard, directory: URL? = nil,
         writeRecord: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DayComposerProvenance", isDirectory: true)
        self.writeRecord = writeRecord
    }

    /// Logical key: day_composer_provenance.v1.<SHA256(UTF8(date))>.json
    func recordURL(date: String) -> URL {
        directory.appendingPathComponent("day_composer_provenance.v1.\(Self.hash(Data(date.utf8))).json")
    }
    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func locked<T>(_ operation: () throws -> T) rethrows -> T {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try operation()
    }

    /// Raw presence matters: empty comments, corrupt payloads and out-of-plan
    /// cards count. Hashes contain no recoverable copy of their contents.
    func inventory(date: String, source: DayComposerSource) throws -> Inventory {
        let suffix = "\(source.rawValue)_\(date)"
        let exact = Set(["session_draft_", "session_comment_", "session_draft_protection_",
                         "session_started_at_", "session_chrono_paused_", "session_chrono_is_paused_",
                         "session_chrono_paused_at_"].map { $0 + suffix })
        let prefix = "exo_draft_\(date)_\(source.rawValue)_"
        let values = defaults.dictionaryRepresentation().filter { exact.contains($0.key) || $0.key.hasPrefix(prefix) }
        // Sorted outer array, opaque existing Data payloads; no dictionary ordering dependency.
        let entries: [[Any]] = values.keys.sorted().map { [$0, values[$0]!] }
        let bytes = try PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0)
        return Inventory(hasState: !values.isEmpty, integrity: Self.hash(bytes))
    }

    private func bytes(date: String) throws -> Data? {
        do { return try Data(contentsOf: recordURL(date: date)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }
    func load(date: String) throws -> DayComposerRecoveryProvenance? {
        try locked {
            guard let data = try bytes(date: date) else { return nil }
            guard let header = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = header["schemaVersion"] as? Int else { throw DayComposerSourceAdmission.Denial.corrupt }
            guard version == 1 else { throw DayComposerSourceAdmission.Denial.unsupportedVersion }
            guard let value = try? JSONDecoder().decode(DayComposerRecoveryProvenance.self, from: data),
                  value.context.date == date, Self.validContext(value.context),
                  [value.morning, value.evening].allSatisfy({ $0.revision >= 0 && Self.isDigest($0.integrity) }) else {
                throw DayComposerSourceAdmission.Denial.corrupt
            }
            return value
        }
    }
    private static func validContext(_ context: DayComposerExecutionContext) -> Bool {
        context.version == DayComposerExecutionContext.currentVersion && !context.date.isEmpty
            && !context.activeProgramID.isEmpty && isDigest(context.sourceFingerprint)
            && !context.morningSession.isEmpty && !context.eveningSession.isEmpty
    }
    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private func persist(_ record: DayComposerRecoveryProvenance) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeRecord(JSONEncoder().encode(record), recordURL(date: record.context.date))
    }

    func admission(context: DayComposerExecutionContext, source: DayComposerSource) -> DayComposerSourceAdmission {
        locked {
            do {
                guard Self.validContext(context) else { return .denied(.contextMismatch) }
                let current = try inventory(date: context.date, source: source)
                guard let record = try load(date: context.date) else {
                    return current.hasState ? .denied(.legacyWithoutProvenance) : .fresh
                }
                guard record.context.compatibility(with: context) == .compatible else { return .denied(.contextMismatch) }
                let state = record[source]
                guard state.validity == .valid else { return .denied(.invalidated) }
                guard state.pendingMutation == nil else { return .denied(.interruptedWrite) }
                guard state.integrity == current.integrity else { return .denied(.integrityMismatch) }
                return .validated(executionID: record.executionID, revision: state.revision)
            } catch let reason as DayComposerSourceAdmission.Denial { return .denied(reason) }
            catch { return .denied(.storageUnavailable) }
        }
    }

    /// Explicit establishment only. Validation/preparation never invokes this.
    @discardableResult
    func create(context: DayComposerExecutionContext) throws -> UUID {
        try locked {
            guard Self.validContext(context), try bytes(date: context.date) == nil,
                  admission(context: context, source: .morning) == .fresh,
                  admission(context: context, source: .evening) == .fresh else {
                throw DayComposerSourceAdmission.Denial.contextMismatch
            }
            let record = DayComposerRecoveryProvenance(schemaVersion: 1, executionID: UUID(), context: context,
                morning: .init(integrity: try inventory(date: context.date, source: .morning).integrity),
                evening: .init(integrity: try inventory(date: context.date, source: .evening).integrity))
            try persist(record)
            return record.executionID
        }
    }
    func authorize(context: DayComposerExecutionContext, source: DayComposerSource) throws -> Authorization {
        try locked {
            guard case .validated(let id, _) = admission(context: context, source: source) else {
                throw DayComposerSourceAdmission.Denial.contextMismatch
            }
            return Authorization(context: context, source: source, executionID: id)
        }
    }
    func begin(_ authorization: Authorization) throws -> Mutation {
        try locked {
            guard case .validated(let id, let revision) = admission(context: authorization.context, source: authorization.source),
                  id == authorization.executionID, revision < Int.max,
                  var record = try load(date: authorization.context.date) else {
                throw DayComposerSourceAdmission.Denial.contextMismatch
            }
            let mutation = Mutation(authorization: authorization, id: UUID(), revision: revision)
            record[authorization.source].pendingMutation = mutation.id
            try persist(record) // Must succeed BEFORE touching recovery.
            return mutation
        }
    }
    func finish(_ mutation: Mutation) throws {
        try locked {
            let auth = mutation.authorization
            guard var record = try load(date: auth.context.date), record.executionID == auth.executionID,
                  record.context == auth.context, record[auth.source].validity == .valid,
                  record[auth.source].pendingMutation == mutation.id,
                  record[auth.source].revision == mutation.revision else {
                throw DayComposerSourceAdmission.Denial.interruptedWrite
            }
            record[auth.source].integrity = try inventory(date: auth.context.date, source: auth.source).integrity
            record[auth.source].revision += 1
            record[auth.source].pendingMutation = nil
            try persist(record) // Failure leaves pending on disk. Never repair it on read.
        }
    }

    func invalidate(date: String, source: DayComposerSource) throws {
        try locked {
            let record: DayComposerRecoveryProvenance?
            do { record = try load(date: date) }
            catch is DayComposerSourceAdmission.Denial { return } // Already permanently denied; retain corrupt bytes.
            guard var record, record[source].validity != .invalidated else { return }
            record[source].validity = .invalidated
            try persist(record)
        }
    }
    func invalidateAll(date: String) throws {
        try invalidate(date: date, source: .morning)
        try invalidate(date: date, source: .evening)
    }
    /// Explicit removal is allowed only after ALL covered recovery has been cleared.
    func clear(date: String) throws {
        try locked {
            guard try !inventory(date: date, source: .morning).hasState,
                  try !inventory(date: date, source: .evening).hasState else {
                throw DayComposerSourceAdmission.Denial.contextMismatch
            }
            if try bytes(date: date) != nil { try FileManager.default.removeItem(at: recordURL(date: date)) }
        }
    }

    /// Synchronous boundary shared by existing persistence primitives. No ambient
    /// authorization, no Combine, no recovery callbacks from provenance itself.
    @discardableResult
    func mutate(date: String, sessionType: String, authorization: Authorization? = nil,
                _ write: () -> Void) -> Bool {
        locked {
            do {
                guard let source = DayComposerSource(rawValue: sessionType) else {
                    guard authorization == nil else { return false }
                    write()
                    return true
                }
                if let authorization {
                    guard authorization.context.date == date, authorization.source == source else { return false }
                    let mutation = try begin(authorization)
                    write()
                    try finish(mutation)
                } else {
                    try invalidate(date: date, source: source)
                    write()
                }
                return true
            } catch { return false } // No write if begin/invalidation failed; pending preserved if finish failed.
        }
    }
}
