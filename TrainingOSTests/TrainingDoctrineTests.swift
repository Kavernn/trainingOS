//
//  TrainingDoctrineTests.swift
//  TrainingOSTests
//
//  Vérifie que le mapping muscle_group DB → clé doctrinale reste cohérent
//  avec les 14 valeurs relevées en base (SELECT DISTINCT 2026-07-16) et
//  qu'aucun groupe ne devient silencieusement muet (bug historique de la
//  carte Volume qui listait "Pecs" tandis que la DB stocke "Pectoraux").
//

import XCTest
@testable import TrainingOS

final class TrainingDoctrineTests: XCTestCase {

    // MARK: - 14 valeurs DB → toutes atteignent un seuil (ou une exclusion)

    func testPectorauxMapsToSeuil() {
        let key = TrainingDoctrine.doctrinalMuscleGroup(for: "Pectoraux")
        XCTAssertEqual(key, "Pectoraux")
        XCTAssertNotNil(TrainingDoctrine.muscleMEV[key!])
        XCTAssertNotNil(TrainingDoctrine.muscleMAV[key!])
    }

    func testDosMapsToSeuil() {
        let key = TrainingDoctrine.doctrinalMuscleGroup(for: "Dos")
        XCTAssertEqual(key, "Dos")
        XCTAssertNotNil(TrainingDoctrine.muscleMEV[key!])
    }

    func testEpaulesMapsToSeuil() {
        let key = TrainingDoctrine.doctrinalMuscleGroup(for: "Épaules")
        XCTAssertEqual(key, "Épaules")
        XCTAssertNotNil(TrainingDoctrine.muscleMEV[key!])
    }

    func testBicepsMapsToSeuil() {
        let key = TrainingDoctrine.doctrinalMuscleGroup(for: "Biceps")
        XCTAssertEqual(key, "Biceps")
        XCTAssertNotNil(TrainingDoctrine.muscleMEV[key!])
    }

    func testTricepsMapsToSeuil() {
        let key = TrainingDoctrine.doctrinalMuscleGroup(for: "Triceps")
        XCTAssertEqual(key, "Triceps")
        XCTAssertNotNil(TrainingDoctrine.muscleMEV[key!])
    }

    func testQuadricepsMapsToSeuil() {
        let key = TrainingDoctrine.doctrinalMuscleGroup(for: "Quadriceps")
        XCTAssertEqual(key, "Quadriceps")
        XCTAssertNotNil(TrainingDoctrine.muscleMEV[key!])
    }

    func testIschioJambiersMapsToSeuil() {
        let key = TrainingDoctrine.doctrinalMuscleGroup(for: "Ischio-jambiers")
        XCTAssertEqual(key, "Ischio-jambiers")
        XCTAssertNotNil(TrainingDoctrine.muscleMEV[key!])
    }

    func testGlutesMapsToFessiers() {
        // Anomalie DB (anglais dans colonne française) absorbée par mapping.
        let key = TrainingDoctrine.doctrinalMuscleGroup(for: "glutes")
        XCTAssertEqual(key, "Fessiers")
        XCTAssertNotNil(TrainingDoctrine.muscleMEV[key!])
    }

    func testMolletsMapsToSeuil() {
        let key = TrainingDoctrine.doctrinalMuscleGroup(for: "Mollets")
        XCTAssertEqual(key, "Mollets")
        XCTAssertNotNil(TrainingDoctrine.muscleMEV[key!])
    }

    func testTrapezesMapsToSeuil() {
        let key = TrainingDoctrine.doctrinalMuscleGroup(for: "Trapèzes")
        XCTAssertEqual(key, "Trapèzes")
        XCTAssertNotNil(TrainingDoctrine.muscleMEV[key!])
    }

    // MARK: - Fusions doctrinales

    func testAvantBrasFusesIntoBiceps() {
        XCTAssertEqual(TrainingDoctrine.doctrinalMuscleGroup(for: "Avant-bras"), "Biceps")
    }

