//
//  APIModelsTests.swift
//  TrainingOSTests
//

import XCTest
@testable import TrainingOS

final class APIModelsTests: XCTestCase {

    // MARK: - Dashboard muscle metadata

    func testDashboardMuscleMetadataDecoding() throws {
        let json = dashboardJSON(extraFields: """
            "exercise_muscle_metadata": {
                "Bench Press": {
                    "muscle_group": "Pectoraux",
                    "muscle_specific": "Pectoral majeur — chef sternal",
                    "secondary_muscles": ["Triceps", "Deltoïde antérieur"],
                    "muscles": ["chest", "triceps", "front_delts"]
                }
            },
            """)

        let decoded = try JSONDecoder().decode(DashboardData.self, from: json)
        let metadata = try XCTUnwrap(decoded.exerciseMuscleMetadata["Bench Press"])

        XCTAssertEqual(metadata.muscleGroup, "Pectoraux")
        XCTAssertEqual(metadata.muscleSpecific, "Pectoral majeur — chef sternal")
        XCTAssertEqual(metadata.secondaryMuscles, ["Triceps", "Deltoïde antérieur"])
        XCTAssertEqual(metadata.legacyMuscles, ["chest", "triceps", "front_delts"])
        XCTAssertEqual(decoded.fullProgram["Push A"]?["Bench Press"]?.value, "4x5-7")
    }

    func testDashboardMuscleMetadataDefaultsWhenAbsent() throws {
        let decoded = try JSONDecoder().decode(DashboardData.self, from: dashboardJSON())
        XCTAssertTrue(decoded.exerciseMuscleMetadata.isEmpty)
    }

