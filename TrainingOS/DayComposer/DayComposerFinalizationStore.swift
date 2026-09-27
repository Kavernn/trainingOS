import Foundation

/// Local historical facts only. No transport lookup, server certification,
/// recovery cleanup, provenance ACK, retry, readiness or retention decisions.
final class DayComposerFinalizationStore {
    private static let lock = NSRecursiveLock()
    private static let namespace = "day_composer_finalization."
    private let baseDirectory: URL?
    private let clock: () -> Date
    private let writeRecord: (Data, URL) throws -> Void

    /// An injected directory is the dedicated store directory, not its parent.
    /// The injected writer must preserve the same atomic-replacement contract.
    init(baseDirectory: URL? = nil, clock: @escaping () -> Date = Date.init,
         writeRecord: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.baseDirectory = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask).first?.appendingPathComponent("DayComposerFinalization", isDirectory: true)
        self.clock = clock
        self.writeRecord = writeRecord
    }

    func recordURL(identity: DayComposerExecutionIdentity) throws -> URL {
        try identity.validate()
        guard let baseDirectory else { throw DayComposerFinalizationError.storageUnavailable }
        return baseDirectory.appendingPathComponent(try filename(identity))
    }

    private func filename(_ identity: DayComposerExecutionIdentity) throws -> String {
        let hash = try identity.digest.dropFirst("dc-context-v1:".count)
        return Self.namespace + "v1." + hash + ".json"
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try body()
    }

    private func missing(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
    }

    /// Absent is distinct from unreadable. Never replace an unreadable/corrupt
    /// record with an empty root, and never follow a namespaced symlink.
    private func read(_ url: URL, expected: DayComposerExecutionIdentity? = nil) throws -> DayComposerFinalizationRecord? {
        let data: Data
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw DayComposerFinalizationError.invalidRecord
            }
            data = try Data(contentsOf: url)
        } catch let error as DayComposerFinalizationError { throw error }
        catch {
            if missing(error) { return nil }
            throw DayComposerFinalizationError.storageUnavailable
        }
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        let header: Header
        do { header = try decoder.decode(Header.self, from: data) }
        catch { throw DayComposerFinalizationError.corrupt }
        guard header.schemaVersion == 1 else { throw DayComposerFinalizationError.unsupportedVersion }
        let record: DayComposerFinalizationRecord
        do { record = try decoder.decode(DayComposerFinalizationRecord.self, from: data) }
        catch { throw DayComposerFinalizationError.corrupt }
        try record.executionIdentity.validate()
        guard expected == nil || record.executionIdentity == expected else {
            throw DayComposerFinalizationError.contextMismatch
        }
        guard try url.lastPathComponent == filename(record.executionIdentity) else {
            throw DayComposerFinalizationError.contextMismatch
        }
        try record.validate()
        return record
    }

    func load(identity: DayComposerExecutionIdentity) throws -> DayComposerFinalizationRecord? {
        try locked { try read(recordURL(identity: identity), expected: identity) }
    }

    /// A throwing mutation is the caller's durable boundary. A failed intent or
    /// marker write MUST block any subsequent submission. No cached root writes.
    private func mutate(identity: DayComposerExecutionIdentity,
                        _ merge: (inout DayComposerFinalizationRecord, Date) throws -> Bool) throws {
        try locked {
            let url = try recordURL(identity: identity)
            let now = clock()
            var record = try read(url, expected: identity) ?? DayComposerFinalizationRecord(identity: identity, now: now)
            guard try merge(&record, now) else { return }
            record.updatedAt = now
            try record.validate()
            let data = try DayComposerFinalizationCoding.encode(record)
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try writeRecord(data, url)
            } catch { throw DayComposerFinalizationError.writeFailed }
        }
    }

    /// Future caller preconditions: editing ended, local persistence accepted,
    /// provenance revalidated and no unresolved newer draft. This store cannot
    /// establish those facts and must not inspect drafts or infer readiness.
    func recordSourceSnapshot(identity: DayComposerExecutionIdentity, version: DayComposerSourceVersion,
                              provenanceGuard: DayComposerFinalizationGuard) throws {
        try mutate(identity: identity) { record, now in
            let snapshot = try DayComposerSourceSnapshotRecord(identity: identity, sourceVersion: version,
                provenanceGuard: provenanceGuard, createdAt: now)
            if record.sourceSnapshots.contains(where: { $0.sourceVersion == version && $0.provenanceGuard == provenanceGuard }) {
                return false
            }
            record.sourceSnapshots.append(snapshot)
            return true
        }
    }

    func recordExerciseIntent(identity: DayComposerExecutionIdentity, version: DayComposerExerciseVersion) throws {
        try mutate(identity: identity) { record, now in
            let intent = try DayComposerExerciseIntentRecord(identity: identity, version: version, now: now)
            if let old = record.exerciseIntents.first(where: { $0.operationKey == intent.operationKey }) {
                guard old.exerciseVersion == version, old.contextDigest == intent.contextDigest else {
                    throw DayComposerFinalizationError.conflict
                }
                return false
            }
            record.exerciseIntents.append(intent)
            return true
        }
    }

    func recordFinalIntent(identity: DayComposerExecutionIdentity, sourceVersion: DayComposerSourceVersion,
                           finalPayloadVersion: DayComposerFinalPayloadVersion,
                           provenanceGuard: DayComposerFinalizationGuard) throws {
        try mutate(identity: identity) { record, now in
            let intent = try DayComposerFinalIntentRecord(identity: identity, sourceVersion: sourceVersion,
                finalPayloadVersion: finalPayloadVersion, provenanceGuard: provenanceGuard, now: now)
            if let old = record.finalIntents.first(where: { $0.operationKey == intent.operationKey }) {
                // A recapture does not authorize rewriting the original guard.
                guard old.sourceVersion == sourceVersion, old.finalPayloadVersion == finalPayloadVersion,
                      old.provenanceGuard == provenanceGuard, old.dependencies == intent.dependencies else {
                    throw DayComposerFinalizationError.conflict
                }
                return false
            }
            record.finalIntents.append(intent) // root validation requires snapshot + exact dependencies
            return true
        }
    }

    func markSubmissionMayHaveStarted(identity: DayComposerExecutionIdentity, operationKey: OfflineOperationKey) throws {
        try mutate(identity: identity) { record, now in
            if let index = record.exerciseIntents.firstIndex(where: { $0.operationKey == operationKey }) {
                guard record.exerciseIntents[index].submissionPhase != .submissionMayHaveStarted else { return false }
                record.exerciseIntents[index].submissionPhase = .submissionMayHaveStarted
                record.exerciseIntents[index].updatedAt = now
            } else if let index = record.finalIntents.firstIndex(where: { $0.operationKey == operationKey }) {
                guard record.finalIntents[index].submissionPhase != .submissionMayHaveStarted else { return false }
                record.finalIntents[index].submissionPhase = .submissionMayHaveStarted
                record.finalIntents[index].updatedAt = now
            } else { throw DayComposerFinalizationError.invalidRecord }
            return true
        }
    }

    private func shouldMerge(_ incoming: DayComposerApplicationState, into old: DayComposerApplicationState) throws -> Bool {
        guard incoming != .unknown else { throw DayComposerFinalizationError.invalidRecord }
        if incoming == old { return false }
        guard old == .unknown else { throw DayComposerFinalizationError.conflict }
        return true
    }

    func recordExerciseApplication(identity: DayComposerExecutionIdentity, version: DayComposerExerciseVersion,
                                   state: DayComposerApplicationState) throws {
        try mutate(identity: identity) { record, now in
            let key = try version.operationKey(identity: identity)
            guard let index = record.exerciseIntents.firstIndex(where: { $0.operationKey == key && $0.exerciseVersion == version }),
                  record.exerciseIntents[index].submissionPhase == .submissionMayHaveStarted else {
                throw DayComposerFinalizationError.invalidRecord
            }
            guard try self.shouldMerge(state, into: record.exerciseIntents[index].applicationState) else { return false }
            record.exerciseIntents[index].applicationEvidence = state
            record.exerciseIntents[index].updatedAt = now
            return true
        }
    }

    func recordFinalApplication(identity: DayComposerExecutionIdentity, sourceVersion: DayComposerSourceVersion,
                                finalPayloadVersion: DayComposerFinalPayloadVersion, state: DayComposerApplicationState) throws {
        try mutate(identity: identity) { record, now in
            let key = try finalPayloadVersion.operationKey(identity: identity, sourceVersion: sourceVersion)
            guard let index = record.finalIntents.firstIndex(where: {
                $0.operationKey == key && $0.sourceVersion == sourceVersion && $0.finalPayloadVersion == finalPayloadVersion
            }), record.finalIntents[index].submissionPhase == .submissionMayHaveStarted else {
                throw DayComposerFinalizationError.invalidRecord
            }
            guard try self.shouldMerge(state, into: record.finalIntents[index].applicationState) else { return false }
            record.finalIntents[index].applicationState = state
            record.finalIntents[index].updatedAt = now
            return true
        }
    }

    func recordCompletionObservation(identity: DayComposerExecutionIdentity, observation: DayComposerCompletionObservationRecord) throws {
        try mutate(identity: identity) { record, _ in
            guard !record.completionObservations.contains(observation) else { return false }
            record.completionObservations.append(observation)
            return true
        }
    }

    /// Historical response only. Not sufficient to finalize a current source;
    /// in particular this does not resolve intervening E2 after E1 -> E2 -> E1.
    func exerciseEvidence(identity: DayComposerExecutionIdentity, version: DayComposerExerciseVersion) throws -> DayComposerApplicationState? {
        try locked {
            let key = try version.operationKey(identity: identity)
            return try load(identity: identity)?.exerciseIntents.first {
                $0.operationKey == key && $0.exerciseVersion == version
            }?.applicationEvidence
        }
    }

    func finalEvidence(identity: DayComposerExecutionIdentity, sourceVersion: DayComposerSourceVersion,
                       finalPayloadVersion: DayComposerFinalPayloadVersion) throws -> DayComposerApplicationState? {
        try locked {
            let key = try finalPayloadVersion.operationKey(identity: identity, sourceVersion: sourceVersion)
            return try load(identity: identity)?.finalIntents.first {
                $0.operationKey == key && $0.sourceVersion == sourceVersion && $0.finalPayloadVersion == finalPayloadVersion
            }?.applicationState
        }
    }

    /// Scan only our dedicated namespace, including old programs/executions.
    /// Any unreadable namespaced candidate fails the scan, never a partial list.
    func candidateRecords(date: String, source: DayComposerSource) throws -> [DayComposerFinalizationRecord] {
        try locked {
            try DayComposerFinalizationCoding.require(DayComposerFinalizationCoding.isDate(date))
            guard let baseDirectory else { throw DayComposerFinalizationError.storageUnavailable }
            let urls: [URL]
            do {
                urls = try FileManager.default.contentsOfDirectory(at: baseDirectory,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            } catch {
                if missing(error) { return [] }
                throw DayComposerFinalizationError.storageUnavailable
            }
            var records: [DayComposerFinalizationRecord] = []
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                where url.lastPathComponent.hasPrefix(Self.namespace) {
                guard let record = try read(url) else { throw DayComposerFinalizationError.storageUnavailable }
                if record.executionIdentity.date == date && record.contains(source: source) { records.append(record) }
            }
            return records
        }
    }
}
