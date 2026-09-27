import XCTest
@testable import TrainingOS

/// Real owner/provenance/recovery/input/finalization stores; isolated by date
/// and directory. Only server/transport facts are injected, never local ACKs.
@MainActor
final class DayComposerFinishRig {
    let directory: URL
    let inputs: DayComposerFinalInputsStore
    let store: DayComposerFinalizationStore
    let fixture: DayComposerStabilizationFixture
    var statuses: [OfflineOperationKey: OfflineMutationStatus] = [:]
    var queried: [OfflineOperationKey] = []
    var posted: [OfflineOperationKey] = []
    var completionCalls = 0
    var completion: SourceCompletionObservation = .observed
    var serverCompletion: DayComposerSourceCompletion = .notCompleted
    var serverOverride: DayComposerSourceServerFacts?
    var serverError = false
    var exerciseHook: ((NeutralExerciseSubmissionRequest) async -> NeutralSubmissionOutcome<LogExerciseResponse>)?
    var finalHook: ((NeutralSourceFinalizationRequest) async -> NeutralSubmissionOutcome<LogSessionResponse>)?
    var completionHook: (() async -> SourceCompletionObservation)?
    lazy var engine = DayComposerFinishCoordinator(execution: fixture.coordinator, barrier: fixture.barrier,
        store: store, inputs: inputs, dependencies: .init(server: { [unowned self] _, source in
            if self.serverError { throw DayComposerFinishCoordinator.Failure.contextRejected }
            return self.serverOverride ?? self.server(source)
        }, status: { [unowned self] key in
            self.queried.append(key)
            return self.statuses[key] ?? .notFound
        }, exercise: { [unowned self] request in
            self.assertStarted(request.operationKey)
            self.posted.append(request.operationKey)
            if let hook = self.exerciseHook { return await hook(request) }
            self.statuses[request.operationKey] = .delivered(Self.record(request.operationKey))
            return .applicationConfirmed(Self.exerciseOK)
        }, final: { [unowned self] request in
            self.assertStarted(request.operationKey)
            XCTAssertEqual(request.dependencies, .satisfied)
            self.posted.append(request.operationKey)
            if let hook = self.finalHook { return await hook(request) }
            self.statuses[request.operationKey] = .delivered(Self.record(request.operationKey))
            return .applicationConfirmed(.init(success: true))
        }, completion: { [unowned self] _, _ in
            self.completionCalls += 1
            if let hook = self.completionHook { return await hook() }
            return self.completion
        }))

