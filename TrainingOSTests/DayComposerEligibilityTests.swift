import XCTest
import SwiftUI
@testable import TrainingOS

@MainActor
final class DayComposerEligibilityTests: XCTestCase {
    private final class PlanningFixture {
        var date = DateFormatter.isoDate.date(from: "2026-09-27")!
        var active = "A"
        var loaded: String?
        var hasMorning = true
        var hasEvening = true
        var morningDone = false
        var eveningDone = false
        var tracking = "reps"
        var requests: [URLRequest] = []

        func transport(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            let url = try XCTUnwrap(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let day = TrainingDoctrine.dayName(on: date)
            let dateString = DateFormatter.isoDate.string(from: date)
            let am = "\(active) Matin"
            let pm = "\(active) Soir"
            let program = [am: ["Squat": "3x8"], pm: ["Tirage": "3x10"], "Ancien override": ["Ancien": "3x5"]]
            let schedule = [day: hasMorning ? am : "Repos"]
            let eveningSchedule = hasEvening ? [day: pm] : [:]
            var json: [String: Any]
            switch url.path {
            case "/api/programme_data":
                json = ["active_program_id": active, "current_program_id": loaded ?? active,
                        "full_program": program, "schedule": schedule,
                        "exercise_order": program.mapValues { $0.keys.sorted() }]
            case "/api/seance_data", "/api/seance_soir_data":
                XCTAssertEqual(query.first { $0.name == "date" }?.value, dateString)
                let evening = url.path == "/api/seance_soir_data"
                let name = evening ? pm : (query.first { $0.name == "session_name" }?.value ?? "Ancien override")
                json = ["today": name, "today_date": dateString, "already_logged": evening ? eveningDone : morningDone,
                        "has_evening_session": hasEvening, "full_program": program,
                        "weights": [:], "week": 1,
                        "schedule": evening ? eveningSchedule : schedule,
                        "inventory_tracking": ["Squat": tracking, "Tirage": tracking],
                        "exercise_order": program.mapValues { $0.keys.sorted() }]
            case "/api/dashboard":
                // Dashboard identity is deliberately unrelated: only dated
                // source completion is consumed by Day Composer.
                json = ["today_date": dateString, "today": "Ancien override",
                        "second_session_completed": eveningDone]
            default: throw URLError(.unsupportedURL)
            }
            return (try JSONSerialization.data(withJSONObject: json),
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        func load(_ requested: String? = nil) async throws -> DayComposerLoadedBundle {
            try await DayComposerLoader.loadBundle(program: requested ?? active, now: { self.date },
                transport: transport, hasRecovery: { _ in false })
        }
    }

    func testCanonicalActiveDatePlanBypassesStaleOverrideWithoutServerLogs() async throws {
        let f = PlanningFixture()
        let bundle = try await f.load()
        XCTAssertTrue(bundle.snapshot.isRelevant(hasSavedOrder: false))
        XCTAssertEqual(bundle.snapshot.morning.session, "A Matin")
        XCTAssertEqual(bundle.snapshot.evening.session, "A Soir")
        XCTAssertEqual(bundle.snapshot.morning.units.flatMap(\.items).map(\.name), ["Squat"])
        XCTAssertEqual(bundle.snapshot.evening.units.flatMap(\.items).map(\.name), ["Tirage"])
        XCTAssertEqual(bundle.snapshot.initialIDs.map(\.source), [.morning, .evening])
        XCTAssertTrue(f.requests.allSatisfy { ($0.httpMethod ?? "GET") == "GET" })
        XCTAssertTrue(f.requests.contains { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(URLQueryItem(name: "session_name", value: "A Matin")) == true })
    }

    func testMissingSourcesAndUnsupportedOnlyContentAreNotEligible() async throws {
        let f = PlanningFixture()
        f.hasEvening = false
        do { _ = try await f.load(); XCTFail("Morning-only must not be offered") } catch {}
        f.hasEvening = true
        f.hasMorning = false
        let pmOnly = try await f.load()
        XCTAssertFalse(pmOnly.snapshot.isRelevant(hasSavedOrder: false))
        f.hasMorning = true
        f.tracking = "mobility"
        let unsupported = try await f.load()
        XCTAssertFalse(unsupported.snapshot.isRelevant(hasSavedOrder: false))
    }

    func testInactiveSelectionActiveSwitchAndExplicitDate() async throws {
        let f = PlanningFixture()
        do { _ = try await f.load("B"); XCTFail("Selected B cannot replace active A") } catch {}
        f.loaded = "B"
        do { _ = try await f.load(); XCTFail("Inactive payload must fail closed") } catch {}
        f.loaded = nil
        f.active = "B"
        f.date = DateFormatter.isoDate.date(from: "2026-09-28")!
        let next = try await f.load()
        XCTAssertEqual(next.snapshot.activeProgramID, "B")
        XCTAssertEqual(next.snapshot.date, "2026-09-28")
        XCTAssertEqual(next.snapshot.morning.session, "B Matin")
        XCTAssertTrue(next.snapshot.isRelevant(hasSavedOrder: false))
    }

    func testOneCompletedSourceRemainsConsultableButFinishedDayNeedsSavedOrder() async throws {
        let f = PlanningFixture()
        f.eveningDone = true
        let partial = try await f.load()
        XCTAssertTrue(partial.snapshot.isRelevant(hasSavedOrder: false))
        f.morningDone = true
        let complete = try await f.load()
        XCTAssertFalse(complete.snapshot.isRelevant(hasSavedOrder: false))
        XCTAssertTrue(complete.snapshot.isRelevant(hasSavedOrder: true))
    }

    func testProductionEntryMountsWhileHiddenAndPreparationUsesSamePlan() async throws {
        let f = PlanningFixture()
        f.date = Date()
        var snapshots: [DayComposerSnapshot] = []
        let load: (String) async throws -> DayComposerSnapshot = { program in
            let snapshot = try await f.load(program).snapshot
            snapshots.append(snapshot)
            return snapshot
        }
        await capture("Entry-production-AM-PM", view: NavigationStack {
            DayComposerTodayEntry(activeProgramID: "A", loadSnapshot: load)
        })
        XCTAssertFalse(snapshots.isEmpty, "Regression: an empty Group never starts its eligibility task")
        XCTAssertTrue(try XCTUnwrap(snapshots.last).isRelevant(hasSavedOrder: false))
        let before = snapshots.count
        await capture("Preparation-production-AM-PM", view: NavigationStack {
            DayComposerView(activeProgramID: "A", loadSnapshot: load)
        })
        XCTAssertGreaterThan(snapshots.count, before)
        let prepared = try XCTUnwrap(snapshots.last)
        XCTAssertEqual(prepared.initialIDs.map(\.source), [.morning, .evening])
        let suite = "Eligibility-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DayComposerStore(defaults: defaults)
        let moved = DayComposerSnapshot.moving(prepared.initialUnits, from: IndexSet(integer: 0), to: 2)
        try store.save(moved, for: prepared)
        guard case .restored(let restored) = try store.load(prepared) else { return XCTFail("Order must restore") }
        XCTAssertEqual(restored, moved)
    }

    private func capture<V: View>(_ name: String, view: V) async {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        try? await Task.sleep(nanoseconds: 500_000_000)
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
