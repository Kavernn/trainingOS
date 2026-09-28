import XCTest
import SwiftUI
@testable import TrainingOS

@MainActor
final class DashboardPresentationLoadingTests: XCTestCase {
    private let date = DateFormatter.isoDate.date(from: "2026-09-28")!

    func testAppearanceBannerRendersWithoutNetworkDataOrPreferenceMutation() throws {
        let suite = "DashboardBanner.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = APIService(dashboardDefaults: defaults)
        let preference = HeroMoodPreference.currentRawValue
        XCTAssertNil(api.dashboard)
        XCTAssertNil(api.dashboardPlan)
        let renderer = ImageRenderer(content: DashboardView(api: api).pageContent.frame(width: 370))
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertGreaterThan(image.size.height, 0)
        XCTAssertEqual(HeroMoodPreference.currentRawValue, preference)
        XCTAssertNil(api.dashboard)
    }

    func testPrimaryPresentationDoesNotAttributeRecoveryToNewPlan() {
        let resumed = DashboardPrimaryPresentation(plannedSession: "Programme B", hasMorningRecovery: true, completed: false)
        XCTAssertEqual(resumed.title, "Séance à reprendre")
        XCTAssertEqual(resumed.action, "Reprendre ma séance")
        let planned = DashboardPrimaryPresentation(plannedSession: "Programme B", hasMorningRecovery: false, completed: false)
        XCTAssertEqual(planned.title, "Programme B")
        XCTAssertEqual(planned.action, "Ouvrir ma séance")
        XCTAssertNil(DashboardPrimaryPresentation(plannedSession: "Repos", hasMorningRecovery: false, completed: false).action)
        XCTAssertEqual(DashboardPrimaryPresentation(plannedSession: "Repos", hasMorningRecovery: true, completed: false).action, "Reprendre ma séance")
        XCTAssertNil(DashboardPrimaryPresentation(plannedSession: "Programme B", hasMorningRecovery: false, completed: true).action)
    }

    func testWarmReturnRequiresSameDayGenerationAndFreshness() {
        XCTAssertTrue(DashboardViewModel.canReuse(lastLoad: date, now: date.addingTimeInterval(20), loadedDate: "2026-09-28", sameContext: true))
        XCTAssertFalse(DashboardViewModel.canReuse(lastLoad: date, now: date, loadedDate: "2026-09-28", sameContext: false))
        XCTAssertFalse(DashboardViewModel.canReuse(lastLoad: date, now: date, loadedDate: "2026-09-27", sameContext: true))
        XCTAssertFalse(DashboardViewModel.canReuse(lastLoad: date, now: date.addingTimeInterval(301), loadedDate: "2026-09-28", sameContext: true))
        XCTAssertFalse(DashboardViewModel.canReuse(lastLoad: nil, now: date, loadedDate: "2026-09-28", sameContext: true))
    }

    func testPrimaryAndDayAvailableWhileAnalysisSuspendsThenFails() async throws {
        let suite = "DashboardPriority.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = APIService(dashboardDefaults: defaults)
        var paths: [String] = []
        let clock = ContinuousClock()
        let start = clock.now
        let loaded = await api.fetchDashboard(now: { self.date }, transport: { request in
            paths.append(request.url!.path)
            return self.reply(request)
        })
        XCTAssertTrue(loaded)
        XCTAssertEqual(paths.filter { $0 == "/api/dashboard_context" }.count, 3)
        XCTAssertEqual(paths.filter { $0 == "/api/dashboard" }.count, 1)
        XCTAssertEqual(paths.filter { $0 == "/api/evening_schedule" }.count, 1)
        print("Dashboard controlled transport: VM publication \(start.duration(to: clock.now)); \(paths.count) reads. Not UI latency.")
        let waiting = expectation(description: "analysis waiting")
        let dayPublished = expectation(description: "day published independently")
        var gate: CheckedContinuation<Void, Never>?
        var dayReady = false
        var analysisFailed = false
        let work = Task {
            await DashboardViewModel.enrich(day: {
                dayReady = true
                dayPublished.fulfill()
            }, analytics: {
                await withCheckedContinuation { gate = $0; waiting.fulfill() }
                // An isolated failed secondary read does not mutate the primary owner.
                do { throw URLError(.timedOut) } catch { analysisFailed = true }
            })
        }
        await fulfillment(of: [waiting, dayPublished], timeout: 5)
        XCTAssertTrue(dayReady)
        XCTAssertNotNil(api.dashboard)
        XCTAssertEqual(api.dashboardPlan?.morning(on: date), "Lundi — Force")
        XCTAssertFalse(analysisFailed)
        gate?.resume()
        await work.value
        XCTAssertTrue(analysisFailed)
        XCTAssertNotNil(api.dashboard)
        XCTAssertNil(APILoadingState.shared.error)
        XCTAssertEqual(paths.count, 5)
    }

