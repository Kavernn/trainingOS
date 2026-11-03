import XCTest
@testable import TrainingOS

@MainActor
final class LoadableTests: XCTestCase {

    // MARK: - LoadError.from mapping

    func test_cancellationIgnored() {
        XCTAssertNil(LoadError.from(CancellationError()))
    }

    func test_urlCancelledIgnored() {
        XCTAssertNil(LoadError.from(URLError(.cancelled)))
    }

    func test_queuedOfflineIgnored_defensiveReadsOnly() {
        // Loadable est lectures uniquement — queuedOffline ne devrait jamais arriver,
        // mais le mapping doit retourner nil (pas un message mensonger).
        XCTAssertNil(LoadError.from(APIError.queuedOffline))
    }

    func test_offlineMapped() {
        let presentable = LoadError.from(URLError(.notConnectedToInternet))
        XCTAssertEqual(presentable?.kind, .offline)
        XCTAssertEqual(presentable?.message, "Hors ligne")
    }

    func test_timeoutMapped() {
        let presentable = LoadError.from(URLError(.timedOut))
        XCTAssertEqual(presentable?.kind, .network)
    }

    func test_genericURLErrorMappedToNetwork() {
        let presentable = LoadError.from(URLError(.badServerResponse))
        XCTAssertEqual(presentable?.kind, .network)
    }

    func test_serverErrorMappedToMessage() {
        let presentable = LoadError.from(APIError.serverError(503, "Service indisponible"))
        XCTAssertEqual(presentable?.kind, .server(503))
        XCTAssertEqual(presentable?.message, "Service indisponible")
    }

    func test_serverErrorEmptyMessageFallsBack() {
        let presentable = LoadError.from(APIError.serverError(500, ""))
        XCTAssertEqual(presentable?.message, "Erreur serveur (500)")
    }

    func test_invalidURLMappedToUnknown() {
        let presentable = LoadError.from(APIError.invalidURL(path: "/api/stats"))
        XCTAssertEqual(presentable?.kind, .unknown)
        XCTAssertTrue(presentable?.message.contains("/api/stats") == true)
    }

    func test_decodingFailedCarriesEndpoint() {
        let underlying = DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "corrupt")
        )
        let presentable = LoadError.from(
            APIError.decodingFailed(endpoint: "/api/stats_data", error: underlying)
        )
        XCTAssertEqual(presentable?.kind, .decoding)
        XCTAssertTrue(presentable?.message.contains("/api/stats_data") == true)
    }

    func test_unknownErrorMapped() {
        struct Weird: Error {}
        let presentable = LoadError.from(Weird())
        XCTAssertEqual(presentable?.kind, .unknown)
    }

    // MARK: - Loadable.load behaviour

    func test_loadSuccess() async {
        var state = Loadable<Int>()
        await state.load { 42 }
        XCTAssertEqual(state.value, 42)
        XCTAssertNil(state.error)
        XCTAssertNotNil(state.lastUpdated)
        XCTAssertFalse(state.isLoading)
    }

    func test_refreshFailureKeepsValueAndSetsError() async {
        var state = Loadable<Int>()
        await state.load { 1 }
        XCTAssertEqual(state.value, 1)

        await state.load { throw APIError.serverError(500, "down") }
        XCTAssertEqual(state.value, 1, "valeur préservée pendant un refresh raté")
        XCTAssertEqual(state.error?.kind, .server(500))
    }

    func test_seedShownOnFirstLoadFailure() async {
        var state = Loadable<Int>()
        await state.load(seed: 99) {
            throw APIError.serverError(500, "boom")
        }
        XCTAssertEqual(state.value, 99, "seed devient la valeur affichée (stale)")
        XCTAssertNotNil(state.error)
    }

    func test_seedWithSavedAt_bannerShowsRealAge() async {
        var state = Loadable<Int>()
        let seededAt = Date(timeIntervalSinceNow: -3600)
        await state.load(seed: 99, savedAt: seededAt) {
            throw APIError.serverError(500, "boom")
        }
        XCTAssertEqual(state.value, 99)
        XCTAssertEqual(state.lastUpdated, seededAt,
                       "staleBanner doit refléter l'âge réel de la seed, pas .now ni nil")
        XCTAssertNotNil(state.error)
    }

    func test_seedOverwrittenOnSuccess() async {
        var state = Loadable<Int>()
        await state.load(seed: 99) { 100 }
        XCTAssertEqual(state.value, 100, "fresh écrase le seed au succès")
    }

    func test_seedIgnoredWhenValueAlreadyPresent() async {
        var state = Loadable<Int>()
        await state.load { 1 }
        // Deuxième load avec seed différent — valeur fresh existe déjà,
        // seed ne doit pas écraser.
        await state.load(seed: 42) { throw APIError.serverError(500, "x") }
        XCTAssertEqual(state.value, 1, "seed ignoré si valeur déjà chargée")
    }

    func test_successClearsPreviousError() async {
        var state = Loadable<Int>()
        await state.load { throw APIError.serverError(500, "x") }
        XCTAssertNotNil(state.error)
        await state.load { 7 }
        XCTAssertNil(state.error, "succès suivant efface l'erreur")
        XCTAssertEqual(state.value, 7)
    }

    func test_cancellationDoesNotSetError() async {
        var state = Loadable<Int>()
        await state.load { 1 }
        await state.load { throw CancellationError() }
        XCTAssertNil(state.error, "annulation ne doit pas être affichée")
        XCTAssertEqual(state.value, 1)
    }

    func test_doubleLoadReturnsEarly() async {
        var state = Loadable<Int>()
        state.isLoading = true
        await state.load { 42 }
        XCTAssertNil(state.value, "guard non-réentrant : opération ignorée")
    }

    func test_isInitialLoadOnlyWhenNoValue() async {
        var state = Loadable<Int>()
        XCTAssertFalse(state.isInitialLoad, "pas de load en cours")

        state.isLoading = true
        XCTAssertTrue(state.isInitialLoad, "load en cours, pas de valeur")

        state.value = 5
        XCTAssertFalse(state.isInitialLoad, "load en cours mais valeur présente = refresh, pas initial")
    }

    /// Garantie "ouverture instantanée" exigée par HealthDashboard : quand
    /// un seed de cache est fourni, la valeur est visible DÈS QUE l'appel
    /// réseau commence à s'exécuter (opération suspendue), AVANT qu'elle
    /// n'ait pu retourner. `isLoading` reste true pendant ce temps pour
    /// que l'UI puisse signaler "en train de rafraîchir".
    func test_load_seedVisibleWhileOperationSuspended() async {
        let state = Loadable<Int>()
        let box = ContinuationBox()

        let loadTask = Task { @MainActor in
            await state.load(seed: 42, savedAt: .now) {
                await withCheckedContinuation { c in box.continuation = c }
            }
        }

        // Attend que l'opération réseau soit entrée dans son `await` (seed appliqué).
        while box.continuation == nil { await Task.yield() }

        XCTAssertEqual(state.value, 42, "seed visible pendant que l'opération réseau est suspendue")
        XCTAssertTrue(state.isLoading, "pendant l'await réseau, isLoading reste true")
        XCTAssertNotNil(state.lastUpdated, "savedAt du cache remonte au Loadable")

        box.continuation?.resume(returning: 100)
        await loadTask.value

        XCTAssertEqual(state.value, 100, "après succès réseau, value = valeur fresh")
        XCTAssertFalse(state.isLoading, "après la fin, isLoading = false")
    }
}

@MainActor
private final class ContinuationBox {
    var continuation: CheckedContinuation<Int, Never>?
}
