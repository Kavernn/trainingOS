import XCTest
@testable import TrainingOS

@MainActor
final class LoadableAggregatorTests: XCTestCase {

    func test_offlinePlusServerError_bannerGlobalAndServerSectionCard() async {
        let offline = Loadable<Int>()
        let server  = Loadable<Int>()

        await offline.load { throw URLError(.notConnectedToInternet) }
        await server.load  { throw APIError.serverError(500, "boom") }

        let agg = LoadableAggregator(groups: [
            .init(states: [offline, server], retry: {})
        ])

        XCTAssertTrue(agg.hasGlobalFailure, "offline tenté → bandeau global")
        XCTAssertEqual(agg.globalKind, .offline, "priorité offline > network")
        XCTAssertEqual(server.errorKind, .server(500),
                       "l'erreur serveur reste visible pour sa carte section (pas suppressed)")
    }

    func test_untriedLoadable_ignoredFromAggregation() async {
        let tried   = Loadable<Int>()
        let untried = Loadable<Int>()

        await tried.load { throw URLError(.notConnectedToInternet) }
        // untried : aucun load() → wasAttempted == false

        let agg = LoadableAggregator(groups: [
            .init(states: [tried, untried], retry: {})
        ])

        XCTAssertFalse(untried.wasAttempted,
                       "Loadable jamais déclenché n'est pas tenté")
        XCTAssertEqual(agg.tried.count, 1,
                       "seul le Loadable tenté entre dans l'agrégation")
    }

    func test_retryAll_onlyRunsGroupsWithTriedStates() async {
        let triedState   = Loadable<Int>()
        let untriedState = Loadable<Int>()

        await triedState.load { throw URLError(.notConnectedToInternet) }

        actor Count { var v = 0; func inc() { v += 1 } }
        let triedCount   = Count()
        let untriedCount = Count()

        let agg = LoadableAggregator(groups: [
            .init(states: [triedState],   retry: { await triedCount.inc()   }),
            .init(states: [untriedState], retry: { await untriedCount.inc() }),
        ])

        await agg.retryAll()

        let triedN   = await triedCount.v
        let untriedN = await untriedCount.v
        XCTAssertEqual(triedN,   1, "groupe avec state tenté : relancé")
        XCTAssertEqual(untriedN, 0, "groupe sans state tenté : ignoré")
    }
}
