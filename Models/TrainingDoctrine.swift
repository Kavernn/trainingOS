import Foundation

/// Constantes doctrinales du domaine training (valeurs figées côté client).
/// Séparé des structs Codable de WorkoutModels.swift — ici, du littéral figé,
/// pas de la donnée backend.
enum TrainingDoctrine {

    /// Jours de la semaine, abréviations FR. Ordre : lundi = index 0.
    /// Source unique pour toute grille hebdo (programme, stats, séance).
    static let dayNames: [String] = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    /// Ordre canonique des séances du split hebdomadaire. Les séances custom
    /// (hors de cette liste) viennent après, triées alphabétiquement — voir
    /// consommateurs (ProgrammeView.orderedSeances, SeanceView.sessionList).
    static let canonicalSeanceOrder: [String] = [
        "Push A", "Pull A", "Legs", "Push B", "Pull B + Full Body",
        "Yoga / Tai Chi", "Recovery",
    ]

    /// Seuils de volume hebdomadaire par groupe musculaire (sets/sem).
    /// MEV = Minimum Effective Volume, MAV = Maximum Adaptive Volume.
    /// Réf. : Israetel volume landmarks framework, Schoenfeld et al. 2017.
    ///
    /// ⚠️ BUG LATENT (hors scope de ce diff d'extraction) : ces clés ne
    /// matchent PAS les valeurs réelles de exercises.muscle_group en base
    /// (SELECT DISTINCT 2026-07-16 : Pectoraux, Quadriceps, glutes,
    /// Ischio-jambiers, Biceps+Avant-bras, Mollets, etc.). Le consommateur
    /// ProgrammeView.weeklyVolumeByMuscle est donc partiellement muet pour
    /// 4 groupes sur 8. À corriger dans un diff séparé — préservé tel quel
    /// ici pour respecter "zéro changement de comportement".
    static let muscleMEV: [String: Int] = [
        "Pecs": 10, "Dos": 10, "Épaules": 8, "Biceps": 6,
        "Triceps": 6, "Jambes": 8, "Fessiers": 6, "Core": 6,
    ]
    static let muscleMAV: [String: Int] = [
        "Pecs": 16, "Dos": 16, "Épaules": 14, "Biceps": 12,
        "Triceps": 12, "Jambes": 14, "Fessiers": 10, "Core": 12,
    ]
}