    func testOwnerCancellationReachesBothStructuredChildren() async {
        let started = expectation(description: "children started")
        started.expectedFulfillmentCount = 2
        var gates: [CheckedContinuation<Void, Never>] = []
        var cancellations = 0
        let child: @MainActor @Sendable () async -> Void = {
            await withCheckedContinuation { gates.append($0); started.fulfill() }
            if Task.isCancelled { cancellations += 1 }
        }
        let owner = Task { await DashboardViewModel.enrich(day: child, analytics: child) }
        await fulfillment(of: [started], timeout: 5)
        owner.cancel()
        gates.forEach { $0.resume() }
        await owner.value
        XCTAssertEqual(cancellations, 2)
    }

    func testProductionDashboardFixtureRendering() async throws {
        let suite = "DashboardRender.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = APIService(dashboardDefaults: defaults)
        let loaded = await api.fetchDashboard(now: { self.date }, transport: { self.reply($0) })
        XCTAssertTrue(loaded)
        let oldTheme = AppTheme.shared.selectedTheme
        defer { AppTheme.shared.selectedTheme = oldTheme }
        _ = try XCTUnwrap(api.dashboard)
        for large in [false] {
            AppTheme.shared.selectedTheme = large ? .electricLight : .electric
            let view = DashboardView(api: api).pageContent
                .environment(\.colorScheme, large ? .light : .dark)
                .environment(\.dynamicTypeSize, large ? .accessibility1 : .large)
                .frame(width: 402, height: 874, alignment: .top)
                .clipped()
                .background(Color.appBg)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = large ? "dashboard-fixture-large-light" : "dashboard-banner-first-fixture"
            attachment.lifetime = .keepAlways
            add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/\(attachment.name).png"))
        }
    }

    private func reply(_ request: URLRequest) -> (Data, URLResponse) {
        let payload: String
        switch request.url!.path {
        case "/api/dashboard_context", "/api/programme_data":
            payload = """
            {"active_program_id":"fixture","current_program_id":"fixture",
             "schedule":{"Lun":"Lundi — Force"},
             "full_program":{"Lundi — Force":{"Squat":"3 × 8","Row":"3 × 10"}}}
            """
        case "/api/evening_schedule": payload = "{}"
        default:
            payload = """
            {"today":"Override inutilisé","today_date":"2026-09-28","week":1,
             "schedule":{},"sessions":{},"goals":{},"full_program":{},"nutrition_totals":{},"profile":{}}
            """
        }
        var bytes = Data(payload.utf8)
        if request.url!.path == "/api/dashboard_context" {
            var json = try! JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            let full = json["full_program"] as! [String: [String: String]]
            json["schema_version"] = 1
            json["date"] = "2026-09-28"
            json["evening_schedule"] = [:] as [String: String]
            json["session_order"] = full.keys.sorted()
            json["exercise_order"] = full.mapValues { $0.keys.sorted() }
            bytes = try! JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
        }
        return (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
