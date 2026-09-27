import XCTest
@testable import TrainingOS

/// Real f1 queue, isolated storage, injected HTTP. No live API or owner.finish().
@MainActor
final class NeutralFinalizationTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var manager: SyncManager!
    private let date = "2026-09-27"
    private let key = OfflineOperationKey(rawValue: "neutral-exercise-v1")
    private let ok = Data(#"{"success":true}"#.utf8)

    override func setUp() async throws {
        suite = "neutral-finalization-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        manager = SyncManager(queue: UserDefaultsSyncQueue(defaults: defaults))
        manager.isOnlineProvider = { true }
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        manager = nil
        defaults = nil
    }

    private func result(_ source: DayComposerSource = .morning, name: String = "Carry") -> ExerciseLogResult {
        ExerciseLogResult(name: name, weight: 40, reps: "8/8", rpe: 7,
            sets: [["weight": 40, "reps": 8, "duration": 30, "duration_left": 12,
                    "duration_right": 18, "distance_m": 15, "intensity": 20,
                    "rir": 2, "rpe": 7, "protocol_completed": true]],
            isSecond: source == .evening, equipmentType: "dumbbell", painZone: "knee",
            notes: " note exacte \n", trackingType: "carry", scheme: "3x8", isUnilateral: true)
    }

    private func exercise(_ source: DayComposerSource = .morning,
                          operationKey: OfflineOperationKey? = nil) throws -> NeutralExerciseSubmissionRequest {
        try NeutralExerciseSubmissionRequest(itemIdentity: "exercise-stable-id", source: source,
            date: date, result: result(source), operationKey: operationKey ?? key)
    }

    private func final(_ source: DayComposerSource = .morning,
                       dependencies: NeutralSourceDependencies = .satisfied,
                       comment: String = " exact \n") throws -> NeutralSourceFinalizationRequest {
        try NeutralSourceFinalizationRequest(source: source, date: date, sessionName: "Session réelle",
            resultsByIdentity: ["z": result(source, name: "Z"), "a": result(source, name: "A")],
            comment: comment, rpe: 8, durationMin: 42, energyPre: 3,
            operationKey: OfflineOperationKey(rawValue: "final-\(source.rawValue)"), dependencies: dependencies)
    }

    private func response(_ request: URLRequest, code: Int = 200, body: Data? = nil) -> (Data, URLResponse) {
        (body ?? ok, HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func tag<R>(_ outcome: NeutralSubmissionOutcome<R>) -> String {
        switch outcome {
        case .applicationConfirmed: return "confirmed"
        case .queued: return "queued"
        case .transportDeliveredUnverified: return "unverified"
        case .discarded: return "discarded"
        case .uncertain: return "uncertain"
        case .applicationFailure: return "rejected"
        case .invalidResponse: return "invalid"
        case .failedBeforeSubmission: return "failed"
        case .correlationConflict: return "conflict"
        case .noExistingTransport: return "notFound"
        case .dependenciesBlocked: return "blocked"
        }
    }

    func testExerciseBuilderStableBytesAndSpecializedFields() throws {
        for source in [DayComposerSource.morning, .evening] {
            let a = try exercise(source)
            let b = try exercise(source)
            XCTAssertEqual(a.payloadData, b.payloadData)
            let body = try object(a.payloadData)
            XCTAssertEqual(body["session_date"] as? String, date)
            XCTAssertEqual(body["is_second"] as? Bool ?? false, source == .evening)
            XCTAssertFalse(body["is_bonus"] as? Bool ?? false)
            XCTAssertEqual(body["notes"] as? String, " note exacte \n")
            XCTAssertEqual(body["equipment_type"] as? String, "dumbbell")
            XCTAssertEqual(body["pain_zone"] as? String, "knee")
            XCTAssertEqual(body["rpe"] as? Double, 7)
            XCTAssertEqual(body["force"] as? Bool, true)
            XCTAssertEqual(try WorkoutPayloadBuilder.encode(["sets": result(source).sets]),
                           try WorkoutPayloadBuilder.encode(["sets": body["sets"]!]))
            XCTAssertNil(body["scheme"])
            XCTAssertNil(body["tracking_type"]) // local reconstruction metadata stays local
        }
    }

    func testFinalBuilderStableOrderExactCommentAndSnapshot() throws {
        for source in [DayComposerSource.morning, .evening] {
            for comment in ["", " exact \n"] {
                let request = try final(source, comment: comment)
                let body = try object(request.payloadData)
                XCTAssertEqual(body["date"] as? String, date)
                XCTAssertEqual(body["comment"] as? String, comment)
                XCTAssertEqual(body["session_name"] as? String, "Session réelle")
                XCTAssertEqual(body["second_session"] as? Bool ?? false, source == .evening)
                XCTAssertFalse(body["bonus_session"] as? Bool ?? false)
                XCTAssertEqual(body["rpe"] as? Double, 8)
                XCTAssertEqual(body["exos"] as? [String], ["A 40.0lbs 8/8", "Z 40.0lbs 8/8"])
                XCTAssertEqual(request.payloadData, try final(source, comment: comment).payloadData)
                var results = ["a": result(source, name: "A"), "z": result(source, name: "Z")]
                let same = try NeutralSourceFinalizationRequest(source: source, date: date,
                    sessionName: "Session réelle", resultsByIdentity: results, comment: comment,
                    rpe: 8, durationMin: 42, energyPre: 3, operationKey: request.operationKey, dependencies: .satisfied)
                results.removeAll()
                XCTAssertEqual(request.payloadData, same.payloadData)
            }
        }
    }

    func testLegacyExercisePayloadUsesSameBuilder() async throws {
        let r = result()
        let request = try exercise()
        _ = try await APIService.shared.logExerciseOutcome(exercise: r.name, weight: r.weight, reps: r.reps,
            rpe: r.rpe, sets: r.sets, force: true, equipmentType: r.equipmentType,
            painZone: r.painZone, notes: r.notes, date: date, invalidate: false, post: { body in
                XCTAssertEqual(try WorkoutPayloadBuilder.encode(body), request.payloadData)
                return self.ok
            })
    }

    func testParsersAndLegacyErrors() async throws {
        for data in [Data(#"{"success":false}"#.utf8), Data("invalid".utf8), Data("{}".utf8)] {
            do {
                _ = try await SessionSaveOutcome.fromOfflinePost { data }
                XCTFail("Legacy final must reject")
            } catch APIError.decodingFailed(let endpoint, _) { XCTAssertEqual(endpoint, "/api/log_session") }
            do {
                _ = try await ExerciseSaveOutcome.fromOfflinePost { data }
                XCTFail("Legacy exercise must reject")
            } catch APIError.decodingFailed(let endpoint, _) { XCTAssertEqual(endpoint, "/api/log") }
        }
        guard case .success = WorkoutResponseParser.exercise(ok),
              case .success = WorkoutResponseParser.session(ok),
              case .failure = WorkoutResponseParser.exercise(Data(#"{"success":false}"#.utf8)),
              case .failure = WorkoutResponseParser.session(Data(#"{"success":false}"#.utf8)),
              case .invalidResponse = WorkoutResponseParser.exercise(Data("{}".utf8)),
              case .invalidResponse = WorkoutResponseParser.session(Data("{}".utf8)) else {
            return XCTFail("Shared parser contract")
        }
        guard case .queuedOffline = try await ExerciseSaveOutcome.fromOfflinePost({ nil }),
              case .queuedOffline = try await SessionSaveOutcome.fromOfflinePost({ nil }) else {
            return XCTFail("Legacy queued acceptance must stay unchanged")
        }
    }

    func testOnlineExerciseThenDeliveredReplayIsNotConfirmed() async throws {
        let request = try exercise()
        var calls = 0
        let send: (URLRequest) async throws -> (Data, URLResponse) = { http in
            calls += 1
            XCTAssertEqual(http.url?.path, "/api/log")
            XCTAssertEqual(http.httpBody, request.payloadData)
            return self.response(http)
        }
        let first = await APIService.shared.submitExerciseCorrelated(request, manager: manager, transport: send)
        let replay = await APIService.shared.submitExerciseCorrelated(request, manager: manager, transport: send)
        XCTAssertEqual(tag(first), "confirmed")
        XCTAssertEqual(tag(replay), "unverified")
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(NeutralSourceDependencies.evaluate([replay]), .unverified)
        guard case .delivered(let record) = manager.status(for: key) else { return XCTFail("f1 journal") }
        XCTAssertEqual(record.operationKey, request.operationKey)
    }

    func testOfflineDeduplicationAndSameKeyConflict() async throws {
        manager.isOnlineProvider = { false }
        var calls = 0
        let send: (URLRequest) async throws -> (Data, URLResponse) = { http in
            calls += 1; return self.response(http)
        }
        let request = try exercise()
        let a = await APIService.shared.submitExerciseCorrelated(request, manager: manager, transport: send)
        let b = await APIService.shared.submitExerciseCorrelated(request, manager: manager, transport: send)
        guard case .queued(let ra) = a, case .queued(let rb) = b else { return XCTFail("Not confirmed") }
        XCTAssertEqual(ra, rb)
        let changed = try NeutralExerciseSubmissionRequest(itemIdentity: request.itemIdentity, source: .morning,
            date: date, result: result(name: "Different"), operationKey: key)
        let conflict = await APIService.shared.submitExerciseCorrelated(changed, manager: manager, transport: send)
        XCTAssertEqual(tag(conflict), "conflict")
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(NeutralSourceDependencies.evaluate([a]), .waiting)
    }

    func testExerciseAndFinalHTTPMapping() async throws {
        for code in [200, 409, 422, 429, 500] {
            for isFinal in [false, true] {
                // Independent journal per operation: deterministic keys, no cross-case terminal reuse.
                let operation = OfflineOperationKey(rawValue: "http-\(code)-\(isFinal)")
                let send: (URLRequest) async throws -> (Data, URLResponse) = { self.response($0, code: code) }
                let actual: String
                if isFinal {
                    let request = try NeutralSourceFinalizationRequest(source: .evening, date: date,
                        sessionName: "PM", resultsByIdentity: [:], comment: "", rpe: 7,
                        operationKey: operation, dependencies: .satisfied)
                    actual = tag(await APIService.shared.submitSourceFinalCorrelated(request, manager: manager, transport: send))
                } else {
                    actual = tag(await APIService.shared.submitExerciseCorrelated(try exercise(operationKey: operation),
                        manager: manager, transport: send))
                }
                XCTAssertEqual(actual, code == 200 ? "confirmed" : ([409, 422].contains(code) ? "discarded" : "queued"))
            }
        }
    }

    func testBothSubmissionParsersUseExactOnlineBody() async throws {
        for (index, body) in [Data(#"{"success":false}"#.utf8), Data("invalid".utf8)].enumerated() {
            let send: (URLRequest) async throws -> (Data, URLResponse) = { self.response($0, body: body) }
            let ex = try exercise(operationKey: OfflineOperationKey(rawValue: "parse-ex-\(index)"))
            let request = try NeutralSourceFinalizationRequest(source: .morning, date: date,
                sessionName: "AM", resultsByIdentity: [:], comment: "", rpe: 7,
                operationKey: OfflineOperationKey(rawValue: "parse-final-\(index)"), dependencies: .satisfied)
            let a = await APIService.shared.submitExerciseCorrelated(ex, manager: manager, transport: send)
            let b = await APIService.shared.submitSourceFinalCorrelated(request, manager: manager, transport: send)
            XCTAssertEqual(tag(a), index == 0 ? "rejected" : "invalid")
            XCTAssertEqual(tag(b), index == 0 ? "rejected" : "invalid")
        }
    }

    func testAmbiguousExerciseAndFinalNeverResend() async throws {
        var calls = 0
        let send: (URLRequest) async throws -> (Data, URLResponse) = { _ in
            calls += 1; throw URLError(.timedOut)
        }
        let ex = try exercise()
        let request = try final()
        for _ in 0..<2 {
            let a = await APIService.shared.submitExerciseCorrelated(ex, manager: manager, transport: send)
            let b = await APIService.shared.submitSourceFinalCorrelated(request, manager: manager, transport: send)
            XCTAssertEqual(tag(a), "uncertain")
            XCTAssertEqual(tag(b), "uncertain")
        }
        XCTAssertEqual(calls, 2)
    }

    func testDependencyGateDoesNotEvenEnqueue() async throws {
        var calls = 0
        for state in [NeutralSourceDependencies.waiting, .unverified, .failed, .uncertain] {
            let request = try final(dependencies: state)
            let outcome = await APIService.shared.submitSourceFinalCorrelated(request, manager: manager, transport: {
                calls += 1; return self.response($0)
            })
            guard case .dependenciesBlocked(let actual) = outcome else { return XCTFail("Gate") }
            XCTAssertEqual(actual, state)
            XCTAssertEqual(manager.status(for: request.operationKey), .notFound)
        }
        XCTAssertEqual(calls, 0)
    }

    func testDependencyClassificationFailsClosed() {
        typealias O = NeutralSubmissionOutcome<LogExerciseResponse>
        let failures: [O] = [.applicationFailure, .invalidResponse, .failedBeforeSubmission("invalid"), .correlationConflict]
        for failure in failures { XCTAssertEqual(NeutralSourceDependencies.evaluate([failure]), .failed) }
        XCTAssertEqual(NeutralSourceDependencies.evaluate([.uncertain(nil)]), .uncertain)
        XCTAssertEqual(NeutralSourceDependencies.evaluate([.noExistingTransport]), .unverified)
        XCTAssertEqual(tag(O.existing(.notFound)), "notFound")
        guard case .success(let response) = WorkoutResponseParser.exercise(ok) else { return XCTFail("fixture") }
        XCTAssertEqual(NeutralSourceDependencies.evaluate([.applicationConfirmed(response)]), .satisfied)
    }

    func testFinalMorningAndEveningRoutingExactSnapshot() async throws {
        for source in [DayComposerSource.morning, .evening] {
            let request = try final(source)
            var calls = 0
            let outcome = await APIService.shared.submitSourceFinalCorrelated(request, manager: manager, transport: { http in
                calls += 1
                XCTAssertEqual(http.url?.path, "/api/log_session")
                XCTAssertEqual(http.httpBody, request.payloadData)
                return self.response(http)
            })
            XCTAssertEqual(tag(outcome), "confirmed") // application only, no observation/cleanup
            XCTAssertEqual(calls, 1)
            guard case .delivered(let record) = manager.status(for: request.operationKey) else { return XCTFail("key") }
            XCTAssertEqual(record.operationKey, request.operationKey)
        }
    }

    func testFinalOfflineIsOnlyQueued() async throws {
        manager.isOnlineProvider = { false }
        let outcome = await APIService.shared.submitSourceFinalCorrelated(try final(), manager: manager, transport: { http in
            XCTFail("offline transport"); return self.response(http)
        })
        XCTAssertEqual(tag(outcome), "queued")
    }

    func testFinalTerminalIsUnverifiedAndRefusesChangedBytes() async throws {
        let request = try final()
        var calls = 0
        let send: (URLRequest) async throws -> (Data, URLResponse) = {
            calls += 1; return self.response($0)
        }
        let first = await APIService.shared.submitSourceFinalCorrelated(request, manager: manager, transport: send)
        let changed = try final(comment: "newer local version")
        let second = await APIService.shared.submitSourceFinalCorrelated(changed, manager: manager, transport: send)
        XCTAssertEqual(tag(first), "confirmed")
        // f1 terminal identity refuses reuse before comparing payload. It does
        // not replace the operation or acknowledge the newer bytes.
        XCTAssertEqual(tag(second), "unverified")
        XCTAssertEqual(calls, 1)
    }

    func testFinalPendingKeyConflictIsExplicit() async throws {
        manager.isOnlineProvider = { false }
        let first = await APIService.shared.submitSourceFinalCorrelated(try final(), manager: manager)
        let changed = await APIService.shared.submitSourceFinalCorrelated(try final(comment: "changed"), manager: manager)
        XCTAssertEqual(tag(first), "queued")
        XCTAssertEqual(tag(changed), "conflict")
    }

    func testDiscardedDependencyCannotSatisfyGate() async throws {
        let outcome = await APIService.shared.submitExerciseCorrelated(try exercise(), manager: manager,
            transport: { self.response($0, code: 422) })
        XCTAssertEqual(NeutralSourceDependencies.evaluate([outcome]), .failed)
    }

    func testLegacyFinalBuildersRemainIdenticalToNeutral() async throws {
        for source in [DayComposerSource.morning, .evening] {
            let request = try final(source, comment: "")
            let summary = WorkoutPayloadBuilder.summaries(["z": result(source, name: "Z"), "a": result(source, name: "A")])
            // nil avoids legacy cache/notification effects; exercises the real
            // classic builder and historical queued adapter, not a copy.
            let post: ([String: Any]) async throws -> Data? = { body in
                XCTAssertEqual(try WorkoutPayloadBuilder.encode(body), request.payloadData)
                return nil
            }
            let outcome: SessionSaveOutcome
            if source == .morning {
                outcome = try await APIService.shared.logMorningSessionOutcome(exos: summary.exos, rpe: 8,
                    comment: "", date: date, durationMin: 42, energyPre: 3, sessionName: "Session réelle",
                    exerciseLogs: summary.exerciseLogs, post: post)
            } else {
                outcome = try await APIService.shared.logEveningSessionOutcome(exos: summary.exos, rpe: 8,
                    comment: "", durationMin: 42, energyPre: 3, sessionName: "Session réelle",
                    exerciseLogs: summary.exerciseLogs, date: date, post: post)
            }
            guard case .queuedOffline = outcome else { return XCTFail("Legacy queue contract") }
        }
    }

    func testValidationRejectsBeforeTransport() throws {
        for badDate in ["", "2026-02-30", "2026-9-27", "nonsense"] {
            XCTAssertThrowsError(try NeutralExerciseSubmissionRequest(itemIdentity: "x", source: .morning,
                date: badDate, result: result(), operationKey: key))
            XCTAssertThrowsError(try NeutralSourceFinalizationRequest(source: .morning, date: badDate,
                sessionName: "AM", resultsByIdentity: [:], comment: "", rpe: 7,
                operationKey: key, dependencies: .satisfied))
        }
        var bonus = result(); bonus.isBonus = true
        for invalid in [bonus, result(.evening)] {
            XCTAssertThrowsError(try NeutralExerciseSubmissionRequest(itemIdentity: "x", source: .morning,
                date: date, result: invalid, operationKey: key))
        }
        XCTAssertThrowsError(try exercise(operationKey: OfflineOperationKey(rawValue: " ")))
        XCTAssertThrowsError(try NeutralSourceFinalizationRequest(source: .morning, date: date,
            sessionName: "AM", resultsByIdentity: ["x": bonus], comment: "", rpe: 7,
            operationKey: key, dependencies: .satisfied))
    }

    func testCompletionObservationExactDateAndFailures() async {
        for source in [DayComposerSource.morning, .evening] {
            let field = source == .morning ? "already_logged" : "second_session_completed"
            for (returnedDate, completed, expected) in [
                (date, true, SourceCompletionObservation.observed), (date, false, .unconfirmed),
                ("2026-09-26", true, source == .morning ? .unsupportedDate : .unconfirmed)
            ] {
                let outcome = await APIService.shared.observeSourceCompletion(source: source, date: date, transport: { http in
                    XCTAssertEqual(http.url?.path, source == .morning ? "/api/seance_data" : "/api/dashboard")
                    XCTAssertEqual(http.cachePolicy, .reloadIgnoringLocalCacheData)
                    if source == .evening { XCTAssertTrue(http.url!.absoluteString.contains("date=\(self.date)")) }
                    return self.response(http, body: try JSONSerialization.data(withJSONObject: ["today_date": returnedDate, field: completed]))
                })
                XCTAssertEqual(outcome, expected)
            }
            let malformed = await APIService.shared.observeSourceCompletion(source: source, date: date,
                transport: { self.response($0, body: Data("{}".utf8)) })
            let network = await APIService.shared.observeSourceCompletion(source: source, date: date,
                transport: { _ in throw URLError(.notConnectedToInternet) })
            let httpFailure = await APIService.shared.observeSourceCompletion(source: source, date: date,
                transport: { self.response($0, code: 500) })
            let badDate = await APIService.shared.observeSourceCompletion(source: source, date: "", transport: {
                XCTFail("Invalid date must not fetch"); return self.response($0)
            })
            XCTAssertEqual(malformed, .lookupFailure)
            XCTAssertEqual(network, .lookupFailure)
            XCTAssertEqual(httpFailure, .lookupFailure)
            XCTAssertEqual(badDate, .unsupportedDate)
        }
    }
}
