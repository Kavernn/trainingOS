//
//  SyncManagerTests.swift
//  TrainingOSTests
//

import XCTest
@testable import TrainingOS

@MainActor
final class SyncManagerTests: XCTestCase {

    var queue: UserDefaultsSyncQueue!
    var manager: SyncManager!

    override func setUp() async throws {
        try await super.setUp()
        // Isolated UserDefaults — never pollutes .standard
        let defaults = UserDefaults(suiteName: "test-sync-\(UUID().uuidString)")!
        queue = UserDefaultsSyncQueue(defaults: defaults)
        manager = SyncManager(queue: queue)
        manager.isOnlineProvider = { true }
        manager.urlSession = makeMockURLSession(statusCode: 200)
    }

    // MARK: - Tests

    func testEnqueueIncreasesPendingCount() {
        let before = manager.pendingCount
        manager.enqueue(endpoint: "/api/log", payload: ["exercise": "Bench Press"])
        XCTAssertEqual(manager.pendingCount, before + 1)
    }

    func testFlushSuccessMarksSynced() async throws {
        manager.urlSession = makeMockURLSession(statusCode: 200)
        manager.enqueue(endpoint: "/api/log", payload: ["exercise": "Squat"])
        await manager.flushQueue()
        XCTAssertEqual(manager.pendingCount, 0)
        XCTAssertTrue(queue.load().allSatisfy { $0.isSynced })
    }

    func testFlush409CountsAsSuccess() async throws {
        manager.urlSession = makeMockURLSession(statusCode: 409)
        manager.enqueue(endpoint: "/api/log", payload: ["exercise": "Deadlift"])
        await manager.flushQueue()
        XCTAssertEqual(manager.pendingCount, 0)
        XCTAssertTrue(queue.load().allSatisfy { $0.isSynced })
    }

    func testFlushFailureIncrementsRetry() async throws {
        manager.urlSession = makeMockURLSession(statusCode: 500)
        manager.enqueue(endpoint: "/api/log", payload: ["exercise": "OHP"])
        await manager.flushQueue()
        let all = queue.load()
        XCTAssertEqual(all.first?.retryCount, 1)
        XCTAssertFalse(all.first?.isSynced ?? true)
    }

    func testFlushIgnoresMutationsOver5Retries() async throws {
        var mutation = PendingMutation(endpoint: "/api/log", payload: ["exercise": "Curl"])
        mutation.retryCount = 5
        queue.append(mutation)
        manager.urlSession = makeMockURLSession(statusCode: 200)
        await manager.flushQueue()
        // Zombie is dropped entirely (not synced), not present in queue anymore
        let all = queue.load()
        XCTAssertFalse(all.contains { $0.id == mutation.id }, "Zombie should be purged")
    }

    func testPurgeOldSynced() async throws {
        var old = PendingMutation(endpoint: "/api/log", payload: [:])
        old.isSynced = true
        old.createdAt = Date().addingTimeInterval(-8 * 86_400)
        queue.append(old)
        manager.urlSession = makeMockURLSession(statusCode: 200)
        manager.enqueue(endpoint: "/api/log", payload: ["exercise": "Row"])
        await manager.flushQueue()
        let all = queue.load()
        XCTAssertFalse(all.contains { $0.id == old.id }, "Old synced mutation should have been purged")
    }
}
