import XCTest
@testable import TrainingOS

@MainActor
final class ProgressionExplainabilityTests: XCTestCase {
    private let context = ProgressionContext(date: "2088-10-03", sessionType: "morning", sessionName: "Fixture")
    private func maintain() -> ProgressionSuggestion {
        .init(exerciseName: "Fixture", loadProfile: "compound_hypertrophy", suggestionType: "maintain",
              currentWeight: 100, suggestedWeight: nil, currentScheme: "3x10", suggestedScheme: nil,
              reason: "Fixture", fatigueWarning: false)
    }

    func testMaintainExplainedBeforeFinalCompletion() async {
        ActionFeedbackManager.shared.current = nil
        defer { ActionFeedbackManager.shared.current = nil }
        let flow = ProgressionFlow()
        var completed = false
        flow.begin(context) {
            XCTAssertEqual(ActionFeedbackManager.shared.current?.message, "Coaching analysé · Maintien recommandé")
            completed = true
        }
        await flow.fetch { _ in .maintainOnly([self.maintain()]) }
        XCTAssertTrue(completed)
        XCTAssertEqual(ActionFeedbackManager.shared.current?.message, "Coaching analysé · Maintien recommandé")
    }

    func testNoneExplainedWithoutInventingCause() async {
        ActionFeedbackManager.shared.current = nil
        defer { ActionFeedbackManager.shared.current = nil }
        let flow = ProgressionFlow()
        flow.begin(context) {}
        await flow.fetch { _ in .none }
        XCTAssertEqual(ActionFeedbackManager.shared.current?.message, "Coaching analysé · Aucun ajustement recommandé")
    }

    func testActionableAndFailuresNeverEmitSuccessFeedback() async {
        var actionable = maintain()
        actionable = .init(exerciseName: "Fixture", loadProfile: "compound_hypertrophy",
            suggestionType: "increase_weight", currentWeight: 100, suggestedWeight: 105,
            currentScheme: "3x10", suggestedScheme: nil, reason: "Fixture", fatigueWarning: false)
        for outcome in [ProgressionFetchOutcome.actionable([actionable]), .failed(.network),
                        .failed(.http(503)), .failed(.decoding), .failed(.cancelled), .failed(.staleContext)] {
            ActionFeedbackManager.shared.current = nil
            let flow = ProgressionFlow()
            var completed = false
            flow.begin(context) { completed = true }
            await flow.fetch { _ in outcome }
            XCTAssertNil(ActionFeedbackManager.shared.current)
            XCTAssertFalse(completed)
            if case .actionable = outcome { XCTAssertEqual(flow.phase, .coaching) }
            else { XCTAssertTrue(flow.isFailure) }
        }
    }

    func testEveningAndBonusFeedbackSurvivesFinalDismissal() async {
        for source in ["evening", "bonus"] {
            ActionFeedbackManager.shared.current = nil
            defer { ActionFeedbackManager.shared.current = nil }
            var parentMounted = true
            do {
                let flow = ProgressionFlow()
                flow.begin(.init(date: context.date, sessionType: source, sessionName: context.sessionName)) {
                    XCTAssertNotNil(ActionFeedbackManager.shared.current, "Publish to the surviving app owner before dismissal")
                    parentMounted = false
                }
                await flow.fetch { _ in .maintainOnly([self.maintain()]) }
            }
            XCTAssertFalse(parentMounted)
            XCTAssertEqual(ActionFeedbackManager.shared.current?.message, "Coaching analysé · Maintien recommandé")
            XCTAssertEqual(ActionFeedbackManager.shared.current?.duration, 6)
            XCTAssertEqual(ActionFeedbackManager.shared.current?.accessibilityAnnouncement,
                           "Coaching analysé · Maintien recommandé")
        }
    }

    func testFinishedCycleDoesNotReplayButNewFinalizationCanExplain() async {
        ActionFeedbackManager.shared.current = nil
        defer { ActionFeedbackManager.shared.current = nil }
        let flow = ProgressionFlow()
        flow.begin(context) {}
        await flow.fetch { _ in .none }
        let first = ActionFeedbackManager.shared.current?.id
        XCTAssertNotNil(first)
        ActionFeedbackManager.shared.current = nil
        await flow.fetch { _ in XCTFail("finished cycle must not fetch"); return .none }
        let reconstructed = ProgressionFlow()
        await reconstructed.fetch { _ in XCTFail("re-render alone must not fetch"); return .none }
        XCTAssertNil(ActionFeedbackManager.shared.current)
        flow.begin(context) {} // Explicitly confirmed new finalization cycle.
        await flow.fetch { _ in .none }
        XCTAssertNotEqual(ActionFeedbackManager.shared.current?.id, first)
    }

