import XCTest
@testable import TrainingOS

/// Isolated UserDefaults and URLProtocol: no live API or workout-side effects.
@MainActor
final class OfflineCorrelationTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var queue: UserDefaultsSyncQueue!
    private var manager: SyncManager!
    private let key = OfflineOperationKey(rawValue: "opaque-operation-v1")
    private let bytes = Data(#"{ "date": "2026-01-01", "value": 1 }"#.utf8)

    override func setUp() async throws {
        suite = "correlation-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        queue = UserDefaultsSyncQueue(defaults: defaults)
        manager = SyncManager(queue: queue)
        manager.isOnlineProvider = { false }
        CorrelationURLProtocol.handler = { request in
            (200, Data("response".utf8))
        }
        CorrelationURLProtocol.sends = 0
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CorrelationURLProtocol.self]
        manager.urlSession = URLSession(configuration: config)
    }

    override func tearDown() async throws {
        manager.urlSession.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suite)
        manager = nil; queue = nil; defaults = nil
        CorrelationURLProtocol.handler = nil
    }

    private func enqueue(_ operation: OfflineOperationKey? = nil, body: Data? = nil,
                         path: String = "/correlation-test", method: String = "POST") throws -> OfflineMutationReceipt {
        try manager.enqueue(endpoint: path, method: method, payloadData: body ?? bytes,
                            operationKey: operation ?? key)
    }

    private func mutation() throws -> PendingMutation { try XCTUnwrap(queue.load().first) }
    private func recreated() -> UserDefaultsSyncQueue { UserDefaultsSyncQueue(defaults: defaults) }
    private func flush() async {
        manager.isOnlineProvider = { true }
        await manager.flushQueue()
    }
    private func terminal(_ state: OfflineMutationRecord.State) throws {
        _ = try enqueue()
        let m = try mutation()
        try queue.beginAttempt(m)
        try queue.finishAttempt(m, state: state, statusCode: state == .delivered ? 200 : nil)
    }

    func testLegacyJSONWithoutOperationKeyDecodes() throws {
        let old = PendingMutation(endpoint: "/legacy", payload: ["a": 1])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "operationKey")
        let restored = try JSONDecoder().decode(PendingMutation.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.operationKey)
        XCTAssertNil(restored.receipt)
        XCTAssertEqual(restored.id, old.id)
    }

    func testReceiptDedupeAndExactBytesSurviveRecreation() throws {
        XCTAssertEqual(queue.status(for: key), .notFound)
        let first = try enqueue()
        XCTAssertEqual(try enqueue(), first)
        // Semantic JSON equality is allowed, but never rewrites the original bytes.
        XCTAssertEqual(try enqueue(body: Data(#"{"value":1,"date":"2026-01-01"}"#.utf8)), first)
        XCTAssertEqual(queue.load().count, 1)
        XCTAssertEqual(try mutation().payloadData, bytes)
        XCTAssertEqual(try mutation().operationKey, key)
        XCTAssertEqual(recreated().status(for: key), .pending(first))
    }

    func testSameKeyChangedBodyPathOrMethodRefusedDifferentKeyAllowed() throws {
        let first = try enqueue()
        for (body, path, method) in [(Data("{}".utf8), "/correlation-test", "POST"),
                                     (bytes, "/other", "POST"), (bytes, "/correlation-test", "PUT")] {
            XCTAssertThrowsError(try enqueue(body: body, path: path, method: method)) { error in
                guard case OfflineCorrelationError.payloadConflict = error else { return XCTFail("Expected conflict") }
            }
        }
        let second = try enqueue(.init(rawValue: "opaque-v2"), body: Data("{}".utf8))
        XCTAssertNotEqual(first.mutationID, second.mutationID)
        XCTAssertEqual(queue.load().count, 2)
    }

    func testDeliveredReplayRecordsActualHTTPAndExactBytes() async throws {
        let receipt = try enqueue()
        let expected = bytes
        CorrelationURLProtocol.handler = { request in
            XCTAssertEqual(request.httpBody ?? request.bodyFromStream(), expected)
            return (204, Data())
        }
        await flush()
        guard case .delivered(let record) = recreated().status(for: key) else { return XCTFail("Not delivered") }
        XCTAssertEqual(record.receipt, receipt)
        XCTAssertEqual(record.statusCode, 204)
        XCTAssertTrue(queue.load().isEmpty)
        XCTAssertEqual(CorrelationURLProtocol.sends, 1)
        XCTAssertThrowsError(try enqueue())
    }

    func test409IsDiscardedNotDelivered() async throws {
        _ = try enqueue()
        CorrelationURLProtocol.handler = { _ in (409, Data()) }
        await flush()
        guard case .discarded(let record) = recreated().status(for: key) else { return XCTFail("409 must be discarded") }
        XCTAssertEqual(record.statusCode, 409)
        XCTAssertEqual(CorrelationURLProtocol.sends, 1)
        XCTAssertTrue(queue.load().isEmpty)
    }

    func testPermanentRejectionRetained() async throws {
        _ = try enqueue()
        CorrelationURLProtocol.handler = { _ in (422, Data()) }
        await flush()
        guard case .discarded(let record) = recreated().status(for: key) else { return XCTFail("Not discarded") }
        XCTAssertEqual(record.statusCode, 422)
        XCTAssertThrowsError(try enqueue())
    }

    func testRetryable500And429RemainPendingWithBackoff() async throws {
        for code in [500, 429] {
            let k = OfflineOperationKey(rawValue: "retry-\(code)")
            manager.isOnlineProvider = { false }
            let receipt = try enqueue(k)
            CorrelationURLProtocol.handler = { _ in (code, Data()) }
            await flush()
            XCTAssertEqual(recreated().status(for: k), .pending(receipt))
            let m = try XCTUnwrap(queue.load().first { $0.id == receipt.mutationID })
            XCTAssertEqual(m.retryCount, 1)
            XCTAssertNotNil(m.nextRetryAt)
        }
    }

    func testDefiniteOfflineRetriesButTimeoutBecomesUncertain() async throws {
        let first = try enqueue()
        CorrelationURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await flush()
        XCTAssertEqual(queue.status(for: key), .pending(first))
        manager.isOnlineProvider = { false }
        let other = OfflineOperationKey(rawValue: "timeout")
        _ = try enqueue(other)
        CorrelationURLProtocol.handler = { _ in throw URLError(.timedOut) }
        await flush()
        guard case .uncertain = recreated().status(for: other) else { return XCTFail("Ambiguous timeout") }
        let count = CorrelationURLProtocol.sends
        await manager.flushQueue()
        XCTAssertEqual(CorrelationURLProtocol.sends, count)
    }

    func testCrashAfterAttemptHasNoAutomaticReplay() async throws {
        _ = try enqueue()
        try queue.beginAttempt(try mutation())
        guard case .uncertain = recreated().status(for: key) else { return XCTFail("Attempt must fail closed") }
        await flush()
        XCTAssertEqual(CorrelationURLProtocol.sends, 0)
        guard case .uncertain = queue.status(for: key) else { return XCTFail("Not uncertain") }
        XCTAssertThrowsError(try enqueue())
        XCTAssertFalse(queue.load().isEmpty) // Diagnostic bytes retained.
    }

    func testCrashAfterTerminalBeforeRemovalNeverResends() async throws {
        for state in [OfflineMutationRecord.State.delivered, .discarded] {
            let k = OfflineOperationKey(rawValue: state.rawValue)
            manager.isOnlineProvider = { false }
            let receipt = try enqueue(k)
            let m = try XCTUnwrap(queue.load().first { $0.id == receipt.mutationID })
            try queue.beginAttempt(m)
            try queue.finishAttempt(m, state: state)
            queue.append(m) // Simulates terminal write durable, queue removal not durable.
            await flush()
            XCTAssertFalse(queue.load().contains { $0.id == m.id })
            if state == .delivered {
                guard case .delivered = recreated().status(for: k) else { return XCTFail("Lost delivery") }
            } else {
                guard case .discarded = recreated().status(for: k) else { return XCTFail("Lost rejection") }
            }
        }
        XCTAssertEqual(CorrelationURLProtocol.sends, 0)
    }

    func testDuplicateCorruptKeyPreservesBothAndNeverSends() async throws {
        _ = try enqueue()
        var other = try mutation()
        other.id = UUID()
        other.payloadData = Data("{}".utf8)
        queue.append(other)
        await flush()
        XCTAssertEqual(queue.load().count, 2)
        XCTAssertEqual(CorrelationURLProtocol.sends, 0)
        guard case .uncertain = recreated().status(for: key) else { return XCTFail("Collision not blocked") }
    }

    func testZombieBecomesUncertainNotDelivered() async throws {
        _ = try enqueue()
        var m = try mutation()
        m.retryCount = 5
        queue.update(m)
        await flush()
        XCTAssertTrue(queue.load().isEmpty)
        XCTAssertEqual(CorrelationURLProtocol.sends, 0)
        guard case .uncertain = recreated().status(for: key) else { return XCTFail("Purge isn't delivery") }
    }

    func testAllTerminalStatesBlockEnqueue() throws {
        for state in [OfflineMutationRecord.State.delivered, .discarded, .uncertain] {
            let k = OfflineOperationKey(rawValue: "terminal-\(state.rawValue)")
            let r = try enqueue(k)
            let m = try XCTUnwrap(queue.load().first { $0.id == r.mutationID })
            try queue.beginAttempt(m)
            try queue.finishAttempt(m, state: state)
            XCTAssertThrowsError(try enqueue(k))
        }
        XCTAssertTrue(queue.load().isEmpty)
    }

    func testMixedStatesRecreateExactly() throws {
        let p = try enqueue(.init(rawValue: "pending"))
        for state in [OfflineMutationRecord.State.delivered, .discarded, .uncertain] {
            let k = OfflineOperationKey(rawValue: state.rawValue)
            let r = try enqueue(k)
            let m = try XCTUnwrap(queue.load().first { $0.id == r.mutationID })
            try queue.beginAttempt(m)
            try queue.finishAttempt(m, state: state)
        }
        let restored = recreated()
        XCTAssertEqual(restored.status(for: p.operationKey), .pending(p))
        guard case .delivered = restored.status(for: .init(rawValue: "delivered")),
              case .discarded = restored.status(for: .init(rawValue: "discarded")),
              case .uncertain = restored.status(for: .init(rawValue: "uncertain")) else { return XCTFail("Lost terminal states") }
    }

    func testRetentionExpiresOnlyTerminalsWithoutPending() throws {
        try terminal(.delivered)
        let pending = try enqueue(.init(rawValue: "pending"))
        try queue.pruneTerminalHistory(now: Date().addingTimeInterval(29 * 86_400))
        guard case .delivered = queue.status(for: key) else { return XCTFail("Early expiry") }
        try queue.pruneTerminalHistory(now: Date().addingTimeInterval(31 * 86_400))
        XCTAssertEqual(queue.status(for: key), .notFound)
        XCTAssertEqual(queue.status(for: pending.operationKey), .pending(pending))
        XCTAssertEqual(queue.load().count, 1)
    }

    func testCorruptQueuePreservesTerminalAndRefusesOverwrite() throws {
        try terminal(.delivered)
        let corrupt = Data("broken".utf8)
        defaults.set(corrupt, forKey: "sync_queue_v2")
        guard case .delivered = recreated().status(for: key) else { return XCTFail("Lost separate terminal") }
        let unknown = OfflineOperationKey(rawValue: "unknown")
        guard case .uncertain = queue.status(for: unknown) else { return XCTFail("Corrupt queue isn't empty") }
        XCTAssertThrowsError(try enqueue(unknown))
        queue.append(PendingMutation(endpoint: "/legacy", payload: [:]))
        XCTAssertEqual(defaults.data(forKey: "sync_queue_v2"), corrupt)
    }

    func testCorruptHistoryBlocksReplayWithoutOverwriting() async throws {
        _ = try enqueue()
        let corrupt = Data("broken".utf8)
        defaults.set(corrupt, forKey: "sync_correlation_v1")
        await flush()
        XCTAssertEqual(CorrelationURLProtocol.sends, 0)
        XCTAssertEqual(defaults.data(forKey: "sync_correlation_v1"), corrupt)
        XCTAssertThrowsError(try enqueue())
    }

    func testCorrelatedAPIResponseQueuedAndNoOtherPreferenceWrites() async throws {
        defaults.set("untouched", forKey: "unrelated-recovery-sentinel")
        manager.isOnlineProvider = { true }
        let data = Data("online".utf8)
        let outcome = try await APIService.shared.offlinePostCorrelated(endpoint: "/correlation-test",
            payload: ["date": "2026-01-01"], operationKey: key, manager: manager) { request in
                XCTAssertEqual(String(data: request.httpBody!, encoding: .utf8), #"{"date":"2026-01-01"}"#)
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        guard case .response(let received) = outcome else { return XCTFail("No response") }
        XCTAssertEqual(received, data)
        manager.isOnlineProvider = { false }
        let pending = OfflineOperationKey(rawValue: "offline")
        let queued = try await APIService.shared.offlinePostCorrelated(endpoint: "/correlation-test",
            payload: [:], operationKey: pending, manager: manager) { _ in
                XCTFail("Offline must not send"); throw URLError(.notConnectedToInternet)
            }
        guard case .queued(let receipt) = queued else { return XCTFail("No receipt") }
        XCTAssertEqual(recreated().status(for: pending), .pending(receipt))
        XCTAssertEqual(defaults.string(forKey: "unrelated-recovery-sentinel"), "untouched")
        XCTAssertTrue(Set((defaults.persistentDomain(forName: suite) ?? [:]).keys).isSubset(of:
            ["sync_queue_v2", "sync_correlation_v1", "unrelated-recovery-sentinel"]))
    }

    func testLiveAttemptIsNotReconciledAsAbandoned() async throws {
        manager.isOnlineProvider = { true }
        let outcome = try await manager.postCorrelated(endpoint: "/correlation-test", method: "POST",
            payloadData: bytes, operationKey: key) { request in
                await self.manager.flushQueue()
                XCTAssertEqual(CorrelationURLProtocol.sends, 0)
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200,
                                               httpVersion: nil, headerFields: nil)!)
            }
        guard case .response = outcome,
              case .delivered = recreated().status(for: key) else { return XCTFail("Live attempt lost") }
    }

    func testLegacyUpdateCannotReplaceCorrelatedRequest() throws {
        _ = try enqueue()
        var changed = try mutation()
        changed.payloadData = Data("{}".utf8)
        queue.update(changed)
        XCTAssertEqual(try mutation().payloadData, bytes)
        XCTAssertThrowsError(try queue.beginAttempt(changed))
    }

    func testLegacyOfflinePostStillReturnsDataOrNilAndNoCorrelation() async throws {
        let expected = Data("legacy".utf8)
        let online = try await APIService.shared.offlinePost(endpoint: "/legacy-test", payload: [:],
            transport: { request in
                (expected, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }, enqueue: { _, _, _ in XCTFail("Online must not enqueue") })
        XCTAssertEqual(online, expected)
        let offline = try await APIService.shared.offlinePost(endpoint: "/legacy-test", payload: ["frozen": "value"],
            transport: { _ in throw URLError(.notConnectedToInternet) },
            enqueue: { path, method, payload in
                self.manager.enqueue(endpoint: path, method: method, payload: payload)
            })
        XCTAssertNil(offline)
        XCTAssertEqual(queue.load().count, 1)
        XCTAssertNil(try mutation().operationKey)
        XCTAssertEqual(try mutation().payloadDict?["frozen"] as? String, "value")
    }
}

private final class CorrelationURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var sends = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.sends += 1
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private extension URLRequest {
    func bodyFromStream() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}
