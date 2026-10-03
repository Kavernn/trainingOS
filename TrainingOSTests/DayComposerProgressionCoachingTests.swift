import XCTest
@testable import TrainingOS

@MainActor
final class DayComposerProgressionCoachingTests: XCTestCase {
    // These contracts also run against pre-R11.1: a confirmed source had no
    // retained Coaching owner and the day could complete before any decision.
    func testMorningConfirmedRetainsCoachingOwner() async throws { try await confirmedOwner(.morning) }
    func testEveningConfirmedRetainsCoachingOwner() async throws { try await confirmedOwner(.evening) }
    private func confirmedOwner(_ source: DayComposerSource) async throws {
        let rig = try DayComposerFinishRig(); defer { rig.cleanup() }
        await rig.engine.finishSource(source, rpe: 8)
        XCTAssertEqual(rig.engine.productState(source), .completed)
        XCTAssertEqual(rig.engine.coaching.activeSource, source)
        XCTAssertEqual(rig.engine.coaching.flow.phase, .recap)
        XCTAssertFalse(rig.engine.coaching.allResolved)
    }
    func testBothConfirmedDoNotFinishDayBeforeCoachingDecisions() async throws {
        let rig = try DayComposerFinishRig(); defer { rig.cleanup() }
        await rig.engine.finishSource(.morning, rpe: 8)
        await rig.engine.finishSource(.evening, rpe: 8)
        XCTAssertFalse(rig.engine.dayCompleted, "Coaching decisions must precede the completed-day screen")
    }

    private func suggestion(_ type: String = "increase_weight") -> ProgressionSuggestion {
        var value = ProgressionSuggestion(exerciseName: "A", loadProfile: "compound_hypertrophy", suggestionType: type,
            currentWeight: 100, suggestedWeight: 105, currentScheme: "3x12", suggestedScheme: "4x12",
            reason: "Fixture", fatigueWarning: false)
        value.expectedCurrentWeight = 100; value.expectedCurrentScheme = "3x12"
        value.programID = "A"; value.referenceAvailable = true
        return value
    }

    func testMorningAndEveningExactContexts() async throws {
        for source in [DayComposerSource.morning, .evening] {
            let r = try DayComposerFinishRig(); defer { r.cleanup() }
            await r.engine.finishSource(source, rpe: 8)
            let owner = r.engine.coaching
            await owner.fetch { context in
                XCTAssertEqual(context.date, r.fixture.date)
                XCTAssertEqual(context.sessionType, source.rawValue)
                XCTAssertEqual(context.sessionName, source == .morning ? "AM" : "PM")
                return .actionable([self.suggestion()])
            }
            XCTAssertEqual(owner.flow.phase, .coaching)
            XCTAssertEqual(r.engine.productState(source), .completed)
            XCTAssertFalse(owner.allResolved)
            owner.finishDecision()
            XCTAssertTrue(owner.allResolved)
        }
    }

