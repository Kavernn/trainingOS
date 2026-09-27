import XCTest
import Combine
@testable import TrainingOS

/// Real shared persistence hooks, isolated by an unused, valid ISO date. No network.
@MainActor
final class DayComposerStabilizationFixture {
    let date: String
    let coordinator: DayComposerExecutionCoordinator
    let barrier: DayComposerLocalStabilizationBarrier
    let morning: DayComposerCommentParticipant
    let evening: DayComposerCommentParticipant
    var vms: [ExerciseViewModel] = []
    var handles: [ExerciseEditorPreparationController] = []

    static func unusedDate() throws -> String {
        let store = DayComposerProvenanceStore.shared
        for _ in 0..<100 {
            let date = String(format: "%04d-%02d-%02d", Int.random(in: 7000...9000), Int.random(in: 1...12), Int.random(in: 1...28))
            if try store.load(date: date) == nil,
               try !store.inventory(date: date, source: .morning).hasState,
               try !store.inventory(date: date, source: .evening).hasState { return date }
        }
        throw DayComposerStabilizationError.contextRejected
    }

    init(morning names: [String] = ["A"], evening eveningNames: [String] = ["A"],
         tracking: [String: String] = [:], observed: [String] = [],
         supersets: [String: [String: SupersetEntry]] = [:],
         finalInputsStore: DayComposerFinalInputsStore = DayComposerFinalInputsStore()) throws {
        date = try Self.unusedDate()
        let date = date
        let sharedID = UUID().uuidString
        let program = ["AM": Dictionary(uniqueKeysWithValues: names.map { ($0, SafeString("1x5")) }),
                       "PM": Dictionary(uniqueKeysWithValues: eveningNames.map { ($0, SafeString("1x5")) })]
        let order = ["AM": names, "PM": eveningNames]
        func dto(_ session: String) -> SeanceData {
            .init(today: session, todayDate: date, alreadyLogged: false,
                schedule: [TrainingDoctrine.dayNames[0]: session], fullProgram: program, weights: [:], week: 1,
                inventoryTypes: [:], inventoryTracking: tracking, exerciseOrder: order,
                exerciseSupersets: supersets, exerciseIds: ["A": sharedID])
        }
        let context = DayComposerLoader.Context(active_program_id: "A", current_program_id: "A",
            full_program: program, schedule: dto("AM").schedule, exercise_order: order)
        let bundle = try DayComposerLoader.validate(program: "A", date: date, currentDate: date, weekdayIndex: 0,
            before: context, after: context, morning: dto("AM"), evening: dto("PM"),
            completion: .init(today_date: date, second_session_completed: false))
        let history: [String: Any] = ["session_list": [["date": date, "session_type": "morning",
                                                      "exos": observed.map { ["exercise": $0] }]]]
        let input = try DayComposerValidatedExecutionInput(bundle: bundle, orderedItemIDs: bundle.snapshot.initialIDs,
            serverProjection: DayComposerServerProjection(date: date, historyData: JSONSerialization.data(withJSONObject: history)))
        coordinator = try .make(validatedInput: input, currentDate: { date }, finalInputsStore: finalInputsStore)
        barrier = try coordinator.makeStabilizationBarrier()
        morning = .init(source: .morning, text: coordinator.comment(for: .morning))
        evening = .init(source: .evening, text: coordinator.comment(for: .evening))
        barrier.registerComment(morning); barrier.registerComment(evening)
    }

    func mount(_ source: DayComposerSource, validator: (() -> LocalPersistenceResult)? = nil) throws {
        for id in coordinator.expectedMutableParticipantIDs(for: source) {
            let p = try XCTUnwrap(coordinator.presentation(for: id.itemID))
            let c = coordinator
            let vm = ExerciseViewModel(name: p.item.name, scheme: p.item.scheme, weightData: nil,
                trackingType: p.item.tracking, isSecondSession: source == .evening, sessionDate: date,
                draftAuthorization: p.authorization, validateLocalPersistence: validator ?? { c.validateLocalPersistence() })
            if let hydration = p.hydration { vm.initializeRecovery(hydration) } else { vm.initializeSets() }
            let handle = ExerciseEditorPreparationController()
            handle.attach(vm)
            vms.append(vm); handles.append(handle)
            barrier.register(handle, identity: id)
        }
    }

    func cleanup() {
        for handle in handles { handle.detach() }
        handles.removeAll(); vms.removeAll()
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        try? DayComposerProvenanceStore.shared.clear(date: date)
    }

    func input(_ facts: DayComposerLocalFinalizationFacts) -> DayComposerSourceFinalizationInput {
        // Explicit fixture facts, NOT a freshness claim made by the production capture.
        .init(identity: facts.identity, source: facts.source, canonicalPlan: facts.canonicalPlan,
            contextFreshness: .fresh, provenanceGuard: facts.guardValue, provenanceCompatible: true,
            stabilization: .stableAccepted(facts.guardValue), itemFacts: facts.itemFacts, comment: facts.comment,
            server: .init(source: facts.source, date: date, freshness: .fresh, observedNames: [], completion: .notCompleted),
            history: .init(durability: .trusted, current: nil, candidates: [], transports: [:]))
    }
}

