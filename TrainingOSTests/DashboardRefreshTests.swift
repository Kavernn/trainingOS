import XCTest
import Combine
@testable import TrainingOS

@MainActor
final class DashboardRefreshTests: XCTestCase {
    private let date = DateFormatter.isoDate.date(from: "2026-09-27")!
    private var defaults: UserDefaults!
    private var suite: String!
    private var api: APIService!

    override func setUp() async throws {
        suite = "DashboardRefreshTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        api = APIService(dashboardDefaults: defaults)
        APILoadingState.shared.error = nil
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        APILoadingState.shared.isLoading = false
        APILoadingState.shared.isRefreshing = false
        APILoadingState.shared.error = nil
    }

    private func reply(_ request: URLRequest, program: String = "A", override: String = "Jeudi AM — Push B") throws -> (Data, URLResponse) {
        let payload: String
        switch request.url!.path {
        case "/api/programme_data":
            payload = """
            {"active_program_id":"\(program)","current_program_id":"\(program)",
             "schedule":{"Dim":"\(program) dimanche","Lun":"\(program) lundi"},
             "full_program":{"\(program) dimanche":{"Squat":"3x10"},"\(program) lundi":{},"\(program) soir":{}}}
            """
        case "/api/evening_schedule": payload = "{\"Dim\":\"\(program) soir\"}"
        default:
            payload = """
            {"today":"\(override)","today_date":"2026-09-27","week":1,
             "schedule":{},"sessions":{},"goals":{},"full_program":{},"nutrition_totals":{},"profile":{}}
            """
        }
        return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    private func seed() async {
        await api.fetchDashboard(mode: .initial, now: { self.date }, transport: { try self.reply($0) })
        XCTAssertNotNil(api.dashboard)
    }

    func testMetricsStartWhileEveningWaitsAndPlanPublishesBeforeMetrics() async {
        let eveningStarted = expectation(description: "evening started")
        let metricsStarted = expectation(description: "metrics started independently")
        let planReady = expectation(description: "validated plan published before metrics")
        var eveningGate: CheckedContinuation<Void, Never>?
        var metricsGate: CheckedContinuation<Void, Never>?
        var paths: [String] = []
        let subscription = api.$dashboardPlan.dropFirst().sink { plan in
            if plan != nil { planReady.fulfill() }
        }
        defer { subscription.cancel() }
        let task = Task {
            await self.api.fetchDashboard(now: { self.date }, transport: { request in
                paths.append(request.url!.path)
                if request.url!.path == "/api/evening_schedule" {
                    await withCheckedContinuation { eveningGate = $0; eveningStarted.fulfill() }
                }
                if request.url!.path == "/api/dashboard" {
                    await withCheckedContinuation { metricsGate = $0; metricsStarted.fulfill() }
                }
                return try self.reply(request)
            })
        }
        await fulfillment(of: [eveningStarted, metricsStarted], timeout: 5)
        XCTAssertNil(api.dashboard)
        XCTAssertFalse(api.dashboardPlanIsCurrent(on: date))
        eveningGate?.resume()
        await fulfillment(of: [planReady], timeout: 5)
        XCTAssertNil(api.dashboard, "Slow metrics must not prevent a certified plan")
        XCTAssertTrue(api.dashboardPlanIsCurrent(on: date))
        XCTAssertEqual(api.dashboardPlan?.morning(on: date), "A dimanche")
        metricsGate?.resume()
        let loaded = await task.value
        XCTAssertTrue(loaded)
        XCTAssertEqual(paths.count, 5)
        XCTAssertEqual(paths.filter { $0 == "/api/programme_data" }.count, 3)
        api.invalidateDashboardContext()
        XCTAssertFalse(api.dashboardPlanIsCurrent(on: date))
    }

    func testPersistedPlanIsNotCertifiedUntilRevalidated() async {
        await seed()
        let reopened = APIService(dashboardDefaults: defaults)
        XCTAssertNotNil(reopened.dashboardPlan)
        XCTAssertFalse(reopened.dashboardPlanIsCurrent(on: date))
        XCTAssertFalse(api.dashboardPlanIsCurrent(on: date.addingTimeInterval(86400)))
    }

    func testManualRefreshKeepsDashboardThroughoutRequests() async {
        await seed()
        await api.fetchDashboard(mode: .refresh, now: { self.date }, transport: {
            XCTAssertNotNil(self.api.dashboard)
            XCTAssertFalse(APILoadingState.shared.isLoading)
            XCTAssertTrue(APILoadingState.shared.isRefreshing)
            return try self.reply($0)
        })
        XCTAssertNotNil(api.dashboard)
        XCTAssertFalse(APILoadingState.shared.isLoading)
        XCTAssertFalse(APILoadingState.shared.isRefreshing)
    }

    func testBothCancellationTypesRetainSuccessWithoutError() async {
        await seed()
        for error in [CancellationError() as Error, URLError(.cancelled) as Error] {
            let loaded = await api.fetchDashboard(mode: .refresh, now: { self.date }, transport: { _ in throw error })
            XCTAssertFalse(loaded, "Cancelled API work must not start subsequent Dashboard loads")
            XCTAssertNotNil(api.dashboard)
            XCTAssertNil(APILoadingState.shared.error)
            XCTAssertFalse(APILoadingState.shared.isLoading)
            XCTAssertFalse(APILoadingState.shared.isRefreshing)
        }
    }

    func testNetworkFailureRetainsSuccessButInitialFailureReportsError() async {
        await api.fetchDashboard(mode: .initial, now: { self.date }, transport: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertNil(api.dashboard)
        XCTAssertNotNil(APILoadingState.shared.error)
        await seed()
        await api.fetchDashboard(mode: .refresh, now: { self.date }, transport: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertNotNil(api.dashboard)
        XCTAssertNil(APILoadingState.shared.error)
    }

    func testOverlappingCallIsSingleFlight() async {
        var nested = false
        await api.fetchDashboard(mode: .refresh, now: { self.date }, transport: { request in
            if !nested {
                nested = true
                await self.api.fetchDashboard(mode: .refresh, now: { self.date }, transport: { _ in
                    XCTFail("overlap must not start another request")
                    throw URLError(.unknown)
                })
            }
            return try self.reply(request)
        })
        XCTAssertNotNil(api.dashboard)
    }

    func testActivationInvalidatesOldResponseEvenAfterNewResponse() async {
        var switched = false
        await api.fetchDashboard(mode: .refresh, now: { self.date }, transport: { request in
            if request.url!.path == "/api/dashboard", !switched {
                switched = true
                self.api.invalidateDashboardContext()
                await self.api.fetchDashboard(mode: .refresh, now: { self.date }, transport: { try self.reply($0, program: "B", override: "new response") })
            }
            return try self.reply(request)
        })
        XCTAssertEqual(api.dashboard?.today, "new response")
        XCTAssertEqual(api.dashboardPlan?.programme.active_program_id, "B")
    }

    func testDateChangeDiscardsResponse() async {
        var current = date
        await api.fetchDashboard(mode: .refresh, now: { current }, transport: { request in
            if request.url!.path == "/api/dashboard" { current = self.date.addingTimeInterval(86400) }
            return try self.reply(request)
        })
        XCTAssertNil(api.dashboard)
        XCTAssertNil(APILoadingState.shared.error)
    }

    func testRemoteActiveChangeDiscardsResponseAndOldPlan() async {
        var loadedMetrics = false
        await api.fetchDashboard(mode: .refresh, now: { self.date }, transport: { request in
            if request.url!.path == "/api/dashboard" { loadedMetrics = true }
            return try self.reply(request, program: loadedMetrics ? "B" : "A")
        })
        XCTAssertNil(api.dashboard)
        XCTAssertNil(api.dashboardPlan)
    }

    func testSundayIdentityUsesStructureScheduleNotOverrideAndResolvesExplicitDate() async throws {
        await seed()
        let plan = try XCTUnwrap(api.dashboardPlan)
        let structure = ProgrammeViewModel()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan.programme)) as? [String: Any])
        structure.applyJSON(json)
        structure.eveningSchedule = plan.eveningSchedule
        let structureDay = TrainingDoctrine.dayNames[(Calendar.mtl.component(.weekday, from: date) + 5) % 7]
        XCTAssertEqual(plan.morning(on: date), structure.schedule[structureDay])
        XCTAssertEqual(plan.evening(on: date), structure.eveningSchedule[structureDay])
        XCTAssertNotEqual(plan.morning(on: date), api.dashboard?.today)
        XCTAssertEqual(plan.morning(on: date.addingTimeInterval(86400)), plan.programme.schedule["Lun"])
    }

