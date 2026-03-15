//
//  TestHelpers.swift
//  TrainingOSTests
//

import Foundation
import SwiftData
@testable import TrainingOS

// MARK: - CacheService factory

func makeTempCacheService() -> CacheService {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("tests-cache-\(UUID().uuidString)", isDirectory: true)
    return CacheService(directory: tmp)
}

// MARK: - SwiftData in-memory container

func makeInMemoryContainer() throws -> ModelContainer {
    let schema = Schema([PendingMutation.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    static var responseData: Data = Data()
    static var responseStatusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MockURLProtocol.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func makeMockURLSession(statusCode: Int, data: Data = Data()) -> URLSession {
    MockURLProtocol.responseStatusCode = statusCode
    MockURLProtocol.responseData = data
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Fixture JSON helpers

enum Fixtures {
    /// Build a minimal SeanceData JSON blob for tests.
    static func seanceDataJSON(
        today: String = "Push A",
        todayDate: String,
        alreadyLogged: Bool = false,
        exerciseName: String = "Bench Press",
        historyDate: String? = nil,
        historyWeight: Double = 80.0,
        historyReps: String = "5"
    ) -> Data {
        let historyJSON: String
        if let hDate = historyDate {
            historyJSON = """
            [{"date": "\(hDate)", "weight": \(historyWeight), "reps": "\(historyReps)"}]
            """
        } else {
            historyJSON = "[]"
        }
        let json = """
        {
            "today": "\(today)",
            "today_date": "\(todayDate)",
            "already_logged": \(alreadyLogged ? "true" : "false"),
            "schedule": {"Lun": "\(today)"},
            "full_program": {"\(today)": {"\(exerciseName)": "4x5-7"}},
            "weights": {
                "\(exerciseName)": {
                    "current_weight": \(historyWeight),
                    "last_reps": "\(historyReps)",
                    "last_logged": "\(historyDate ?? todayDate)",
                    "history": \(historyJSON)
                }
            },
            "week": 1,
            "inventory_types": {},
            "exercise_order": {}
        }
        """
        return Data(json.utf8)
    }
}
