import XCTest
@testable import TrainingOS

@MainActor
final class SeanceCurrentPlanningTests: XCTestCase {
    private let date = DateFormatter.isoDate.date(from: "2088-09-26")!
    private func data(_ name: String, date: Date) -> SeanceData {
        SeanceData(today: name, todayDate: DateFormatter.isoDate.string(from: date), alreadyLogged: false,
                   schedule: [TrainingDoctrine.dayName(on: date): name], fullProgram: [name: [:]],
                   weights: [:], week: 1, inventoryTypes: [:], exerciseOrder: [:])
    }
    private func owner() -> SeanceViewModel {
        let vm = SeanceViewModel(draftSessionType: "morning", followsActivePlanning: true)
        vm.planningNow = { self.date }
        return vm
    }
    override func tearDown() async throws {
        for offset in [0.0, 86400.0] {
            let day = DateFormatter.isoDate.string(from: date.addingTimeInterval(offset))
            SessionDraftStore.clear(date: day, sessionType: "morning")
            for key in UserDefaults.standard.dictionaryRepresentation().keys
                where key.hasPrefix("\(ExerciseDraftPersistence.keyPrefix)\(day)_morning_") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    func testPassiveCardInitializationDoesNotFreezePlanning() async {
        let vm = owner()
        vm.currentPlanningLoader = { date, _ in ("active", self.data("A", date: date)) }
        await vm.load()
        let card = ExerciseViewModel(name: "Passive test", scheme: "3x10", weightData: nil,
                                     sessionDate: DateFormatter.isoDate.string(from: date))
        card.initializeSets()
        XCTAssertFalse(vm.preservesCurrentExecution, "Displaying blank sets is not starting a workout")
        vm.currentPlanningLoader = { date, _ in ("active", self.data("B", date: date)) }
        await vm.reloadCurrentPlanning(now: date)
        XCTAssertEqual(vm.seanceData?.today, "B")
    }
    func testRealCardDraftKeepsIdentityUntilExplicitClear() async {
        let vm = owner()
        vm.currentPlanningLoader = { date, _ in ("active", self.data("A", date: date)) }
        await vm.load()
        let identity = vm.contentIdentity
        let store = ExerciseDraftPersistence(date: DateFormatter.isoDate.string(from: date),
                                             sessionType: "morning", exerciseName: "Real test")
        XCTAssertTrue(store.save([DraftSet(weight: "80", reps: "", rir: 3, duration: 30)]))
        vm.currentPlanningLoader = { date, _ in ("active", self.data("B", date: date)) }
        await vm.reloadCurrentPlanning(now: date)
        XCTAssertEqual(vm.contentIdentity, identity)
        XCTAssertEqual(store.loadCard()?.sets.first?.weight, "80")
        XCTAssertEqual(store.clear(), .accepted)
        await vm.reloadCurrentPlanning(now: date)
        XCTAssertEqual(vm.seanceData?.today, "B")
        XCTAssertNotEqual(vm.contentIdentity, identity)
    }
    func testEveryNonDefaultDraftFieldAndUnreadableRecoveryProtectExecution() async {
        let vm = owner()
        vm.currentPlanningLoader = { date, _ in ("active", self.data("A", date: date)) }
        await vm.load()
        let day = DateFormatter.isoDate.string(from: date)
        let store = ExerciseDraftPersistence(date: day, sessionType: "morning", exerciseName: "Fields test")
        let blank = DraftSet(weight: "", reps: "", rir: 3, duration: 30)
        let edits: [(inout DraftSet) -> Void] = [
            { $0.weight = "0" }, { $0.reps = "1" }, { $0.rir = 2 },
            { $0.duration = 31 }, { $0.rpe = 5 }, { $0.distance = "1" },
            { $0.intensity = "1" }, { $0.durationLeft = 30 },
            { $0.durationRight = 30 }, { $0.protocolCompleted = true }
        ]
        for edit in edits {
            var set = blank
            edit(&set)
            XCTAssertTrue(store.save([set]))
            XCTAssertTrue(vm.preservesCurrentExecution)
        }
        XCTAssertTrue(store.save([blank], sessionNote: "Note"))
        XCTAssertTrue(vm.preservesCurrentExecution)
        UserDefaults.standard.set(Data([0xff]), forKey: "\(ExerciseDraftPersistence.keyPrefix)\(day)_morning_Fields test")
        XCTAssertTrue(vm.preservesCurrentExecution)
    }
    func testRenderIdentityStableOnRefreshAndChangesWithEveryContextDimension() async {
        let vm = owner()
        vm.currentPlanningLoader = { date, _ in ("active", self.data("A", date: date)) }
        await vm.load()
        let a = vm.contentIdentity!
        await vm.reloadCurrentPlanning(now: date)
        XCTAssertEqual(vm.contentIdentity, a)
        typealias Identity = SeanceViewModel.ContentIdentity
        XCTAssertNotEqual(a, Identity(program: "other", date: a.date, source: a.source, session: a.session))
        XCTAssertNotEqual(a, Identity(program: a.program, date: "2088-09-27", source: a.source, session: a.session))
        XCTAssertNotEqual(a, Identity(program: a.program, date: a.date, source: "evening", session: a.session))
        XCTAssertNotEqual(a, Identity(program: a.program, date: a.date, source: a.source, session: "B"))
        // Inactive selection has no planning notification; a rejected/stale load
        // also cannot change the identity of the rendered subtree.
        vm.currentPlanningLoader = { _, _ in throw URLError(.cancelled) }
        await vm.reloadCurrentPlanning(now: date)
        XCTAssertEqual(vm.contentIdentity, a)
    }
    func testStructureNotificationReplacesIdleAWithBWithoutTabReset() async {
        let vm = owner()
        var name = "A"
        let updated = expectation(description: "planning event loaded B")
        vm.currentPlanningLoader = { date, _ in
            if name == "B" { updated.fulfill() }
            return ("active", self.data(name, date: date))
        }
        await vm.load()
        XCTAssertEqual(vm.seanceData?.today, "A")
        name = "B"
        NotificationCenter.default.post(name: .activeProgrammePlanningDidChange, object: nil)
        await fulfillment(of: [updated], timeout: 5)
        XCTAssertEqual(vm.seanceData?.today, "B")
    }
    func testStartedExecutionSurvivesScheduleChange() async {
        let vm = owner()
        vm.currentPlanningLoader = { date, _ in ("active", self.data("A", date: date)) }
        await vm.load()
        vm.startSession()
        vm.currentPlanningLoader = { _, _ in XCTFail("active execution must not reload"); throw URLError(.unknown) }
        await vm.reloadCurrentPlanning(now: date)
        XCTAssertEqual(vm.seanceData?.today, "A")
        XCTAssertTrue(vm.sessionStarted)
    }
    func testStartDuringRequestPreventsReplacement() async {
        let vm = owner()
        vm.currentPlanningLoader = { date, _ in ("active", self.data("A", date: date)) }
        await vm.load()
        vm.currentPlanningLoader = { [weak vm] date, _ in
            vm?.startSession()
            return ("active", self.data("B", date: date))
        }
        await vm.load()
        XCTAssertEqual(vm.seanceData?.today, "A")
    }
    func testActiveProgramAndDateChangeReplaceIdleContext() async {
        let vm = owner()
        vm.currentPlanningLoader = { date, _ in ("A", self.data("First", date: date)) }
        await vm.load()
        vm.currentPlanningLoader = { date, _ in ("B", self.data("Second", date: date)) }
        let tomorrow = date.addingTimeInterval(86400)
        await vm.reloadCurrentPlanning(now: tomorrow)
        XCTAssertEqual(vm.plannedProgramID, "B")
        XCTAssertEqual(vm.seanceData?.today, "Second")
        XCTAssertEqual(vm.seanceData?.todayDate, DateFormatter.isoDate.string(from: tomorrow))
    }
    func testUnsavedCommentPreservesExecution() async {
        let vm = owner()
        vm.currentPlanningLoader = { date, _ in ("A", self.data("First", date: date)) }
        await vm.load()
        vm.sessionComment = "Keep recovery"
        vm.currentPlanningLoader = { _, _ in XCTFail("comment must be preserved"); throw URLError(.unknown) }
        await vm.reloadCurrentPlanning(now: date)
        XCTAssertEqual(vm.sessionComment, "Keep recovery")
        XCTAssertEqual(vm.seanceData?.today, "First")
    }
    func testDateRolloverWithinSameProgramme() async {
        let vm = owner()
        vm.currentPlanningLoader = { date, _ in
            ("active", self.data(TrainingDoctrine.dayName(on: date), date: date))
        }
        await vm.load()
        let tomorrow = date.addingTimeInterval(86400)
        await vm.reloadCurrentPlanning(now: tomorrow)
        XCTAssertEqual(vm.plannedProgramID, "active")
        XCTAssertEqual(vm.seanceData?.today, TrainingDoctrine.dayName(on: tomorrow))
    }
    func testActiveProgrammeSwitchWithinSameDate() async {
        let vm = owner()
        vm.currentPlanningLoader = { date, _ in ("A", self.data("First", date: date)) }
        await vm.load()
        vm.currentPlanningLoader = { date, _ in ("B", self.data("Second", date: date)) }
        await vm.load()
        XCTAssertEqual(vm.plannedProgramID, "B")
        XCTAssertEqual(vm.seanceData?.today, "Second")
    }
    func testColdRecoveryKeepsExecutionOverrideWithoutExplicitSessionSelector() async throws {
        let result = try await APIService.shared.fetchCurrentPlannedSeance(date: date, preserveRecovery: true) { request in
            let bytes: Data
            if request.url!.path == "/api/programme_data" {
                bytes = try JSONEncoder().encode(DashboardPlan.Programme(active_program_id: "A", current_program_id: "A",
                    schedule: [TrainingDoctrine.dayName(on: self.date): "New plan"], full_program: ["New plan": [:]]))
            } else {
                XCTAssertFalse(request.url!.absoluteString.contains("session_name="))
                bytes = try JSONEncoder().encode(self.data("Execution A", date: self.date))
            }
            return (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertEqual(result.data.today, "Execution A")
    }
    func testRealLoaderMatchesStructureAndDashboardIgnoringOldOverride() async throws {
        let day = TrainingDoctrine.dayName(on: date)
        let programme = DashboardPlan.Programme(active_program_id: "active", current_program_id: "active",
            schedule: [day: "Planned"], full_program: ["Planned": [:]])
        let structure = ProgrammeViewModel()
        structure.applyJSON(try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(programme)) as? [String: Any]))
        let api = APIService()
        let result = try await api.fetchCurrentPlannedSeance(date: date, preserveRecovery: false) { request in
            let bytes: Data
            if request.url!.path == "/api/programme_data" {
                bytes = try JSONEncoder().encode(programme)
            } else {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertEqual(query.first { $0.name == "program_id" }?.value, "active")
                XCTAssertEqual(query.first { $0.name == "date" }?.value, DateFormatter.isoDate.string(from: self.date))
                bytes = try JSONEncoder().encode(self.data(query.first { $0.name == "session_name" }?.value ?? "Jeudi AM — Push B", date: self.date))
            }
            return (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertEqual(result.data.today, structure.schedule[day])
        XCTAssertEqual(result.data.today, DashboardPlan(programme: programme, eveningSchedule: [:]).morning(on: date))
    }
    func testInactiveSelectedPayloadIsRejected() async {
        do {
            _ = try await APIService.shared.fetchCurrentPlannedSeance(date: date, preserveRecovery: false) { request in
                let p = DashboardPlan.Programme(active_program_id: "A", current_program_id: "B", schedule: [:], full_program: [:])
                return (try JSONEncoder().encode(p), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            XCTFail("selected inactive content must not be admitted")
        } catch { XCTAssertEqual((error as? URLError)?.code, .cancelled) }
    }

    func testDatedOverrideCannotRelabelAExercisesAsPlannedB() async throws {
        let vm = owner()
        let api = APIService()
        let a = ["A1": SafeString("3x10"), "A2": SafeString("3x10")]
        let b = ["B1": SafeString("3x10"), "B2": SafeString("3x10"), "B3": SafeString("3x10")]
        var planned = "A"
        let published = expectation(description: "Structure notification resolves B")
        vm.currentPlanningLoader = { date, recovery in
            let result = try await api.fetchCurrentPlannedSeance(date: date, preserveRecovery: recovery) { request in
                XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
                let bytes: Data
                if request.url!.path == "/api/programme_data" {
                    bytes = try JSONEncoder().encode(DashboardPlan.Programme(
                        active_program_id: "active", current_program_id: "active",
                        schedule: [TrainingDoctrine.dayName(on: date): planned],
                        full_program: ["A": a, "B": b]))
                } else {
                    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                    XCTAssertEqual(query.first { $0.name == "program_id" }?.value, "active")
                    XCTAssertEqual(query.first { $0.name == "date" }?.value, DateFormatter.isoDate.string(from: date))
                    let title = query.first { $0.name == "session_name" }?.value ?? "A"
                    if title == "B" {
                        // Shared contract: pytest verifies these fields against
                        // the real Flask route with the dated override still A.
                        let fixture = URL(fileURLWithPath: #filePath)
                            .deletingLastPathComponent().deletingLastPathComponent()
                            .appendingPathComponent("tests/fixtures/seance_explicit_selection.json")
                        bytes = try Data(contentsOf: fixture)
                    } else {
                    let program = ["A": a, "B": b]
                    bytes = try JSONEncoder().encode(SeanceData(
                        today: title, todayDate: DateFormatter.isoDate.string(from: date), alreadyLogged: false,
                        schedule: [TrainingDoctrine.dayName(on: date): planned], fullProgram: program,
                        weights: [:], week: 1, inventoryTypes: [:],
                        exerciseOrder: program.mapValues { $0.keys.sorted() }))
                    }
                }
                return (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            if planned == "B" { published.fulfill() }
            return result
        }
        await vm.load()
        XCTAssertEqual(vm.seanceData?.today, "A")
        XCTAssertEqual(vm.seanceData?.exerciseOrder["A"], ["A1", "A2"])
        planned = "B"
        NotificationCenter.default.post(name: .activeProgrammePlanningDidChange, object: nil)
        await fulfillment(of: [published], timeout: 5)
        let result = try XCTUnwrap(vm.seanceData)
        XCTAssertEqual(result.today, "B")
        XCTAssertEqual(vm.contentIdentity?.session, "B")
        XCTAssertEqual(result.fullProgram[result.today]?.keys.sorted(), ["B1", "B2", "B3"])
        XCTAssertEqual(result.exerciseOrder[result.today], ["B1", "B2", "B3"])
    }
}
