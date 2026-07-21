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
        let vm = SeanceViewModel()
        vm.cacheService = cache
        return vm
    }

    // MARK: - Tests

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