    static var exerciseOK: LogExerciseResponse {
        .init(success: true, newWeight: nil, oneRM: nil, isPR: nil, baselineCount: nil, confidence: nil)
    }
    static func receipt(_ key: OfflineOperationKey) -> OfflineMutationReceipt {
        .init(mutationID: UUID(), operationKey: key, createdAt: Date())
    }
    static func record(_ key: OfflineOperationKey, state: OfflineMutationRecord.State = .delivered) -> OfflineMutationRecord {
        .init(operationKey: key, receipt: receipt(key), state: state, createdAt: Date(), updatedAt: Date())
    }
    init(names: [String] = ["A"], writer: ((Data, URL) throws -> Void)? = nil,
         inputWriter: ((Data, URL) throws -> Void)? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inputDirectory = directory.appendingPathComponent("inputs", isDirectory: true)
        let historyDirectory = directory.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        inputs = .init(baseDirectory: inputDirectory,
            writeRecord: inputWriter ?? { try $0.write(to: $1, options: .atomic) })
        store = .init(baseDirectory: historyDirectory,
            writeRecord: writer ?? { try $0.write(to: $1, options: .atomic) })
        fixture = try .init(morning: names, evening: names, finalInputsStore: inputs)
        for source in [DayComposerSource.morning, .evening] {
            for item in fixture.coordinator.orderedUnits.flatMap(\.items).filter({ $0.id.source == source }) {
                XCTAssertEqual(fixture.coordinator.submit(candidate: Self.log(item.name, source: source), for: item.id), .accepted)
            }
            try fixture.mount(source)
            try fixture.coordinator.setFinalRPE(7, for: source)
        }
    }
    static func log(_ name: String, source: DayComposerSource, weight: Double = 80) -> ExerciseLogResult {
        .init(name: name, weight: weight, reps: "5", rpe: 8,
            sets: [["weight": weight, "reps": "5", "rir": 2, "rpe": 8.0]],
            isSecond: source == .evening, equipmentType: "machine", notes: "exact note", trackingType: "reps")
    }
    func server(_ source: DayComposerSource) -> DayComposerSourceServerFacts {
        .init(source: source, date: fixture.date, freshness: .fresh, observedNames: [], completion: serverCompletion)
    }
    func prepare(_ source: DayComposerSource = .morning) throws -> DayComposerPreparedFinalization {
        try engine.prepareSource(source, server: server(source))
    }
    func assertStarted(_ key: OfflineOperationKey) {
        do {
            let record = try XCTUnwrap(store.load(identity: fixture.coordinator.morningFinalInputs.identity))
            XCTAssertTrue(record.exerciseIntents.contains { $0.operationKey == key && $0.submissionPhase == .submissionMayHaveStarted }
                || record.finalIntents.contains { $0.operationKey == key && $0.submissionPhase == .submissionMayHaveStarted })
            XCTAssertTrue(queried.contains(key), "reconcile f1 BEFORE transport")
        } catch { XCTFail("Missing durable marker: \(error)") }
    }
    func cleanup() {
        fixture.cleanup()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
final class DayComposerFinalCaptureTests: XCTestCase {
    struct Oracle: Equatable {
        let data: [Data]
        let versions: [DayComposerExerciseVersion]
        let keys: [OfflineOperationKey]
        let source: DayComposerSourceVersion
        let final: Data
        let finalVersion: DayComposerFinalPayloadVersion
        let finalKey: OfflineOperationKey
        @MainActor init(_ artifact: DayComposerPreparedFinalization) {
            let a = artifact.adapter
            data = a.exercises.map(\.payloadData); versions = a.snapshot.exerciseVersions
            keys = a.exercises.map(\.operationKey); source = a.snapshot.sourceVersion
            final = a.finalData; finalVersion = a.finalVersion; finalKey = a.finalKey
        }
    }

    func testMorningExactBytesVersionsAndKeysSurviveRecreation() throws { try reopen(.morning) }
    func testEveningExactBytesVersionsAndKeysSurviveRecreation() throws { try reopen(.evening) }

    private func reopen(_ source: DayComposerSource) throws {
        let cases: [(String, String, [String: Any])] = [
            ("Strength", "reps", ["weight": 80.5, "reps": "5", "rir": 2, "rpe": 8.0]),
            ("Time", "time", ["weight": 0, "reps": "45"]),
            ("Carry", "carry", ["weight": 40.0, "distance_m": 25]),
            ("Plyo", "plyo", ["weight": 0.0, "reps": "6", "intensity": 42.5]),
            ("Protocol", "protocol", ["weight": 0]),
            ("Unilateral", "time", ["weight": 0, "reps": "65", "left": ["time": 30], "right": ["time": 35]])
        ]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("inputs", isDirectory: true)
        let historyURL = directory.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: inputURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
        var f: DayComposerStabilizationFixture? = try .init(morning: cases.map { $0.0 }, evening: cases.map { $0.0 },
            tracking: Dictionary(uniqueKeysWithValues: cases.map { ($0.0, $0.1) }),
            finalInputsStore: .init(baseDirectory: inputURL))
        let validatedInput = try XCTUnwrap(f?.coordinator.input)
        let date = validatedInput.context.date
        defer {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            try? DayComposerProvenanceStore.shared.clear(date: date)
        }
        var originalBytes: [String: Data] = [:]
        for (name, tracking, set) in cases {
            let item = try XCTUnwrap(f?.coordinator.orderedUnits.flatMap(\.items).first { $0.name == name && $0.id.source == source })
            let log = ExerciseLogResult(name: name, weight: 40.5, reps: "5", rpe: 8, sets: [set],
                isSecond: source == .evening, equipmentType: "machine", notes: " note \n é ", trackingType: tracking,
                scheme: "1x5", isUnilateral: name == "Unilateral")
            XCTAssertEqual(f?.coordinator.submit(candidate: log, for: item.id), .accepted)
            originalBytes[name] = try NeutralExerciseSubmissionRequest(itemIdentity: name, source: source, date: date,
                result: log, operationKey: .init(rawValue: "oracle")).payloadData
        }
        try f?.mount(source)
        try f?.coordinator.setFinalRPE(7, for: source)
        let server = DayComposerSourceServerFacts(source: source, date: date, freshness: .fresh,
            observedNames: [], completion: .notCompleted)
        func oracle(_ fixture: DayComposerStabilizationFixture) throws -> Oracle {
            let engine = DayComposerFinishCoordinator(execution: fixture.coordinator, barrier: fixture.barrier,
                store: .init(baseDirectory: historyURL), inputs: .init(baseDirectory: inputURL),
                dependencies: .init(server: { _, _ in server }, status: { _ in .notFound },
                    exercise: { _ in XCTFail("capture must not POST"); return .invalidResponse },
                    final: { _ in XCTFail("capture must not POST"); return .invalidResponse },
                    completion: { _, _ in XCTFail("capture must not GET"); return .lookupFailure }))
            let artifact = try engine.prepareSource(source, server: server)
            for request in artifact.adapter.exercises {
                XCTAssertEqual(request.payloadData, originalBytes[request.itemIdentity], request.itemIdentity)
            }
            let results = source == .morning ? fixture.coordinator.morningVM.logResults : fixture.coordinator.eveningVM.logResults
            let legacy = try NeutralSourceFinalizationRequest(source: source, date: date,
                sessionName: artifact.reference.executionIdentity.session(for: source), resultsByIdentity: results,
                comment: "", rpe: 7, operationKey: artifact.adapter.finalKey, dependencies: .satisfied)
            XCTAssertEqual(artifact.adapter.finalData, legacy.payloadData, "Same final bytes as existing builder")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: artifact.adapter.finalData) as? [String: Any])
            XCTAssertEqual(body["comment"] as? String, "")
            XCTAssertNil(body["duration_min"]); XCTAssertNil(body["energy_pre"])
            return Oracle(artifact)
        }
        let before = try oracle(XCTUnwrap(f))
        weak var oldCoordinator = f?.coordinator
        weak var oldOwner = f?.coordinator.morningVM
        weak var oldBarrier = f?.barrier
        f = nil // release owners, barrier, participants and stores; retain only immutable oracle/input
        XCTAssertNil(oldCoordinator); XCTAssertNil(oldOwner); XCTAssertNil(oldBarrier)
        let recreated = try DayComposerStabilizationFixture(restoring: validatedInput,
            finalInputsStore: .init(baseDirectory: inputURL))
        try recreated.mount(source)
        let after = try oracle(recreated)
        XCTAssertEqual(before, after, "Exact Data/version/key proof for \(source), not semantic JSON equality")
        recreated.cleanup()
    }

