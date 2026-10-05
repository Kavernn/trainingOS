import Foundation
import CryptoKit

enum DayComposerFinalizationError: Error, Equatable {
    case storageUnavailable, corrupt, unsupportedVersion, contextMismatch
    case conflict, writeFailed, invalidRecord
}

/// Canonical envelopes only. Payloads are hashed as supplied, never re-encoded.
enum DayComposerFinalizationCoding {
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func digest<T: Encodable>(_ prefix: String, _ value: T) throws -> String {
        prefix + ":" + hash(try encode(value))
    }

    static func require(_ condition: Bool) throws {
        guard condition else { throw DayComposerFinalizationError.invalidRecord }
    }

    static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func isDate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard value.utf8.count == 10, let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    static func validate(_ item: DayComposerItemID) throws {
        if item.exercise.hasPrefix("id:") {
            try require(UUID(uuidString: String(item.exercise.dropFirst(3))) != nil)
        } else {
            try require(item.exercise.hasPrefix("name:") && !item.exercise.dropFirst(5).isEmpty)
        }
    }

    static func precedes(_ lhs: DayComposerItemID, _ rhs: DayComposerItemID) -> Bool {
        if lhs.source != rhs.source { return lhs.source.rawValue < rhs.source.rawValue }
        return lhs.exercise < rhs.exercise
    }
}

struct DayComposerExecutionIdentity: Codable, Hashable {
    let executionID: UUID
    let contextVersion: Int
    let date: String
    let activeProgramID: String
    let sourceFingerprint: String
    let morningSession: String
    let eveningSession: String

    init(executionID: UUID, context: DayComposerExecutionContext) throws {
        self.executionID = executionID
        contextVersion = context.version
        date = context.date
        activeProgramID = context.activeProgramID
        sourceFingerprint = context.sourceFingerprint
        morningSession = context.morningSession
        eveningSession = context.eveningSession
        try validate()
    }

    var digest: String { get throws { try DayComposerFinalizationCoding.digest("dc-context-v1", self) } }

    func validate() throws {
        try DayComposerFinalizationCoding.require(contextVersion == DayComposerExecutionContext.currentVersion
            && DayComposerFinalizationCoding.isDate(date) && !activeProgramID.isEmpty
            && DayComposerFinalizationCoding.isHash(sourceFingerprint)
            && !morningSession.isEmpty && !eveningSession.isEmpty)
    }

    func session(for source: DayComposerSource) -> String {
        source == .morning ? morningSession : eveningSession
    }
}

/// An external local-provenance guard, not a network ACK or a business version.
struct DayComposerFinalizationGuard: Codable, Hashable {
    let executionID: UUID
    let source: DayComposerSource
    let revision: Int
    let integrity: String

    init(executionID: UUID, source: DayComposerSource, revision: Int, integrity: String) throws {
        self.executionID = executionID
        self.source = source
        self.revision = revision
        self.integrity = integrity
        try DayComposerFinalizationCoding.require(revision >= 0 && DayComposerFinalizationCoding.isHash(integrity))
    }

    func validate(identity: DayComposerExecutionIdentity, source: DayComposerSource) throws {
        try DayComposerFinalizationCoding.require(executionID == identity.executionID && self.source == source
            && revision >= 0 && DayComposerFinalizationCoding.isHash(integrity))
    }
}

struct DayComposerExerciseVersion: Codable, Hashable {
    let formatVersion: Int
    let operation: String
    let source: DayComposerSource
    let itemID: DayComposerItemID
    let date: String
    let payloadDigest: String

    init(itemID: DayComposerItemID, date: String, payloadData: Data, source: DayComposerSource? = nil) throws {
        formatVersion = 1
        operation = "exercise"
        self.source = source ?? itemID.source
        self.itemID = itemID
        self.date = date
        payloadDigest = DayComposerFinalizationCoding.hash(payloadData)
        try DayComposerFinalizationCoding.require(!payloadData.isEmpty)
        try validate()
    }

    var digest: String { get throws { try DayComposerFinalizationCoding.digest("dc-exercise-v1", self) } }

    func validate() throws {
        try DayComposerFinalizationCoding.validate(itemID)
        try DayComposerFinalizationCoding.require(formatVersion == 1 && operation == "exercise"
            && DayComposerFinalizationCoding.isDate(date)
            && DayComposerFinalizationCoding.isHash(payloadDigest))
    }

