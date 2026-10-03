import XCTest
@testable import TrainingOS

@MainActor final class ProgressionCoachingTests: XCTestCase {
    let context = ProgressionContext(date: "2026-10-02", sessionType: "evening", sessionName: "A")
    func suggestion(_ name: String = "X", type: String = "increase_weight") -> ProgressionSuggestion {
        var s = ProgressionSuggestion(exerciseName: name, loadProfile: "compound_hypertrophy", suggestionType: type,
            currentWeight: 100, suggestedWeight: 105, currentScheme: "3x12", suggestedScheme: "4x12", reason: "Fixture", fatigueWarning: false)
        s.expectedCurrentWeight = 100; s.expectedCurrentScheme = "3x12"; s.programID = "fixture"; s.referenceAvailable = true
        return s
    }
    func testEveningParentSurvivesUntilCoachingDismissExactlyOnce() async {
        let flow = ProgressionFlow(); var dismissals = 0
        flow.begin(context) { dismissals += 1 }
        await flow.fetch { _ in .actionable([self.suggestion()]) }
        XCTAssertEqual(flow.phase, .coaching); XCTAssertEqual(dismissals, 0)
        flow.finish(); flow.finish(); XCTAssertEqual(dismissals, 1)
    }
    func testMorningEveningBonusTypesAndLifecycle() async {
        for (second, bonus, expected) in [(false,false,"morning"),(true,false,"evening"),(false,true,"bonus")] {
            XCTAssertEqual(ProgressionContext.sessionType(second: second, bonus: bonus), expected)
            let flow = ProgressionFlow(); var done = 0
            flow.begin(.init(date: context.date, sessionType: expected, sessionName: "A")) { done += 1 }
            await flow.fetch { value in XCTAssertEqual(value.sessionType, expected); return .actionable([self.suggestion()]) }
            XCTAssertEqual(done, 0);flow.finish();XCTAssertEqual(done, 1)
        }
    }
    func testEmptyAndMaintainCompleteNormally() async {
        for outcome: ProgressionFetchOutcome in [.none, .maintainOnly([suggestion(type:"maintain")])] {
            let flow = ProgressionFlow();var done=0;flow.begin(context){done += 1}
            await flow.fetch { _ in outcome };XCTAssertEqual(done,1);XCTAssertEqual(flow.phase,.finished)
        }
    }
    func testFetchFailuresAreNotEmpty() async {
        for error: ProgressionFetchFailure in [.http(401),.http(500),.network,.decoding,.cancelled,.staleContext] {
            let flow=ProgressionFlow();var done=0;flow.begin(context){done += 1}
            await flow.fetch { _ in .failed(error) };XCTAssertEqual(done,0);XCTAssertEqual(flow.phase,.failed(error))
            flow.finish();XCTAssertEqual(done,1)
        }
    }
    func testStaleContinuationCannotPresent() async {
        let flow=ProgressionFlow();var continuation: CheckedContinuation<ProgressionFetchOutcome,Never>?
        let started=expectation(description:"started")
        flow.begin(context) { XCTFail("obsolete finish") }
        let work=Task { await flow.fetch { _ in await withCheckedContinuation { continuation=$0;started.fulfill() } } }
        await fulfillment(of:[started]);flow.contextChanged(to:.init(date:"2026-10-03",sessionType:"morning",sessionName:"B"))
        continuation?.resume(returning:.actionable([suggestion()]));await work.value
        XCTAssertNotEqual(flow.phase,.coaching)
    }
    func testFetchDecodeOutcomes() throws {
        let bytes=try JSONEncoder().encode(ProgressionSuggestionsResponse(suggestions:[suggestion()]))
        if case .actionable = ProgressionFetchOutcome.decode(bytes,status:200) {} else { XCTFail() }
        let maintain=try JSONEncoder().encode(ProgressionSuggestionsResponse(suggestions:[suggestion(type:"maintain")]))
        if case .maintainOnly = ProgressionFetchOutcome.decode(maintain,status:200) {} else { XCTFail() }
        if case .none = ProgressionFetchOutcome.decode(Data(#"{"suggestions":[]}"#.utf8),status:200) {} else { XCTFail() }
        if case .failed(.decoding) = ProgressionFetchOutcome.decode(Data(),status:200) {} else { XCTFail() }
        if case .failed(.http(404)) = ProgressionFetchOutcome.decode(bytes,status:404) {} else { XCTFail() }
    }
    func testApplyDecodeRejectsBusinessFalseInvalidAndMissingFields() {
        for json in ["invalid",#"{"success":false}"#,#"{"success":true}"#] {
            if case .failed = ProgressionApplyOutcome.response(Data(json.utf8)) {} else { XCTFail(json) }
        }
        if case .confirmed = ProgressionApplyOutcome.response(Data(#"{"success":true,"current_weight":105,"current_scheme":"4x12"}"#.utf8)) {} else { XCTFail() }
    }
    func testQueuedIsNotConfirmedAndBlocksDuplicate() async {
        let rows=ProgressionRows();let s=suggestion();var sends=0
        await rows.apply(s,context:context){ _ in sends += 1;return .queued }
        await rows.apply(s,context:context){ _ in sends += 1;return .queued }
        XCTAssertEqual(rows.state(s),.queued);XCTAssertEqual(sends,1);XCTAssertFalse(rows.canUndo(s))
    }
    func testDoubleTapAndTwoIndependentRows() async {
        let rows=ProgressionRows();let a=suggestion();let b=suggestion("B")
        var continuation: CheckedContinuation<ProgressionApplyOutcome,Never>?
        let started=expectation(description:"apply started");var sends=0
        let first=Task { await rows.apply(a,context:context){_ in sends += 1;return await withCheckedContinuation {continuation=$0;started.fulfill()} } }
        await fulfillment(of:[started]);await rows.apply(a,context:context){_ in XCTFail("duplicate");return .queued}
        await rows.apply(b,context:context){_ in sends += 1;return .queued}
        XCTAssertEqual(rows.state(a),.applying);XCTAssertEqual(rows.state(b),.queued)
        continuation?.resume(returning:.confirmed(.init(success:true,currentWeight:105,currentScheme:"4x12")));await first.value
        XCTAssertEqual(sends,2);XCTAssertEqual(rows.state(a),.confirmed)
    }
    func testConflictFailureAndNilSuggestion() async {
        let rows=ProgressionRows();let a=suggestion()
        await rows.apply(a,context:context){_ in .conflict};XCTAssertEqual(rows.state(a),.conflict)
        let b=suggestion("B");await rows.apply(b,context:context){_ in .failed("fixture")};XCTAssertEqual(rows.state(b),.failed("fixture"))
        let nilSuggestion=ProgressionSuggestion(exerciseName:"nil",loadProfile:nil,suggestionType:"regression",currentWeight:nil,suggestedWeight:nil,currentScheme:nil,suggestedScheme:nil,reason:"",fatigueWarning:false)
        await rows.apply(nilSuggestion,context:context){_ in XCTFail("no-op mutation");return .queued}
        XCTAssertEqual(rows.state(nilSuggestion),.idle)
    }
    func testIgnoreHasExactContextAndSuggestionIdentity() {
        let s=suggestion();let base=context.ignoreKey(for:s)
        for other in [ProgressionContext(date:"2026-10-03",sessionType:"evening",sessionName:"A"),.init(date:context.date,sessionType:"bonus",sessionName:"A"),.init(date:context.date,sessionType:"evening",sessionName:"B")] {XCTAssertNotEqual(base,other.ignoreKey(for:s))}
        XCTAssertNotEqual(base,context.ignoreKey(for:suggestion(type:"deload")))
        XCTAssertEqual(base,context.ignoreKey(for:s))
    }
    func testUndoRestoresBothWithCASAndFailureVisible() async {
        let rows=ProgressionRows();let s=suggestion()
        await rows.apply(s,context:context){_ in .confirmed(.init(success:true,currentWeight:105,currentScheme:"4x12"))}
        await rows.undo(s) { request in
            XCTAssertEqual(request.weight,100);XCTAssertEqual(request.scheme,"3x12")
            XCTAssertEqual(request.expectedWeight,105);XCTAssertEqual(request.expectedScheme,"4x12");XCTAssertTrue(request.restore)
            return .failed("restoration failed")
        }
        XCTAssertEqual(rows.state(s),.failed("restoration failed"))
    }
}
