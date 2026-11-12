import XCTest
@testable import TrainingOS

@MainActor
final class LessonOfDayStoreTests: XCTestCase {
    private let keys = [
        "lessonOfDay.seenIds", "lessonOfDay.seenAt",
        "lessonOfDay.todayId", "lessonOfDay.todayDate", "lessonOfDay.todayIsRevision",
    ]

    override func setUp() async throws {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() async throws {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private func capsule(_ id: Int) -> EducationalCapsule {
        let json = """
        {"id":\(id),"category":"anatomie","title":"T\(id)","body":"B\(id)"}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(EducationalCapsule.self, from: json)
    }

    func testPoolExhaustedFallsBackToRevisionOldestFirst() throws {
        let pool = [capsule(1), capsule(2), capsule(3)]
        // Simule 3 vues anciennes : 1 vue il y a 10 jours, 2 il y a 5 j., 3 hier.
        let seenAt: [String: Double] = [
            "1": Date().timeIntervalSince1970 - 10 * 86400,
            "2": Date().timeIntervalSince1970 - 5 * 86400,
            "3": Date().timeIntervalSince1970 - 86400,
        ]
        UserDefaults.standard.set([1, 2, 3], forKey: "lessonOfDay.seenIds")
        UserDefaults.standard.set(seenAt, forKey: "lessonOfDay.seenAt")

        let pick = LessonOfDayStore.todayPick(from: pool, todayStr: "2026-11-12")
        XCTAssertNotNil(pick)
        XCTAssertTrue(pick!.isRevision, "pool épuisé doit retourner une révision")
        XCTAssertEqual(pick!.capsule.id, 1, "la plus anciennement vue d'abord")
    }

    func testNewCapsuleSupersedesRevision() throws {
        let oldPool = [capsule(1), capsule(2)]
        UserDefaults.standard.set([1, 2], forKey: "lessonOfDay.seenIds")
        UserDefaults.standard.set(["1": 1.0, "2": 2.0], forKey: "lessonOfDay.seenAt")
        let revision = LessonOfDayStore.todayPick(from: oldPool, todayStr: "2026-11-12")
        XCTAssertTrue(revision!.isRevision)

        let newPool = oldPool + [capsule(3)]
        let fresh = LessonOfDayStore.supersedeRevisionIfPossible(from: newPool, todayStr: "2026-11-12")
        XCTAssertNotNil(fresh)
        XCTAssertFalse(fresh!.isRevision, "la nouvelle capsule supplante la révision")
        XCTAssertEqual(fresh!.capsule.id, 3)
    }

    func testInitialFetchFailureShowsRefreshFailedCardNotEmpty() throws {
        // Scénario : premier chargement du pool KO. L'UI reçoit pick=nil
        // + refreshFailedToday=true. La présentation doit être .refreshFailed,
        // JAMAIS une carte invisible. Verrouille la combinaison des deux
        // signaux côté DashboardView (loadEducationalIfNeeded catch).
        XCTAssertEqual(
            LessonOfDayStore.presentation(pick: nil, refreshFailedToday: true),
            .refreshFailed
        )
        // Contrôle : aucun pick + aucun échec (DB réellement vide) = .absent.
        XCTAssertEqual(
            LessonOfDayStore.presentation(pick: nil, refreshFailedToday: false),
            .absent
        )
    }

    func testNetworkFailureKeepsPinUntouchedForRetry() throws {
        // Résilience "erreur réseau → carte d'erreur + Réessayer" portée par
        // DashboardView. Ici on verrouille le contrat du store : si une capsule
        // est pinnée, un bypass réseau raté (supersedeRevisionIfPossible non
        // appelé) ne doit NI écraser le pin NI changer isRevision.
        UserDefaults.standard.set([1], forKey: "lessonOfDay.seenIds")
        UserDefaults.standard.set(["1": 1.0], forKey: "lessonOfDay.seenAt")
        _ = LessonOfDayStore.todayPick(from: [capsule(1)], todayStr: "2026-11-12")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "lessonOfDay.todayId"), 1)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "lessonOfDay.todayIsRevision"))

        let unchanged = LessonOfDayStore.todayPick(from: [capsule(1)], todayStr: "2026-11-12")
        XCTAssertEqual(unchanged?.capsule.id, 1)
        XCTAssertEqual(unchanged?.isRevision, true)
    }
}
