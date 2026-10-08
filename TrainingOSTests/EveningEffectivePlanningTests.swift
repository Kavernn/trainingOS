import XCTest
import Combine
@testable import TrainingOS

@MainActor
final class EveningEffectivePlanningTests: XCTestCase {
    private let original = ["Cable Lateral Raise", "Dumbbell Lateral Raise", "Rear Delt Cable Fly",
                            "Barbell Upright Row", "Triceps Pushdown", "Single-Arm Triceps Extension",
                            "Neck Extension", "Neck Curl"]
    private let warmups = ["Wall Slides", "Thoracic Extension"]
    private let moved: Set<String> = ["Dumbbell Lateral Raise", "Neck Extension", "Neck Curl"]

    private func data(session: String, names: [String], logged: [String] = []) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:
            Fixtures.seanceDataJSON(today: session, todayDate: "2098-10-08")) as? [String: Any])
        json["full_program"] = [session: Dictionary(uniqueKeysWithValues: names.map { ($0, "3x10") })]
        json["exercise_order"] = [session: names]
        json["logged_today_names"] = logged
        return try JSONSerialization.data(withJSONObject: json)
    }

    private final class Owner: SeanceSoirViewModel {
        var fetch: ((String) async throws -> SeanceData)!
        override func fetchNamedSession(_ name: String) async throws -> SeanceData { try await fetch(name) }
    }

    /// Captures the first model mounted by WorkoutSeanceView, whose editable plan
    /// is seeded once on appearance. A later network value cannot repair that seed.
    func testPushBDoesNotMountMorningCacheBeforeEffectiveEveningArrives() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CacheService(directory: directory)
        cache.save(try data(session: "AM", names: warmups + Array(moved), logged: Array(moved)), for: "seance_data")
        let expected = original.filter { !moved.contains($0) }
        let fresh = try APIService.decoder.decode(SeanceData.self, from: data(session: "PM", names: expected))
        let vm = Owner(sessionName: "PM")
        vm.cacheService = cache
        var firstMounted: SeanceData?
        let subscription = vm.$seanceData.compactMap { $0 }.sink { if firstMounted == nil { firstMounted = $0 } }
        defer { subscription.cancel() }
        vm.fetch = { name in
            XCTAssertEqual(name, "PM")
            XCTAssertNil(vm.seanceData, "AM cache must never become the PM active model")
            await Task.yield()
            return fresh
        }
        await vm.load()
        let mounted = try XCTUnwrap(firstMounted)
        let visible = (mounted.exerciseOrder[mounted.today] ?? []).filter { !mounted.loggedTodayNames.contains($0) }
        XCTAssertEqual(visible, expected)
        XCTAssertEqual(vm.draftSessionType, "evening")
    }

    func testFailedNamedPMReadNeverFallsBackToMorning() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vm = Owner(sessionName: "PM")
        vm.cacheService = CacheService(directory: directory)
        vm.cacheService.save(try data(session: "AM", names: warmups), for: "seance_data")
        vm.fetch = { _ in throw URLError(.notConnectedToInternet) }
        await vm.load()
        XCTAssertNil(vm.seanceData)
        XCTAssertNotNil(vm.error)
    }
    func testProgrammeTodayUsesSameNamedEffectivePlanAsStartWithoutMutatingTemplate() async throws {
        let date = try XCTUnwrap(DateFormatter.isoDate.date(from: "2098-10-08"))
        let day = TrainingDoctrine.dayName(on: date)
        let expected = original.filter { !moved.contains($0) }
        let evening = try data(session: "PM", names: expected)
        let morning = try data(session: "AM", names: warmups + original.filter { moved.contains($0) })
        let raw: [String: Any] = ["active_program_id": "isolated-r131", "current_program_id": "isolated-r131",
            "full_program": ["AM": ["Press": "3x10"], "PM": Dictionary(uniqueKeysWithValues: original.map { ($0, "3x10") })],
            "schedule": [day: "AM"], "exercise_order": ["PM": original]]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vm = ProgrammeViewModel(transport: { request in
            let url = try XCTUnwrap(request.url)
            let bytes: Data
            switch url.path {
            case "/api/programme_data": bytes = try JSONSerialization.data(withJSONObject: raw)
            case "/api/evening_schedule": bytes = try JSONSerialization.data(withJSONObject: [day: "PM"])
            case "/api/seance_data":
                let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "session_name" }?.value
                bytes = name == "PM" ? evening : morning
            default: throw URLError(.unsupportedURL)
            }
            return (bytes, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, cache: CacheService(directory: directory), now: { date })
        await vm.loadData()
        let plan = try XCTUnwrap(vm.todayPlan(session: "PM", source: .evening))
        let owner = Owner(sessionName: "PM")
        owner.fetch = { _ in try APIService.decoder.decode(SeanceData.self, from: evening) }
        await owner.load()
        XCTAssertEqual(plan.exerciseOrder["PM"], expected)
        XCTAssertEqual(plan.exerciseOrder["PM"], owner.seanceData?.exerciseOrder["PM"])
        XCTAssertEqual(vm.fullProgram["PM"]?.count, 8, "Structural editor must retain the original programme")
        XCTAssertNil(vm.todayPlan(session: "PM", source: .morning))
    }

}
