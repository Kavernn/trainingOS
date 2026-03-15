//
//  APIModelsTests.swift
//  TrainingOSTests
//

import XCTest
@testable import TrainingOS

final class APIModelsTests: XCTestCase {

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
}
