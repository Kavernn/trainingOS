import XCTest
import Combine
@testable import TrainingOS

@MainActor
final class ProgrammeRefreshTests: XCTestCase {
    @MainActor private final class Fixture {
        var date = DateFormatter.isoDate.date(from: "2026-09-27")!
        var active = "active"
        var rawMorning = "NEW B"
        var beforeResponse: (() -> Void)?
        var cancel = false
        var requests: [URLRequest] = []
        var day: String { TrainingDoctrine.dayName(on: date) }
        var programme: [String: Any] {
            ["active_program_id": active, "current_program_id": active,
             "full_program": ["NEW B": ["Squat": "3x8"], "OLD A": ["Bench": "3x8"], "PM": ["Row": "3x8"]],
             "schedule": [day: "NEW B"], "exercise_order": [:]]
        }
        func transport(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            beforeResponse?()
            if cancel { throw CancellationError() }
            let url = try XCTUnwrap(request.url)
            let json: [String: Any]
            switch url.path {
            case "/api/programme_data": json = programme
            case "/api/evening_schedule": json = [day: "PM"]
            case "/api/seance_data":
                let explicit = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first { $0.name == "session_name" }?.value
                json = ["today": explicit ?? rawMorning, "today_date": DateFormatter.isoDate.string(from: date),
                        "weights": [:], "week": 1, "already_logged": false,
                        "full_program": programme["full_program"]!, "schedule": programme["schedule"]!,
                        "exercise_order": [:]]
            case "/api/seance_soir_data":
                json = ["today": "PM", "today_date": DateFormatter.isoDate.string(from: date),
                        "weights": [:], "week": 1, "already_logged": false, "has_evening_session": true,
                        "full_program": programme["full_program"]!, "schedule": [day: "PM"], "exercise_order": [:]]
            case "/api/dashboard":
                json = ["today_date": DateFormatter.isoDate.string(from: date), "second_session_completed": false]
            default: throw URLError(.unsupportedURL)
            }
            return (try JSONSerialization.data(withJSONObject: json),
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testPullToRefreshNeverPublishesOldExecutionOverrideAsPlanning() async throws {
        let fixture = Fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CacheService(directory: directory)
        let vm = ProgrammeViewModel(transport: fixture.transport, cache: cache, now: { fixture.date })
        await vm.loadData()
        XCTAssertEqual(vm.plannedMorning(on: fixture.date), "NEW B")
        fixture.rawMorning = "OLD A"
        var observed: [String?] = []
        fixture.beforeResponse = { observed.append(vm.plannedMorning(on: fixture.date)) }
        let subscription = vm.objectWillChange.sink { observed.append(vm.plannedMorning(on: fixture.date)) }
        defer { subscription.cancel() }
        await vm.refreshActiveProgramme() // Exact production pull-to-refresh path.
        observed.append(vm.plannedMorning(on: fixture.date))
        XCTAssertEqual(vm.plannedMorning(on: fixture.date), "NEW B")
        XCTAssertFalse(observed.contains("OLD A"))
        XCTAssertEqual(vm.schedule[fixture.day], "NEW B")
        let composer = try await DayComposerLoader.loadBundle(program: fixture.active, now: { fixture.date },
            transport: fixture.transport, hasRecovery: { _ in false })
        XCTAssertEqual(composer.snapshot.morning.session, "NEW B")
        XCTAssertTrue(composer.snapshot.isRelevant(hasSavedOrder: false))
    }

    func testRefreshPreservesMountedContentAndRejectsCancelledOrWrongDateResponses() async throws {
        let fixture = Fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vm = ProgrammeViewModel(transport: fixture.transport, cache: CacheService(directory: directory),
                                    now: { fixture.date })
        await vm.loadData()
        var loadingDuringRefresh: [Bool] = []
        fixture.beforeResponse = { loadingDuringRefresh.append(vm.isLoading) }
        fixture.cancel = true
        await vm.refreshActiveProgramme()
        XCTAssertEqual(vm.plannedMorning(on: fixture.date), "NEW B")
        XCTAssertFalse(loadingDuringRefresh.contains(true), "Refresh must not dismantle the ScrollView")
        fixture.cancel = false
        fixture.active = "different-active"
        fixture.beforeResponse = {
            fixture.beforeResponse = nil
            fixture.date = fixture.date.addingTimeInterval(86400)
        }
        await vm.refreshActiveProgramme()
        XCTAssertEqual(vm.activeProgramId, "active", "A response crossing midnight must not publish")
        XCTAssertFalse(vm.isLoading)
    }

    func testRefreshResolvesBackendActiveNotInactiveStructureSelectionOrOldCache() async throws {
        let fixture = Fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CacheService(directory: directory)
        let vm = ProgrammeViewModel(transport: fixture.transport, cache: cache, now: { fixture.date })
        await vm.loadData()
        vm.userDidSelect = true
        vm.selectedProgramId = "structure-only"
        var stale = fixture.programme
        stale["schedule"] = [fixture.day: "OLD A"]
        cache.save(try JSONSerialization.data(withJSONObject: stale), for: "programme_data")
        fixture.active = "new-active"
        fixture.rawMorning = "OLD A"
        var observed: [String?] = []
        fixture.beforeResponse = { observed.append(vm.plannedMorning(on: fixture.date)) }
        await vm.refreshActiveProgramme()
        observed.append(vm.plannedMorning(on: fixture.date))
        XCTAssertEqual(vm.activeProgramId, "new-active")
        XCTAssertEqual(vm.loadedProgramId, "new-active")
        XCTAssertEqual(vm.selectedProgramId, "structure-only")
        XCTAssertEqual(vm.plannedMorning(on: fixture.date), "NEW B")
        XCTAssertFalse(observed.contains("OLD A"))
        XCTAssertTrue(fixture.requests.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
        XCTAssertTrue(fixture.requests.filter { $0.url?.path == "/api/programme_data" }
            .allSatisfy { $0.url?.query == nil })
    }

    func testLateRefreshCannotOverwriteNewActiveContext() async throws {
        let fixture = Fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let held = expectation(description: "Old programme response held")
        var continuation: CheckedContinuation<Void, Never>?
        var holdNext = false
        let vm = ProgrammeViewModel(transport: { request in
            let response = try await fixture.transport(request)
            if holdNext, request.url?.path == "/api/programme_data" {
                holdNext = false
                await withCheckedContinuation { continuation = $0; held.fulfill() }
            }
            return response
        }, cache: CacheService(directory: directory), now: { fixture.date })
        await vm.loadData()
        holdNext = true
        let old = Task { await vm.refreshActiveProgramme() }
        await fulfillment(of: [held], timeout: 2)
        fixture.active = "new-active"
        await vm.refreshActiveProgramme(invalidate: true)
        let revision = vm.planningRevision
        let replacement = vm.dayComposerCandidate
        continuation?.resume()
        await old.value
        XCTAssertEqual(vm.activeProgramId, "new-active")
        XCTAssertEqual(vm.loadedProgramId, "new-active")
        XCTAssertEqual(vm.planningRevision, revision)
        XCTAssertTrue(vm.dayComposerCandidate === replacement)
        XCTAssertEqual(vm.plannedMorning(on: fixture.date), "NEW B")
    }

    func testPendingRefreshKeepsWholePlanningAndEntryAndDeduplicatesCallers() async throws {
        let f = Fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let held = expectation(description: "Evening replacement held")
        var gate: CheckedContinuation<Void, Never>?
        var hold = false
        let vm = ProgrammeViewModel(transport: { request in
            let result = try await f.transport(request)
            if hold, request.url?.path == "/api/evening_schedule" {
                hold = false
                await withCheckedContinuation { gate = $0; held.fulfill() }
            }
            return result
        }, cache: CacheService(directory: directory), now: { f.date })
        await vm.loadData()
        let candidate = try XCTUnwrap(vm.dayComposerCandidate)
        let revision = vm.planningRevision
        hold = true
        let refresh = Task { await vm.refreshActiveProgramme() }
        await fulfillment(of: [held], timeout: 2)
        XCTAssertEqual(vm.plannedMorning(on: f.date), "NEW B")
        XCTAssertEqual(vm.eveningSchedule[f.day], "PM")
        XCTAssertTrue(vm.dayComposerCandidate === candidate)
        XCTAssertTrue(candidate.canPresent(on: candidate.preview.date))
        XCTAssertEqual(vm.planningRevision, revision, "No partial publication before PM is ready")
        XCTAssertFalse(vm.isLoading)
        let count = f.requests.count
        let duplicateEntered = expectation(description: "Duplicate caller entered")
        let duplicate = Task { duplicateEntered.fulfill(); await vm.refreshActiveProgramme() }
        await fulfillment(of: [duplicateEntered], timeout: 2)
        XCTAssertEqual(f.requests.count, count)
        gate?.resume()
        await refresh.value
        await duplicate.value
        XCTAssertTrue(vm.dayComposerCandidate === candidate)
        XCTAssertEqual(vm.planningRevision, revision + 1)
    }

    func testCancelledRefreshRetainsEligibleCandidate() async throws {
        let f = Fixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let held = expectation(description: "Response held")
        var gate: CheckedContinuation<Void, Never>?
        var hold = false
        let vm = ProgrammeViewModel(transport: { request in
            let result = try await f.transport(request)
            if hold, request.url?.path == "/api/programme_data" {
                hold = false
                await withCheckedContinuation { gate = $0; held.fulfill() }
            }
            return result
        }, cache: CacheService(directory: directory), now: { f.date })
        await vm.loadData()
        let candidate = try XCTUnwrap(vm.dayComposerCandidate)
        let revision = vm.planningRevision
        hold = true
        let refresh = Task { await vm.refreshActiveProgramme() }
        await fulfillment(of: [held], timeout: 2)
        refresh.cancel()
        gate?.resume()
        await refresh.value
        XCTAssertEqual(vm.planningRevision, revision)
        XCTAssertTrue(vm.dayComposerCandidate === candidate)
        XCTAssertTrue(candidate.canPresent(on: candidate.preview.date))
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.lastSaveError)
    }

    func testCandidateAndPreparationExistBeforeWeightsAndReuseSuccessfulRead() async throws {
        let f = Fixture()
        f.date = Date()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let held = expectation(description: "Weights held")
        var gate: CheckedContinuation<Void, Never>?
        var hold = true
        let vm = ProgrammeViewModel(transport: { request in
            let result = try await f.transport(request)
            if hold, request.url?.path == "/api/seance_data" {
                hold = false
                await withCheckedContinuation { gate = $0; held.fulfill() }
            }
            return result
        }, cache: CacheService(directory: directory), now: { f.date })
        let load = Task { await vm.loadData() }
        await fulfillment(of: [held], timeout: 2)
        let candidate = try XCTUnwrap(vm.dayComposerCandidate)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(candidate.canPresent(on: candidate.preview.date))
        let count = f.requests.count
        let initial = candidate.initialPresentation()
        _ = DayComposerView(candidate: candidate)
        XCTAssertEqual(initial.units.flatMap(\.items).map(\.name), ["Squat", "Row"])
        XCTAssertEqual(f.requests.count, count, "Opening has no planning fetch dependency")
        gate?.resume()
        await load.value
        _ = try await candidate.resolve()
        _ = try await candidate.resolve()
        XCTAssertEqual(f.requests.filter { $0.url?.path == "/api/seance_data" }.count, 1)
        XCTAssertEqual(f.requests.filter { $0.url?.path == "/api/evening_schedule" }.count, 1)
        XCTAssertEqual(f.requests.filter { $0.url?.path == "/api/programme_data" }.count, 2,
                       "One initial read and one final context validation, no duplicated initial reads")
        XCTAssertEqual(candidate.initialPresentation().units.flatMap(\.items).map(\.name), ["Squat", "Row"])
    }
}
