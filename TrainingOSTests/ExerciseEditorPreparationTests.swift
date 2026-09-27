import XCTest
@testable import TrainingOS

@MainActor
final class ExerciseEditorPreparationTests: XCTestCase {
    private var dates: [String] = []

    private func makeVM(validator: (() -> LocalPersistenceResult)? = nil, initialize: Bool = true) throws -> ExerciseViewModel {
        let date = "editor-prepare-\(UUID().uuidString)"
        dates.append(date)
        let context = try DayComposerExecutionContext(snapshot: DayComposerSnapshot(date: date, activeProgramID: "A",
            morning: DayComposerPlan(source: .morning, session: "AM", schemes: ["A": "1x5"], order: []),
            evening: DayComposerPlan(source: .evening, session: "PM", schemes: [:], order: []),
            morningCompleted: false, eveningCompleted: false))
        try DayComposerProvenanceStore.shared.create(context: context)
        let token = try DayComposerProvenanceStore.shared.authorize(context: context, source: .morning)
        let vm = ExerciseViewModel(name: "A", scheme: "1x5", weightData: nil,
            sessionDate: date, draftAuthorization: token, validateLocalPersistence: validator)
        if initialize { vm.initializeSets() }
        return vm
    }

    override func tearDown() async throws {
        for date in dates {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            try? DayComposerProvenanceStore.shared.clear(date: date)
        }
        dates = []
    }

    private func ready(_ controller: ExerciseEditorPreparationController) throws -> ExerciseEditorPreparationReceipt {
        try controller.prepareEditorsForStabilization().get()
    }

    private func mountStepper(_ controller: ExerciseEditorPreparationController, read: @escaping () -> String,
                              write: @escaping (String) -> Void, identity: String = "set-0.weight",
                              minimum: Double = 0, isInteger: Bool = false) -> ExerciseStepperEditor {
        let editor = ExerciseStepperEditor()
        editor.mount(read: read, write: write, minimum: minimum, isInteger: isInteger,
            context: .init(controller: controller, identity: identity, writeNormalized: write))
        return editor
    }

