//
//  SyncManagerTests.swift
//  TrainingOSTests
//

import XCTest
import SwiftData
@testable import TrainingOS

@MainActor
final class SyncManagerTests: XCTestCase {

    var container: ModelContainer!
    var manager: SyncManager!

    override func setUp() async throws {
        try await super.setUp()
        container = try makeInMemoryContainer()
        manager = SyncManager()
        manager.setup(container: container)
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
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PendingMutation>()
        let all = try context.fetch(descriptor)
        XCTAssertTrue(all.allSatisfy { $0.isSynced })
    }

    func testFlush409CountsAsSuccess() async throws {
        manager.urlSession = makeMockURLSession(statusCode: 409)
        manager.enqueue(endpoint: "/api/log", payload: ["exercise": "Deadlift"])

        await manager.flushQueue()

        XCTAssertEqual(manager.pendingCount, 0)
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PendingMutation>()
        let all = try context.fetch(descriptor)
        XCTAssertTrue(all.allSatisfy { $0.isSynced })
    }

    func testFlushFailureIncrementsRetry() async throws {
        manager.urlSession = makeMockURLSession(statusCode: 500)
        manager.enqueue(endpoint: "/api/log", payload: ["exercise": "OHP"])

        await manager.flushQueue()

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PendingMutation>()
        let all = try context.fetch(descriptor)
        XCTAssertEqual(all.first?.retryCount, 1)
        XCTAssertFalse(all.first?.isSynced ?? true)
    }

    func testFlushIgnoresMutationsOver5Retries() async throws {
        // Insert a mutation with retryCount = 5 directly
        let context = ModelContext(container)
        let mutation = PendingMutation(endpoint: "/api/log", payload: ["exercise": "Curl"])
        mutation.retryCount = 5
        context.insert(mutation)
        try context.save()

        manager.urlSession = makeMockURLSession(statusCode: 200)
        await manager.flushQueue()

        // Mutation with retryCount=5 is excluded from flush predicate → still not synced
        let all = try context.fetch(FetchDescriptor<PendingMutation>())
        XCTAssertFalse(all.first?.isSynced ?? true)
    }

    func testPurgeOldSynced() async throws {
        // Insert a synced mutation older than 7 days
        let context = ModelContext(container)
        let old = PendingMutation(endpoint: "/api/log", payload: [:])
        old.isSynced = true
        old.createdAt = Date().addingTimeInterval(-8 * 86_400)
        context.insert(old)
        try context.save()

        // Also enqueue a fresh one so flushQueue has work to do and runs purge
        manager.urlSession = makeMockURLSession(statusCode: 200)
        manager.enqueue(endpoint: "/api/log", payload: ["exercise": "Row"])
        await manager.flushQueue()

        let all = try context.fetch(FetchDescriptor<PendingMutation>())
        XCTAssertFalse(all.contains { $0.id == old.id }, "Old synced mutation should have been purged")
    }
}