    func operationKey(identity: DayComposerExecutionIdentity) throws -> OfflineOperationKey {
        try identity.validate()
        try validate()
        try DayComposerFinalizationCoding.require(date == identity.date)
        // Deliberately independent of the source comment, final inputs and guard.
        let envelope = [try identity.digest, source.rawValue, itemID.exercise, try digest, "/api/log", "POST"]
        return .init(rawValue: try DayComposerFinalizationCoding.digest("dc-op-exercise-v1", envelope))
    }
}

struct DayComposerSourceVersion: Codable, Hashable {
    struct PlanReference: Codable, Hashable {
        let itemID: DayComposerItemID
        let sourceOrder: Int
        var assignedSource: DayComposerSource? = nil
    }

    let formatVersion: Int
    let source: DayComposerSource
    let sessionName: String
    let orderedItems: [PlanReference]
    let exerciseVersions: [DayComposerExerciseVersion]
    let commentDigest: String

    init(source: DayComposerSource, sessionName: String, items: [DayComposerItem],
         exerciseVersions: [DayComposerExerciseVersion], comment: String) throws {
        try DayComposerFinalizationCoding.require(items.allSatisfy { $0.assignedSource == source })
        formatVersion = 1
        self.source = source
        self.sessionName = sessionName
        orderedItems = items.map { PlanReference(itemID: $0.id, sourceOrder: $0.sourceOrder, assignedSource: $0.assignedSourceOverride) }
            .sorted(by: Self.planOrder)
        self.exerciseVersions = exerciseVersions.sorted {
            DayComposerFinalizationCoding.precedes($0.itemID, $1.itemID)
        }
        commentDigest = DayComposerFinalizationCoding.hash(Data(comment.utf8))
        try validate()
    }

    private static func planOrder(_ lhs: PlanReference, _ rhs: PlanReference) -> Bool {
        lhs.sourceOrder != rhs.sourceOrder ? lhs.sourceOrder < rhs.sourceOrder
            : DayComposerFinalizationCoding.precedes(lhs.itemID, rhs.itemID)
    }

    var digest: String { get throws { try DayComposerFinalizationCoding.digest("dc-source-v1", self) } }

    func validate() throws {
        try DayComposerFinalizationCoding.require(formatVersion == 1 && !sessionName.isEmpty
            && DayComposerFinalizationCoding.isHash(commentDigest)
            && Set(orderedItems.map(\.itemID)).count == orderedItems.count
            && Set(exerciseVersions.map(\.itemID)).count == exerciseVersions.count
            && orderedItems == orderedItems.sorted(by: Self.planOrder)
            && exerciseVersions == exerciseVersions.sorted { DayComposerFinalizationCoding.precedes($0.itemID, $1.itemID) })
        for item in orderedItems {
            try DayComposerFinalizationCoding.validate(item.itemID)
            try DayComposerFinalizationCoding.require((item.assignedSource ?? item.itemID.source) == source && item.sourceOrder >= 0)
        }
        for exercise in exerciseVersions {
            try exercise.validate()
            try DayComposerFinalizationCoding.require(exercise.source == source && orderedItems.contains { $0.itemID == exercise.itemID })
        }
        try DayComposerFinalizationCoding.require(Set(exerciseVersions.map(\.date)).count <= 1)
    }

    func validate(identity: DayComposerExecutionIdentity) throws {
        try validate()
        try DayComposerFinalizationCoding.require(sessionName == identity.session(for: source)
            && exerciseVersions.allSatisfy { $0.date == identity.date })
    }
}

struct DayComposerFinalPayloadVersion: Codable, Hashable {
    // After reopening, an owner must reproduce these exact bytes/digest before
    // submitting. This digest does not grant permission to reconstruct/retry.
    let payloadDigest: String

    init(payloadData: Data) throws {
        try DayComposerFinalizationCoding.require(!payloadData.isEmpty)
        payloadDigest = DayComposerFinalizationCoding.hash(payloadData)
    }

    var digest: String { "dc-final-v1:" + payloadDigest }

    func validate() throws { try DayComposerFinalizationCoding.require(DayComposerFinalizationCoding.isHash(payloadDigest)) }

    func operationKey(identity: DayComposerExecutionIdentity, sourceVersion: DayComposerSourceVersion) throws -> OfflineOperationKey {
        try identity.validate()
        try sourceVersion.validate(identity: identity)
        try validate()
        let envelope = [try identity.digest, sourceVersion.source.rawValue, try sourceVersion.digest,
                        digest, "/api/log_session", "POST"]
        return .init(rawValue: try DayComposerFinalizationCoding.digest("dc-op-final-v1", envelope))
    }
}

