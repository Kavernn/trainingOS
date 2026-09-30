import XCTest
@testable import TrainingOS

private actor CacheRefreshTransport {
    private(set) var requests: [URLRequest] = []
    private var continuations: [Int: CheckedContinuation<(Data, URLResponse), Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let index = requests.count
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
            let ready = waiters.filter { requests.count >= $0.0 }
            waiters.removeAll { requests.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForStarts(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func finish(_ index: Int, data: Data = Data("fresh".utf8), status: Int = 200) {
        let response = HTTPURLResponse(url: requests[index].url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        continuations.removeValue(forKey: index)?.resume(returning: (data, response))
    }
    func fail(_ index: Int, error: Error = URLError(.notConnectedToInternet)) {
        continuations.removeValue(forKey: index)?.resume(throwing: error)
    }
    func count() -> Int { requests.count }
}

@MainActor
final class DashboardCacheSingleFlightTests: XCTestCase {
    private var directory: URL!
    private var cache: CacheService!
    private var transport: CacheRefreshTransport!
    private var api: APIService!
    private var now = DateFormatter.isoDate.date(from: "2026-09-28")!
    private let stale = Data("stale-authorized".utf8)
    private let url = URL(string: "https://fixture.invalid/api/streak_data?date=2026-09-28&program_id=A")!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DashboardCacheSingleFlight-\(UUID())")
        cache = CacheService(directory: directory)
        transport = CacheRefreshTransport()
        let fixture = transport!
        api = APIService(dashboardDefaults: UserDefaults(suiteName: "DashboardCacheSingleFlight-\(UUID())")!,
                         cache: cache, cacheTransport: { try await fixture.send($0) }, cacheNow: { self.now })
    }

    private func seedStale(_ key: String) throws {
        // Real disk layout; a new isolated cache has no L1 entry. TTL is not changed.
        let expired = Date().addingTimeInterval(-7200).timeIntervalSince1970
        var bytes = Data()
        withUnsafeBytes(of: expired) { bytes.append(contentsOf: $0) }
        withUnsafeBytes(of: expired) { bytes.append(contentsOf: $0) }
        bytes.append(stale)
        let safe = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "?", with: "_")
        try bytes.write(to: directory.appendingPathComponent(safe + ".cache"), options: .atomic)
        XCTAssertNil(cache.load(for: key))
        XCTAssertEqual(cache.loadIncludingStale(for: key).data, stale)
    }

    func testThreeStaleCallersReturnBeforeTransportCompletes() async throws {
        try seedStale("streak_data")
        async let a = api.fetchWithCache(url: url, key: "streak_data")
        async let b = api.fetchWithCache(url: url, key: "streak_data")
        async let c = api.fetchWithCache(url: url, key: "streak_data")
        let values = try await [a, b, c]
        XCTAssertEqual(values, [stale, stale, stale])
        await transport.waitForStarts(1)
        let count = await transport.count()
        XCTAssertEqual(count, 1)
        print("STALE_CACHE_MEASUREMENT callers=3 stale_returns=3 blocked_refreshes=\(count)")
        let task = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
        await transport.finish(0)
        await task.value
        XCTAssertEqual(cache.load(for: "streak_data"), Data("fresh".utf8))
        XCTAssertNil(api.cacheRefreshTask(for: "streak_data"))
        let refreshed = try await api.fetchWithCache(url: url, key: "streak_data")
        XCTAssertEqual(refreshed, Data("fresh".utf8))
        let finalCount = await transport.count()
        XCTAssertEqual(finalCount, 1)
    }

    func testFreshCacheStartsNoRefresh() async throws {
        cache.save(stale, for: "streak_data")
        async let a = api.fetchWithCache(url: url, key: "streak_data")
        async let b = api.fetchWithCache(url: url, key: "streak_data")
        async let c = api.fetchWithCache(url: url, key: "streak_data")
        let values = try await [a, b, c]
        XCTAssertEqual(values, [stale, stale, stale])
        let count = await transport.count()
        XCTAssertEqual(count, 0)
    }

    func testDistinctKeysStartIndependentRefreshes() async throws {
        try seedStale("streak_data"); try seedStale("readiness")
        let first = try await api.fetchWithCache(url: url, key: "streak_data")
        let second = try await api.fetchWithCache(url: URL(string: "https://fixture.invalid/api/readiness")!, key: "readiness")
        XCTAssertEqual(first, stale); XCTAssertEqual(second, stale)
        await transport.waitForStarts(2)
        let count = await transport.count()
        XCTAssertEqual(count, 2)
        let firstTask = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
        let secondTask = try XCTUnwrap(api.cacheRefreshTask(for: "readiness"))
        await transport.fail(0); await transport.fail(1)
        await firstTask.value; await secondTask.value
    }

    func testMissingCacheAwaitsNormalTransport() async throws {
        let task = Task { try await self.api.fetchWithCache(url: self.url, key: "streak_data") }
        await transport.waitForStarts(1)
        XCTAssertNil(cache.loadIncludingStale(for: "streak_data").data)
        await transport.finish(0)
        let result = try await task.value
        XCTAssertEqual(result, Data("fresh".utf8))
        XCTAssertEqual(cache.load(for: "streak_data"), result)
    }

    func testFailuresCleanUpAndLaterCallCanRetry() async throws {
        try seedStale("streak_data")
        for index in 0..<3 {
            let result = try await api.fetchWithCache(url: url, key: "streak_data")
            XCTAssertEqual(result, stale)
            let task = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
            await transport.waitForStarts(index + 1)
            if index == 0 { await transport.fail(index) }
            else if index == 1 { await transport.fail(index, error: CancellationError()) }
            else { await transport.finish(index, status: 500) }
            await task.value
            XCTAssertNil(api.cacheRefreshTask(for: "streak_data"))
            XCTAssertNil(cache.load(for: "streak_data"))
            XCTAssertEqual(cache.loadIncludingStale(for: "streak_data").data, stale)
        }
        let count = await transport.count()
        XCTAssertEqual(count, 3, "Retries require another caller; no automatic loop")
    }

    func testInvalidationABALateTaskCannotWriteOrRemoveReplacement() async throws {
        try seedStale("streak_data")
        _ = try await api.fetchWithCache(url: url, key: "streak_data")
        let first = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
        await transport.waitForStarts(1)
        cache.clear(for: "streak_data")
        try seedStale("streak_data")
        _ = try await api.fetchWithCache(url: url, key: "streak_data")
        let second = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
        await transport.waitForStarts(2)
        XCTAssertTrue(first.isCancelled)
        // This controlled transport deliberately ignores cancellation.
        await transport.finish(0, data: Data("obsolete".utf8))
        await first.value
        XCTAssertNotNil(api.cacheRefreshTask(for: "streak_data"))
        XCTAssertFalse(second.isCancelled)
        XCTAssertNil(cache.load(for: "streak_data"))
        XCTAssertEqual(cache.loadIncludingStale(for: "streak_data").data, stale)
        _ = try await api.fetchWithCache(url: url, key: "streak_data")
        let count = await transport.count()
        XCTAssertEqual(count, 2)
        await transport.finish(1, data: Data("replacement".utf8))
        await second.value
        XCTAssertEqual(cache.load(for: "streak_data"), Data("replacement".utf8))
        XCTAssertNil(api.cacheRefreshTask(for: "streak_data"))
    }

    func testPrefixInvalidationRejectsOldRefreshWithoutAnotherCaller() async throws {
        let key = "health_weekly_7"
        try seedStale(key)
        _ = try await api.fetchWithCache(url: url, key: key)
        let task = try XCTUnwrap(api.cacheRefreshTask(for: key))
        await transport.waitForStarts(1)
        cache.clear(prefix: "health_weekly")
        await transport.finish(0)
        await task.value
        XCTAssertNil(cache.loadIncludingStale(for: key).data)
        XCTAssertNil(api.cacheRefreshTask(for: key))
    }

    func testCancellingStaleCallerDoesNotCancelOwnedRefresh() async throws {
        try seedStale("streak_data")
        let caller = Task { try await self.api.fetchWithCache(url: self.url, key: "streak_data") }
        let result = try await caller.value
        XCTAssertEqual(result, stale)
        await transport.waitForStarts(1)
        let task = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
        caller.cancel()
        let other = try await api.fetchWithCache(url: url, key: "streak_data")
        XCTAssertEqual(other, stale)
        XCTAssertFalse(task.isCancelled)
        await transport.finish(0)
        await task.value
        XCTAssertEqual(cache.load(for: "streak_data"), Data("fresh".utf8))
        let count = await transport.count()
        XCTAssertEqual(count, 1)
    }

    func testMidnightRejectsOldResponseAndPermitsNewFlight() async throws {
        try seedStale("streak_data")
        _ = try await api.fetchWithCache(url: url, key: "streak_data")
        let old = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
        await transport.waitForStarts(1)
        now = now.addingTimeInterval(86400)
        await transport.finish(0, data: Data("yesterday".utf8))
        await old.value
        XCTAssertNil(cache.load(for: "streak_data"))
        XCTAssertNil(api.cacheRefreshTask(for: "streak_data"))
        let tomorrowURL = URL(string: "https://fixture.invalid/api/streak_data?date=2026-09-29&program_id=A")!
        _ = try await api.fetchWithCache(url: tomorrowURL, key: "streak_data")
        let new = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
        await transport.waitForStarts(2)
        await transport.finish(1, data: Data("today".utf8))
        await new.value
        XCTAssertEqual(cache.load(for: "streak_data"), Data("today".utf8))
    }

    func testDifferentURLContextsNeverShareAFlight() async throws {
        try seedStale("streak_data")
        _ = try await api.fetchWithCache(url: url, key: "streak_data")
        let old = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
        await transport.waitForStarts(1)
        let otherURL = URL(string: "https://fixture.invalid/api/streak_data?date=2026-09-29&program_id=B")!
        _ = try await api.fetchWithCache(url: otherURL, key: "streak_data")
        let new = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
        await transport.waitForStarts(2)
        await transport.finish(1, data: Data("context B".utf8))
        await new.value
        await transport.finish(0, data: Data("context A".utf8))
        await old.value
        XCTAssertEqual(cache.load(for: "streak_data"), Data("context B".utf8))
        XCTAssertNil(api.cacheRefreshTask(for: "streak_data"))
    }

    func testProgramInvalidationDiscardsOldGeneration() async throws {
        try seedStale("streak_data")
        _ = try await api.fetchWithCache(url: url, key: "streak_data")
        let old = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
        await transport.waitForStarts(1)
        api.invalidateDashboardContext()
        _ = try await api.fetchWithCache(url: url, key: "streak_data")
        let new = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
        await transport.waitForStarts(2)
        await transport.finish(0)
        await old.value
        XCTAssertNotNil(api.cacheRefreshTask(for: "streak_data"))
        XCTAssertNil(cache.load(for: "streak_data"))
        await transport.finish(1, data: Data("new generation".utf8))
        await new.value
        XCTAssertEqual(cache.load(for: "streak_data"), Data("new generation".utf8))
    }

    func testExplicitRefreshStartsItsOwnTransportAndObsoletesStaleFlight() async throws {
        try seedStale("streak_data")
        _ = try await api.fetchWithCache(url: url, key: "streak_data")
        let old = try XCTUnwrap(api.cacheRefreshTask(for: "streak_data"))
        await transport.waitForStarts(1)
        var requests = 0
        let loaded = await api.fetchDashboard(mode: .refresh, now: { self.now }, transport: { _ in
            requests += 1
            throw URLError(.cancelled)
        })
        XCTAssertFalse(loaded)
        XCTAssertEqual(requests, 1, "Explicit refresh cannot join a stale background task")
        await transport.finish(0)
        await old.value
        XCTAssertNil(cache.load(for: "streak_data"))
        XCTAssertNil(api.cacheRefreshTask(for: "streak_data"))
    }

    func testAbsentCacheRemainsForegroundAndRejectsPostInvalidationWrite() async throws {
        let task = Task { try await self.api.fetchWithCache(url: self.url, key: "streak_data") }
        await transport.waitForStarts(1)
        cache.clear(for: "streak_data")
        await transport.finish(0)
        let result = try await task.value
        XCTAssertEqual(result, Data("fresh".utf8))
        XCTAssertNil(cache.load(for: "streak_data"))
    }
}
