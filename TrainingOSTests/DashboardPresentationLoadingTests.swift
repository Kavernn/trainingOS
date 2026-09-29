import XCTest
import SwiftUI
import Combine
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

@MainActor
private final class DashboardChildGate {
    let ready: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ name: String) { ready = XCTestExpectation(description: name) }
    func wait() async {
        await withCheckedContinuation { continuation = $0; ready.fulfill() }
    }
    func release() { continuation?.resume(); continuation = nil }
}

extension DashboardPresentationLoadingTests {
    private func pattern(_ headline: String = "Original", threshold: Double = 100) throws -> PatternEntry {
        let json: [String: Any] = ["id": "same-id", "family": "C", "sub_label": "fixture", "headline": headline,
            "confidence": "forte", "effect_pct": 10, "n": 12,
            "bar_a": ["label": "A", "value": 1, "frac": 1], "bar_b": ["label": "B", "value": 0, "frac": 0],
            "icon": "leaf", "color": "green", "pinned": false, "is_new": false,
            "macro_threshold": ["macro": "proteines", "value": threshold, "unit": "g"]]
        return try JSONDecoder().decode(PatternEntry.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testControlledDayPublications() async throws {
        var hints: [MacroNutritionHint?] = []
        let vm = DashboardViewModel(publicationPermission: { $0 == 7 && $1 == "2026-09-28" }, publishMacroHint: { hints.append($0) })
        let value = try pattern()
        let nutrition = NutritionDayHistory(date: "2026-09-27", calories: 2100, proteines: 120)
        let cardio = try JSONDecoder().decode(CardioEntry.self, from: Data(#"{"id":"cardio","date":"2026-09-28","duration_min":25}"#.utf8))
        let a = DashboardChildGate("pattern waiting"), b = DashboardChildGate("nutrition waiting"), c = DashboardChildGate("cardio waiting")
        let aPublished = expectation(description: "pattern received"), bPublished = expectation(description: "nutrition received"), cPublished = expectation(description: "cardio received")
        var counts = ["pattern": 0, "nutrition": 0, "type": 0, "cardio": 0, "global": 0]
        let subscriptions = [
            vm.$dailyPattern.dropFirst().sink { _ in counts["pattern", default: 0] += 1; if counts["pattern"] == 1 { aPublished.fulfill() } },
            vm.$yesterdayNutrition.dropFirst().sink { _ in counts["nutrition", default: 0] += 1; if counts["nutrition"] == 1 { bPublished.fulfill() } },
            vm.$todayNutritionType.dropFirst().sink { _ in counts["type", default: 0] += 1 },
            vm.$cardioToday.dropFirst().sink { _ in counts["cardio", default: 0] += 1; if counts["cardio"] == 1 { cPublished.fulfill() } },
            vm.objectWillChange.sink { counts["global", default: 0] += 1 }
        ]
        let work = Task {
            await vm.receiveDay(today: "2026-09-28", contextVersion: 7) { group, state in
                group.addTask { @MainActor in await a.wait(); state.dailyPattern = value; state.receivedPattern = true; return (.pattern, 0) }
                group.addTask { @MainActor in await b.wait(); state.yesterdayNutrition = nutrition; state.todayNutritionType = "heavy"; state.receivedNutrition = true; return (.nutrition, 0) }
                group.addTask { @MainActor in await c.wait(); state.cardioToday = cardio; state.receivedCardio = true; return (.cardio, 0) }
            }
        }
        await fulfillment(of: [a.ready, b.ready, c.ready], timeout: 5)
        a.release()
        await fulfillment(of: [aPublished], timeout: 5)
        XCTAssertEqual(vm.dailyPattern?.headline, "Original")
        XCTAssertNil(vm.yesterdayNutrition); XCTAssertNil(vm.cardioToday)
        XCTAssertEqual(hints.count, 1); XCTAssertNil(hints[0])
        b.release()
        await fulfillment(of: [bPublished], timeout: 5)
        XCTAssertEqual(vm.yesterdayNutrition?.proteines, 120)
        XCTAssertEqual(vm.todayNutritionType, "heavy"); XCTAssertNil(vm.cardioToday)
        XCTAssertEqual(hints.last!, MacroNutritionHint(isAbove: true, macro: "protéines", value: 120, threshold: 100, unit: "g"))
        c.release()
        await fulfillment(of: [cPublished], timeout: 5)
        await work.value
        XCTAssertEqual(vm.cardioToday?.durationMin, 25)
        XCTAssertEqual(counts, ["pattern": 1, "nutrition": 1, "type": 1, "cardio": 1, "global": 4])
        XCTAssertEqual(hints.count, 2)
        print("DASHBOARD_DAY_PUBLICATIONS \(counts) macro=\(hints.count); staged values verified; initial subscriptions excluded")
        withExtendedLifetime(subscriptions) {}
    }

    func testControlledAnalyticsPublications() async {
        let vm = DashboardViewModel(publicationPermission: { _, _ in true }, publishMacroHint: { _ in XCTFail("Unrelated macro calculation") })
        let a = DashboardChildGate("tonnage waiting"), b = DashboardChildGate("configuration waiting"), c = DashboardChildGate("status waiting")
        let first = expectation(description: "tonnage"), second = expectation(description: "configuration"), third = expectation(description: "status")
        var counts = ["tonnage": 0, "config": 0, "result": 0, "temptation": 0, "global": 0]
        let subscriptions = [
            vm.$weeklyTonnage.dropFirst().sink { _ in counts["tonnage", default: 0] += 1; if counts["tonnage"] == 1 { first.fulfill() } },
            vm.$warRoomEnabled.dropFirst().sink { _ in counts["config", default: 0] += 1; if counts["config"] == 1 { second.fulfill() } },
            vm.$warRoomHasResult.dropFirst().sink { _ in counts["result", default: 0] += 1; if counts["result"] == 1 { third.fulfill() } },
            vm.$warRoomHasTemptation.dropFirst().sink { _ in counts["temptation", default: 0] += 1 },
            vm.objectWillChange.sink { counts["global", default: 0] += 1 }
        ]
        let work = Task {
            await vm.receiveAnalytics(today: "2026-09-28", contextVersion: 7) { group, state in
                group.addTask { @MainActor in await a.wait(); state.weeklyTonnage = 42; return .tonnage }
                group.addTask { @MainActor in await b.wait(); state.warRoomEnabled = true; return .warRoomConfig }
                group.addTask { @MainActor in await c.wait(); state.warRoomHasResult = true; state.warRoomHasTemptation = false; return .warRoomStatus }
            }
        }
        await fulfillment(of: [a.ready, b.ready, c.ready], timeout: 5)
        a.release(); await fulfillment(of: [first], timeout: 5)
        XCTAssertEqual(vm.weeklyTonnage, 42); XCTAssertFalse(vm.warRoomEnabled)
        b.release(); await fulfillment(of: [second], timeout: 5)
        XCTAssertTrue(vm.warRoomEnabled); XCTAssertFalse(vm.warRoomHasResult)
        c.release(); await fulfillment(of: [third], timeout: 5)
        await work.value
        XCTAssertTrue(vm.warRoomHasResult); XCTAssertFalse(vm.warRoomHasTemptation)
        XCTAssertEqual(counts, ["tonnage": 1, "config": 1, "result": 1, "temptation": 1, "global": 4])
        print("DASHBOARD_ANALYTICS_PUBLICATIONS \(counts); staged values verified; initial subscriptions excluded")
        withExtendedLifetime(subscriptions) {}
    }
}

extension DashboardPresentationLoadingTests {
    func testContextResetClearsMacroHintEvenWhenNewSourcesFail() async throws {
        var hints: [MacroNutritionHint?] = []
        let vm = DashboardViewModel(publicationPermission: { _, _ in true }, publishMacroHint: { hints.append($0) })
        let value = try pattern()
        vm.yesterdayNutrition = .init(date: "2026-09-27", calories: 2100, proteines: 120)
        await vm.receiveDay(today: "2026-09-28", contextVersion: 7) { group, state in
            group.addTask { @MainActor in state.dailyPattern = value; state.receivedPattern = true; return (.pattern, 0) }
        }
        XCTAssertEqual(hints, [MacroNutritionHint(isAbove: true, macro: "protéines", value: 120, threshold: 100, unit: "g")])
        vm.resetMacroInputs()
        XCTAssertNil(vm.dailyPattern); XCTAssertNil(vm.yesterdayNutrition)
        XCTAssertEqual(hints.count, 2); XCTAssertNil(hints[1])
        await vm.receiveDay(today: "2026-09-28", contextVersion: 8) { group, _ in
            group.addTask { (.pattern, 0) }
            group.addTask { (.nutrition, 0) }
            group.addTask { (.alerts, 0) }
        }
        XCTAssertEqual(hints.count, 2); XCTAssertNil(hints[1])
    }

    func testSameIdentityChangedContentAndValidEmptyRepliesPublishExactly() async throws {
        var hints: [MacroNutritionHint?] = []
        let vm = DashboardViewModel(publicationPermission: { _, _ in true }, publishMacroHint: { hints.append($0) })
        vm.yesterdayNutrition = .init(date: "2026-09-27", calories: 2100, proteines: 120)
        vm.todayNutritionType = "heavy"
        let original = try pattern(), changed = try pattern("Correction", threshold: 150)
        var headlines: [String?] = []
        let subscription = vm.$dailyPattern.dropFirst().sink { headlines.append($0?.headline) }
        for value in [original, changed] {
            await vm.receiveDay(today: "2026-09-28", contextVersion: 7) { group, state in
                group.addTask { @MainActor in state.dailyPattern = value; state.receivedPattern = true; return (.pattern, 0) }
            }
        }
        XCTAssertEqual(original.id, changed.id)
        XCTAssertEqual(headlines, ["Original", "Correction"])
        XCTAssertEqual(hints, [MacroNutritionHint(isAbove: true, macro: "protéines", value: 120, threshold: 100, unit: "g"),
                               MacroNutritionHint(isAbove: false, macro: "protéines", value: 120, threshold: 150, unit: "g")])
        await vm.receiveDay(today: "2026-09-28", contextVersion: 7) { group, _ in
            group.addTask { (.nutrition, 0) } // Failed fetch: receivedNutrition remains false.
        }
        XCTAssertEqual(vm.todayNutritionType, "heavy")
        XCTAssertEqual(vm.yesterdayNutrition?.proteines, 120)
        XCTAssertEqual(hints.count, 2)
        await vm.receiveDay(today: "2026-09-28", contextVersion: 7) { group, state in
            group.addTask { @MainActor in state.receivedNutrition = true; return (.nutrition, 0) }
        }
        XCTAssertNil(vm.yesterdayNutrition); XCTAssertNil(vm.todayNutritionType)
        XCTAssertEqual(vm.dailyPattern?.headline, "Correction")
        XCTAssertEqual(hints.count, 3); XCTAssertNil(hints[2])
        await vm.receiveDay(today: "2026-09-28", contextVersion: 7) { group, state in
            group.addTask { @MainActor in state.receivedPattern = true; return (.pattern, 0) }
        }
        XCTAssertNil(vm.dailyPattern)
        XCTAssertEqual(headlines, ["Original", "Correction", nil])
        XCTAssertEqual(hints.count, 4); XCTAssertNil(hints[3])
        withExtendedLifetime(subscription) {}
    }

    func testUnrelatedCompletionCannotReplayAnOlderAccumulatedValue() async throws {
        var hints: [MacroNutritionHint?] = []
        let vm = DashboardViewModel(publicationPermission: { _, _ in true }, publishMacroHint: { hints.append($0) })
        let original = try pattern(), edited = try pattern("Local accepted edit", threshold: 150)
        let gate = DashboardChildGate("nutrition waits for local edit")
        let published = expectation(description: "first pattern")
        let subscription = vm.$dailyPattern.dropFirst().first().sink { _ in published.fulfill() }
        let work = Task {
            await vm.receiveDay(today: "2026-09-28", contextVersion: 7) { group, state in
                group.addTask { @MainActor in state.dailyPattern = original; state.receivedPattern = true; return (.pattern, 0) }
                group.addTask { @MainActor in
                    await gate.wait()
                    state.receivedNutrition = true
                    state.yesterdayNutrition = .init(date: "2026-09-27", calories: 2100, proteines: 120)
                    return (.nutrition, 0)
                }
            }
        }
        await fulfillment(of: [published, gate.ready], timeout: 5)
        vm.dailyPattern = edited
        gate.release(); await work.value
        XCTAssertEqual(vm.dailyPattern?.headline, "Local accepted edit")
        XCTAssertEqual(hints.last!, MacroNutritionHint(isAbove: false, macro: "protéines", value: 120, threshold: 150, unit: "g"))
        withExtendedLifetime(subscription) {}

        let status = expectation(description: "initial status")
        let slow = DashboardChildGate("tonnage pending")
        let statusSub = vm.$warRoomHasResult.dropFirst().first().sink { _ in status.fulfill() }
        let analytics = Task {
            await vm.receiveAnalytics(today: "2026-09-28", contextVersion: 7) { group, state in
                group.addTask { @MainActor in state.warRoomHasResult = false; return .warRoomStatus }
                group.addTask { @MainActor in await slow.wait(); state.weeklyTonnage = 70; return .tonnage }
            }
        }
        await fulfillment(of: [status, slow.ready], timeout: 5)
        vm.warRoomHasResult = true
        slow.release(); await analytics.value
        XCTAssertTrue(vm.warRoomHasResult)
        XCTAssertEqual(vm.weeklyTonnage, 70)
        withExtendedLifetime(statusSub) {}
    }

    func testPartialFailureAndBriefRecoveryKeepOtherSections() async throws {
        let vm = DashboardViewModel(publicationPermission: { _, _ in true }, publishMacroHint: { _ in XCTFail("Unrelated projection") })
        vm.dailyPattern = try pattern()
        var warnings: [Bool] = []
        var briefFailures: [Bool] = []
        let subscriptions = [vm.$partialLoadWarning.dropFirst().sink { warnings.append($0) },
                             vm.$morningBriefFailed.dropFirst().sink { briefFailures.append($0) }]
        await vm.receiveDay(today: "2026-09-28", contextVersion: 7) { group, state in
            group.addTask { (.recovery, 1) }
            group.addTask { @MainActor in state.morningBriefFailed = true; return (.morningBrief, 0) }
            group.addTask { (.alerts, 0) }
        }
        XCTAssertEqual(vm.dailyPattern?.headline, "Original")
        XCTAssertTrue(vm.partialLoadWarning); XCTAssertTrue(vm.morningBriefFailed)
        XCTAssertEqual(warnings, [true]); XCTAssertEqual(briefFailures, [true])
        let brief = MorningBriefData(date: "2026-09-28", sessionToday: "Séance", sessionIntensity: "moderate", lss: nil,
            recommendation: "go", message: "Exact briefing", adjustments: [],
            flags: .init(hrvDrop: false, sleepDeprivation: false, trainingOverload: false), dataCoverage: 1, components: nil, ritualRate7d: nil)
        await vm.receiveDay(today: "2026-09-28", contextVersion: 7) { group, state in
            group.addTask { @MainActor in state.morningBrief = brief; return (.morningBrief, 0) }
        }
        XCTAssertEqual(vm.morningBrief?.message, "Exact briefing")
        XCTAssertFalse(vm.morningBriefFailed); XCTAssertFalse(vm.partialLoadWarning)
        XCTAssertEqual(briefFailures, [true, false]); XCTAssertEqual(warnings, [true, false])
        withExtendedLifetime(subscriptions) {}
    }

    func testCancelledAndStaleReceiversCannotPublish() async throws {
        for cancelled in [false, true] {
            var version = 7
            let vm = DashboardViewModel(publicationPermission: { $0 == version && $1 == "2026-09-28" }, publishMacroHint: { _ in XCTFail("Obsolete macro") })
            let value = try pattern()
            let a = DashboardChildGate("day pending"), b = DashboardChildGate("analytics pending")
            var publications = 0
            let subscription = vm.objectWillChange.sink { publications += 1 }
            let work = Task {
                await DashboardViewModel.enrich(day: {
                    await vm.receiveDay(today: "2026-09-28", contextVersion: 7) { group, state in
                        group.addTask { @MainActor in await a.wait(); state.dailyPattern = value; state.receivedPattern = true; return (.pattern, 0) }
                    }
                }, analytics: {
                    await vm.receiveAnalytics(today: "2026-09-28", contextVersion: 7) { group, state in
                        group.addTask { @MainActor in await b.wait(); state.weeklyTonnage = 70; return .tonnage }
                    }
                })
            }
            await fulfillment(of: [a.ready, b.ready], timeout: 5)
            if cancelled { work.cancel() } else { version = 8 }
            a.release(); b.release(); await work.value
            XCTAssertNil(vm.dailyPattern); XCTAssertNil(vm.weeklyTonnage)
            XCTAssertEqual(publications, 0)
            withExtendedLifetime(subscription) {}
        }
    }

    func testEffectOnlyChildDoesNotRepublishAlreadyReceivedAnalytics() async {
        let vm = DashboardViewModel(publicationPermission: { _, _ in true }, publishMacroHint: { _ in XCTFail("Unrelated projection") })
        let gate = DashboardChildGate("effect pending")
        let first = expectation(description: "data published")
        var dataPublications = 0, effects = 0
        let subscription = vm.$weeklyTonnage.dropFirst().sink { _ in dataPublications += 1; if dataPublications == 1 { first.fulfill() } }
        let task = Task {
            await vm.receiveAnalytics(today: "2026-09-28", contextVersion: 7) { group, state in
                group.addTask { @MainActor in state.weeklyTonnage = 0; return .tonnage }
                group.addTask { @MainActor in await gate.wait(); effects += 1; return .effects }
            }
        }
        await fulfillment(of: [first, gate.ready], timeout: 5)
        XCTAssertEqual(vm.weeklyTonnage, 0)
        gate.release(); await task.value
        XCTAssertEqual(dataPublications, 1); XCTAssertEqual(effects, 1)
        withExtendedLifetime(subscription) {}
    }
}