    func testHistoricalNormalizationAndIdempotentLateBlur() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        var raw = "12,50"
        var writes = 0
        let editor = mountStepper(controller, read: { raw }, write: { raw = $0; writes += 1 })
        let receipt = try ready(controller)
        XCTAssertEqual(raw, "12.5")
        XCTAssertEqual(writes, 1)
        editor.normalizeOrdinary() // Real focus-loss path.
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(controller.verifyEditors(receipt))
        XCTAssertEqual(ExerciseStepperEditor.normalized("", minimum: 1, isInteger: true), "")
        XCTAssertEqual(ExerciseStepperEditor.normalized("bad", minimum: 1, isInteger: true), "1")
        XCTAssertEqual(ExerciseStepperEditor.normalized("-8", minimum: 0, isInteger: false), "0")
        XCTAssertEqual(ExerciseStepperEditor.normalized("3,9", minimum: 1, isInteger: true), "3")
    }

    func testNormalizationReadbackMustMatch() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        let editor = mountStepper(controller, read: { "12,50" }, write: { _ in })
        defer { editor.unmount() }
        guard case .failure(.failedPreparation) = controller.prepareEditorsForStabilization() else {
            return XCTFail("A rejected Binding write is not acknowledged")
        }
    }

    func testPreparationCancelsHoldAndRejectsAlreadyQueuedTick() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        var raw = "1"
        let editor = mountStepper(controller, read: { raw }, write: { raw = $0 })
        let epoch = editor.holdEpoch
        let queuedTick = { if editor.holdIsCurrent(epoch) { raw = "99" } }
        queuedTick()
        XCTAssertEqual(raw, "99")
        editor.holdTask = Task { @MainActor in queuedTick() }
        let task = try XCTUnwrap(editor.holdTask)
        _ = try ready(controller)
        XCTAssertTrue(task.isCancelled)
        XCTAssertNil(editor.holdTask)
        raw = "2"
        queuedTick() // Even an already queued MainActor block checks its epoch.
        XCTAssertEqual(raw, "2")
    }

    func testPreparationAndUnmountInvalidateFocusCallbacks() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        let editor = mountStepper(controller, read: { "1" }, write: { _ in })
        let before = editor.callbackEpoch
        XCTAssertTrue(editor.callbackIsCurrent(before))
        _ = try ready(controller)
        XCTAssertFalse(editor.callbackIsCurrent(before))
        let after = editor.callbackEpoch
        editor.unmount()
        XCTAssertFalse(editor.callbackIsCurrent(after))
    }

    func testFrozenGateAllowsOnlyPreparationNormalization() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        var raw = "2,50"
        let editor = mountStepper(controller, read: { raw }, write: { raw = $0 })
        controller.gate.allowsOrdinaryMutation = false
        editor.normalizeOrdinary()
        XCTAssertEqual(raw, "2,50")
        XCTAssertFalse(editor.step(1, increment: 1, minimum: 0, placeholder: 0, isInteger: false))
        XCTAssertEqual(raw, "2,50")
        let equipment = vm.equipmentType
        controller.setEquipment("barbell")
        XCTAssertEqual(vm.equipmentType, equipment)
        XCTAssertFalse(editor.allowsOrdinaryMutation)
        _ = try ready(controller)
        XCTAssertEqual(raw, "2.5")
        XCTAssertFalse(controller.gate.allowsOrdinaryMutation)
    }

    func testClassicStepperNeedsNoContext() {
        var raw = "3,50"
        let editor = ExerciseStepperEditor()
        editor.mount(read: { raw }, write: { raw = $0 }, minimum: 0, isInteger: false, context: nil)
        XCTAssertTrue(editor.allowsOrdinaryMutation)
        editor.normalizeOrdinary()
        XCTAssertEqual(raw, "3.5")
        editor.unmount()
    }

    func testGateRejectsBeforeSetsNotePainAndActionWrites() throws {
        let vm = try makeVM()
        let gate = ExerciseEditorMutationGate()
        let generation = vm.localEditGeneration
        let originalReps = vm.sets[0].reps
        var actions = 0
        gate.allowsOrdinaryMutation = false
        XCTAssertFalse(gate.performOrdinaryMutation { vm.sets[0].reps = "9" })
        XCTAssertFalse(gate.performOrdinaryMutation { vm.sessionNote = "Blocked" })
        XCTAssertFalse(gate.performOrdinaryMutation { vm.painZone = "Blocked" })
        XCTAssertFalse(gate.performOrdinaryMutation { actions += 1 })
        XCTAssertEqual(vm.sets[0].reps, originalReps)
        XCTAssertEqual(vm.sessionNote, "")
        XCTAssertEqual(vm.painZone, "")
        XCTAssertEqual(vm.localEditGeneration, generation)
        XCTAssertNil(vm.draftSavedAt)
        XCTAssertEqual(actions, 0)
        gate.allowsOrdinaryMutation = true
        XCTAssertTrue(gate.performOrdinaryMutation { actions += 1 })
        XCTAssertEqual(actions, 1)
    }

    func testCounterRemainsUnresolvedAcrossCollapseAndDecrementToZero() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        let child = ExercisePrivateEditor()
        child.mount(controller, identity: "counter.set-0.reps")
        controller.setCount(1, identity: "counter.set-0.reps")
        let before = vm.sets
        child.unmount()
        guard case .failure(.unresolvedPrivateState) = controller.prepareEditorsForStabilization() else {
            return XCTFail("Collapse cannot confirm a count")
        }
        XCTAssertEqual(vm.sets.map(\.reps), before.map(\.reps))
        let replacement = ExercisePrivateEditor()
        replacement.mount(controller, identity: "counter.set-0.reps")
        XCTAssertEqual(controller.count(identity: "counter.set-0.reps"), 1)
        controller.setCount(0, identity: "counter.set-0.reps")
        XCTAssertThrowsError(try ready(controller))
        controller.setCount(0, identity: "counter.set-0.reps", explicitlyResolved: true)
        _ = try ready(controller)
    }

    func testExplicitCounterConfirmationTransfersBeforeResolution() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        controller.setCount(5, identity: "counter.set-0.reps")
        XCTAssertThrowsError(try ready(controller))
        _ = vm.confirmSet(reps: controller.count(identity: "counter.set-0.reps"))
        controller.setCount(0, identity: "counter.set-0.reps", explicitlyResolved: true)
        _ = try ready(controller)
        XCTAssertEqual(vm.sets[0].reps, "5")
        XCTAssertFalse(vm.isLogged)
    }

    func testEveryActiveTimerStateBlocksWithoutFinishingOrLogging() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm, requiresEnduranceInspection: true)
        let duration = vm.sets[0].duration
        for state in [ExerciseEndurancePreparationState.countdown, .running, .warning, .paused, .completionUndelivered] {
            controller.enduranceTransition(state)
            guard case .editorFailure(.unresolvedPrivateState) = controller.prepareAndFlush() else {
                return XCTFail("Private timer state incorrectly certified: \(state)")
            }
            XCTAssertEqual(vm.sets[0].duration, duration)
            XCTAssertFalse(vm.isLogged)
            XCTAssertNil(vm.draftSavedAt)
        }
    }

    func testEnduranceDisappearAndIdleRemountDoNotEraseRecovery() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm, requiresEnduranceInspection: true)
        let child = ExercisePrivateEditor()
        child.mount(controller, identity: "endurance.set-0.left")
        controller.enduranceTransition(.running)
        child.unmount()
        controller.inspectEnduranceIdle()
        XCTAssertThrowsError(try ready(controller))
        controller.enduranceTransition(.explicitlyStopped)
        _ = try ready(controller)
    }

    func testDeliveredDurationResolvesAndUnilateralIdentityChangesInvalidate() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm, requiresEnduranceInspection: true)
        let child = ExercisePrivateEditor()
        child.mount(controller, identity: "endurance.set-0.left")
        controller.enduranceTransition(.completionUndelivered)
        XCTAssertThrowsError(try ready(controller))
        vm.sets[0].durationLeft = 45 // Historical callback delivery, not prepare.
        controller.enduranceTransition(.completionDelivered)
        let receipt = try ready(controller)
        XCTAssertEqual(vm.sets[0].durationLeft, 45)
        child.mount(controller, identity: "endurance.set-0.right")
        XCTAssertFalse(controller.verifyEditors(receipt))
    }

    func testEquipmentChangeBlocksUntilAcceptedLogBaseline() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        let receipt = try ready(controller)
        controller.setEquipment("barbell")
        XCTAssertFalse(controller.verifyEditors(receipt))
        XCTAssertThrowsError(try ready(controller))
        vm.sets[0].weight = "80"; vm.sets[0].reps = "5"
        XCTAssertEqual(vm.submitLog(alreadyLoggedViaBinding: false) { _ in .accepted }, .accepted)
        controller.acceptedEquipmentLog()
        XCTAssertEqual(try ready(controller).equipmentType, "barbell")
        controller.removedEquipmentLog()
        XCTAssertThrowsError(try ready(controller)) // Removed log no longer represents this equipment.
    }

    func testRegistryIdempotenceDuplicateMissingAndStaleUnregister() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        var first: ExercisePrivateEditor? = ExercisePrivateEditor()
        let oldToken = try XCTUnwrap(first).instance
        first?.mount(controller, identity: "child")
        let generation = controller.registryGeneration
        first?.mount(controller, identity: "child")
        XCTAssertEqual(controller.registryGeneration, generation)
        first = nil
        guard case .failure(.missingEditor("child")) = controller.prepareEditorsForStabilization() else {
            return XCTFail("Dead weak participant cannot be silently omitted")
        }
        let replacement = ExercisePrivateEditor()
        replacement.mount(controller, identity: "child")
        controller.unregister(identity: "child", token: oldToken)
        _ = try ready(controller)
        let duplicate = ExercisePrivateEditor()
        duplicate.mount(controller, identity: "child")
        guard case .failure(.instanceChanged) = controller.prepareEditorsForStabilization() else {
            return XCTFail("Duplicate live identity accepted")
        }
        replacement.unmount()
        _ = try ready(controller) // Overlapping appear/disappear leaves the surviving token registered.
    }

    func testAllPrivateAndLifecycleChangesInvalidateReceipts() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        let beforeCount = try ready(controller)
        controller.setCount(1, identity: "counter")
        XCTAssertFalse(controller.verifyEditors(beforeCount))
        controller.setCount(0, identity: "counter", explicitlyResolved: true)
        let beforeTimer = try ready(controller)
        controller.enduranceTransition(.paused)
        XCTAssertFalse(controller.verifyEditors(beforeTimer))
        controller.enduranceTransition(.explicitlyStopped)
        let beforeRegister = try ready(controller)
        let child = ExercisePrivateEditor()
        child.mount(controller, identity: "child")
        XCTAssertFalse(controller.verifyEditors(beforeRegister))
        let beforeUnmount = try ready(controller)
        child.unmount()
        XCTAssertFalse(controller.verifyEditors(beforeUnmount))
        let beforeDetach = try ready(controller)
        controller.detach()
        XCTAssertFalse(controller.verifyEditors(beforeDetach))
    }

    func testUnpreparedNumericStateSurvivesCollapse() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        var raw = "3,50"
        let editor = mountStepper(controller, read: { raw }, write: { raw = $0 })
        editor.unmount()
        XCTAssertThrowsError(try ready(controller))
        let replacement = mountStepper(controller, read: { raw }, write: { raw = $0 })
        defer { replacement.unmount() }
        _ = try ready(controller)
        XCTAssertEqual(raw, "3.5")
    }

    func testRealC2aCompositionAndBothInvalidationDomains() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        let editor = mountStepper(controller, read: { vm.sets[0].weight }, write: { vm.sets[0].weight = $0 })
        defer { editor.unmount() }
        vm.sets[0].weight = "80,50"
        guard case .stable(let receipt) = controller.prepareAndFlush() else { return XCTFail("Expected card receipt") }
        XCTAssertEqual(vm.sets[0].weight, "80.5")
        XCTAssertTrue(controller.verifyCardStabilization(receipt))
        vm.sets[0].reps = "6"
        XCTAssertFalse(controller.verifyCardStabilization(receipt))
        guard case .stable(let second) = controller.prepareAndFlush() else { return XCTFail("Expected second receipt") }
        controller.setCount(1, identity: "counter")
        XCTAssertFalse(controller.verifyCardStabilization(second))
        XCTAssertFalse(vm.isLogged)
        XCTAssertNil(vm.logStatus)
    }

    func testPainAndCleanupFailurePropagateWithoutLogging() throws {
        var allowCleanup = true
        let vm = try makeVM(validator: { allowCleanup ? .accepted : .failed })
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        vm.painZone = "Knee"
        guard case .persistenceFailure(.nonRepresentableState(.painZone)) = controller.prepareAndFlush() else {
            return XCTFail("Pain failure lost")
        }
        XCTAssertFalse(vm.isLogged)
        vm.sets[0].weight = "80"; vm.sets[0].reps = "5"
        XCTAssertEqual(vm.submitLog(alreadyLoggedViaBinding: false) { _ in
            allowCleanup = false
            return .accepted
        }, .failed)
        allowCleanup = true
        guard case .persistenceFailure(.failed) = controller.prepareAndFlush() else { return XCTFail("Cleanup failure lost") }
        XCTAssertTrue(vm.cleanupPending)
    }

    func testHydrationRegistrationNeverCreatesEditOrSave() throws {
        let vm = try makeVM(initialize: false)
        vm.initializeRecovery(.init(sets: [SetInput(weight: "80", reps: "5")], note: "Recovered", painZone: ""))
        XCTAssertEqual(vm.sessionNote, "Recovered")
        XCTAssertEqual(vm.localEditGeneration, 0)
        let controller = ExerciseEditorPreparationController()
        XCTAssertThrowsError(try ready(controller)) // Before attach/hydration acknowledgment.
        let generation = vm.localEditGeneration
        controller.attach(vm)
        XCTAssertEqual(controller.editorGeneration, 0)
        let child = mountStepper(controller, read: { vm.sets[0].weight }, write: { vm.sets[0].weight = $0 })
        defer { child.unmount() }
        guard case .stable = controller.prepareAndFlush() else { return XCTFail("Hydrated baseline not stable") }
        XCTAssertEqual(vm.localEditGeneration, generation)
        XCTAssertNil(vm.draftSavedAt)
        XCTAssertFalse(vm.isLogged)
    }

    func testUnavailableStepperRefusesPreparation() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        var exists = true
        var raw = "2,50"
        let child = ExerciseStepperEditor()
        child.mount(read: { raw }, write: { raw = $0 }, minimum: 0, isInteger: false,
            context: .init(controller: controller, identity: "stepper.0.weight",
                           writeNormalized: { raw = $0 }, isAvailable: { exists }))
        exists = false
        guard case .failure(.missingEditor) = controller.prepareEditorsForStabilization() else {
            return XCTFail("Removed/replaced set must not be acknowledged")
        }
        XCTAssertEqual(raw, "2,50")
    }

    func testRegistryChangeDuringPreparationRefusesReceipt() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        let replacement = ExercisePrivateEditor()
        var raw = "2,50"
        let child = mountStepper(controller, read: { raw }, write: {
            raw = $0
            replacement.mount(controller, identity: "new-child")
        })
        defer { child.unmount() }
        guard case .failure(.instanceChanged) = controller.prepareEditorsForStabilization() else {
            return XCTFail("Reentrant registry change accepted")
        }
    }

    func testDifferentCardsCannotReuseReceipts() throws {
        let vm = try makeVM()
        let first = ExerciseEditorPreparationController()
        let second = ExerciseEditorPreparationController()
        first.attach(vm); second.attach(vm)
        XCTAssertFalse(second.verifyEditors(try ready(first)))
    }

    func testRepeatedSetIDsStillHaveDistinctIndexedFieldIdentities() throws {
        let vm = try makeVM()
        let controller = ExerciseEditorPreparationController()
        controller.attach(vm)
        vm.sets = Array(repeating: SetInput(), count: 2)
        XCTAssertEqual(vm.sets[0].id, vm.sets[1].id)
        let first = mountStepper(controller, read: { vm.sets[0].weight }, write: { vm.sets[0].weight = $0 },
                                 identity: "stepper.0.\(vm.sets[0].id).weight")
        let second = mountStepper(controller, read: { vm.sets[1].weight }, write: { vm.sets[1].weight = $0 },
                                  identity: "stepper.1.\(vm.sets[1].id).weight")
        defer { first.unmount(); second.unmount() }
        vm.sets[0].weight = "10,50"; vm.sets[1].weight = "20,50"
        _ = try ready(controller)
        XCTAssertEqual(vm.sets.map(\.weight), ["10.5", "20.5"])
    }
}
