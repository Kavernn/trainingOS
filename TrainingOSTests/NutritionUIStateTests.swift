import XCTest
@testable import TrainingOS

@MainActor
final class NutritionUIStateTests: XCTestCase {
    private func payload(_ name: String) -> Data {
        Data("{\"entries\":[{\"id\":\"1\",\"name\":\"\(name)\"}],\"history\":[]}".utf8)
    }
    private func response(_ request: URLRequest, _ data: Data, status: Int = 200) -> (Data, URLResponse) {
        (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    private func model(fetch: @escaping (URLRequest) async throws -> (Data, URLResponse),
                       remove: @escaping (String) async throws -> Void = { _ in }) -> NutritionViewModel {
        NutritionViewModel(fetch: fetch, remove: remove, fetchEnergy: { throw URLError(.notConnectedToInternet) })
    }

    func testLateInitialResponseCannotOverwriteNewRefresh() async {
        let started = expectation(description: "first request suspended")
        var first: CheckedContinuation<(Data, URLResponse), Error>?
        var requestA: URLRequest?
        var count = 0
        let vm = model { request in
            guard request.url!.path.contains("nutrition_data") else { throw URLError(.timedOut) }
            count += 1
            if count == 1 {
                requestA = request
                return try await withCheckedThrowingContinuation {
                    first = $0
                    started.fulfill()
                }
            }
            return self.response(request, self.payload("new"))
        }
        let a = Task { await vm.loadData() }
        await fulfillment(of: [started], timeout: 2)
        await vm.loadData(days: 30)
        XCTAssertEqual(vm.entries.first?.name, "new")
        first!.resume(returning: response(requestA!, payload("old")))
        await a.value
        XCTAssertEqual(vm.entries.first?.name, "new")
        XCTAssertFalse(vm.isLoading)
    }

    func testFailedDeleteRetainsEntryAndErrorWithoutRefreshing() async throws {
        var reads = 0
        let vm = model(fetch: { request in
            reads += 1
            guard request.url!.path.contains("nutrition_data") else { throw URLError(.timedOut) }
            return self.response(request, self.payload("Lunch"))
        }, remove: { _ in throw URLError(.notConnectedToInternet) })
        await vm.loadData()
        let count = reads
        await vm.deleteEntry(try XCTUnwrap(vm.entries.first))
        XCTAssertEqual(reads, count)
        XCTAssertEqual(vm.entries.first?.name, "Lunch")
        XCTAssertEqual(vm.networkError, "Suppression échouée — réessaie")
    }

    func testServerErrorDoesNotPublishPlausiblePayloadOrEraseCache() async {
        var status = 200
        let vm = model { request in
            guard request.url!.path.contains("nutrition_data") else { throw URLError(.timedOut) }
            return self.response(request, self.payload(status == 200 ? "cached" : "bad"), status: status)
        }
        await vm.loadData()
        status = 500
        await vm.loadData()
        XCTAssertEqual(vm.entries.first?.name, "cached")
        XCTAssertTrue(vm.hasLoaded)
        XCTAssertNotNil(vm.networkError)
        XCTAssertFalse(vm.isLoading)
    }

    func testEmptySuccessIsLoadedAndCancelledRefreshRetainsIt() async {
        var cancel = false
        let vm = model { request in
            if cancel { throw CancellationError() }
            guard request.url!.path.contains("nutrition_data") else { throw URLError(.timedOut) }
            return self.response(request, Data("{\"entries\":[],\"history\":[]}".utf8))
        }
        await vm.loadData()
        XCTAssertTrue(vm.hasLoaded)
        XCTAssertTrue(vm.entries.isEmpty)
        cancel = true
        await vm.loadData()
        XCTAssertTrue(vm.hasLoaded)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.networkError)
    }

    func testMacroDraftRejectsNonFiniteNegativeAndOverflowValues() {
        for value in ["NaN", "inf", "-1", "1e999", "1e308", "abc"] {
            XCTAssertNil(NutritionMacroDraft(protein: value, fat: "0", carbs: "1"), value)
        }
        let decimal = NutritionMacroDraft(protein: " 12,5 ", fat: "2.5", carbs: "")
        XCTAssertEqual(decimal?.protein, 12.5)
        XCTAssertEqual(decimal?.calories, 72)
        XCTAssertEqual(decimal?.canSave, true)
        XCTAssertEqual(NutritionMacroDraft(protein: "", fat: "", carbs: "")?.canSave, false)
    }

    func testStatsExerciseSheetIdentitySurvivesReevaluation() {
        XCTAssertEqual(ExerciseWrapper(name: "Bench Press").id, ExerciseWrapper(name: "Bench Press").id)
        XCTAssertNotEqual(ExerciseWrapper(name: "Bench Press").id, ExerciseWrapper(name: "Row").id)
    }

}