    func testBothActionableAreSequentialAndBlockCompletedDay() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        await r.engine.finishSource(.evening, rpe: 8)
        let owner = r.engine.coaching
        for source in [DayComposerSource.morning, .evening] {
            XCTAssertEqual(owner.activeSource, source)
            XCTAssertEqual(owner.flow.phase, .recap)
            await owner.fetch { _ in .actionable([self.suggestion()]) }
            XCTAssertEqual(owner.activeSource, source)
            XCTAssertFalse(r.engine.dayCompleted)
            owner.finishDecision()
        }
        XCTAssertTrue(r.engine.dayCompleted)
    }

    func testNewlyFinishedEveningComesFirst() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.evening, rpe: 8)
        await r.engine.finishSource(.morning, rpe: 8)
        XCTAssertEqual(r.engine.coaching.activeSource, .evening)
        r.engine.coaching.finishDecision()
        XCTAssertEqual(r.engine.coaching.activeSource, .morning)
    }

    func testActionableNoneCombinations() async throws {
        for (am, pm) in [(true, false), (false, true), (false, false)] {
            let r = try DayComposerFinishRig(); defer { r.cleanup() }
            await r.engine.finishSource(.morning, rpe: 8)
            await r.engine.finishSource(.evening, rpe: 8)
            for actionable in [am, pm] {
                await r.engine.coaching.fetch { _ in actionable ? .actionable([self.suggestion()]) : .none }
                if actionable { r.engine.coaching.finishDecision() }
            }
            XCTAssertTrue(r.engine.dayCompleted)
        }
    }

    func testMaintainOnlyResolvesWithoutSheet() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        await r.engine.coaching.fetch { _ in .maintainOnly([self.suggestion("maintain")]) }
        XCTAssertNil(r.engine.coaching.activeSource)
        XCTAssertTrue(r.engine.coaching.allResolved)
        XCTAssertFalse(r.engine.dayCompleted)
    }

    func testFetchErrorRetryKeepsSourceCompleted() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        await r.engine.coaching.fetch { _ in .failed(.http(503)) }
        XCTAssertEqual(r.engine.coaching.flow.phase, .failed(.http(503)))
        XCTAssertEqual(r.engine.productState(.morning), .completed)
        await r.engine.coaching.fetch { _ in .actionable([self.suggestion()]) }
        XCTAssertEqual(r.engine.coaching.flow.phase, .coaching)
    }

    func testContinueAfterErrorAllowsEveningCoaching() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        await r.engine.finishSource(.evening, rpe: 8)
        await r.engine.coaching.fetch { _ in .failed(.network) }
        XCTAssertFalse(r.engine.dayCompleted)
        r.engine.coaching.finishDecision()
        XCTAssertEqual(r.engine.coaching.activeSource, .evening)
        await r.engine.coaching.fetch { _ in .actionable([self.suggestion()]) }
        XCTAssertEqual(r.engine.coaching.flow.phase, .coaching)
        r.engine.coaching.finishDecision()
        XCTAssertTrue(r.engine.dayCompleted)
    }

    func testQueuedFinalizationNeverFetchesCoaching() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        r.finalHook = { request in
            let receipt = DayComposerFinishRig.receipt(request.operationKey)
            r.statuses[request.operationKey] = .pending(receipt)
            return .queued(receipt)
        }
        await r.engine.finishSource(.morning, rpe: 8)
        XCTAssertEqual(r.engine.productState(.morning), .pending)
        await r.engine.coaching.fetch { _ in XCTFail("queued source cannot fetch"); return .none }
        XCTAssertTrue(r.engine.coaching.required.isEmpty)
    }

    func testFailedUnverifiedFinalizationNeverFetchesCoaching() async throws {
        for outcome: NeutralSubmissionOutcome<LogSessionResponse> in [.applicationFailure, .invalidResponse] {
            let r = try DayComposerFinishRig(); defer { r.cleanup() }
            r.finalHook = { _ in outcome }
            await r.engine.finishSource(.morning, rpe: 8)
            await r.engine.coaching.fetch { _ in XCTFail("unconfirmed source"); return .none }
            XCTAssertNil(r.engine.coaching.activeSource)
        }
    }

    func testOneFetchWhileRepeatedObservationsAndUpdates() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        let owner = r.engine.coaching
        var continuation: CheckedContinuation<ProgressionFetchOutcome, Never>?
        var calls = 0
        let first = Task { await owner.fetch { _ in
            calls += 1
            return await withCheckedContinuation { continuation = $0 }
        } }
        while continuation == nil { await Task.yield() }
        for _ in 0..<4 {
            owner.observe(r.engine.productResults[.morning]?.reconciliation)
            owner.resume()
            await owner.fetch { _ in calls += 1; return .none }
        }
        XCTAssertEqual(calls, 1)
        continuation?.resume(returning: .actionable([suggestion()]))
        await first.value
        XCTAssertEqual(owner.flow.phase, .coaching)
    }

    func testStaleOwnerIgnoresResponse() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        var valid = true
        let owner = DayComposerCoachingCoordinator(context: r.fixture.coordinator.context, ownerIsValid: { valid })
        owner.observe(r.engine.productResults[.morning]?.reconciliation)
        await owner.fetch { _ in valid = false; return .actionable([self.suggestion()]) }
        XCTAssertNil(owner.activeSource)
        XCTAssertNotEqual(owner.flow.phase, .coaching)
        XCTAssertFalse(owner.allResolved)
    }

    func testCancellationThenResumeRefetchesWithoutDuplicateFinalization() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        let owner = r.engine.coaching, posted = r.posted
        await owner.fetch { _ in owner.suspend(); return .actionable([self.suggestion()]) }
        XCTAssertNil(owner.activeSource)
        owner.resume()
        XCTAssertEqual(owner.flow.phase, .recap)
        await owner.fetch { _ in .none }
        XCTAssertTrue(owner.allResolved)
        XCTAssertEqual(r.posted, posted)
    }

    func testRestoreUnresolvedAndResolvedMarkers() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        await r.engine.finishSource(.evening, rpe: 8)
        let suite = "dc-coaching-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func restored() -> DayComposerCoachingCoordinator {
            let owner = DayComposerCoachingCoordinator(context: r.fixture.coordinator.context, defaults: defaults, ownerIsValid: { true })
            for source in [DayComposerSource.morning, .evening] {
                owner.observe(r.engine.productResults[source]?.reconciliation)
            }
            return owner
        }
        let first = restored()
        await first.fetch { _ in .actionable([self.suggestion()]) }
        first.suspend()
        let second = restored()
        XCTAssertEqual(second.activeSource, .morning)
        await second.fetch { _ in .none }
        XCTAssertEqual(second.activeSource, .evening)
        second.finishDecision()
        XCTAssertTrue(restored().allResolved)
        XCTAssertNil(restored().activeSource)
    }

    func testApplyOutcomesReuseR11Rows() async throws {
        for outcome in [ProgressionApplyOutcome.confirmed(.init(success: true, currentWeight: 105, currentScheme: "4x12")),
                        .queued, .conflict, .failed("fixture")] {
            let r = try DayComposerFinishRig(); defer { r.cleanup() }
            await r.engine.finishSource(.morning, rpe: 8)
            let owner = r.engine.coaching, rows = ProgressionRows(), value = suggestion()
            await owner.fetch { _ in .actionable([value]) }
            let context = try XCTUnwrap(owner.flow.context)
            await rows.apply(value, context: context) { request in
                XCTAssertEqual(request.context, context)
                XCTAssertEqual(request.expectedWeight, 100)
                XCTAssertEqual(request.expectedScheme, "3x12")
                return outcome
            }
            switch outcome {
            case .confirmed: XCTAssertEqual(rows.state(value), .confirmed)
            case .queued: XCTAssertEqual(rows.state(value), .queued)
            case .conflict: XCTAssertEqual(rows.state(value), .conflict)
            case .failed(let error): XCTAssertEqual(rows.state(value), .failed(error))
            }
            XCTAssertEqual(r.engine.productState(.morning), .completed)
            owner.finishDecision()
            XCTAssertTrue(owner.allResolved)
        }
    }

    func testQueuedMorningConfirmedEveningDoNotBlockDayClose() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        await r.engine.finishSource(.evening, rpe: 8)
        for outcome in [ProgressionApplyOutcome.queued, .confirmed(.init(success: true, currentWeight: 105, currentScheme: "4x12"))] {
            let owner = r.engine.coaching, rows = ProgressionRows(), value = suggestion()
            await owner.fetch { _ in .actionable([value]) }
            await rows.apply(value, context: try XCTUnwrap(owner.flow.context)) { _ in outcome }
            owner.finishDecision()
        }
        XCTAssertTrue(r.engine.dayCompleted)
    }

    func testDoubleTapProtectionAndUndoKeepSourceCompleted() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        let owner = r.engine.coaching, rows = ProgressionRows(), value = suggestion()
        await owner.fetch { _ in .actionable([value]) }
        let context = try XCTUnwrap(owner.flow.context)
        var calls = 0
        await rows.apply(value, context: context) { _ in
            calls += 1
            await rows.apply(value, context: context) { _ in calls += 1; return .queued }
            return .confirmed(.init(success: true, currentWeight: 105, currentScheme: "4x12"))
        }
        XCTAssertEqual(calls, 1)
        await rows.undo(value) { request in
            XCTAssertTrue(request.restore)
            XCTAssertEqual(request.weight, 100); XCTAssertEqual(request.scheme, "3x12")
            return .confirmed(.init(success: true, currentWeight: 100, currentScheme: "3x12"))
        }
        XCTAssertEqual(rows.state(value), .restored)
        XCTAssertEqual(r.engine.productState(.morning), .completed)
    }

    func testCancelledFetchReturnsToRecapWithoutErrorAlert() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        await r.engine.coaching.fetch { _ in .failed(.cancelled) }
        XCTAssertEqual(r.engine.coaching.flow.phase, .recap)
        XCTAssertFalse(r.engine.coaching.allResolved)
    }

    func testOldSourceDismissCannotResolveNextSource() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        await r.engine.finishSource(.evening, rpe: 8)
        r.engine.coaching.finishDecision(for: .morning)
        r.engine.coaching.finishDecision(for: .morning)
        XCTAssertEqual(r.engine.coaching.activeSource, .evening)
        XCTAssertFalse(r.engine.dayCompleted)
    }

    func testActualFinalizationRestoreAdmitsCoachingWithoutPosting() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        r.serverCompletion = .completedObserved
        let restored = DayComposerFinishCoordinator(execution: r.fixture.coordinator, barrier: r.fixture.barrier,
            store: r.store, inputs: r.inputs, dependencies: .init(server: { _, source in r.server(source) },
                status: { r.statuses[$0] ?? .notFound },
                exercise: { _ in XCTFail("restore must not POST"); return .invalidResponse },
                final: { _ in XCTFail("restore must not POST"); return .invalidResponse },
                completion: { _, _ in .observed }))
        await restored.refreshSource(.morning)
        XCTAssertEqual(restored.productState(.morning), .completed)
        XCTAssertEqual(restored.coaching.activeSource, .morning)
        await restored.coaching.fetch { _ in .none }
        XCTAssertTrue(restored.coaching.allResolved)
    }

    func testConfirmedSourcePrescriptionChangeKeepsOtherSourceIdentity() throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        let original = r.fixture.coordinator.input.snapshot
        func changed(_ plan: DayComposerPlan, scheme: String = "4x12", name: String? = nil) throws -> DayComposerPlan {
            let items = plan.units.flatMap(\.items)
            return try .init(source: plan.source, session: name ?? plan.session,
                schemes: Dictionary(uniqueKeysWithValues: items.map { ($0.name, scheme) }),
                order: items.map(\.name),
                exerciseIDs: Dictionary(uniqueKeysWithValues: items.compactMap { item in
                    item.id.exercise.hasPrefix("id:") ? (item.name, String(item.id.exercise.dropFirst(3))) : nil
                }), tracking: Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.tracking) }))
        }
        let fresh = DayComposerSnapshot(date: original.date, activeProgramID: original.activeProgramID,
            morning: try changed(original.morning), evening: original.evening,
            morningCompleted: true, eveningCompleted: false)
        let normalized = DayComposerCoachingCoordinator.snapshotForFinalization(fresh, completedPlans: [.morning: original.morning])
        XCTAssertEqual(try normalized.fingerprint, try original.fingerprint)
        XCTAssertEqual(normalized.evening, original.evening)
        XCTAssertNotEqual(try DayComposerCoachingCoordinator.snapshotForFinalization(fresh, completedPlans: [:]).fingerprint,
                          try original.fingerprint)
        let unfinishedChanged = DayComposerSnapshot(date: fresh.date, activeProgramID: fresh.activeProgramID,
            morning: fresh.morning, evening: try changed(original.evening), morningCompleted: true, eveningCompleted: false)
        XCTAssertNotEqual(try DayComposerCoachingCoordinator.snapshotForFinalization(unfinishedChanged,
            completedPlans: [.morning: original.morning, .evening: original.evening]).fingerprint, try original.fingerprint)
        let renamed = DayComposerSnapshot(date: fresh.date, activeProgramID: fresh.activeProgramID,
            morning: try changed(original.morning, name: "OTHER"), evening: original.evening,
            morningCompleted: true, eveningCompleted: false)
        XCTAssertNotEqual(try DayComposerCoachingCoordinator.snapshotForFinalization(renamed,
            completedPlans: [.morning: original.morning]).fingerprint, try original.fingerprint)
    }

    func testOfflineForegroundKeepsConfirmedSourceCompleted() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        let posted = r.posted
        r.serverError = true
        await r.engine.refreshSource(.morning)
        XCTAssertEqual(r.engine.productState(.morning), .completed)
        XCTAssertEqual(r.engine.coaching.activeSource, .morning)
        XCTAssertEqual(r.posted, posted)
        await r.engine.coaching.fetch { _ in .failed(.network) }
        XCTAssertEqual(r.engine.productState(.morning), .completed)
        r.engine.coaching.finishDecision(for: .morning)
        XCTAssertTrue(r.engine.coaching.allResolved)
    }

    func testDifferentProgrammeResponseNeverPresentsCoaching() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        var other = suggestion(); other.programID = "OTHER"
        await r.engine.coaching.fetch { _ in .actionable([other]) }
        XCTAssertTrue(r.engine.coaching.contextRejected)
        XCTAssertNil(r.engine.coaching.activeSource)
        r.engine.coaching.resume()
        XCTAssertNil(r.engine.coaching.activeSource)
        XCTAssertEqual(r.engine.productState(.morning), .completed)
    }

    func testLateWrongProgrammeResponseCannotInvalidateResumedFetch() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        let owner = r.engine.coaching
        var oldReply: CheckedContinuation<ProgressionFetchOutcome, Never>?
        var newReply: CheckedContinuation<ProgressionFetchOutcome, Never>?
        let old = Task { await owner.fetch { _ in await withCheckedContinuation { oldReply = $0 } } }
        while oldReply == nil { await Task.yield() }
        owner.suspend(); owner.resume()
        let current = Task { await owner.fetch { _ in await withCheckedContinuation { newReply = $0 } } }
        while newReply == nil { await Task.yield() }
        var obsolete = suggestion(); obsolete.programID = "OLD"
        oldReply?.resume(returning: .actionable([obsolete]))
        await old.value
        XCTAssertFalse(owner.contextRejected)
        XCTAssertEqual(owner.flow.phase, .loading)
        newReply?.resume(returning: .actionable([suggestion()]))
        await current.value
        XCTAssertEqual(owner.flow.phase, .coaching)
    }

    func testDecisionMarkerUsesOnlyDateSourceAndSession() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        let suite = "dc-marker-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = DayComposerCoachingCoordinator(context: r.fixture.coordinator.context,
            defaults: defaults, ownerIsValid: { true })
        owner.observe(r.engine.productResults[.morning]?.reconciliation)
        let context = try XCTUnwrap(owner.flow.context)
        owner.finishDecision()
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("dc-coaching-resolved-") }
        XCTAssertEqual(keys, ["dc-coaching-resolved-v1-" + Data(context.identity.utf8).base64EncodedString()])
    }

    func testResumeWithBothUnresolvedAlwaysPresentsMorningFirst() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.evening, rpe: 8)
        await r.engine.finishSource(.morning, rpe: 8)
        let owner = r.engine.coaching
        XCTAssertEqual(owner.activeSource, .evening, "Newly finished source keeps live priority")
        owner.suspend(); owner.resume()
        XCTAssertEqual(owner.activeSource, .morning, "Resume orders both unresolved sources deterministically")
        await owner.fetch { _ in .actionable([self.suggestion()]) }
        owner.finishDecision()
        XCTAssertEqual(owner.activeSource, .evening)
    }


    func testConcurrentRestorationReadsMorningFirstWithoutPosting() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        await r.engine.finishSource(.evening, rpe: 8)
        r.serverCompletion = .completedObserved
        var reads: [DayComposerSource] = []
        var releaseMorning: CheckedContinuation<Void, Never>?
        let restored = DayComposerFinishCoordinator(execution: r.fixture.coordinator, barrier: r.fixture.barrier,
            store: r.store, inputs: r.inputs, dependencies: .init(server: { _, source in
                reads.append(source)
                if reads.count == 1 { await withCheckedContinuation { releaseMorning = $0 } }
                return r.server(source)
            }, status: { r.statuses[$0] ?? .notFound },
            exercise: { _ in XCTFail("restore must not POST"); return .invalidResponse },
            final: { _ in XCTFail("restore must not POST"); return .invalidResponse },
            completion: { _, _ in .observed }))
        let first = Task { await restored.refreshSources() }
        while releaseMorning == nil { await Task.yield() }
        await restored.refreshSources()
        XCTAssertEqual(reads, [.morning])
        XCTAssertNil(restored.coaching.activeSource)
        releaseMorning?.resume(); await first.value
        XCTAssertEqual(restored.productState(.morning), .completed)
        XCTAssertEqual(restored.productState(.evening), .completed)
        XCTAssertEqual(restored.coaching.activeSource, .morning)
        await restored.coaching.fetch { _ in .actionable([self.suggestion()]) }
        restored.coaching.finishDecision()
        XCTAssertEqual(restored.coaching.activeSource, .evening)
        await restored.coaching.fetch { _ in .actionable([self.suggestion()]) }
        XCTAssertFalse(restored.dayCompleted)
        restored.coaching.finishDecision()
        XCTAssertTrue(restored.dayCompleted)
    }

}