    func testBicepsAvantBrasHistoriqueMapsToBiceps() {
        // Safety net : valeur historique combinée qui existait au mapping Swift.
        XCTAssertEqual(TrainingDoctrine.doctrinalMuscleGroup(for: "Biceps+Avant-bras"), "Biceps")
    }

    func testAbdominauxFusesIntoCore() {
        XCTAssertEqual(TrainingDoctrine.doctrinalMuscleGroup(for: "Abdominaux"), "Core")
    }

    func testCoreMapsToCore() {
        XCTAssertEqual(TrainingDoctrine.doctrinalMuscleGroup(for: "Core"), "Core")
    }

    // MARK: - Exclusion & valeur inconnue

    func testCouIsExcluded() {
        // Exclusion intentionnelle, silencieuse (aucun warning logué).
        XCTAssertNil(TrainingDoctrine.doctrinalMuscleGroup(for: "Cou"))
    }

    func testUnknownValueReturnsNilWithoutCrash() {
        // Le canal de log (OSLog warning) n'est pas testé ici — on vérifie
        // uniquement que le retour est nil et que l'appel ne crashe pas.
        XCTAssertNil(TrainingDoctrine.doctrinalMuscleGroup(for: "InventedMuscle"))
        XCTAssertNil(TrainingDoctrine.doctrinalMuscleGroup(for: ""))
    }

    // MARK: - Cohérence interne : chaque clé du mapping a un seuil

    // MARK: - Symétrie canonicalMuscleOrder ↔ muscleMEV/MAV

    func testEveryMEVKeyIsInCanonicalOrder() {
        // Un consommateur qui itère sur canonicalMuscleOrder doit voir chaque
        // clé de muscleMEV. Sans cette symétrie, ajouter une clé au dict
        // laisse le muscle invisible dans les vues qui parcourent l'ordre.
        for key in TrainingDoctrine.muscleMEV.keys {
            XCTAssertTrue(TrainingDoctrine.canonicalMuscleOrder.contains(key),
                          "muscleMEV['\(key)'] existe mais absent de canonicalMuscleOrder → invisible dans les vues qui itèrent sur l'ordre")
        }
    }

    func testEveryCanonicalOrderKeyHasMEVAndMAV() {
        // Inverse : une clé dans l'ordre visuel sans seuil = tuile fantôme
        // (MEV=0, MAV=12 fallback) sans base doctrinale.
        for key in TrainingDoctrine.canonicalMuscleOrder {
            XCTAssertNotNil(TrainingDoctrine.muscleMEV[key],
                            "canonicalMuscleOrder contient '\(key)' sans MEV")
            XCTAssertNotNil(TrainingDoctrine.muscleMAV[key],
                            "canonicalMuscleOrder contient '\(key)' sans MAV")
        }
    }

    // MARK: - Cohérence interne : chaque clé du mapping a un seuil

    func testAllDoctrinalKeysHaveMEVAndMAV() {
        // Toute valeur mappée doit avoir un couple MEV/MAV, sinon une valeur
        // DB pourrait être "reconnue" mais silencieusement sans alerte —
        // exactement le bug qu'on corrige.
        let dbValues = ["Pectoraux", "Dos", "Épaules", "Biceps",
                        "Biceps+Avant-bras", "Avant-bras", "Triceps",
                        "Quadriceps", "Ischio-jambiers", "glutes", "Mollets",
                        "Trapèzes", "Abdominaux", "Core"]
        for db in dbValues {
            guard let doctrinal = TrainingDoctrine.doctrinalMuscleGroup(for: db) else {
                XCTFail("'\(db)' devrait mapper vers un groupe doctrinal")
                continue
            }
            XCTAssertNotNil(TrainingDoctrine.muscleMEV[doctrinal], "'\(doctrinal)' (de '\(db)') n'a pas de MEV")
            XCTAssertNotNil(TrainingDoctrine.muscleMAV[doctrinal], "'\(doctrinal)' (de '\(db)') n'a pas de MAV")
        }
    }
}
