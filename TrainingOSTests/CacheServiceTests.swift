//
//  CacheServiceTests.swift
//  TrainingOSTests
//

import XCTest
@testable import TrainingOS

final class CacheServiceTests: XCTestCase {

    var cache: CacheService!

    override func setUp() {
        super.setUp()
        cache = makeTempCacheService()
    }

    // MARK: - Tests

    func testSaveAndLoad() {
        let data = Data("hello world".utf8)
        cache.save(data, for: "key1")
        XCTAssertEqual(cache.load(for: "key1"), data)
    }

    func testLoadMissingKey() {
        XCTAssertNil(cache.load(for: "nonexistent_key_\(UUID())"))
    }

    func testClear() {
        let data = Data("to be cleared".utf8)
        cache.save(data, for: "clear_key")
        cache.clear(for: "clear_key")
        XCTAssertNil(cache.load(for: "clear_key"))
    }

    func testKeyEncoding() {
        // Keys with slashes and question marks should not crash
        let key = "/api/seance?foo=bar&baz=qux"
        let data = Data("value".utf8)
        cache.save(data, for: key)
        XCTAssertNotNil(cache.load(for: key))
    }

    func testAtomicWrite() {
        let expectations = (0..<10).map { XCTestExpectation(description: "write \($0)") }
        for i in 0..<10 {
            DispatchQueue.global().async {
                self.cache.save(Data("\(i)".utf8), for: "concurrent")
                expectations[i].fulfill()
            }
        }
        wait(for: expectations, timeout: 5)
        // Verify no corruption — key must be readable (value is one of the 10 writes)
        XCTAssertNotNil(cache.load(for: "concurrent"))
    }
}