    func testRPEAndCommentVersionBoundariesAndABARequireNewBinding() throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        let a = try r.prepare()
        try r.fixture.coordinator.setFinalRPE(8, for: .morning)
        XCTAssertFalse(try r.inputs.verifyCaptureBinding(a.binding))
        let b = try r.prepare()
        XCTAssertEqual(a.adapter.exercises.map(\.operationKey), b.adapter.exercises.map(\.operationKey))
        XCTAssertEqual(a.adapter.snapshot.sourceVersion, b.adapter.snapshot.sourceVersion)
        XCTAssertNotEqual(a.adapter.finalVersion, b.adapter.finalVersion)
        XCTAssertNotEqual(a.adapter.finalKey, b.adapter.finalKey)
        try r.fixture.coordinator.setFinalRPE(7, for: .morning)
        let c = try r.prepare()
        XCTAssertEqual(a.adapter.finalKey, c.adapter.finalKey)
        XCTAssertGreaterThan(c.binding.revision, a.binding.revision)
        XCTAssertNotEqual(c.binding, a.binding)
        XCTAssertTrue(r.fixture.barrier.editComment(r.fixture.morning, text: "changed"))
        let d = try r.prepare()
        XCTAssertEqual(c.adapter.snapshot.exerciseVersions, d.adapter.snapshot.exerciseVersions)
        XCTAssertNotEqual(c.adapter.snapshot.sourceVersion, d.adapter.snapshot.sourceVersion)
        XCTAssertNotEqual(c.adapter.finalKey, d.adapter.finalKey)
    }

    func testSnapshotWriteFailureNeverBinds() throws {
        let r = try DayComposerFinishRig(writer: { _, _ in throw CocoaError(.fileWriteUnknown) })
        defer { r.cleanup() }
        XCTAssertThrowsError(try r.prepare())
        XCTAssertNil(try r.inputs.load(executionIdentity: r.fixture.coordinator.morningFinalInputs.identity,
            source: .morning)?.captureBinding)
        XCTAssertTrue(r.posted.isEmpty)
    }

    func testBindingFailureLeavesHistoricalSnapshotButNoArtifact() throws {
        var rejectBinding = false
        let r = try DayComposerFinishRig(inputWriter: { data, url in
            if rejectBinding { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        })
        defer { r.cleanup() }
        rejectBinding = true
        XCTAssertThrowsError(try r.prepare())
        let identity = r.fixture.coordinator.morningFinalInputs.identity
        XCTAssertEqual(try r.store.load(identity: identity)?.sourceSnapshots.count, 1)
        XCTAssertNil(try r.inputs.load(executionIdentity: identity, source: .morning)?.captureBinding)
        XCTAssertTrue(r.posted.isEmpty)
    }
}