    func testStaleResponseAndCancelledTransportCannotAnnounceSuccess() async {
        for stale in [false, true] {
            ActionFeedbackManager.shared.current = nil
            let flow = ProgressionFlow()
            var reply: CheckedContinuation<ProgressionFetchOutcome, Never>?
            flow.begin(context) { XCTFail("cancelled/stale must not complete") }
            let work = Task { await flow.fetch { _ in await withCheckedContinuation { reply = $0 } } }
            while reply == nil { await Task.yield() }
            if stale { flow.contextChanged(to: .init(date: "2088-10-04", sessionType: "morning", sessionName: "Other")) }
            else { work.cancel() }
            reply?.resume(returning: .none) // A transport deliberately ignoring cancellation.
            await work.value
            XCTAssertNil(ActionFeedbackManager.shared.current)
        }
    }

    func testDayComposerSourceFeedbackDoesNotBlockDayOrUseGlobalToasts() async throws {
        ActionFeedbackManager.shared.current = nil
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        var row = maintain(); row.programID = "A"
        await r.engine.coaching.fetch { _ in .maintainOnly([row]) }
        XCTAssertEqual(r.engine.coaching.resultFeedback[.morning], .maintain)
        XCTAssertNil(r.engine.coaching.resultFeedback[.evening])
        XCTAssertEqual(r.engine.productState(.morning), .completed)
        await r.engine.finishSource(.evening, rpe: 8)
        await r.engine.coaching.fetch { _ in .none }
        XCTAssertEqual(r.engine.coaching.resultFeedback[.evening], ProgressionResultFeedback.none)
        XCTAssertEqual(r.engine.coaching.resultFeedback.count, 2)
        XCTAssertTrue(r.engine.dayCompleted)
        XCTAssertNil(ActionFeedbackManager.shared.current)
    }

    func testDayComposerRestoreAndReappearanceDoNotRepeatFeedback() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        let suite = "explainability-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let owner = DayComposerCoachingCoordinator(context: r.fixture.coordinator.context,
            defaults: defaults, ownerIsValid: { true })
        owner.observe(r.engine.productResults[.morning]?.reconciliation) // Restored, not a new finalization.
        await owner.fetch { _ in .none }
        XCTAssertTrue(owner.resultFeedback.isEmpty)
        XCTAssertTrue(owner.allResolved)
        let resolved = DayComposerCoachingCoordinator(context: r.fixture.coordinator.context,
            defaults: defaults, ownerIsValid: { true })
        resolved.observe(r.engine.productResults[.morning]?.reconciliation)
        await resolved.fetch { _ in XCTFail("resolved marker must not fetch"); return .none }
        XCTAssertTrue(resolved.resultFeedback.isEmpty)
        await r.engine.coaching.fetch { _ in .none }
        XCTAssertEqual(r.engine.coaching.resultFeedback.count, 1)
        r.engine.coaching.suspend(); r.engine.coaching.resume()
        await r.engine.refreshSource(.morning)
        XCTAssertTrue(r.engine.coaching.resultFeedback.isEmpty)
    }

    func testDayComposerRetryExplainsOnlySuccessfulOutcome() async throws {
        let r = try DayComposerFinishRig(); defer { r.cleanup() }
        await r.engine.finishSource(.morning, rpe: 8)
        await r.engine.coaching.fetch { _ in .failed(.network) }
        XCTAssertTrue(r.engine.coaching.resultFeedback.isEmpty)
        XCTAssertEqual(r.engine.productState(.morning), .completed)
        await r.engine.coaching.fetch { _ in .failed(.cancelled) }
        XCTAssertTrue(r.engine.coaching.resultFeedback.isEmpty)
        await r.engine.coaching.fetch { _ in .none }
        XCTAssertEqual(r.engine.coaching.resultFeedback[.morning], ProgressionResultFeedback.none)
    }

}
