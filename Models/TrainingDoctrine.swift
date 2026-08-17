import Foundation
import OSLog

private let doctrineLogger = Logger(subsystem: "TrainingOS", category: "doctrine")

/// Constantes doctrinales du domaine training (valeurs figées côté client).
/// Séparé des structs Codable de WorkoutModels.swift — ici, du littéral figé,
/// pas de la donnée backend.
enum TrainingDoctrine {

    /// Jours de la semaine, abréviations FR. Ordre : lundi = index 0.
    /// Source unique pour toute grille hebdo (programme, stats, séance).
    static let dayNames: [String] = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    /// Nom de la séance de demain d'après le schedule hebdo (clés "Lun"…"Dim").
    /// Weekday en timezone MTL (Calendar.mtl) — cohérent avec _today_mtl backend.
    /// "Repos" si la clé de demain est absente du schedule.
    static func tomorrowSessionName(from schedule: [String: String],
                                    now: Date = Date()) -> String {
        // Calendar.mtl.component(.weekday, …) : Dim=1, Lun=2, …, Sam=7
        let weekday = Calendar.mtl.component(.weekday, from: now)
        let todayIdx = (weekday + 5) % 7        // 0=Lun … 6=Dim
        let tomorrowIdx = (todayIdx + 1) % 7
        return schedule[dayNames[tomorrowIdx]] ?? "Repos"
    }

    /// Durée du cycle mésocycle en semaines. Miroir backend : utils.MESOCYCLE_WEEKS.
    /// Toute modification doit être répercutée dans les 2 sources en même temps.
    static let mesocycleWeeks: Int = 11

    /// Ordre canonique des séances du split hebdomadaire. Les séances custom
    /// (hors de cette liste) viennent après, triées alphabétiquement — voir
    /// consommateurs (ProgrammeView.orderedSeances, SeanceView.sessionList).
    static let canonicalSeanceOrder: [String] = [
        "Push A", "Pull A", "Legs", "Push B", "Pull B + Full Body",
        "Yoga / Tai Chi", "Recovery",
    ]

    // MARK: - Volume landmarks (MEV/MAV) — sets/sem par groupe doctrinal
    //
    // MEV = Minimum Effective Volume, MAV = Maximum Adaptive Volume.
    // Réf. : Israetel Renaissance Periodization volume landmarks, Schoenfeld
    // et al. 2017. Option A appliquée : chiffres actuels préservés pour les
    // 8 groupes historiques, chiffres RP pour les 4 nouveaux séparés
    // (Quadriceps, Ischio-jambiers, Mollets, Trapèzes). Révision RP complète
    // = diff futur si l'usage révèle un mauvais calibrage.

    static let muscleMEV: [String: Int] = [
        "Pectoraux":       10,
        "Dos":             10,
        "Épaules":          8,
        "Biceps":           6,
        "Triceps":          6,
        "Quadriceps":       8,   // RP séparé (ex-"Jambes")
        "Ischio-jambiers":  6,   // RP séparé
        "Fessiers":         6,
        "Mollets":          6,   // RP séparé
        "Trapèzes":         4,   // RP séparé, seuil bas (stimulé indirectement en Row/OHP)
        "Core":             6,
    ]

    static let muscleMAV: [String: Int] = [
        "Pectoraux":       16,
        "Dos":             16,
        "Épaules":         14,
        "Biceps":          12,
        "Triceps":         12,
        "Quadriceps":      18,   // RP
        "Ischio-jambiers": 14,   // RP
        "Fessiers":        10,
        "Mollets":         12,   // RP
        "Trapèzes":        10,   // RP conservateur
        "Core":            12,
    ]

    /// Ordre visuel canonique pour l'affichage groupé (tab Semaine
    /// volumeSection). Cohérent avec les clés de muscleMEV/MAV — la symétrie
    /// est verrouillée par les tests (TrainingDoctrineTests).
    /// Ordre : haut du corps antérieur → haut du corps postérieur → bras →
    /// bas du corps antérieur → bas du corps postérieur → tronc.
    static let canonicalMuscleOrder: [String] = [
        "Pectoraux", "Dos", "Épaules", "Trapèzes",
        "Biceps", "Triceps",
        "Quadriceps", "Ischio-jambiers", "Fessiers", "Mollets",
        "Core",
    ]

    // MARK: - Mapping muscle_group DB → groupe doctrinal
    //
    // Valeurs réelles de exercises.muscle_group (SELECT DISTINCT 2026-07-16) :
    // Épaules(20), Dos(16), Quadriceps(16), Pectoraux(15), Biceps(11),
    // Ischio-jambiers(8), Triceps(8), Abdominaux(5), Avant-bras(5), glutes(5),
    // Mollets(4), Core(3), Trapèzes(3), Cou(2).
    // L'anomalie "glutes" (anglais dans une colonne française) est absorbée
    // par le mapping ici — harmonisation de la colonne au backlog.
    // Fusions doctrinales : Biceps+Avant-bras (avant-bras stimulés indirectement,
    // pas de MEV RP propre) ; Abdominaux+Core (redondance sémantique).

    private static let _dbToDoctrinal: [String: String] = [
        "Pectoraux":         "Pectoraux",
        "Dos":               "Dos",
        "Épaules":           "Épaules",
        "Biceps":            "Biceps",
        "Biceps+Avant-bras": "Biceps",  // safety net (valeur historique)
        "Avant-bras":        "Biceps",  // fusion doctrinale
        "Triceps":           "Triceps",
        "Quadriceps":        "Quadriceps",
        "Ischio-jambiers":   "Ischio-jambiers",
        "glutes":            "Fessiers",
        "Mollets":           "Mollets",
        "Trapèzes":          "Trapèzes",
        "Abdominaux":        "Core",   // fusion doctrinale
        "Core":              "Core",
    ]

    /// Valeurs DB explicitement hors du suivi de volume (aucun seuil pertinent
    /// en musculation classique). Exclusion intentionnelle, silencieuse.
    private static let _excludedFromVolume: Set<String> = ["Cou"]

    /// Résout une valeur DB `muscle_group` vers son groupe doctrinal.
    /// - Retourne nil si explicitement exclue (`_excludedFromVolume`).
    /// - Retourne nil + warning OSLog si non mappée ni exclue — le crime
    ///   "groupe silencieusement muet" devient un signal visible. Réponse
    ///   attendue : ajouter la valeur au mapping ou au set d'exclusion.
    static func doctrinalMuscleGroup(for dbValue: String) -> String? {
        if _excludedFromVolume.contains(dbValue) { return nil }
        if let mapped = _dbToDoctrinal[dbValue]  { return mapped }
        doctrineLogger.warning("unknown muscle_group '\(dbValue, privacy: .public)' — ni mappé ni exclu. Ajouter à _dbToDoctrinal ou _excludedFromVolume.")
        return nil
    }
}
