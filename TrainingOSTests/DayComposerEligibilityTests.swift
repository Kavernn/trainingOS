import XCTest
import SwiftUI
@testable import TrainingOS

@MainActor
final class DayComposerEligibilityTests: XCTestCase {
    @MainActor private final class PlanningFixture {
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

    func testMissingSourcesAreNotEligibleButUnsupportedContentCanBePrepared() async throws {
        let f = PlanningFixture()
        f.hasEvening = false
        do { _ = try await f.load(); XCTFail("Morning-only must not be offered") } catch {}
        f.hasEvening = true
        f.hasMorning = false
        let pmOnly = try await f.load()
        XCTAssertFalse(pmOnly.snapshot.isRelevant(hasSavedOrder: false))
        f.hasMorning = true
        f.tracking = "future-mobility"
        let unsupported = try await f.load()
        XCTAssertTrue(unsupported.snapshot.isRelevant(hasSavedOrder: false))
        XCTAssertFalse(unsupported.snapshot.canStart(orderedIDs: unsupported.snapshot.initialIDs,
            activeProgram: f.active, date: unsupported.snapshot.date, loading: false, incompatible: false))
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
        XCTAssertTrue(DayComposerStore.sourcesLocked(partial.snapshot))
        XCTAssertTrue(DayComposerStore.sourcesLocked(complete.snapshot))
        let samePlanningBeforeCompletion = DayComposerSnapshot(date: complete.snapshot.date,
            activeProgramID: complete.snapshot.activeProgramID, morning: complete.snapshot.morning,
            evening: complete.snapshot.evening, morningCompleted: false, eveningCompleted: false)
        XCTAssertEqual(try samePlanningBeforeCompletion.fingerprint, try complete.snapshot.fingerprint,
                       "Completion flags alone must not invalidate the planning identity")
        let suite = "CompletedDay-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DayComposerStore(defaults: defaults)
        // Existing execution data must survive passive preparation checks byte-for-byte.
        defaults.set(Data("accepted log".utf8), forKey: "execution-log")
        defaults.set(Data("confirmed finalization".utf8), forKey: "finalization")
        let before = defaults.dictionaryRepresentation() as NSDictionary
        XCTAssertFalse(store.hasSavedOrder(date: complete.snapshot.date, program: f.active))
        guard case .initial = try store.load(complete.snapshot) else {
            return XCTFail("A completed classic day must not manufacture a saved preparation")
        }
        let units = complete.snapshot.initialUnits
        XCTAssertThrowsError(try DayComposerSnapshot.transferring(units, id: units[0].id,
            locked: DayComposerStore.sourcesLocked(complete.snapshot))) { error in
            guard case DayComposerError.executionStarted = error else {
                return XCTFail("Must reject for execution, not empty-source or planning failure")
            }
        }
        XCTAssertEqual(complete.snapshot.initialUnits, units)
        XCTAssertEqual(units.flatMap(\.items).map(\.assignedSource), units.flatMap(\.items).map(\.originSource))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        XCTAssertTrue(f.requests.allSatisfy { ($0.httpMethod ?? "GET") == "GET" },
                      "Eligibility must never rewrite logs or finalization")
        // A saved recovery may be consulted, but never becomes editable.
        try store.save(units, for: complete.snapshot)
        let savedBefore = defaults.dictionaryRepresentation() as NSDictionary
        guard case .restored(let restored) = try store.load(complete.snapshot) else {
            return XCTFail("Existing recovery must remain available")
        }
        XCTAssertThrowsError(try DayComposerSnapshot.transferring(restored, id: restored[0].id,
            locked: DayComposerStore.sourcesLocked(complete.snapshot)))
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, savedBefore)
    }

    func testPreparationInitialPresentationDoesNotAwaitEnrichment() async throws {
        let f = PlanningFixture()
        f.date = Date()
        let prepared = try await f.load().snapshot
        var enrichments = 0
        let candidate = DayComposerPreparationCandidate(preview: prepared) {
            enrichments += 1
            return prepared
        }
        // This exact synchronous function also seeds DayComposerView's State.
        let initial = candidate.initialPresentation()
        _ = DayComposerTodayEntry(candidate: candidate)
        _ = DayComposerView(candidate: candidate)
        XCTAssertTrue(candidate.canPresent(on: prepared.date))
        XCTAssertFalse(candidate.canPresent(on: "2099-01-01"))
        XCTAssertEqual(initial.units, prepared.initialUnits)
        XCTAssertFalse(initial.verified, "Preview IDs must not be persisted as execution IDs")
        XCTAssertEqual(enrichments, 0, "Opening must not depend on duplicate network planning")
        _ = try await candidate.resolve()
        _ = try await candidate.resolve()
        XCTAssertEqual(enrichments, 1)
        XCTAssertEqual(prepared.initialIDs.map(\.source), [.morning, .evening])
        let suite = "Eligibility-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DayComposerStore(defaults: defaults)
        let moved = DayComposerSnapshot.moving(prepared.initialUnits, from: IndexSet(integer: 0), to: 2)
        try store.save(moved, for: prepared)
        guard case .restored(let restored) = try store.load(prepared) else { return XCTFail("Order must restore") }
        XCTAssertEqual(restored, moved)
        XCTAssertEqual(candidate.initialPresentation(store: store).units, moved)
    }

    func testMobilityAllowsProductionEntryPreparationAndStart() async throws {
        let f = PlanningFixture()
        f.date = Date()
        f.tracking = "mobility"
        let snapshot = try await f.load().snapshot
        let candidate = DayComposerPreparationCandidate(preview: snapshot) { snapshot }
        XCTAssertTrue(candidate.canPresent(on: snapshot.date))
        let initial = candidate.initialPresentation()
        XCTAssertEqual(initial.units, snapshot.initialUnits)
        _ = DayComposerView(candidate: candidate)
        XCTAssertEqual(snapshot.initialIDs.map(\.source), [.morning, .evening])
        XCTAssertTrue(snapshot.canStart(orderedIDs: snapshot.initialIDs, activeProgram: f.active,
            date: snapshot.date, loading: false, incompatible: false))
    }

    func testConcurrentPreparationEnrichmentIsSharedWithoutClearingPreview() async throws {
        let f = PlanningFixture()
        let snapshot = try await f.load().snapshot
        let held = expectation(description: "Enrichment held")
        var gate: CheckedContinuation<Void, Never>?
        var calls = 0
        let candidate = DayComposerPreparationCandidate(preview: snapshot) {
            calls += 1
            await withCheckedContinuation { gate = $0; held.fulfill() }
            return snapshot
        }
        let first = Task { try await candidate.resolve() }
        await fulfillment(of: [held], timeout: 2)
        let entered = expectation(description: "Second consumer entered")
        let second = Task { entered.fulfill(); return try await candidate.resolve() }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertEqual(candidate.initialPresentation().units, snapshot.initialUnits)
        XCTAssertEqual(calls, 1)
        gate?.resume()
        _ = try await first.value
        _ = try await second.value
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(candidate.initialPresentation().verified)
    }

}