@MainActor
final class DayComposerStabilizationTests: XCTestCase {
    private func withFinalFixture(_ body: (DayComposerStabilizationFixture, DayComposerFinalInputsStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DayComposerFinalInputsStore(baseDirectory: directory)
        let f = try DayComposerStabilizationFixture(finalInputsStore: store)
        defer { f.cleanup() }
        try f.mount(.morning); try f.mount(.evening)
        defer {
            XCTAssertFalse(f.barrier.isInteractionFrozen)
            for source in [DayComposerSource.morning, .evening] {
                XCTAssertEqual(f.barrier.phase(for: source), .idle)
                XCTAssertTrue(f.barrier.permitsOrdinaryMutation(for: source))
            }
            for handle in f.handles { XCTAssertTrue(handle.gate.allowsOrdinaryMutation) }
        }
        try body(f, store, directory)
    }

    func testFinalMissingInputsFailsBeforeClosureButLocalOnlySucceeds() throws {
        try withFinalFixture { f, store, _ in
            let id = f.coordinator.morningFinalInputs.identity
            var calls = 0
            try f.barrier.withStabilizedSource(.morning) { _ in calls += 1 }
            XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.morning) { _ in calls += 1 }) {
                XCTAssertEqual($0 as? DayComposerFinalInputsError, .missingRequiredRPE)
            }
            XCTAssertEqual(calls, 1)
            XCTAssertNil(try store.load(executionIdentity: id, source: .morning))
        }
    }

    func testFinalBothSourcesExposeExactImmutableCaptureWithoutBindingOrSnapshotWrite() throws {
        try withFinalFixture { f, store, directory in
            let identity = f.coordinator.morningFinalInputs.identity
            let history = DayComposerFinalizationStore()
            let historyBefore = try history.load(identity: identity)
            for (source, rpe) in [(DayComposerSource.morning, 7.0), (.evening, 9.0)] {
                let receipt = try f.coordinator.setFinalRPE(rpe, for: source)
                let holder = source == .morning ? f.morning : f.evening
                XCTAssertTrue(f.barrier.editComment(holder, text: source == .morning ? "" : " exact \n"))
                let bytes = try Data(contentsOf: store.recordURL(executionIdentity: identity, source: source))
                let capture = try f.barrier.withStabilizedFinalSource(source) { evidence in
                    XCTAssertTrue(evidence.isCurrentAttempt)
                    XCTAssertEqual(evidence.finalInputs, receipt)
                    XCTAssertEqual(evidence.local.identity, identity)
                    return try f.coordinator.captureFinalSource(for: source, evidence: evidence)
                }
                XCTAssertEqual(capture.finalInputs, receipt)
                XCTAssertEqual(capture.finalInputs.values.rpe, rpe)
                XCTAssertNil(capture.finalInputs.values.durationMin)
                XCTAssertNil(capture.finalInputs.values.energyPre)
                XCTAssertEqual(capture.local.comment, holder.text)
                XCTAssertEqual(capture.local.source, source)
                XCTAssertEqual(try Data(contentsOf: store.recordURL(executionIdentity: identity, source: source)), bytes)
                XCTAssertNil(try store.load(executionIdentity: identity, source: source)?.captureBinding)
            }
            XCTAssertEqual(try history.load(identity: identity), historyBefore)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
        }
    }

    func testCorruptFinalInputsLeaveLocalModeUsableAndBytesUntouched() throws {
        try withFinalFixture { f, store, _ in
            let receipt = try f.coordinator.setFinalRPE(7, for: .morning)
            let url = try store.recordURL(executionIdentity: receipt.executionIdentity, source: .morning)
            try Data("{".utf8).write(to: url)
            var called = false
            XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.morning) { _ in called = true }) {
                XCTAssertEqual($0 as? DayComposerFinalInputsError, .corruptPersistence)
            }
            XCTAssertFalse(called)
            try f.barrier.withStabilizedSource(.morning) { _ in }
            XCTAssertEqual(try Data(contentsOf: url), Data("{".utf8))
            // Final AM must not inspect a corrupt PM file, and conversely.
            _ = try f.coordinator.setFinalRPE(9, for: .evening)
            try f.barrier.withStabilizedFinalSource(.evening) { _ in }
        }
    }

    func testFinalPostVerifyDetectsSeparateStoreWriteAndABA() throws {
        for aba in [false, true] {
            try withFinalFixture { f, _, directory in
                let first = try f.coordinator.setFinalRPE(7, for: .morning)
                let bypass = DayComposerFinalInputsStore(baseDirectory: directory)
                XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.morning) { _ -> Int in
                    let second = try bypass.save(executionIdentity: first.executionIdentity, source: .morning,
                        values: DayComposerFinalInputs(rpe: 8), expectedRevision: first.revision)
                    if aba {
                        let third = try bypass.save(executionIdentity: first.executionIdentity, source: .morning,
                            values: DayComposerFinalInputs(rpe: 7), expectedRevision: second.revision)
                        XCTAssertEqual(third.finalInputsVersion, first.finalInputsVersion)
                    }
                    return 42
                }) { XCTAssertEqual($0 as? DayComposerStabilizationError, .staleEvidence) }
                XCTAssertFalse(try bypass.verify(first))
            }
        }
    }

    func testFinalGateBlocksTargetSetterIncludingNoOpButAllowsOtherSource() throws {
        try withFinalFixture { f, store, _ in
            let first = try f.coordinator.setFinalRPE(7, for: .morning)
            try f.barrier.withStabilizedFinalSource(.morning) { _ in
                for rpe in [7.0, 8] {
                    XCTAssertThrowsError(try f.coordinator.setFinalRPE(rpe, for: .morning)) {
                        XCTAssertEqual($0 as? DayComposerStabilizationError, .sourceFrozen)
                    }
                    // Direct participant access uses the SAME injected gate, no bypass.
                    XCTAssertThrowsError(try f.coordinator.morningFinalInputs.setRPE(rpe)) {
                        XCTAssertEqual($0 as? DayComposerStabilizationError, .sourceFrozen)
                    }
                }
                XCTAssertEqual(f.coordinator.morningFinalInputs.state, .loaded(first))
                XCTAssertTrue(try store.verify(first))
                XCTAssertEqual(try f.coordinator.setFinalRPE(9, for: .evening).values.rpe, 9)
            }
            XCTAssertEqual(try f.coordinator.setFinalRPE(8, for: .morning).revision, 2)
            // Local-only attempts must gate the setter too, without requiring inputs.
            try f.barrier.withStabilizedSource(.morning) { _ in
                XCTAssertThrowsError(try f.coordinator.setFinalRPE(8, for: .morning)) {
                    XCTAssertEqual($0 as? DayComposerStabilizationError, .sourceFrozen)
                }
            }
        }
    }

    func testFinalRegistryMissingDuplicateIdempotenceAndStaleUnregister() throws {
        try withFinalFixture { f, store, _ in
            let original = f.coordinator.morningFinalInputs
            _ = try f.coordinator.setFinalRPE(7, for: .morning)
            XCTAssertTrue(f.barrier.registerFinalInputsParticipant(original))
            f.barrier.unregisterFinalInputsParticipant(source: .morning, token: original.instance)
            XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.morning) { _ in XCTFail("Missing participant") }) {
                XCTAssertEqual($0 as? DayComposerStabilizationError, .missingParticipant)
            }
            try f.barrier.withStabilizedSource(.morning) { _ in }
            let replacement = DayComposerFinalInputsParticipant(identity: original.identity, source: .morning,
                store: store, authorizeMutation: { throw DayComposerStabilizationError.sourceFrozen })
            XCTAssertTrue(f.barrier.registerFinalInputsParticipant(replacement))
            f.barrier.unregisterFinalInputsParticipant(source: .morning, token: original.instance)
            try f.barrier.withStabilizedFinalSource(.morning) { _ in }
            XCTAssertFalse(f.barrier.registerFinalInputsParticipant(original))
            XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.morning) { _ in XCTFail("Duplicate") }) {
                XCTAssertEqual($0 as? DayComposerStabilizationError, .duplicateParticipant)
            }
            try f.barrier.withStabilizedSource(.morning) { _ in }
        }
    }

    func testFinalParticipantReplacementDuringClosureInvalidatesAndReleases() throws {
        try withFinalFixture { f, store, _ in
            let original = f.coordinator.morningFinalInputs
            _ = try f.coordinator.setFinalRPE(7, for: .morning)
            let replacement = DayComposerFinalInputsParticipant(identity: original.identity, source: .morning,
                store: store, authorizeMutation: {})
            XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.morning) { evidence in
                f.barrier.unregisterFinalInputsParticipant(source: .morning, token: original.instance)
                XCTAssertTrue(f.barrier.registerFinalInputsParticipant(replacement))
                XCTAssertThrowsError(try f.coordinator.captureFinalSource(for: .morning, evidence: evidence))
            }) { XCTAssertEqual($0 as? DayComposerStabilizationError, .staleEvidence) }
        }
    }

    func testFinalEvidenceExpiresAndRejectsWrongSourceAndExecution() throws {
        try withFinalFixture { f, store, _ in
            _ = try f.coordinator.setFinalRPE(7, for: .morning)
            let other = try DayComposerStabilizationFixture(finalInputsStore: store)
            defer { other.cleanup() }
            var escaped: DayComposerStableFinalSourceEvidence?
            try f.barrier.withStabilizedFinalSource(.morning) { evidence in
                escaped = evidence
                XCTAssertThrowsError(try f.coordinator.captureFinalSource(for: .evening, evidence: evidence)) {
                    XCTAssertEqual($0 as? DayComposerFinalInputsError, .sourceMismatch)
                }
                XCTAssertThrowsError(try other.coordinator.captureFinalSource(for: .morning, evidence: evidence)) {
                    XCTAssertEqual($0 as? DayComposerFinalInputsError, .contextMismatch)
                }
            }
            let old = try XCTUnwrap(escaped)
            XCTAssertFalse(old.isCurrentAttempt)
            XCTAssertThrowsError(try f.coordinator.captureFinalSource(for: .morning, evidence: old)) {
                XCTAssertEqual($0 as? DayComposerStabilizationError, .staleEvidence)
            }
            try f.barrier.withStabilizedFinalSource(.morning) { _ in
                XCTAssertFalse(old.isCurrentAttempt)
                XCTAssertThrowsError(try old.verifyCurrent())
            }
        }
    }

    func testFinalCaptureRejectsExternalMutationBeforeReturningData() throws {
        try withFinalFixture { f, store, _ in
            let first = try f.coordinator.setFinalRPE(7, for: .morning)
            XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.morning) { evidence in
                _ = try store.save(executionIdentity: first.executionIdentity, source: .morning,
                    values: DayComposerFinalInputs(rpe: 8), expectedRevision: first.revision)
                XCTAssertThrowsError(try f.coordinator.captureFinalSource(for: .morning, evidence: evidence)) {
                    XCTAssertEqual($0 as? DayComposerFinalInputsError, .staleInputs)
                }
            }) { XCTAssertEqual($0 as? DayComposerStabilizationError, .staleEvidence) }
        }
    }

    func testFinalPostVerifyCorruptionAndClosureThrowRelease() throws {
        enum Expected: Error { case stop }
        try withFinalFixture { f, store, _ in
            let receipt = try f.coordinator.setFinalRPE(7, for: .morning)
            XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.morning) { _ in throw Expected.stop }) {
                XCTAssertTrue($0 is Expected)
            }
            XCTAssertFalse(f.barrier.isInteractionFrozen)
            let url = try store.recordURL(executionIdentity: receipt.executionIdentity, source: .morning)
            XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.morning) { _ in
                try Data("{".utf8).write(to: url)
            }) { XCTAssertEqual($0 as? DayComposerStabilizationError, .staleEvidence) }
            XCTAssertEqual(try Data(contentsOf: url), Data("{".utf8))
        }
    }

    func testCoordinatorParticipantsRecreateWithExactReceiptsAndWeakOwnership() throws {
        try withFinalFixture { f, store, directory in
            let input = f.coordinator.input, date = f.date
            var coordinator: DayComposerExecutionCoordinator? = try .make(validatedInput: input,
                currentDate: { date }, finalInputsStore: store)
            let a = try XCTUnwrap(coordinator).setFinalRPE(8, for: .morning)
            let b = try XCTUnwrap(coordinator).setFinalRPE(9, for: .evening)
            let barrier = try XCTUnwrap(coordinator).makeStabilizationBarrier()
            weak var weakCoordinator = coordinator
            weak var weakParticipant = coordinator?.morningFinalInputs
            coordinator = nil
            XCTAssertNil(weakCoordinator)
            XCTAssertNil(weakParticipant) // Retained barrier holds neither strongly.
            XCTAssertFalse(barrier.isInteractionFrozen)
            let readOnly = DayComposerFinalInputsStore(baseDirectory: directory, writeRecord: { _, _ in XCTFail("Reload wrote") })
            let rebuilt = try DayComposerExecutionCoordinator.make(validatedInput: input,
                currentDate: { date }, finalInputsStore: readOnly)
            XCTAssertEqual(rebuilt.morningFinalInputs.state, .loaded(a))
            XCTAssertEqual(rebuilt.eveningFinalInputs.state, .loaded(b))
            XCTAssertEqual(try rebuilt.morningFinalInputs.prepare(), a)
            XCTAssertEqual(try rebuilt.eveningFinalInputs.prepare(), b)
        }
    }

    func testCoordinatorSameContentSetterStillRejectsInvalidContext() throws {
        try withFinalFixture { f, store, _ in
            let receipt = try f.coordinator.setFinalRPE(7, for: .morning)
            SessionDraftStore.saveComment("outside authorization", date: f.date, sessionType: "morning")
            XCTAssertThrowsError(try f.coordinator.setFinalRPE(7, for: .morning)) {
                XCTAssertEqual($0 as? DayComposerStabilizationError, .contextRejected)
            }
            XCTAssertTrue(f.coordinator.isLocked)
            XCTAssertTrue(try store.verify(receipt))
        }
    }

    func testFinalPrepareFailurePreventsAllForcedFlushes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let h = try Harness(), a = Card(), b = Card()
        h.add(a, id: h.id("A")); h.add(b, id: h.id("B"))
        var events: [String] = []
        a.onEvent = { events.append("A-\($0)") }; b.onEvent = { events.append("B-\($0)") }
        let inputs = DayComposerFinalInputsParticipant(identity: h.identity, source: .morning,
            store: DayComposerFinalInputsStore(baseDirectory: directory), authorizeMutation: {})
        h.barrier.registerFinalInputsParticipant(inputs)
        XCTAssertThrowsError(try h.barrier.withStabilizedFinalSource(.morning) { _ in XCTFail("Missing RPE") }) {
            XCTAssertEqual($0 as? DayComposerFinalInputsError, .missingRequiredRPE)
        }
        XCTAssertEqual(events, ["A-prepare", "B-prepare"])
        XCTAssertTrue(h.writes.isEmpty)
        XCTAssertTrue(a.gate.allowsOrdinaryMutation); XCTAssertTrue(b.gate.allowsOrdinaryMutation)
        h.assertReleased()
    }

    func testFinalDeadAndWrongExecutionParticipantsFailClosed() throws {
        try withFinalFixture { f, store, _ in
            let original = f.coordinator.morningFinalInputs
            f.barrier.unregisterFinalInputsParticipant(source: .morning, token: original.instance)
            var dead: DayComposerFinalInputsParticipant? = .init(identity: original.identity, source: .morning,
                store: store, authorizeMutation: {})
            XCTAssertTrue(f.barrier.registerFinalInputsParticipant(try XCTUnwrap(dead)))
            dead = nil
            XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.morning) { _ in XCTFail("Dead participant") }) {
                XCTAssertEqual($0 as? DayComposerStabilizationError, .missingParticipant)
            }
            let otherIdentity = try DayComposerExecutionIdentity(executionID: UUID(), context: f.coordinator.context)
            let other = DayComposerFinalInputsParticipant(identity: otherIdentity, source: .morning,
                store: store, authorizeMutation: {})
            XCTAssertFalse(f.barrier.registerFinalInputsParticipant(other))
            XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.morning) { _ in XCTFail("Wrong execution") }) {
                XCTAssertEqual($0 as? DayComposerFinalInputsError, .contextMismatch)
            }
            try f.barrier.withStabilizedSource(.morning) { _ in }
        }
    }

    func testFinalRegistryNoOpAndOtherSourceChangesDoNotInvalidateTarget() throws {
        try withFinalFixture { f, _, _ in
            _ = try f.coordinator.setFinalRPE(7, for: .morning)
            try f.barrier.withStabilizedFinalSource(.morning) { evidence in
                XCTAssertTrue(f.barrier.registerFinalInputsParticipant(f.coordinator.morningFinalInputs))
                let pm = f.coordinator.eveningFinalInputs
                f.barrier.unregisterFinalInputsParticipant(source: .evening, token: pm.instance)
                XCTAssertTrue(f.barrier.registerFinalInputsParticipant(pm))
                _ = try f.coordinator.captureFinalSource(for: .morning, evidence: evidence)
                XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.evening) { _ in }) {
                    XCTAssertEqual($0 as? DayComposerStabilizationError, .busy)
                }
            }
        }
    }

    func testFinalPublicationReentranceCannotDeliverStaleInputs() throws {
        try withFinalFixture { f, store, _ in
            let first = try f.coordinator.setFinalRPE(7, for: .morning)
            var injected = false
            let observation = f.barrier.$phases.sink { phases in
                guard phases[.morning] == .frozenForSnapshot, !injected else { return }
                injected = true
                XCTAssertNoThrow(try store.save(executionIdentity: first.executionIdentity, source: .morning,
                    values: DayComposerFinalInputs(rpe: 8), expectedRevision: first.revision))
            }
            defer { observation.cancel() }
            var invoked = false
            XCTAssertThrowsError(try f.barrier.withStabilizedFinalSource(.morning) { _ in invoked = true }) {
                XCTAssertEqual($0 as? DayComposerFinalInputsError, .staleInputs)
            }
            XCTAssertTrue(injected)
            XCTAssertFalse(invoked)
        }
    }

    @MainActor private final class Card: DayComposerCardParticipant {
        let instance = UUID()
        let gate = ExerciseEditorMutationGate()
        var generation = 0
        var prepareHook: () throws -> Void = {}
        var flushHook: () throws -> Void = {}
        var onEvent: (String) -> Void = { _ in }
        func prepareForSource() throws -> DayComposerPreparedCard {
            XCTAssertFalse(gate.allowsOrdinaryMutation)
            onEvent("prepare"); try prepareHook()
            let expected = generation
            return .init(verify: { self.generation == expected }, flush: {
                self.onEvent("flush"); try self.flushHook()
                return .init(verify: { self.generation == expected })
            })
        }
    }
    @MainActor private final class Harness {
        let identity: DayComposerExecutionIdentity
        var expected: [DayComposerSource: [DayComposerExecutionItemIdentity]] = [:]
        var valid = true
        var rejected = false
        var revision = 0
        var writeResult: LocalPersistenceResult = .accepted
        var persisted: [DayComposerSource: String] = [:]
        var writes: [DayComposerSource] = []
        var mismatch = false
        var guardHook: () throws -> Void = {}
        var barrier: DayComposerLocalStabilizationBarrier!
        let am = DayComposerCommentParticipant(source: .morning, text: " AM ")
        let pm = DayComposerCommentParticipant(source: .evening, text: "PM")

        init() throws {
            let plan = try DayComposerSnapshot(date: "2091-01-02", activeProgramID: "P",
                morning: DayComposerPlan(source: .morning, session: "AM", schemes: ["A": "1x5"], order: []),
                evening: DayComposerPlan(source: .evening, session: "PM", schemes: ["A": "1x5"], order: []),
                morningCompleted: false, eveningCompleted: false)
            identity = try .init(executionID: UUID(), context: DayComposerExecutionContext(snapshot: plan))
            barrier = DayComposerLocalStabilizationBarrier(dependencies: .init(identity: identity,
                expected: { [unowned self] in self.expected[$0] ?? [] }, validate: { [unowned self] in self.valid },
                guardValue: { [unowned self] source in try self.guardHook(); return try self.guardValue(source) },
                writeComment: { [unowned self] text, source in
                    self.writes.append(source)
                    if self.writeResult == .accepted { self.persisted[source] = text; self.revision += 1 }
                    return self.writeResult
                }, commentMatches: { [unowned self] in !self.mismatch && self.persisted[$1] == $0 },
                rejected: { [unowned self] in self.rejected = true }))
            barrier.registerComment(am); barrier.registerComment(pm)
        }
        func id(_ name: String = "A", _ source: DayComposerSource = .morning) -> DayComposerExecutionItemIdentity {
            .init(executionID: identity.executionID, version: identity.contextVersion, date: identity.date,
                  activeProgramID: identity.activeProgramID, sourceFingerprint: identity.sourceFingerprint,
                  itemID: .init(source: source, name: name, exerciseID: "00000000-0000-0000-0000-000000000001"))
        }
        func guardValue(_ source: DayComposerSource) throws -> DayComposerFinalizationGuard {
            try .init(executionID: identity.executionID, source: source, revision: revision,
                      integrity: String(repeating: "a", count: 64))
        }
        func add(_ card: Card, id: DayComposerExecutionItemIdentity) {
            expected[id.itemID.source, default: []].append(id)
            barrier.register(card, identity: id)
        }
        func assertReleased(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertFalse(barrier.isInteractionFrozen, file: file, line: line)
            XCTAssertEqual(barrier.phase(for: .morning), .idle, file: file, line: line)
            XCTAssertEqual(barrier.phase(for: .evening), .idle, file: file, line: line)
        }
    }

    func testPrepareAllThenFlushAndExactSuccessResult() throws {
        let h = try Harness(); let a = Card(); let b = Card()
        let bID = DayComposerExecutionItemIdentity(executionID: h.identity.executionID, version: h.identity.contextVersion,
            date: h.identity.date, activeProgramID: h.identity.activeProgramID, sourceFingerprint: h.identity.sourceFingerprint,
            itemID: .init(source: .morning, name: "B", exerciseID: nil))
        h.add(a, id: h.id()); h.add(b, id: bID)
        var events: [String] = []; a.onEvent = { events.append("A:\($0)") }; b.onEvent = { events.append("B:\($0)") }
        var escaped: DayComposerStableSourceEvidence?
        let value = try h.barrier.withStabilizedSource(.morning) { evidence in
            XCTAssertEqual(h.barrier.phase(for: .morning), .frozenForSnapshot)
            XCTAssertEqual(evidence.guardValue.revision, 1)
            XCTAssertEqual(evidence.comment, " AM ")
            XCTAssertTrue(evidence.isCurrentAttempt); escaped = evidence
            XCTAssertEqual(events, ["A:prepare", "B:prepare", "A:flush", "B:flush"])
            return 17
        }
        XCTAssertEqual(value, 17); XCTAssertFalse(try XCTUnwrap(escaped).isCurrentAttempt)
        XCTAssertEqual(try XCTUnwrap(escaped).stabilization, .unknown)
        XCTAssertTrue(a.gate.allowsOrdinaryMutation); XCTAssertTrue(b.gate.allowsOrdinaryMutation); h.assertReleased()
    }

    func testRegistryIdempotenceDuplicateAndStaleUnregister() throws {
        let h = try Harness(); let a = Card(); let replacement = Card(); h.add(a, id: h.id())
        let generation = h.barrier.registryGeneration(for: .morning)
        XCTAssertTrue(h.barrier.register(a, identity: h.id()))
        XCTAssertEqual(generation, h.barrier.registryGeneration(for: .morning))
        XCTAssertFalse(h.barrier.register(replacement, identity: h.id()))
        XCTAssertThrowsError(try h.barrier.withStabilizedSource(.morning) { _ in XCTFail() })
        h.barrier.unregister(identity: h.id(), token: a.instance)
        h.barrier.unregister(identity: h.id(), token: a.instance)
        XCTAssertNoThrow(try h.barrier.withStabilizedSource(.morning) { _ in })
        h.assertReleased()
    }

    func testMissingExtraDeadAndWrongExecutionFailClosed() throws {
        for kind in 0..<4 {
            let h = try Harness()
            var card: Card? = Card()
            if kind != 1 { h.expected[.morning] = [h.id()] }
            if kind != 0 { h.barrier.register(card!, identity: h.id()) }
            if kind == 2 { card = nil }
            if kind == 3 {
                let id = h.id()
                h.expected[.morning] = [.init(executionID: UUID(), version: id.version, date: id.date,
                    activeProgramID: id.activeProgramID, sourceFingerprint: id.sourceFingerprint, itemID: id.itemID)]
            }
            XCTAssertThrowsError(try h.barrier.withStabilizedSource(.morning) { _ in XCTFail() })
            withExtendedLifetime(card) {}; h.assertReleased()
        }
    }

    func testRegistryChangeDuringPreparationAndClosureFails() throws {
        for duringPrepare in [true, false] {
            let h = try Harness(); let card = Card(); h.add(card, id: h.id())
            let change = { h.barrier.unregister(identity: h.id(), token: card.instance) }
            if duringPrepare { card.prepareHook = change }
            XCTAssertThrowsError(try h.barrier.withStabilizedSource(.morning) { _ in
                if duringPrepare { XCTFail() } else { change() }
            })
            XCTAssertTrue(card.gate.allowsOrdinaryMutation); h.assertReleased()
        }
    }

    func testCommentsExactEmptySpacesSameContentAndGeneration() throws {
        let h = try Harness()
        for source in [DayComposerSource.morning, .evening] {
            let holder = source == .morning ? h.am : h.pm
            for text in ["", "  ", "A", "B", "A", "A"] {
                let old = holder.text; let generation = holder.generation
                XCTAssertTrue(h.barrier.editComment(holder, text: text))
                XCTAssertEqual(holder.generation, generation + (old == text ? 0 : 1))
                let count = h.writes.count
                try h.barrier.withStabilizedSource(source) { XCTAssertEqual($0.comment, text) }
                XCTAssertEqual(h.writes.count, count + 1)
                XCTAssertEqual(h.persisted[source], text)
            }
        }
        h.assertReleased()
    }

    func testCommentFailureRejectionAndReadbackMismatchKeepText() throws {
        for outcome in [LocalPersistenceResult.failed, .rejectedContext, .accepted] {
            let h = try Harness(); h.writeResult = outcome; h.mismatch = outcome == .accepted
            XCTAssertThrowsError(try h.barrier.withStabilizedSource(.morning) { _ in XCTFail() })
            XCTAssertEqual(h.am.text, " AM ")
            XCTAssertEqual(h.rejected, outcome == .rejectedContext); h.assertReleased()
        }
        let h = try Harness(); h.writeResult = .failed
        XCTAssertTrue(h.barrier.editComment(h.am, text: "latest failed"))
        XCTAssertEqual(h.am.text, "latest failed"); XCTAssertFalse(h.rejected)
    }

    func testCommentReplacementMissingDuplicateAndReadbackAfterClosure() throws {
        for kind in 0..<4 {
            let h = try Harness(); let replacement = DayComposerCommentParticipant(source: .morning, text: h.am.text)
            if kind == 0 { h.barrier.unregisterComment(source: .morning, token: h.am.instance) }
            if kind == 1 { h.barrier.registerComment(replacement) }
            XCTAssertThrowsError(try h.barrier.withStabilizedSource(.morning) { _ in
                if kind < 2 { XCTFail() }
                if kind == 2 {
                    h.barrier.unregisterComment(source: .morning, token: h.am.instance)
                    h.barrier.registerComment(replacement)
                } else { h.persisted[.morning] = "different" }
            })
            withExtendedLifetime(replacement) {}; h.assertReleased()
        }
    }

    func testFrozenMutationNavigationAndSourceIsolation() throws {
        let h = try Harness(); let am = Card(); let pm = Card()
        h.add(am, id: h.id()); h.add(pm, id: h.id("A", .evening))
        pm.onEvent = { _ in XCTFail("PM touched") }
        let generation = h.pm.generation
        try h.barrier.withStabilizedSource(.morning) { _ in
            XCTAssertFalse(am.gate.performOrdinaryMutation { XCTFail() })
            XCTAssertTrue(pm.gate.allowsOrdinaryMutation)
            XCTAssertFalse(h.barrier.editComment(h.am, text: "blocked"))
            for _ in 0..<6 { XCTAssertFalse(h.barrier.performNavigation { XCTFail() }) }
        }
        XCTAssertEqual(h.pm.generation, generation); XCTAssertEqual(h.writes, [.morning])
        XCTAssertTrue(h.barrier.performNavigation {}); h.assertReleased()
    }

    func testNestedAttemptsBothSourcesAndPublicationReentranceAreBusy() throws {
        let h = try Harness()
        var reentries = 0
        let observation = h.barrier.objectWillChange.sink {
            // Published state can synchronously call clients on this same MainActor stack.
            MainActor.assumeIsolated {
                guard h.barrier.isInteractionFrozen else { return }
                XCTAssertThrowsError(try h.barrier.withStabilizedSource(.evening) { _ in XCTFail() }) {
                    XCTAssertEqual($0 as? DayComposerStabilizationError, .busy)
                }
                reentries += 1
            }
        }
        try h.barrier.withStabilizedSource(.morning) { _ in
            for source in [DayComposerSource.morning, .evening] {
                XCTAssertThrowsError(try h.barrier.withStabilizedSource(source) { _ in XCTFail() }) {
                    XCTAssertEqual($0 as? DayComposerStabilizationError, .busy)
                }
            }
        }
        XCTAssertGreaterThan(reentries, 0); withExtendedLifetime(observation) {}; h.assertReleased()
    }

    func testThrowPrivateMutationGuardChangeAndGenericFlushRelease() throws {
        enum Marker: Error { case original }
        for kind in 0..<5 {
            let h = try Harness(); let card = Card(); h.add(card, id: h.id())
            if kind == 3 { card.flushHook = { throw DayComposerStabilizationError.persistenceFailed } }
            if kind == 4 { card.prepareHook = { throw DayComposerStabilizationError.editor(.unresolvedPrivateState("counter")) } }
            XCTAssertThrowsError(try h.barrier.withStabilizedSource(.morning) { _ in
                switch kind {
                case 0: throw Marker.original
                case 1: card.generation += 1
                case 2: h.revision += 1
                default: XCTFail()
                }
            }) { if kind == 0 { XCTAssertTrue($0 is Marker) } }
            XCTAssertTrue(card.gate.allowsOrdinaryMutation); XCTAssertFalse(h.rejected); h.assertReleased()
        }
    }

    func testRealDraftFlushG2NormalizationAndReadinessPartial() throws {
        let f = try DayComposerStabilizationFixture(); defer { f.cleanup() }
        try f.mount(.morning); try f.mount(.evening)
        let vm = f.vms[0]; let handle = f.handles[0]
        let editor = ExerciseStepperEditor()
        editor.mount(read: { vm.sets[0].reps }, write: { vm.sets[0].reps = $0 }, minimum: 0, isInteger: true,
            context: .init(controller: handle, identity: "reps", writeNormalized: { vm.sets[0].reps = $0 }))
        defer { editor.unmount() }
        vm.sets[0].reps = "05"
        let before = try f.coordinator.currentFinalizationGuard(for: .morning)
        let pmBefore = try f.coordinator.currentFinalizationGuard(for: .evening)
        try f.barrier.withStabilizedSource(.morning) { evidence in
            XCTAssertEqual(vm.sets[0].reps, "5")
            XCTAssertGreaterThan(evidence.guardValue.revision, before.revision)
            XCTAssertEqual(evidence.guardValue, try f.coordinator.currentFinalizationGuard(for: .morning))
            let facts = try f.coordinator.captureLocalFinalizationFacts(for: .morning, evidence: evidence)
            XCTAssertEqual(facts.itemFacts.first?.draft, .present)
            XCTAssertEqual(DayComposerReadiness.evaluate(f.input(facts)).state, .partial)
            if case .success = DayComposerFinalizationSnapshot.build(f.input(facts)) { XCTFail("Draft accepted") }
        }
        XCTAssertTrue(f.coordinator.morningVM.logResults.isEmpty)
        XCTAssertEqual(pmBefore, try f.coordinator.currentFinalizationGuard(for: .evening))
        XCTAssertNil(SessionDraftStore.loadComment(date: f.date, sessionType: "evening"))
    }

    func testRealLoggedCleanCaptureSnapshotAndStoredThenStale() throws {
        let f = try DayComposerStabilizationFixture(); defer { f.cleanup() }
        let id = try XCTUnwrap(f.coordinator.orderedUnits.first?.items.first?.id)
        var log = ExerciseLogResult(name: "A", weight: 80, reps: "5", equipmentType: "machine")
        log.sets = [["weight": 80.0, "reps": "5"]]
        XCTAssertEqual(f.coordinator.submit(candidate: log, for: id), .accepted)
        try f.mount(.morning)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DayComposerFinalizationStore(baseDirectory: directory)
        var stored: DayComposerFinalizationSnapshot?
        try f.barrier.withStabilizedSource(.morning) { evidence in
            let facts = try f.coordinator.captureLocalFinalizationFacts(for: .morning, evidence: evidence)
            XCTAssertEqual(facts.itemFacts.first?.draft, .absent)
            XCTAssertEqual(DayComposerReadiness.evaluate(f.input(facts)).state, .ready)
            stored = try DayComposerFinalizationSnapshot.build(f.input(facts)).get()
        }
        XCTAssertThrowsError(try f.barrier.withStabilizedSource(.morning) { evidence in
            let facts = try f.coordinator.captureLocalFinalizationFacts(for: .morning, evidence: evidence)
            let snapshot = try DayComposerFinalizationSnapshot.build(f.input(facts)).get()
            stored = snapshot
            try store.recordSourceSnapshot(identity: snapshot.identity, version: snapshot.sourceVersion,
                                           provenanceGuard: snapshot.provenanceGuard)
            f.handles[0].didMutatePrivateState()
        }) { XCTAssertEqual($0 as? DayComposerStabilizationError, .staleEvidence) }
        let snapshot = try XCTUnwrap(stored)
        XCTAssertEqual(try store.load(identity: snapshot.identity)?.sourceSnapshots.count, 1)
        XCTAssertEqual(ExerciseDraftPersistence(date: f.date, sessionType: "morning", exerciseName: "A").presence(), .absent)
        XCTAssertFalse(f.barrier.isInteractionFrozen)
    }

    func testRealPresentationCoverageReadOnlyUnsupportedCorruptAndLocalPrecedence() throws {
        let names = ["A", "Draft", "Observed", "Conflict", "Unsupported", "Corrupt", "Unsafe", "Safe"]
        let f = try DayComposerStabilizationFixture(morning: names,
            tracking: ["Unsupported": "cardio"], observed: ["Observed", "Conflict", "Safe"])
        defer { f.cleanup() }
        let c = f.coordinator
        func item(_ name: String) throws -> DayComposerItemID {
            try XCTUnwrap(c.orderedUnits.flatMap(\.items).first { $0.name == name && $0.id.source == .morning }?.id)
        }
        let token = try c.authorization(for: .morning)
        // Create the local log through the admitted owner to exercise rendering's
        // local precedence even though the cached projection observes that name.
        var safe = ExerciseLogResult(name: "Safe", weight: 80, reps: "5", equipmentType: "machine")
        safe.sets = [["weight": 80.0, "reps": "5"]]
        c.morningVM.logResults["Safe"] = safe
        c.morningVM.logResults["Unsafe"] = ExerciseLogResult(name: "Unsafe", weight: 80, reps: "5", equipmentType: "machine")
        let draftVM = ExerciseViewModel(name: "Draft", scheme: "1x5", weightData: nil, sessionDate: f.date,
                                       draftAuthorization: token, validateLocalPersistence: { c.validateLocalPersistence() })
        draftVM.initializeSets(); draftVM.sets[0].reps = "7"
        guard case .stable = draftVM.flushPendingLocalPersistence() else { return XCTFail("Draft persistence failed") }
        let conflictVM = ExerciseViewModel(name: "Conflict", scheme: "1x5", weightData: nil, sessionDate: f.date,
            draftAuthorization: token, validateLocalPersistence: { c.validateLocalPersistence() })
        conflictVM.initializeSets(); conflictVM.sets[0].reps = "7"
        guard case .stable = conflictVM.flushPendingLocalPersistence() else { return XCTFail("Conflict draft failed") }
        XCTAssertTrue(DayComposerProvenanceStore.shared.mutate(date: f.date, sessionType: "morning", authorization: token) {
            UserDefaults.standard.set(Data("bad".utf8), forKey: "exo_draft_\(f.date)_morning_Corrupt")
        })
        let expected = c.expectedMutableParticipantIDs(for: .morning)
        XCTAssertEqual(Set(expected.map(\.itemID)), Set(try [item("A"), item("Draft"), item("Safe")]))
        XCTAssertEqual(c.presentation(for: try item("Unsafe"))?.rendering, .localReadOnly)
        XCTAssertEqual(c.presentation(for: try item("Corrupt"))?.rendering, .corruptDraft)
        XCTAssertEqual(c.presentation(for: try item("Observed"))?.rendering, .observed)
        XCTAssertEqual(c.presentation(for: try item("Conflict"))?.rendering, .conflict)
        XCTAssertEqual(c.presentation(for: try item("Unsupported"))?.rendering, .unsupported)
        try f.mount(.morning)
        try f.barrier.withStabilizedSource(.morning) { evidence in
            let facts = try c.captureLocalFinalizationFacts(for: .morning, evidence: evidence)
            XCTAssertTrue(try XCTUnwrap(facts.itemFacts.first { $0.itemID == (try? item("Safe")) }).localConflictsWithServer)
            XCTAssertNotEqual(DayComposerReadiness.evaluate(f.input(facts)).state, .ready)
        }
    }

    func testRealSupersetRequiresBothMembersAndReadOnlyTransitionInvalidates() throws {
        let f = try DayComposerStabilizationFixture(morning: ["A", "B"],
            supersets: ["AM": ["SS": .init(a: "A", b: "B", rest: 90)]])
        defer { f.cleanup() }
        let ids = f.coordinator.expectedMutableParticipantIDs(for: .morning)
        XCTAssertEqual(ids.count, 2)
        try f.mount(.morning)
        f.barrier.unregister(identity: ids[1], token: f.handles[1].instance)
        XCTAssertThrowsError(try f.barrier.withStabilizedSource(.morning) { _ in XCTFail() })
        f.barrier.register(f.handles[1], identity: ids[1])
        XCTAssertNoThrow(try f.barrier.withStabilizedSource(.morning) { _ in })
        // A non-hydratable accepted result changes the actual presentation, even
        // before SwiftUI has delivered onDisappear to remove the old participant.
        XCTAssertEqual(f.coordinator.submit(candidate: ExerciseLogResult(name: "B", weight: 80, reps: "5",
            equipmentType: "machine"), for: ids[1].itemID), .accepted)
        XCTAssertEqual(f.coordinator.expectedMutableParticipantIDs(for: .morning).count, 1)
        XCTAssertThrowsError(try f.barrier.withStabilizedSource(.morning) { _ in XCTFail() })
        XCTAssertFalse(f.barrier.isInteractionFrozen)
    }

    func testRealPrivateAndPersistenceFailuresReleaseWithoutLogging() throws {
        for kind in 0..<6 {
            let f = try DayComposerStabilizationFixture(); defer { f.cleanup() }
            var fails = false
            let c = f.coordinator
            try f.mount(.morning, validator: { fails ? .failed : c.validateLocalPersistence() })
            let handle = f.handles[0]; let vm = f.vms[0]
            switch kind {
            case 0: handle.setCount(4, identity: "counter")
            case 1: handle.enduranceTransition(.running)
            case 2: handle.setEquipment("barbell")
            case 3: vm.painZone = "Knee"
            case 4: fails = true
            default:
                vm.sets[0].weight = "80"; vm.sets[0].reps = "5"
                XCTAssertEqual(vm.submitLog(alreadyLoggedViaBinding: false) { _ in fails = true; return .accepted }, .failed)
                XCTAssertTrue(vm.cleanupPending)
                fails = false // Isolate cleanupPending refusal from the validator failure.
            }
            XCTAssertThrowsError(try f.barrier.withStabilizedSource(.morning) { _ in XCTFail() })
            XCTAssertFalse(f.barrier.isInteractionFrozen)
            XCTAssertTrue(handle.gate.allowsOrdinaryMutation)
            XCTAssertFalse(c.isLocked)
            XCTAssertTrue(c.morningVM.logResults.isEmpty)
        }
    }

    func testRealGuardRejectsPendingIntegrityInvalidationExecutionAndContext() throws {
        for kind in 0..<5 {
            let f = try DayComposerStabilizationFixture(); defer { f.cleanup() }
            let store = DayComposerProvenanceStore.shared
            switch kind {
            case 0: _ = try store.begin(f.coordinator.authorization(for: .morning))
            case 1: UserDefaults.standard.set("unattributed", forKey: "session_comment_morning_\(f.date)")
            case 2: try store.invalidate(date: f.date, source: .morning)
            default:
                let old = try XCTUnwrap(store.load(date: f.date))
                let context: DayComposerExecutionContext
                if kind == 4 {
                    let plan = try DayComposerSnapshot(date: f.date, activeProgramID: "different",
                        morning: DayComposerPlan(source: .morning, session: "AM", schemes: ["A": "1x5"], order: []),
                        evening: DayComposerPlan(source: .evening, session: "PM", schemes: ["A": "1x5"], order: []),
                        morningCompleted: false, eveningCompleted: false)
                    context = try .init(snapshot: plan)
                } else { context = old.context }
                let changed = DayComposerRecoveryProvenance(schemaVersion: old.schemaVersion,
                    executionID: kind == 3 ? UUID() : old.executionID, context: context,
                    morning: old.morning, evening: old.evening)
                try JSONEncoder().encode(changed).write(to: store.recordURL(date: f.date), options: .atomic)
            }
            XCTAssertThrowsError(try f.coordinator.currentFinalizationGuard(for: .morning))
            XCTAssertTrue(f.coordinator.isLocked)
            XCTAssertThrowsError(try f.barrier.withStabilizedSource(.morning) { _ in XCTFail() })
            XCTAssertFalse(f.barrier.isInteractionFrozen)
        }
    }

    func testRealCoordinatorNavigationFrozenThenRestoredAndEvidenceExpires() throws {
        let f = try DayComposerStabilizationFixture(morning: ["A", "B"]); defer { f.cleanup() }
        try f.mount(.morning)
        let c = f.coordinator
        let before = c.currentMemberID
        let target = try XCTUnwrap(c.orderedUnits.last?.items.last?.id)
        var escaped: DayComposerStableSourceEvidence?
        try f.barrier.withStabilizedSource(.morning) { evidence in
            escaped = evidence
            c.consult(target); c.consultAdjacent(offset: 1); c.next(); c.previous(); c.selectFirstActionable()
            if let before { c.advanceAfterAcceptedLog(itemID: before) }
            XCTAssertThrowsError(try c.select(target))
            XCTAssertEqual(c.currentMemberID, before)
            XCTAssertFalse(f.barrier.performNavigation { XCTFail("Leave/toggle must not run") })
        }
        XCTAssertThrowsError(try c.captureLocalFinalizationFacts(for: .morning, evidence: XCTUnwrap(escaped)))
        c.consult(target); XCTAssertEqual(c.currentMemberID, target)
    }

    func testRealPostClosureG3FailsAndKeepsLatestComment() throws {
        let f = try DayComposerStabilizationFixture(); defer { f.cleanup() }
        try f.mount(.morning)
        XCTAssertThrowsError(try f.barrier.withStabilizedSource(.morning) { _ in
            // Simulate an out-of-band authorized write, not the gated UI path.
            XCTAssertEqual(f.coordinator.setComment("newer", for: .morning), .accepted)
        }) { XCTAssertEqual($0 as? DayComposerStabilizationError, .staleEvidence) }
        XCTAssertEqual(f.coordinator.comment(for: .morning), "newer")
        XCTAssertFalse(f.coordinator.isLocked); XCTAssertFalse(f.barrier.isInteractionFrozen)
    }

    func testCommentGenerationInvalidatesEvenWhenTextReturnsToOriginal() throws {
        let h = try Harness(); let otherEntry = try Harness()
        XCTAssertThrowsError(try h.barrier.withStabilizedSource(.morning) { _ in
            // A second entry point must not silently make an old generation current.
            otherEntry.barrier.editComment(h.am, text: "changed")
            otherEntry.barrier.editComment(h.am, text: " AM ")
        }) { XCTAssertEqual($0 as? DayComposerStabilizationError, .staleEvidence) }
        XCTAssertEqual(h.am.text, " AM "); XCTAssertEqual(h.am.generation, 2); h.assertReleased()
    }

    func testContextRejectionDuringCardFlushUsesSecurityPath() throws {
        let h = try Harness(); let card = Card(); h.add(card, id: h.id())
        card.flushHook = { throw DayComposerStabilizationError.contextRejected }
        XCTAssertThrowsError(try h.barrier.withStabilizedSource(.morning) { _ in XCTFail() })
        XCTAssertTrue(h.rejected); XCTAssertTrue(card.gate.allowsOrdinaryMutation); h.assertReleased()
    }

    func testLaterPrepareFailurePreventsEveryForcedFlush() throws {
        let h = try Harness(); let a = Card(); let b = Card()
        let second = DayComposerExecutionItemIdentity(executionID: h.identity.executionID, version: h.identity.contextVersion,
            date: h.identity.date, activeProgramID: h.identity.activeProgramID, sourceFingerprint: h.identity.sourceFingerprint,
            itemID: .init(source: .morning, name: "B", exerciseID: nil))
        h.add(a, id: h.id()); h.add(b, id: second)
        a.flushHook = { XCTFail("Flushed before all preparation accepted") }
        b.prepareHook = { throw DayComposerStabilizationError.editor(.unresolvedPrivateState("timer")) }
        XCTAssertThrowsError(try h.barrier.withStabilizedSource(.morning) { _ in XCTFail() })
        XCTAssertTrue(h.writes.isEmpty); h.assertReleased()
    }

    func testPreparedAdapterRejectsStaleReceiptWithoutPreparingAgain() throws {
        let f = try DayComposerStabilizationFixture(); defer { f.cleanup() }
        try f.mount(.morning)
        let handle = f.handles[0]
        let receipt = try handle.prepareEditorsForStabilization().get()
        handle.didMutatePrivateState()
        guard case .editorFailure(.instanceChanged) = handle.flushPreparedEditors(receipt) else {
            return XCTFail("Stale preparation must not silently re-prepare")
        }
        XCTAssertEqual(ExerciseDraftPersistence(date: f.date, sessionType: "morning", exerciseName: "A").presence(), .absent)
    }

    func testExplicitDeadReplacementAndStaleUnregisterAreSafe() throws {
        let h = try Harness()
        var old: Card? = Card()
        let oldToken = old!.instance
        h.add(old!, id: h.id()); old = nil
        let replacement = Card()
        XCTAssertTrue(h.barrier.register(replacement, identity: h.id()))
        let generation = h.barrier.registryGeneration(for: .morning)
        h.barrier.unregister(identity: h.id(), token: oldToken)
        XCTAssertEqual(h.barrier.registryGeneration(for: .morning), generation)
        XCTAssertNoThrow(try h.barrier.withStabilizedSource(.morning) { _ in })
    }

    func testSameCommentStillRejectsInvalidContextAndPreservesPriorGate() throws {
        let h = try Harness(); let card = Card(); h.add(card, id: h.id())
        card.gate.allowsOrdinaryMutation = false
        try h.barrier.withStabilizedSource(.morning) { _ in }
        XCTAssertFalse(card.gate.allowsOrdinaryMutation)
        let writes = h.writes.count
        h.valid = false
        XCTAssertThrowsError(try h.barrier.withStabilizedSource(.morning) { _ in XCTFail() })
        XCTAssertEqual(h.writes.count, writes); XCTAssertTrue(h.rejected); h.assertReleased()
    }

    func testDetachedCardAfterMountIsNotStable() throws {
        let f = try DayComposerStabilizationFixture(); defer { f.cleanup() }
        try f.mount(.morning)
        f.handles[0].detach()
        XCTAssertThrowsError(try f.barrier.withStabilizedSource(.morning) { _ in XCTFail() })
        XCTAssertFalse(f.barrier.isInteractionFrozen)
    }
}