enum DayComposerApplicationState: String, Codable {
    case unknown, confirmed, failure, invalidResponse
}

/// Persist this marker BEFORE calling f1. It proves neither enqueue nor delivery.
enum DayComposerSubmissionPhase: String, Codable {
    case intentRecorded, submissionMayHaveStarted
}

struct DayComposerSourceSnapshotRecord: Codable, Equatable {
    let contextDigest: String
    let sourceVersion: DayComposerSourceVersion
    let provenanceGuard: DayComposerFinalizationGuard
    let createdAt: Date

    init(identity: DayComposerExecutionIdentity, sourceVersion: DayComposerSourceVersion,
         provenanceGuard: DayComposerFinalizationGuard, createdAt: Date) throws {
        try identity.validate()
        try sourceVersion.validate(identity: identity)
        try provenanceGuard.validate(identity: identity, source: sourceVersion.source)
        contextDigest = try identity.digest
        self.sourceVersion = sourceVersion
        self.provenanceGuard = provenanceGuard
        self.createdAt = createdAt
    }

    enum Relation { case current, stale, revalidationRequired, contextMismatch, unknown }

    /// LOCAL relation only. In particular historical E1 evidence is not server
    /// certification after E1 -> E2 -> E1, even if a caller supplies an old guard.
    func relation(to current: Self?) -> Relation {
        guard let current else { return .unknown }
        guard contextDigest == current.contextDigest, sourceVersion.source == current.sourceVersion.source else { return .contextMismatch }
        guard let storedDigest = try? sourceVersion.digest, let currentDigest = try? current.sourceVersion.digest else { return .unknown }
        guard storedDigest == currentDigest else { return .stale }
        return provenanceGuard == current.provenanceGuard ? .current : .revalidationRequired
    }
}

struct DayComposerExerciseIntentRecord: Codable, Equatable {
    let contextDigest: String
    let exerciseVersion: DayComposerExerciseVersion
    let operationKey: OfflineOperationKey
    var submissionPhase: DayComposerSubmissionPhase
    var applicationEvidence: DayComposerApplicationState?
    let createdAt: Date
    var updatedAt: Date

    init(identity: DayComposerExecutionIdentity, version: DayComposerExerciseVersion, now: Date) throws {
        contextDigest = try identity.digest
        exerciseVersion = version
        operationKey = try version.operationKey(identity: identity)
        submissionPhase = .intentRecorded
        applicationEvidence = nil
        createdAt = now
        updatedAt = now
    }

    var applicationState: DayComposerApplicationState { applicationEvidence ?? .unknown }
}

struct DayComposerFinalIntentRecord: Codable, Equatable {
    let contextDigest: String
    let sourceVersion: DayComposerSourceVersion
    let finalPayloadVersion: DayComposerFinalPayloadVersion
    let operationKey: OfflineOperationKey
    let dependencies: [DayComposerExerciseVersion]
    let provenanceGuard: DayComposerFinalizationGuard
    var submissionPhase: DayComposerSubmissionPhase
    var applicationState: DayComposerApplicationState
    let createdAt: Date
    var updatedAt: Date

    init(identity: DayComposerExecutionIdentity, sourceVersion: DayComposerSourceVersion,
         finalPayloadVersion: DayComposerFinalPayloadVersion, provenanceGuard: DayComposerFinalizationGuard,
         now: Date) throws {
        contextDigest = try identity.digest
        self.sourceVersion = sourceVersion
        self.finalPayloadVersion = finalPayloadVersion
        operationKey = try finalPayloadVersion.operationKey(identity: identity, sourceVersion: sourceVersion)
        try provenanceGuard.validate(identity: identity, source: sourceVersion.source)
        self.provenanceGuard = provenanceGuard
        dependencies = sourceVersion.exerciseVersions
        submissionPhase = .intentRecorded
        applicationState = .unknown
        createdAt = now
        updatedAt = now
    }
}

struct DayComposerCompletionObservationRecord: Codable, Equatable {
    enum Result: String, Codable { case observed, unconfirmed, lookupFailure, unsupportedDate }
    let source: DayComposerSource
    let date: String
    let result: Result
    let observedAt: Date
    /// Context only, never a certification of this business version.
    let sourceVersion: DayComposerSourceVersion?