    func testExerciseMuscleMetadataDefaultsWhenInternalFieldsAreAbsent() throws {
        let decoded = try JSONDecoder().decode(
            ExerciseMuscleMetadata.self,
            from: Data(#"{"muscle_group":"Dos"}"#.utf8)
        )

        XCTAssertEqual(decoded.muscleGroup, "Dos")
        XCTAssertNil(decoded.muscleSpecific)
        XCTAssertTrue(decoded.secondaryMuscles.isEmpty)
        XCTAssertTrue(decoded.legacyMuscles.isEmpty)
    }

    // MARK: - SeanceData

    func testSeanceDataDecoding() throws {
        let json = Fixtures.seanceDataJSON(
            today: "Push A",
            todayDate: "2026-03-15",
            exerciseName: "Bench Press"
        )
        let decoded = try JSONDecoder().decode(SeanceData.self, from: json)
        XCTAssertEqual(decoded.today, "Push A")
        XCTAssertEqual(decoded.todayDate, "2026-03-15")
        XCTAssertFalse(decoded.alreadyLogged)
        XCTAssertEqual(decoded.week, 1)
        XCTAssertNotNil(decoded.fullProgram["Push A"])
    }

    // MARK: - SafeString

    func testSafeStringFromString() throws {
        let json = Data("\"foo\"".utf8)
        let s = try JSONDecoder().decode(SafeString.self, from: json)
        XCTAssertEqual(s.value, "foo")
    }

    func testSafeStringFromNull() throws {
        let json = Data("null".utf8)
        let s = try JSONDecoder().decode(SafeString.self, from: json)
        XCTAssertEqual(s.value, "")
    }

    func testSafeStringFromArray() throws {
        let json = Data("[\"a\",\"b\"]".utf8)
        let s = try JSONDecoder().decode(SafeString.self, from: json)
        XCTAssertEqual(s.value, "a, b")
    }

    // MARK: - WeightData

    func testWeightDataDecoding() throws {
        let json = """
        {
            "current_weight": 80.0,
            "last_reps": "5",
            "last_logged": "2026-03-14",
            "history": [
                {"date": "2026-03-14", "weight": 80.0, "reps": "5x5", "1rm": 90.0}
            ]
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WeightData.self, from: json)
        XCTAssertEqual(decoded.currentWeight, 80.0)
        XCTAssertEqual(decoded.history?.first?.date, "2026-03-14")
        XCTAssertEqual(decoded.history?.first?.oneRM, 90.0)
    }

    // MARK: - PagedResponse

    func testPagedResponseDecoding() throws {
        let json = """
        {
            "items": [],
            "offset": 0,
            "limit": 20,
            "total": 42,
            "has_more": true,
            "next_offset": 20
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PagedResponse<HIITEntry>.self, from: json)
        XCTAssertTrue(decoded.hasMore)
        XCTAssertEqual(decoded.nextOffset, 20)
        XCTAssertEqual(decoded.total, 42)
        XCTAssertTrue(decoded.items.isEmpty)
    }

    func testMoodRPEResponseDecoding() throws {
        let json = Data(#"{"rpe_by_date":{"2026-09-08":7.5,"2026-09-06":8.0}}"#.utf8)
        let decoded = try JSONDecoder().decode(MoodRPEResponse.self, from: json)

        XCTAssertEqual(decoded.rpeByDate["2026-09-08"], 7.5)
        XCTAssertEqual(decoded.rpeByDate["2026-09-06"], 8.0)
    }

    func testMoodRPEHTTPFailureReturnsEmptyWithoutThrowing() async {
        let session = makeMockURLSession(statusCode: 500, data: Data(#"{"error":"unavailable"}"#.utf8))

        let result = await APIService.shared.fetchMoodRPE(session: session)

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Stats cockpit contract

    func testStatsCockpitDecodesCompleteContractAndPreservesCivilDatesAndZero() throws {
        let decoded = try JSONDecoder().decode(StatsCockpitResponse.self, from: statsCockpitJSON())

        XCTAssertEqual(decoded.asOf, "2026-09-30")
        XCTAssertEqual(decoded.progression.baselineWindow.start, "2026-08-02")
        XCTAssertEqual(decoded.progression.recentWindow.end, "2026-09-30")
        XCTAssertEqual(decoded.progression.statusCounts.insufficientData, 1)
        XCTAssertEqual(decoded.progression.comparisons.count, 1)
        XCTAssertEqual(decoded.progression.comparisons[0].status, .improving)
        XCTAssertEqual(decoded.progression.comparisons[0].relativeDelta, 0.1)
        XCTAssertEqual(decoded.progression.comparisons[0].insufficiencyReason, nil)
        XCTAssertEqual(decoded.trainingLoad.summary.tonnage.coverage, .complete)
        XCTAssertEqual(decoded.trainingLoad.summary.tonnage.value, 0.0)
        XCTAssertEqual(decoded.trainingLoad.weekly[0].weekStart, "2026-09-28")
        XCTAssertEqual(decoded.muscles.coverage.unmappedExposureCount, 1)
        XCTAssertEqual(decoded.muscles.workloads[0].lastExposureDate, "2026-09-30")
        XCTAssertEqual(decoded.dataQuality.adapter.knownDeloadExposureCount, 0)
    }

    func testStatsCockpitDecodesAllKnownStatusesReasonsAndCoverage() throws {
        let json = statsCockpitJSON(
            comparison: """
            {"exercise_name":"Squat","tracking_type":"reps","status":"insufficientData","baseline_window":{"start":"2026-08-02","end":"2026-08-31"},"recent_window":{"start":"2026-09-01","end":"2026-09-30"},"baseline_best_e1rm":null,"recent_best_e1rm":null,"absolute_delta":null,"relative_delta":null,"baseline_exposure_count":1,"recent_exposure_count":0,"baseline_used_legacy_fallback":false,"recent_used_legacy_fallback":false,"insufficiency_reason":"insufficientBothWindows"}
            """,
            tonnageCoverage: "unavailable",
            tonnageValue: "null",
            attention: """
            {"kind":"noRecentImprovement","exercise_name":"Squat","observation_window":{"start":"2026-09-01","end":"2026-09-30"},"last_exposure_date":"2026-09-10","days_since_last_exposure":20,"valid_exposure_count":3,"covered_days":21,"latest_best_e1rm":100.0}
            """
        )
        let decoded = try JSONDecoder().decode(StatsCockpitResponse.self, from: json)
        XCTAssertEqual(decoded.progression.comparisons[0].status, .insufficientData)
        XCTAssertEqual(decoded.progression.comparisons[0].insufficiencyReason, .insufficientBothWindows)
        XCTAssertEqual(decoded.progression.attention[0].kind, .noRecentImprovement)
        XCTAssertNil(decoded.trainingLoad.summary.tonnage.value)
        XCTAssertEqual(decoded.trainingLoad.summary.tonnage.coverage, .unavailable)
    }

    func testStatsCockpitPreservesUnknownEnumValues() throws {
        let json = statsCockpitJSON(
            comparison: """
            {"exercise_name":"Bench","tracking_type":"futureTracking","status":"rapidlyImproving","baseline_window":{"start":"2026-08-02","end":"2026-08-31"},"recent_window":{"start":"2026-09-01","end":"2026-09-30"},"baseline_best_e1rm":100.0,"recent_best_e1rm":110.0,"absolute_delta":10.0,"relative_delta":0.1,"baseline_exposure_count":2,"recent_exposure_count":2,"baseline_used_legacy_fallback":false,"recent_used_legacy_fallback":false,"insufficiency_reason":"futureReason"}
            """,
            tonnageCoverage: "futureCoverage"
        )
        let decoded = try JSONDecoder().decode(StatsCockpitResponse.self, from: json)
        XCTAssertEqual(decoded.progression.comparisons[0].status, .unknown("rapidlyImproving"))
        XCTAssertEqual(decoded.progression.comparisons[0].insufficiencyReason, .unknown("futureReason"))
        XCTAssertEqual(decoded.trainingLoad.summary.tonnage.coverage, .unknown("futureCoverage"))
    }

    func testStatsCockpitRejectsMissingRequiredKeyAndInvalidType() throws {
        let complete = String(decoding: statsCockpitJSON(), as: UTF8.self)
        let missing = complete.replacingOccurrences(of: "\"data_quality\":", with: "\"removed_data_quality\":")
        XCTAssertThrowsError(try JSONDecoder().decode(StatsCockpitResponse.self, from: Data(missing.utf8)))

        let invalid = complete.replacingOccurrences(of: "\"comparison_window_days\":30", with: "\"comparison_window_days\":\"30\"")
        XCTAssertThrowsError(try JSONDecoder().decode(StatsCockpitResponse.self, from: Data(invalid.utf8)))
    }

    private func statsCockpitJSON(
        comparison: String = """
        {"exercise_name":"Bench Press","tracking_type":"reps","status":"improving","baseline_window":{"start":"2026-08-02","end":"2026-08-31"},"recent_window":{"start":"2026-09-01","end":"2026-09-30"},"baseline_best_e1rm":100.0,"recent_best_e1rm":110.0,"absolute_delta":10.0,"relative_delta":0.1,"baseline_exposure_count":2,"recent_exposure_count":2,"baseline_used_legacy_fallback":false,"recent_used_legacy_fallback":false,"insufficiency_reason":null}
        """,
        tonnageCoverage: String = "complete",
        tonnageValue: String = "0.0",
        attention: String = ""
    ) -> Data {
        Data("""
        {"as_of":"2026-09-30","progression":{"comparison_window_days":30,"baseline_window":{"start":"2026-08-02","end":"2026-08-31"},"recent_window":{"start":"2026-09-01","end":"2026-09-30"},"status_counts":{"improving":1,"stable":0,"declining":0,"insufficient_data":1},"comparisons":[(comparison)],"top_movers":[],"attention":[(attention)]},"training_load":{"period":{"start":"2026-09-01","end":"2026-09-30"},"summary":{"period":{"start":"2026-09-01","end":"2026-09-30"},"exposure_count":1,"session_count":1,"active_day_count":1,"reps_exposure_count":1,"valid_reps_set_count":1,"tonnage":{"value":(tonnageValue),"applicable_exposure_count":1,"calculable_exposure_count":1,"coverage":"(tonnageCoverage)"}},"weekly":[{"week_start":"2026-09-28","week_end":"2026-10-04","covered_window":{"start":"2026-09-28","end":"2026-09-30"},"is_partial":true,"exposure_count":0,"session_count":0,"active_day_count":0,"reps_exposure_count":0,"valid_reps_set_count":0,"tonnage":{"value":null,"applicable_exposure_count":0,"calculable_exposure_count":0,"coverage":"unavailable"}}]},"muscles":{"period":{"start":"2026-09-01","end":"2026-09-30"},"coverage":{"total_exposure_count":1,"mapped_exposure_count":0,"unmapped_exposure_count":1,"reps_exposure_count":1,"mapped_reps_exposure_count":0},"workloads":[{"muscle":"Chest","direct_set_count":0,"indirect_set_count":0,"direct_exposure_count":0,"indirect_exposure_count":0,"session_count":0,"active_day_count":0,"last_exposure_date":"2026-09-30"}]},"data_quality":{"requested_raw_period":{"start":"2026-08-02","end":"2026-09-30"},"adapter":{"queried_exposure_count":1,"analytics_exposure_count":1,"invalid_row_count":0,"missing_tracking_type_count":0,"missing_muscle_mapping_count":1,"legacy_strength_fallback_count":0,"known_deload_exposure_count":0}}}
        """.utf8)
    }

    private func dashboardJSON(extraFields: String = "") -> Data {
        Data("""
        {
            "today": "Push A",
            "week": 1,
            "today_date": "2026-03-15",
            "schedule": {},
            "sessions": {},
            "goals": {},
            "full_program": {"Push A": {"Bench Press": "4x5-7"}},
            \(extraFields)
            "nutrition_totals": {},
            "profile": {}
        }
        """.utf8)
    }
}
