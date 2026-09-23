//
//  SeanceViewModelTests.swift
//  TrainingOSTests
//
//  Strategy: pre-load the injected CacheService with SeanceData JSON,
//  then call load() — network fetch fails (no real server) and is silently
//  ignored since seanceData is already set from cache.

import XCTest
@testable import TrainingOS

@MainActor
final class SeanceViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel(cacheData: Data? = nil, cacheKey: String = "seance_data") -> SeanceViewModel {
        let cache = makeTempCacheService()
        if let data = cacheData {
            cache.save(data, for: cacheKey)
        }
        let vm = SeanceViewModel(draftSessionType: "morning")
        vm.cacheService = cache
        return vm
    }

    // MARK: - Tests

    private final class FinishSaveStub: SeanceViewModel {
        var failures: Set<String> = []
        var queued: Set<String> = []
        var calls: [String] = []
        var sentWeights: [Double] = []
        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome {
            calls.append(result.name)
            sentWeights.append(result.weight)
            if failures.contains(result.name) { throw APIError.serverError(500, "Injected") }
            if queued.contains(result.name) { return .queuedOffline }
            return .confirmed(LogExerciseResponse(success: true, newWeight: nil, oneRM: nil,
                                                  isPR: false, baselineCount: nil, confidence: nil))
        }
    }

    func testFinishGateRetriesOnlyFailuresAndAcceptsOffline() async throws {
        let vm = FinishSaveStub(draftSessionType: "morning")
        let date = "finish-test-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "morning") }
        vm.seanceData = try APIService.decoder.decode(SeanceData.self, from: Fixtures.seanceDataJSON(todayDate: date))
        vm.logResults = Dictionary(uniqueKeysWithValues: ["A", "B", "C"].map {
            ($0, ExerciseLogResult(name: $0, weight: 80, reps: "5"))
        })
        vm.failures = ["B"]
        vm.queued = ["C"]
        let first = await vm.saveExercisesForFinish()
        XCTAssertFalse(first)
        XCTAssertEqual(vm.calls, ["A", "B", "C"])
        XCTAssertEqual(vm.failedExerciseNames, ["B"])
        XCTAssertFalse(vm.showSuccess)
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "morning"))
        let second = await vm.saveExercisesForFinish()
        XCTAssertFalse(second)
        XCTAssertEqual(vm.calls, ["A", "B", "C", "B"])
        vm.failures = []
        let third = await vm.saveExercisesForFinish()
        XCTAssertTrue(third)
        XCTAssertEqual(vm.calls, ["A", "B", "C", "B", "B"])
        XCTAssertTrue(vm.failedExerciseNames.isEmpty)
        XCTAssertNil(vm.submitError)
        // The gate never cleans the draft; finalization owns cleanup.
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "morning"))
        vm.logResults["A"] = ExerciseLogResult(name: "A", weight: 85, reps: "5")
        let edited = await vm.saveExercisesForFinish()
        XCTAssertTrue(edited)
        XCTAssertEqual(vm.calls.last, "A")
        XCTAssertEqual(vm.sentWeights.last, 85)
    }

    func testFinishGateAllConfirmedAndFreshLifecycleResends() async {
        let vm = FinishSaveStub(draftSessionType: "morning")
        vm.logResults = ["A": ExerciseLogResult(name: "A", weight: 80, reps: "5")]
        let accepted = await vm.saveExercisesForFinish()
        XCTAssertTrue(accepted)
        let recreated = FinishSaveStub(draftSessionType: "morning")
        recreated.logResults = vm.logResults
        let restoredAccepted = await recreated.saveExercisesForFinish()
        XCTAssertTrue(restoredAccepted)
        XCTAssertEqual(recreated.calls, ["A"])
    }

    private final class FailingEveningFinish: SeanceSoirViewModel {
        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome {
            throw APIError.serverError(500, "Injected")
        }
    }
    private final class FailingBonusFinish: BonusSeanceViewModel {
        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome {
            throw APIError.serverError(500, "Injected")
        }
    }

    func testBlockingSaveStopsMorningEveningBonusAndPartialEvening() async throws {
        let morning = FinishSaveStub(draftSessionType: "morning")
        morning.failures = ["A"]
        let cases: [(SeanceViewModel, Bool)] = [
            (morning, true), (FailingEveningFinish(), true),
            (FailingBonusFinish(), true), (FailingEveningFinish(), false)
        ]
        for (vm, close) in cases {
            let date = "blocked-finish-\(UUID().uuidString)"
            defer { SessionDraftStore.clear(date: date, sessionType: vm.draftSessionType) }
            vm.seanceData = try APIService.decoder.decode(SeanceData.self, from: Fixtures.seanceDataJSON(todayDate: date))
            vm.logResults = ["A": ExerciseLogResult(name: "A", weight: 80, reps: "5")]
            await vm.finish(rpe: 7, comment: "", closeSession: close)
            XCTAssertFalse(vm.showSuccess)
            XCTAssertFalse(vm.partialSaveAccepted)
            XCTAssertFalse(vm.isFinishing)
            XCTAssertEqual(vm.failedExerciseNames, ["A"])
            XCTAssertNotNil(vm.submitError)
            XCTAssertTrue(vm.canRetryFinish)
            XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: vm.draftSessionType))
            await vm.retryFinish()
            XCTAssertFalse(vm.showSuccess)
            XCTAssertFalse(vm.partialSaveAccepted)
            XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: vm.draftSessionType))
        }
    }

    func testLegacySetDraftsDecodeWithoutSpecializedValues() throws {
        let oldCard = Data(#"{"weight":"80","reps":"5","rir":2,"duration":30,"rpe":8}"#.utf8)
        let card = try APIService.decoder.decode(DraftSet.self, from: oldCard)
        XCTAssertEqual(card.weight, "80")
        XCTAssertEqual(card.reps, "5")
        XCTAssertEqual(card.rir, 2)
        XCTAssertEqual(card.rpe, 8)
        XCTAssertNil(card.distance)
        XCTAssertNil(card.intensity)
        XCTAssertNil(card.durationLeft)
        XCTAssertNil(card.durationRight)
        XCTAssertNil(card.protocolCompleted)
        let oldLog = Data(#"{"weight":80,"reps":"5","rir":2,"rpe":8}"#.utf8)
        let log = try APIService.decoder.decode(PersistedSet.self, from: oldLog)
        XCTAssertEqual(log.weight, 80)
        XCTAssertEqual(log.reps, "5")
        XCTAssertEqual(log.rir, 2)
        XCTAssertEqual(log.rpe, 8)
        XCTAssertNil(log.distanceM)
        XCTAssertNil(log.intensity)
        XCTAssertNil(log.leftTime)
        XCTAssertNil(log.rightTime)
    }

    func testSpecializedLogPayloadsSurviveSessionStoreAndRestore() throws {
        let cases: [(String, [String: Any])] = [
            ("reps", ["weight": 80.0, "reps": "5", "rir": 2, "rpe": 8.0]),
            ("reps", ["weight": 0.0, "reps": "8", "rir": 3, "rpe": 7.0]),
            ("carry", ["weight": 40.0, "distance_m": 25]),
            ("plyo", ["weight": 0.0, "reps": "6", "intensity": 42.5]),
            ("time", ["weight": 0, "reps": "45"]),
            ("time", ["weight": 0, "reps": "65", "left": ["time": 30], "right": ["time": 35]]),
            ("protocol", ["weight": 0])
        ]
        for (tracking, payload) in cases {
            let date = "payload-test-\(UUID().uuidString)"
            defer { SessionDraftStore.clear(date: date, sessionType: "evening") }
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.seanceDataJSON(todayDate: date)) as? [String: Any])
            // Carry/protocol also retain their type when the screen's inventory is not in seanceData.
            json["inventory_tracking"] = ["Bench Press": tracking == "carry" || tracking == "protocol" ? "reps" : tracking]
            let data = try APIService.decoder.decode(SeanceData.self, from: JSONSerialization.data(withJSONObject: json))
            let original = SeanceViewModel(draftSessionType: "evening")
            original.seanceData = data
            original.logResults = ["Bench Press": ExerciseLogResult(
                name: "Bench Press", weight: 40, reps: "1", sets: [payload], isSecond: true,
                trackingType: tracking
            )]
            XCTAssertEqual(SessionDraftStore.load(date: date, sessionType: "evening").first?.sets.count, 1)
            let restored = SeanceViewModel(draftSessionType: "evening")
            restored.seanceData = data
            restored.restoreLogResults(from: data, serverSessionType: "evening", serverCompleted: false)
            let restoredPayload = try XCTUnwrap(restored.logResults["Bench Press"]?.sets.first)
            XCTAssertTrue(NSDictionary(dictionary: payload).isEqual(to: restoredPayload), tracking)
            XCTAssertEqual(SessionDraftStore.load(date: date, sessionType: "evening").first?.sets.count, 1)
        }
        for tracking in ["reps", "carry", "plyo", "time", "protocol"] {
            XCTAssertNil(PersistedSet.preserving([:], trackingType: tracking))
        }
        XCTAssertNil(PersistedSet.preserving(["weight": 0], trackingType: "reps"))
        XCTAssertNil(PersistedSet.preserving(["weight": 0, "distance_m": 0], trackingType: "carry"))
    }

    func testSpecializedCardInputsSurviveDebouncedSaveAndRecreation() async throws {
        let date = "card-test-\(UUID().uuidString)"
        let store = ExerciseDraftPersistence(date: date, sessionType: "morning", exerciseName: "Draft test")
        defer { store.clear() }
        let original = ExerciseViewModel(name: "Draft test", scheme: "1x5", weightData: nil, sessionDate: date)
        original.sets = [SetInput(weight: "12,5", reps: "6", duration: 45,
                                  durationLeft: 20, durationRight: 25, distance: "30",
                                  intensity: "42,5", rir: 2, rpe: 8, protocolCompleted: true)]
        // ExerciseViewModel's production draft save is debounced by 0.5 seconds.
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertNotNil(store.load())
        let recreated = ExerciseViewModel(name: "Draft test", scheme: "1x5", weightData: nil, sessionDate: date)
        recreated.initializeSets()
        let restored = try XCTUnwrap(recreated.sets.first)
        XCTAssertEqual(restored.weight, "12,5")
        XCTAssertEqual(restored.reps, "6")
        XCTAssertEqual(restored.duration, 45)
        XCTAssertEqual(restored.durationLeft, 20)
        XCTAssertEqual(restored.durationRight, 25)
        XCTAssertEqual(restored.distance, "30")
        XCTAssertEqual(restored.intensity, "42,5")
        XCTAssertEqual(restored.rir, 2)
        XCTAssertEqual(restored.rpe, 8)
        XCTAssertTrue(restored.protocolCompleted)
    }

    func testDraftCleanupRequiresMatchingCompletedSession() throws {
        let cases: [(draft: String, source: String, completed: Bool?, clears: Bool)] = [
            ("evening", "morning", true, false),
            ("morning", "evening", true, false),
            ("evening", "evening", false, false),
            ("evening", "evening", nil, false),
            ("evening", "evening", true, true),
            ("morning", "morning", true, true),
            ("bonus", "morning", true, false),
            ("bonus", "evening", true, false)
        ]
        for testCase in cases {
            let date = "draft-cleanup-test-\(UUID().uuidString)"
            defer { SessionDraftStore.clear(date: date, sessionType: testCase.draft) }
            let data = try APIService.decoder.decode(SeanceData.self, from: Fixtures.seanceDataJSON(
                todayDate: date, alreadyLogged: true
            ))
            SessionDraftStore.save(date: date, sessionType: testCase.draft, values: [
                PersistedExerciseLogResult(
                    name: "Bench Press", weight: 80, reps: "5", rpe: 7,
                    isSecond: testCase.draft == "evening", isBonus: testCase.draft == "bonus",
                    equipmentType: "barbell", painZone: "",
                    sets: [PersistedSet(weight: 80, reps: "5", rir: 3, rpe: 7)]
                )
            ])
            let vm = SeanceViewModel(draftSessionType: testCase.draft)
            vm.seanceData = data
            vm.restoreLogResults(from: data, serverSessionType: testCase.source,
                                 serverCompleted: testCase.completed)

            XCTAssertEqual(SessionDraftStore.hasDraft(date: date, sessionType: testCase.draft),
                           !testCase.clears, "\(testCase)")
            XCTAssertEqual(vm.logResults["Bench Press"]?.weight, 80)
            XCTAssertEqual(vm.logResults["Bench Press"]?.reps, "5")

            // A second restore must still find drafts preserved after a foreign/partial state.
            if !testCase.clears {
                vm.restoreLogResults(from: data, serverSessionType: testCase.draft, serverCompleted: nil)
                XCTAssertEqual(vm.logResults["Bench Press"]?.weight, 80)
                XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: testCase.draft))
            }
        }
    }

    func testRestoreLogResultsFromCache() async throws {
        let todayDate = "2026-03-15"
        let data = Fixtures.seanceDataJSON(
            today: "Push A",
            todayDate: todayDate,
            exerciseName: "Bench Press",
            historyDate: todayDate,   // history entry matches today → should restore
            historyWeight: 80.0,
            historyReps: "5"
        )
        let vm = makeViewModel(cacheData: data)

        await vm.load()

        XCTAssertNotNil(vm.logResults["Bench Press"],
                        "logResults should contain Bench Press because history[0].date == todayDate")
        let result = vm.logResults["Bench Press"]
        XCTAssertEqual(result?.weight, 80.0)
        XCTAssertEqual(result?.reps, "5")
    }

    func testNoRestoreIfHistoryOlderThanToday() async throws {
        let todayDate = "2026-03-15"
        let data = Fixtures.seanceDataJSON(
            today: "Push A",
            todayDate: todayDate,
            exerciseName: "Bench Press",
            historyDate: "2026-03-14",  // yesterday → should NOT restore
            historyWeight: 80.0,
            historyReps: "5"
        )
        let vm = makeViewModel(cacheData: data)

        await vm.load()

        XCTAssertNil(vm.logResults["Bench Press"],
                     "logResults should be empty when history date is older than todayDate")
    }

    func testLoadSetsIsLoadingFalseAfterCompletion() async throws {
        let todayDate = "2026-03-15"
        let data = Fixtures.seanceDataJSON(today: "Push A", todayDate: todayDate)
        let vm = makeViewModel(cacheData: data)

        XCTAssertFalse(vm.isLoading, "isLoading should start false")
        await vm.load()
        XCTAssertFalse(vm.isLoading, "isLoading should be false after load() completes")
    }

    func testNoErrorWhenCachePresent() async throws {
        let todayDate = "2026-03-15"
        let data = Fixtures.seanceDataJSON(today: "Push A", todayDate: todayDate)
        let vm = makeViewModel(cacheData: data)

        await vm.load()

        // Network will fail, but we have cached data so error should not be surfaced
        XCTAssertNil(vm.error, "error should remain nil when cached data is available")
        XCTAssertNotNil(vm.seanceData, "seanceData should be populated from cache")
    }

    func testRestoreMatinIgnoresEveningLogSameDay() async throws {
        // Racine 2026-07-20 : Bench loggué matin ET soir même jour. Backend trie
        // history par (date DESC, len(sets) DESC) — la row soir (plus riche) remonte
        // en tête. Sans le filtre session_type, restoreLogResults matin ramènerait
        // le log soir sous la clé matin, puis finish() le ré-posterait (crime 4).
        let todayDate = "2026-03-15"
        let json = """
        {
            "today": "Push A",
            "today_date": "\(todayDate)",
            "already_logged": false,
            "schedule": {"Lun": "Push A"},
            "full_program": {"Push A": {"Bench Press": "4x5-7"}},
            "weights": {
                "Bench Press": {
                    "current_weight": 195.0,
                    "last_reps": "6,5,3,3",
                    "history": [
                        {"date": "\(todayDate)", "weight": 195.0, "reps": "6,5,3,3",
                         "session_type": "evening",
                         "sets": [
                            {"weight": 195, "reps": "6"},
                            {"weight": 195, "reps": "5"},
                            {"weight": 195, "reps": "3"},
                            {"weight": 195, "reps": "3"}
                         ]},
                        {"date": "\(todayDate)", "weight": 185.0, "reps": "5,5,5",
                         "session_type": "morning"}
                    ]
                }
            },
            "week": 1,
            "inventory_types": {},
            "exercise_order": {}
        }
        """
        let vm = makeViewModel(cacheData: Data(json.utf8))
        await vm.load()

        let result = vm.logResults["Bench Press"]
        XCTAssertNotNil(result,
            "logResults doit contenir Bench Press (entry matin même jour existe)")
        XCTAssertEqual(result?.weight, 185.0,
            "restore matin doit prendre la row session_type=morning (185lbs), pas la row evening (195lbs) même si elle est en tête via tri (date DESC, len(sets) DESC)")
        XCTAssertEqual(result?.reps, "5,5,5")
    }
}