    init(source: DayComposerSource, date: String, result: Result, observedAt: Date,
         sourceVersion: DayComposerSourceVersion? = nil) throws {
        self.source = source
        self.date = date
        self.result = result
        self.observedAt = observedAt
        self.sourceVersion = sourceVersion
        try DayComposerFinalizationCoding.require(DayComposerFinalizationCoding.isDate(date)
            && observedAt.timeIntervalSinceReferenceDate.isFinite)
        if let sourceVersion {
            try sourceVersion.validate()
            try DayComposerFinalizationCoding.require(sourceVersion.source == source
                && sourceVersion.exerciseVersions.allSatisfy { $0.date == date })
        }
    }
}

struct DayComposerFinalizationRecord: Codable, Equatable {
    let schemaVersion: Int
    let executionIdentity: DayComposerExecutionIdentity
    var sourceSnapshots: [DayComposerSourceSnapshotRecord]
    var exerciseIntents: [DayComposerExerciseIntentRecord]
    var finalIntents: [DayComposerFinalIntentRecord]
    var completionObservations: [DayComposerCompletionObservationRecord]
    let createdAt: Date
    var updatedAt: Date

    init(identity: DayComposerExecutionIdentity, now: Date) throws {
        try identity.validate()
        schemaVersion = 1
        executionIdentity = identity
        sourceSnapshots = []
        exerciseIntents = []
        finalIntents = []
        completionObservations = []
        createdAt = now
        updatedAt = now
    }

    func contains(source: DayComposerSource) -> Bool {
        sourceSnapshots.contains { $0.sourceVersion.source == source }
            || exerciseIntents.contains { $0.exerciseVersion.source == source }
            || finalIntents.contains { $0.sourceVersion.source == source }
            || completionObservations.contains { $0.source == source }
    }

    /// Also used after Codable decoding: synthesized decoding must not bypass
    /// referential validation. Arrays retain facts, not a mutable current index.
    func validate() throws {
        guard schemaVersion == 1 else { throw DayComposerFinalizationError.unsupportedVersion }
        try executionIdentity.validate()
        let context = try executionIdentity.digest
        var captures = Set<String>()
        var keys = Set<OfflineOperationKey>()
        var times = [createdAt, updatedAt]
        for snapshot in sourceSnapshots {
            try snapshot.sourceVersion.validate(identity: executionIdentity)
            try snapshot.provenanceGuard.validate(identity: executionIdentity, source: snapshot.sourceVersion.source)
            let businessDigest = try snapshot.sourceVersion.digest
            let guardDigest = try DayComposerFinalizationCoding.digest("guard", snapshot.provenanceGuard)
            let capture = businessDigest + ":" + guardDigest
            try DayComposerFinalizationCoding.require(snapshot.contextDigest == context && captures.insert(capture).inserted)
            times.append(snapshot.createdAt)
        }
        for intent in exerciseIntents {
            let expectedKey = try intent.exerciseVersion.operationKey(identity: executionIdentity)
            try DayComposerFinalizationCoding.require(intent.contextDigest == context && intent.operationKey == expectedKey
                && keys.insert(intent.operationKey).inserted && intent.applicationEvidence != .unknown
                && (intent.applicationEvidence == nil || intent.submissionPhase == .submissionMayHaveStarted))
            times += [intent.createdAt, intent.updatedAt]
        }
        for intent in finalIntents {
            let expectedKey = try intent.finalPayloadVersion.operationKey(identity: executionIdentity, sourceVersion: intent.sourceVersion)
            try intent.provenanceGuard.validate(identity: executionIdentity, source: intent.sourceVersion.source)
            try DayComposerFinalizationCoding.require(intent.contextDigest == context && intent.operationKey == expectedKey
                && keys.insert(intent.operationKey).inserted
                && intent.dependencies == intent.sourceVersion.exerciseVersions
                && (intent.applicationState == .unknown || intent.submissionPhase == .submissionMayHaveStarted)
                && sourceSnapshots.contains { $0.sourceVersion == intent.sourceVersion && $0.provenanceGuard == intent.provenanceGuard })
            for dependency in intent.dependencies {
                try DayComposerFinalizationCoding.require(exerciseIntents.contains { $0.exerciseVersion == dependency })
            }
            times += [intent.createdAt, intent.updatedAt]
        }
        for (index, observation) in completionObservations.enumerated() {
            try DayComposerFinalizationCoding.require(observation.date == executionIdentity.date
                && !completionObservations.prefix(index).contains(observation))
            if let version = observation.sourceVersion {
                try version.validate(identity: executionIdentity)
                try DayComposerFinalizationCoding.require(version.source == observation.source)
            }
            times.append(observation.observedAt)
        }
        try DayComposerFinalizationCoding.require(times.allSatisfy { $0.timeIntervalSinceReferenceDate.isFinite })
    }
}
