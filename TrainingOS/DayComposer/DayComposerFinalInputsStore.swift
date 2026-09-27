import Foundation

/// Local canonical inputs only. No cleanup, provenance writes, f2b writes or transport.
/// Static lock serializes RMW across instances in this process, not across processes.
final class DayComposerFinalInputsStore {
    private static let lock = NSRecursiveLock()
    private let directory: URL?
    private let writeRecord: (Data, URL) throws -> Void

    /// Test writer must preserve atomic replacement. No network/async callbacks.
    init(baseDirectory: URL? = nil,
         writeRecord: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        directory = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask).first?.appendingPathComponent("DayComposerFinalInputs", isDirectory: true)
        self.writeRecord = writeRecord
    }

    private func locked<T>(_ operation: () throws -> T) rethrows -> T {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try operation()
    }

    func recordURL(executionIdentity: DayComposerExecutionIdentity, source: DayComposerSource) throws -> URL {
        do { try executionIdentity.validate() }
        catch { throw DayComposerFinalInputsError.contextMismatch }
        guard let directory, directory.isFileURL,
              !directory.pathComponents.contains("..") else { throw DayComposerFinalInputsError.unsafePath }
        // No user-controlled path components: identity is hashed, source is a closed enum.
        let hash = DayComposerFinalizationCoding.hash(try DayComposerFinalizationCoding.encode(executionIdentity))
        return directory.appendingPathComponent("day_composer_final_inputs.v1.\(hash).\(source.rawValue).json")
    }

    private func fileType(_ url: URL) throws -> FileAttributeType? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        } catch { throw DayComposerFinalInputsError.durabilityFailure }
    }

    /// attributesOfItem inspects the link itself, including dangling links.
    private func checkPaths(_ url: URL) throws {
        guard let directory, directory.isFileURL,
              url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw DayComposerFinalInputsError.unsafePath
        }
        if let type = try fileType(directory), type != .typeDirectory { throw DayComposerFinalInputsError.unsafePath }
        if let type = try fileType(url), type != .typeRegular { throw DayComposerFinalInputsError.unsafePath }
    }

    private func read(_ identity: DayComposerExecutionIdentity, _ source: DayComposerSource) throws -> DayComposerFinalInputsRecord? {
        let url = try recordURL(executionIdentity: identity, source: source)
        try checkPaths(url)
        guard try fileType(url) != nil else { return nil }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw DayComposerFinalInputsError.durabilityFailure }
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw DayComposerFinalInputsError.corruptPersistence
        }
        guard header.schemaVersion == 1 else { throw DayComposerFinalInputsError.unsupportedSchema }
        let record: DayComposerFinalInputsRecord
        do { record = try decoder.decode(DayComposerFinalInputsRecord.self, from: data) }
        catch { throw DayComposerFinalInputsError.corruptPersistence }
        guard record.executionIdentity == identity else { throw DayComposerFinalInputsError.contextMismatch }
        guard record.source == source else { throw DayComposerFinalInputsError.sourceMismatch }
        try record.validate()
        return record
    }

    private func persist(_ record: DayComposerFinalInputsRecord) throws {
        try record.validate()
        let url = try recordURL(executionIdentity: record.executionIdentity, source: record.source)
        try checkPaths(url)
        do {
            let data = try DayComposerFinalizationCoding.encode(record)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try checkPaths(url)
            try writeRecord(data, url)
            guard try read(record.executionIdentity, record.source) == record else {
                throw DayComposerFinalInputsError.durabilityFailure
            }
        } catch { throw DayComposerFinalInputsError.durabilityFailure }
    }

    /// nil means absent/incomplete. Corruption is never converted to nil.
    func load(executionIdentity: DayComposerExecutionIdentity, source: DayComposerSource) throws -> DayComposerFinalInputsRecord? {
        try locked { try read(executionIdentity, source) }
    }

    /// nil expectedRevision means CREATE ONLY. Existing records require exact CAS,
    /// even for an identical value. Input revisions start at 1; no deletion/reset API.
    func save(executionIdentity: DayComposerExecutionIdentity, source: DayComposerSource,
              values: DayComposerFinalInputs, expectedRevision: UInt64?) throws -> DayComposerFinalInputsReceipt {
        try locked {
            let old = try read(executionIdentity, source)
            guard old?.revision == expectedRevision else { throw DayComposerFinalInputsError.staleInputs }
            try values.validate()
            if let old, old.values == values { return old.receipt }
            let revision: UInt64
            if let old {
                guard old.revision < UInt64.max else { throw DayComposerFinalInputsError.revisionOverflow }
                revision = old.revision + 1
            } else { revision = 1 }
            let record = DayComposerFinalInputsRecord(schemaVersion: 1, executionIdentity: executionIdentity,
                source: source, revision: revision, values: values,
                finalInputsVersion: try .init(values: values), captureBinding: nil)
            try persist(record)
            return record.receipt
        }
    }

    func verify(_ receipt: DayComposerFinalInputsReceipt) throws -> Bool {
        try locked { try read(receipt.executionIdentity, receipt.source)?.receipt == receipt }
    }

    /// Caller validates existence/currentness of the referenced snapshot separately.
    /// This operation only associates data; it does not inspect finalization history.
    func bindCapture(executionIdentity: DayComposerExecutionIdentity, source: DayComposerSource,
                     expectedReceipt: DayComposerFinalInputsReceipt,
                     snapshotReference: DayComposerFinalInputsSnapshotReference,
                     finalPayloadVersion: DayComposerFinalPayloadVersion) throws -> DayComposerFinalInputsCaptureBinding {
        try locked {
            guard var record = try read(executionIdentity, source) else { throw DayComposerFinalInputsError.missingRequiredRPE }
            guard expectedReceipt.executionIdentity == executionIdentity,
                  snapshotReference.executionIdentity == executionIdentity else { throw DayComposerFinalInputsError.contextMismatch }
            guard expectedReceipt.source == source, snapshotReference.source == source else { throw DayComposerFinalInputsError.sourceMismatch }
            guard record.receipt == expectedReceipt else { throw DayComposerFinalInputsError.staleInputs }
            try snapshotReference.validate()
            do { try finalPayloadVersion.validate() }
            catch { throw DayComposerFinalInputsError.invalidCaptureBinding }
            let binding = DayComposerFinalInputsCaptureBinding(snapshotReference: snapshotReference,
                revision: record.revision, finalInputsVersion: record.finalInputsVersion,
                finalPayloadVersion: finalPayloadVersion)
            if record.captureBinding == binding { return binding }
            // Association replacement preserves input revision, but exact binding
            // verification invalidates any older association receipt.
            record.captureBinding = binding
            try persist(record)
            return binding
        }
    }

    func verifyCaptureBinding(_ binding: DayComposerFinalInputsCaptureBinding) throws -> Bool {
        try locked {
            try binding.snapshotReference.validate()
            return try read(binding.snapshotReference.executionIdentity, binding.snapshotReference.source)?.captureBinding == binding
        }
    }
}
