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

    func testFlush409IsDiscardedRatherThanDelivered() async throws {
        manager.urlSession = makeMockURLSession(statusCode: 409)
        manager.enqueue(endpoint: "/api/log", payload: ["exercise": "Deadlift"])
        await manager.flushQueue()
        XCTAssertEqual(manager.pendingCount, 0)
        XCTAssertTrue(queue.load().allSatisfy { $0.isSynced })
        // isSynced historically means "retired", including rejection. The toast
        // proves the discarded branch ran; the old assertion couldn't distinguish it.
        XCTAssertTrue(manager.offlineToast?.contains("409") == true)
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

    // MARK: - Dédup /api/session/edit (last-write-wins par date + session_type)

    func testSessionEditDedupsSameDateAndType() {
        manager.isOnlineProvider = { false }
        manager.enqueue(endpoint: "/api/session/edit",
                        payload: ["date": "2026-10-20", "session_type": "morning", "rpe": 7])
        manager.enqueue(endpoint: "/api/session/edit",
                        payload: ["date": "2026-10-20", "session_type": "morning", "rpe": 9])
        let pending = queue.load().filter { !$0.isSynced }
        XCTAssertEqual(pending.count, 1, "Dédup last-write-wins : une seule mutation attendue")
        let payload = try? JSONSerialization.jsonObject(with: pending[0].payloadData) as? [String: Any]
        XCTAssertEqual(payload?["rpe"] as? Int, 9, "Dernier payload gagne")
        XCTAssertEqual(manager.pendingCount, 1)
    }

    func testSessionEditDoesNotDedupDifferentDate() {
        manager.isOnlineProvider = { false }
        manager.enqueue(endpoint: "/api/session/edit",
                        payload: ["date": "2026-10-20", "session_type": "morning", "rpe": 7])
        manager.enqueue(endpoint: "/api/session/edit",
                        payload: ["date": "2026-10-21", "session_type": "morning", "rpe": 7])
        XCTAssertEqual(queue.load().filter { !$0.isSynced }.count, 2,
                       "Dates différentes → mutations distinctes")
    }

    func testSessionEditDoesNotDedupDifferentSessionType() {
        manager.isOnlineProvider = { false }
        manager.enqueue(endpoint: "/api/session/edit",
                        payload: ["date": "2026-10-20", "session_type": "morning", "rpe": 7])
        manager.enqueue(endpoint: "/api/session/edit",
                        payload: ["date": "2026-10-20", "session_type": "evening", "rpe": 8])
        XCTAssertEqual(queue.load().filter { !$0.isSynced }.count, 2,
                       "session_type différents sur même date → 2 mutations")
    }

    func testSessionEditDoesNotDedupOtherEndpoints() {
        manager.isOnlineProvider = { false }
        manager.enqueue(endpoint: "/api/log",
                        payload: ["date": "2026-10-20", "exercise": "Bench Press"])
        manager.enqueue(endpoint: "/api/log",
                        payload: ["date": "2026-10-20", "exercise": "Bench Press"])
        XCTAssertEqual(queue.load().filter { !$0.isSynced }.count, 2,
                       "Dédup limité à /api/session/edit — /api/log est incrémental")
    }

    func testSessionEditDedupPreservesSyncedHistory() {
        manager.isOnlineProvider = { false }
        var synced = PendingMutation(endpoint: "/api/session/edit",
                                     payload: ["date": "2026-10-20", "session_type": "morning", "rpe": 6])
        synced.isSynced = true
        queue.append(synced)
        manager.enqueue(endpoint: "/api/session/edit",
                        payload: ["date": "2026-10-20", "session_type": "morning", "rpe": 9])
        let all = queue.load()
        XCTAssertEqual(all.count, 2, "Mutation synced historique préservée")
        XCTAssertTrue(all.contains { $0.id == synced.id }, "Mutation synced non supprimée")
    }
}
