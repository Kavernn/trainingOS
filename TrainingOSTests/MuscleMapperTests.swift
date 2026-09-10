import XCTest
@testable import TrainingOS

final class MuscleMapperTests: XCTestCase {
    func testFrenchAndEnglishLabelsMapToV1Zones() {
        let cases: [(String, MuscleZone)] = [
            ("Pectoraux", .chest),
            ("chest", .chest),
            ("Épaules", .shoulders),
            ("shoulders", .shoulders),
            ("Biceps", .biceps),
            ("Abdominaux", .core),
            ("Core", .core),
            ("Quadriceps", .quads),
            ("Dos", .generalBack),
            ("grand dorsal", .generalBack),
            ("Trapèzes", .traps),
            ("Triceps", .triceps),
            ("Fessiers", .glutes),
            ("hamstrings", .hamstrings),
            ("Mollets", .calves)
        ]

        for (label, expected) in cases {
            XCTAssertEqual(MuscleMapper.zone(for: label), expected, label)
        }
    }

    func testNormalizationHandlesCaseWhitespaceAndAccents() {
        XCTAssertEqual(MuscleMapper.zone(for: "  TRAPÈZES  "), .traps)
        XCTAssertEqual(MuscleMapper.zone(for: "trapezes"), .traps)
        XCTAssertEqual(MuscleMapper.zone(for: "E\u{301}PAULES"), .shoulders)
    }

    func testCanonicalAndLegacyMiddleTrapeziusLabelsMapToTraps() {
        XCTAssertEqual(MuscleMapper.zone(for: "Trapèze moyen"), .traps)
        XCTAssertEqual(MuscleMapper.zone(for: "mid_traps"), .traps)
    }

    func testRecognizedSpecificIsPrimaryBeforeGroup() throws {
        let result = MuscleMapper.map(try metadata(
            group: "Dos",
            specific: "Trapèze supérieur"
        ))

        XCTAssertEqual(result.scoresByZone, [.traps: 2])
    }

    func testGroupBecomesPrimaryWhenSpecificIsUnknown() throws {
        let result = MuscleMapper.map(try metadata(
            group: "Pectoraux",
            specific: "Valeur inconnue"
        ))

        XCTAssertEqual(result.scoresByZone, [.chest: 2])
    }

    func testSecondariesAreUniqueAndDoNotDoubleScorePrimaryZone() throws {
        let result = MuscleMapper.map(try metadata(
            group: "Pectoraux",
            secondary: ["Triceps", "triceps", "chest"]
        ))

        XCTAssertEqual(result.scoresByZone, [.chest: 2, .triceps: 1])
    }

    func testLegacyIsUnweightedFallbackAndIndexZeroIsNotPrimary() throws {
        let firstOrder = MuscleMapper.map(try metadata(legacy: ["Triceps", "Pectoraux"]))
        let reversed = MuscleMapper.map(try metadata(legacy: ["Pectoraux", "Triceps"]))

        XCTAssertEqual(firstOrder.scoresByZone, [.chest: 1, .triceps: 1])
        XCTAssertEqual(firstOrder, reversed)
    }

    func testExplicitZoneSuppressesLegacyFallback() throws {
        let result = MuscleMapper.map(try metadata(
            group: "Pectoraux",
            legacy: ["Triceps", "Quadriceps"]
        ))

        XCTAssertEqual(result.scoresByZone, [.chest: 2])
    }

    func testExplicitSecondarySuppressesLegacyFallback() throws {
        let result = MuscleMapper.map(try metadata(
            secondary: ["Triceps"],
            legacy: ["Pectoraux", "Quadriceps"]
        ))

        XCTAssertEqual(result.scoresByZone, [.triceps: 1])
    }

    func testUnknownAndConservativelyExcludedValuesAreIgnored() throws {
        XCTAssertNil(MuscleMapper.zone(for: "Serratus antérieur"))
        XCTAssertNil(MuscleMapper.zone(for: "Psoas"))
        XCTAssertNil(MuscleMapper.zone(for: "Brachioradialis"))
        XCTAssertNil(MuscleMapper.zone(for: "Muscle imaginaire"))

        let result = MuscleMapper.map(try metadata(
            specific: "Serratus antérieur",
            secondary: ["Psoas", "Brachioradialis"],
            legacy: ["Muscle imaginaire"]
        ))
        XCTAssertTrue(result.scoresByZone.isEmpty)
    }

    func testAggregateSumsScoresAcrossExercises() throws {
        let result = MuscleMapper.aggregate([
            try metadata(group: "Pectoraux", secondary: ["Triceps"]),
            try metadata(specific: "Triceps brachial", secondary: ["Épaules"]),
            try metadata(legacy: ["chest", "shoulders"])
        ])

        XCTAssertEqual(result.scoresByZone, [
            .chest: 3,
            .triceps: 3,
            .shoulders: 2
        ])
    }

    func testRankingIsDeterministicAndSupportsLimit() throws {
        let result = MuscleMapper.map(try metadata(legacy: ["Core", "Chest", "Biceps"]))

        XCTAssertEqual(result.rankedZones(), [
            MuscleZoneScore(zone: .biceps, score: 1),
            MuscleZoneScore(zone: .chest, score: 1),
            MuscleZoneScore(zone: .core, score: 1)
        ])
        XCTAssertEqual(result.rankedZones(limit: 2), [
            MuscleZoneScore(zone: .biceps, score: 1),
            MuscleZoneScore(zone: .chest, score: 1)
        ])
        XCTAssertTrue(result.rankedZones(limit: 0).isEmpty)
    }

    func testEmptyMetadataProducesEmptyResult() throws {
        let result = MuscleMapper.map(try metadata())

        XCTAssertTrue(result.scoresByZone.isEmpty)
        XCTAssertTrue(result.zones.isEmpty)
        XCTAssertTrue(result.rankedZones().isEmpty)
    }

    private func metadata(
        group: String? = nil,
        specific: String? = nil,
        secondary: [String] = [],
        legacy: [String] = []
    ) throws -> ExerciseMuscleMetadata {
        var object: [String: Any] = [
            "secondary_muscles": secondary,
            "muscles": legacy
        ]
        object["muscle_group"] = group
        object["muscle_specific"] = specific

        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(ExerciseMuscleMetadata.self, from: data)
    }
}