    func testSelectedInactivePayloadCannotReplaceActivePlan() async {
        await seed()
        await api.fetchDashboard(mode: .refresh, now: { self.date }, transport: { request in
            var (data, response) = try self.reply(request)
            if request.url!.path == "/api/programme_data" {
                data = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"current_program_id\":\"A\"", with: "\"current_program_id\":\"B\"").utf8)
            }
            return (data, response)
        })
        XCTAssertEqual(api.dashboardPlan?.programme.active_program_id, "A")
    }

    func testOfflineRelaunchRestoresWeeklyPlanWithoutUnscopedMetrics() async {
        await seed()
        let reopened = APIService(dashboardDefaults: defaults)
        await reopened.fetchDashboard(mode: .initial, now: { self.date }, transport: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertEqual(reopened.dashboardPlan?.morning(on: date), api.dashboardPlan?.morning(on: date))
        XCTAssertNil(reopened.dashboard)
    }

    func testInitialMetricsFailureStillLeavesScopedPlan() async {
        await api.fetchDashboard(mode: .initial, now: { self.date }, transport: { request in
            if request.url!.path == "/api/dashboard" { throw URLError(.notConnectedToInternet) }
            return try self.reply(request)
        })
        XCTAssertNil(api.dashboard)
        XCTAssertEqual(api.dashboardPlan?.morning(on: date), "A dimanche")
    }

    func testInitialAndEmptyRefreshHaveExplicitActivityStates() async {
        for mode in [DashboardLoadMode.initial, .refresh] {
            await api.fetchDashboard(mode: mode, now: { self.date }, transport: { _ in
                XCTAssertTrue(APILoadingState.shared.isLoading)
                XCTAssertEqual(APILoadingState.shared.isRefreshing, mode == .refresh)
                throw URLError(.notConnectedToInternet)
            })
            XCTAssertNil(api.dashboard)
            XCTAssertFalse(APILoadingState.shared.isLoading)
            XCTAssertFalse(APILoadingState.shared.isRefreshing)
            XCTAssertNotNil(APILoadingState.shared.error)
        }
    }

    func testRepeatedExplicitRefreshKeepsSameScopedPlan() async {
        await seed()
        for _ in 0..<3 {
            await api.fetchDashboard(mode: .refresh, now: { self.date }, transport: {
                XCTAssertNotNil(self.api.dashboard)
                return try self.reply($0)
            })
            XCTAssertEqual(api.dashboardPlan?.morning(on: date), "A dimanche")
            XCTAssertFalse(APILoadingState.shared.isRefreshing)
        }
    }

    func testCancellationAfterMetricsReadDoesNotPublish() async {
        await seed()
        let entered = expectation(description: "metrics request in flight")
        let task = Task {
            await self.api.fetchDashboard(mode: .refresh, now: { self.date }, transport: { request in
                if request.url!.path == "/api/dashboard" {
                    entered.fulfill()
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                }
                return try self.reply(request)
            })
        }
        await fulfillment(of: [entered], timeout: 5)
        task.cancel()
        await task.value
        XCTAssertNotNil(api.dashboard)
        XCTAssertNil(APILoadingState.shared.error)
    }
}
