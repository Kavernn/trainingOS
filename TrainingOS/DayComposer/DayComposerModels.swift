import Foundation
import CryptoKit
import os

/// Journal Day Composer (avertissements non bloquants, ex. durée de séance).
enum DayComposerLog {
    static let logger = Logger(subsystem: "TrainingOS", category: "day-composer")
}

enum DayComposerSource: String, Codable {
    case morning, evening
    var title: String { self == .morning ? "Matin" : "Soir" }
}

struct DayComposerItemID: Codable, Hashable {
    let source: DayComposerSource
    let exercise: String
    var occurrenceKey: String {
        "dc1:" + SHA256.hash(data: Data("\(source.rawValue)|\(exercise)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    init(source: DayComposerSource, name: String, exerciseID: String?) {
        self.source = source
        // A tagged fallback cannot collide with an ID or the other source.
        exercise = exerciseID.flatMap(UUID.init(uuidString:)).map { "id:\($0.uuidString)" }
            ?? "name:\(name)"
    }
}

struct DayComposerItem: Codable, Equatable, Identifiable {
    let id: DayComposerItemID
    let name: String
    let scheme: String
    let sourceOrder: Int
    let tracking: String
    let unilateral: Bool
    var assignedSourceOverride: DayComposerSource? = nil
    var originSource: DayComposerSource { id.source }
    var assignedSource: DayComposerSource { assignedSourceOverride ?? originSource }
    var occurrenceKey: String? { assignedSourceOverride == nil ? nil : id.occurrenceKey }
    var storageKey: String { occurrenceKey ?? name }
}

/// A superset is ONE movable unit, with its original A/B order retained.
struct DayComposerUnit: Codable, Equatable, Identifiable {
    let items: [DayComposerItem]
    let group: String?
    let rest: Int?
    var id: DayComposerItemID { items[0].id }
    var source: DayComposerSource { items[0].assignedSource }
}

struct DayComposerPlan: Codable, Equatable {
    let source: DayComposerSource
    let session: String
    let units: [DayComposerUnit]

    init(source: DayComposerSource, session: String, units: [DayComposerUnit]) {
        self.source = source; self.session = session; self.units = units
    }

    struct Pair {
        let group: String
        let a: String
        let b: String
        let rest: Int?
    }

    /// An inherited PM name alone is not a second planned session. Only explicit
    /// PM content or exercises actually assigned to PM may enter preparation.
    static func eveningSchemes(_ schemes: [String: String], explicitlyPlanned: Bool,
                               pushedToEvening: Set<String>) -> [String: String] {
        explicitlyPlanned ? schemes : schemes.filter { pushedToEvening.contains($0.key) }
    }

    init(source: DayComposerSource, session: String, schemes: [String: String],
         order: [String], exerciseIDs: [String: String] = [:],
         tracking: [String: String] = [:], unilateral: [String: Bool] = [:],
         pairs: [Pair] = []) throws {
        self.source = source
        self.session = session
        var seen = Set<String>()
        let names = (order + schemes.keys.sorted()).filter {
            schemes[$0] != nil && seen.insert($0).inserted
        }
        let items = names.enumerated().map { index, name in
            DayComposerItem(id: .init(source: source, name: name, exerciseID: exerciseIDs[name]),
                            name: name, scheme: schemes[name]!, sourceOrder: index,
                            tracking: tracking[name] ?? "reps", unilateral: unilateral[name] ?? false)
        }
        guard Set(items.map(\.id)).count == items.count else { throw DayComposerError.invalidPlan }
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        var membership: [String: Pair] = [:]
        for pair in pairs.sorted(by: { $0.group < $1.group }) {
            guard byName[pair.a] != nil || byName[pair.b] != nil else { continue }
            // A moved/missing member or overlapping groups must not silently flatten a superset.
            guard pair.a != pair.b, byName[pair.a] != nil, byName[pair.b] != nil,
                  membership[pair.a] == nil, membership[pair.b] == nil else {
                throw DayComposerError.invalidPlan
            }
            membership[pair.a] = pair
            membership[pair.b] = pair
        }
        var emitted = Set<String>()
        var result: [DayComposerUnit] = []
        for item in items where !emitted.contains(item.name) {
            if let pair = membership[item.name] {
                result.append(.init(items: [byName[pair.a]!, byName[pair.b]!], group: pair.group, rest: pair.rest))
                emitted.formUnion([pair.a, pair.b])
            } else {
                result.append(.init(items: [item], group: nil, rest: nil))
                emitted.insert(item.name)
            }
        }
        units = result
    }
}

/// Cause précise du verrouillage des créneaux (DayComposerStore.lockCause).
enum DayComposerLockCause: Equatable {
    case completed(DayComposerSource)
    case finalizing(DayComposerSource)
    /// Ma journée déjà lancée aujourd'hui (provenance d'exécution).
    case launched
    /// Brouillon local sur un exercice.
    case exerciseEntry(DayComposerSource, exercise: String)
    /// Logs locaux, protection ou commentaire de séance.
    case sessionEntry(DayComposerSource)
    /// Séance commencée : heure de départ ou chronomètre enregistré.
    case started(DayComposerSource)
    /// Exercice déjà observé côté serveur aujourd'hui.
    case logged
    /// État local illisible : verrouillé par sécurité.
    case unreadable
}

enum DayComposerError: Error {
    case invalidPlan, contextChanged, unavailable, executionStarted, emptySource
}

struct DayComposerSnapshot {
    let date: String
    let activeProgramID: String
    let morning: DayComposerPlan
    let evening: DayComposerPlan
    // Only authoritative source completion. Never the global loggedTodayNames union.
    let morningCompleted: Bool
    let eveningCompleted: Bool
    /// Entrées de la durée estimée, HORS empreinte (`fingerprint` n'encode que [morning, evening]).
    /// Indexées par occurrence, lues dans la séance d'origine de l'exercice (comme l'exécution).
    /// Remplies uniquement par `DayComposerLoader.validate` ; vides dans l'aperçu non vérifié.
    var restSeconds: [DayComposerItemID: Int] = [:]
    var prescriptions: [DayComposerItemID: ExercisePrescription] = [:]

    var initialUnits: [DayComposerUnit] { morning.units + evening.units }
    var initialIDs: [DayComposerItemID] { initialUnits.flatMap { $0.items.map(\.id) } }
    var fingerprint: String {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode([morning, evening])
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// `hasSavedOrder` (DayComposerStore) repose sur un invariant d'écriture : `save` écrit
    /// toujours les affectations ; `saveSetAside` sans état préalable n'en écrit pas ;
    /// `saveSetAside` sur un état existant les conserve. Une mise de côté seule ne rend donc
    /// pas pertinente une journée aux deux séances terminées.
    func isRelevant(hasSavedOrder: Bool) -> Bool {
        // One completed source can still be represented alongside the other.
        // A wholly completed day is only offered as an existing saved recovery,
        // not as a new execution. Preparation can represent unsupported items;
        // execution support belongs exclusively to canStart below.
        return !activeProgramID.isEmpty
            && !morning.units.isEmpty && !evening.units.isEmpty
            && (hasSavedOrder || !morningCompleted || !eveningCompleted)
    }

    func completed(_ source: DayComposerSource) -> Bool {
        source == .morning ? morningCompleted : eveningCompleted
    }

    /// Exercices à faire pour une source. SEUL point de filtrage des mises de côté
    /// (têtes d'unité) : le plan, donc l'empreinte et l'identité de finalisation, reste complet.
    func requiredItems(_ source: DayComposerSource, setAside: Set<DayComposerItemID>) -> [DayComposerItem] {
        (source == .morning ? morning : evening).units.filter { !setAside.contains($0.id) }.flatMap(\.items)
    }

    /// Aucun exercice requis dans la journée. Indépendant des affectations Matin/Soir
    /// (les deux sources sont couvertes), donc valable en préparation comme en exécution.
    func isWhollySetAside(_ setAside: Set<DayComposerItemID>) -> Bool {
        requiredItems(.morning, setAside: setAside).isEmpty && requiredItems(.evening, setAside: setAside).isEmpty
    }

    /// Règle validée « Garde au moins un exercice pour la journée » : refus UNIQUEMENT si
    /// la mise de côté viderait la journée ET qu'aucune unité de la journée n'est loguée.
    func setAsideEmptiesUnloggedDay(_ unitID: DayComposerItemID, setAside: Set<DayComposerItemID>,
                                    anyLogged: Bool) -> Bool {
        !anyLogged && isWhollySetAside(setAside.union([unitID]))
    }

    func canStart(orderedIDs: [DayComposerItemID], activeProgram: String, date: String,
                  loading: Bool, incompatible: Bool) -> Bool {
        !loading && !incompatible && activeProgramID == activeProgram && self.date == date
            && !morning.units.isEmpty && !evening.units.isEmpty
            && units(for: orderedIDs)?.isEmpty == false
            && initialUnits.flatMap(\.items).allSatisfy { ["reps", "time", "carry", "plyo", "protocol", "mobility"].contains($0.tracking) }
    }

    /// Reject duplicate/missing/foreign IDs and any attempt to split or reverse a superset.
    func units(for ids: [DayComposerItemID]) -> [DayComposerUnit]? {
        guard ids.count == initialIDs.count, Set(ids) == Set(initialIDs) else { return nil }
        let starts = Dictionary(uniqueKeysWithValues: initialUnits.map { ($0.id, $0) })
        var result: [DayComposerUnit] = []
        var cursor = 0
        while cursor < ids.count {
            guard let unit = starts[ids[cursor]] else { return nil }
            let members = unit.items.map(\.id)
            guard cursor + members.count <= ids.count,
                  Array(ids[cursor..<(cursor + members.count)]) == members else { return nil }
            result.append(unit)
            cursor += members.count
        }
        return result
    }

    func assigning(_ units: [DayComposerUnit]) throws -> DayComposerSnapshot {
        guard self.units(for: units.flatMap { $0.items.map(\.id) }) != nil,
              units.allSatisfy({ unit in unit.items.allSatisfy { $0.assignedSource == unit.source } }),
              [DayComposerSource.morning, .evening].allSatisfy({ source in
                  units.contains { $0.source == source && $0.items.contains { ["reps", "time", "carry", "plyo", "protocol", "mobility"].contains($0.tracking) } }
              }) else { throw DayComposerError.invalidPlan }
        let originals = Dictionary(uniqueKeysWithValues: initialUnits.map { ($0.id, $0) })
        for unit in units {
            guard let original = originals[unit.id], unit.group == original.group, unit.rest == original.rest,
                  unit.items.count == original.items.count else { throw DayComposerError.invalidPlan }
            for (item, expected) in zip(unit.items, original.items) {
                var a = item; var b = expected
                a.assignedSourceOverride = nil; b.assignedSourceOverride = nil
                guard a == b else { throw DayComposerError.invalidPlan }
            }
        }
        return .init(date: date, activeProgramID: activeProgramID,
            morning: .init(source: .morning, session: morning.session, units: units.filter { $0.source == .morning }),
            evening: .init(source: .evening, session: evening.session, units: units.filter { $0.source == .evening }),
            morningCompleted: morningCompleted, eveningCompleted: eveningCompleted,
            restSeconds: restSeconds, prescriptions: prescriptions)
    }

    static func transferring(_ units: [DayComposerUnit], id: DayComposerItemID,
                             locked: Bool) throws -> [DayComposerUnit] {
        guard !locked else { throw DayComposerError.executionStarted }
        guard let unit = units.first(where: { $0.id == id }),
              unit.items.allSatisfy({ $0.assignedSource == unit.source }) else { throw DayComposerError.invalidPlan }
        guard units.contains(where: { $0.id != id && $0.source == unit.source && $0.items.contains {
            ["reps", "time", "carry", "plyo", "protocol", "mobility"].contains($0.tracking)
        } }) else { throw DayComposerError.emptySource }
        let target: DayComposerSource = unit.source == .morning ? .evening : .morning
        let updated: [DayComposerUnit] = units.map { current in
            .init(items: current.items.map { item in
                var value = item
                value.assignedSourceOverride = current.id == id ? target : item.assignedSource
                return value
            }, group: current.group, rest: current.rest)
        }
        return updated.filter { $0.source == .morning } + updated.filter { $0.source == .evening }
    }

    /// Drag and accessible moves share this pure, unit-based operation.
    static func moving(_ units: [DayComposerUnit], from offsets: IndexSet, to destination: Int) -> [DayComposerUnit] {
        guard destination >= 0, destination <= units.count,
              offsets.allSatisfy({ units.indices.contains($0) }) else { return units }
        let moved = offsets.sorted().map { units[$0] }
        var result = units.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        result.insert(contentsOf: moved, at: insertion)
        return result
    }
}

/// No exercise configurations, logs, sets, comments, recovery or network state are persisted.
struct DayComposerState: Codable {
    let version: Int
    let date: String
    let activeProgramID: String
    let sourceFingerprint: String
    let orderedItemIDs: [DayComposerItemID]
    var assignments: [Assignment]? = nil
    /// v3 : unités mises de côté pour la journée (têtes d'unité). Hors empreinte.
    var setAside: [DayComposerItemID]? = nil
    /// v3 : heure de lancement de la journée (durée réelle). Hors empreinte ; nil avant lancement.
    var startedAt: Date? = nil
    struct Assignment: Codable {
        let id: DayComposerItemID
        let source: DayComposerSource
    }
}

/// Durée estimée d'une journée (préparation). Forfait indicatif, pas une mesure.
/// Limite connue V1 : aucun temps de transition entre exercices.
enum DayComposerDuration {
    /// Forfait d'effort par série, en secondes (×2 pour un exercice unilatéral).
    static let effortSecondsPerSet = 40

    /// Exercice seul : séries × effort + (séries − 1) × repos (inventaire, sinon SupersetRest.defaultSeconds).
    /// Superset : n = max des séries ; n × (effortA + effortB) + (n − 1) × repos du superset.
    static func seconds(_ unit: DayComposerUnit, in snapshot: DayComposerSnapshot) -> Int {
        func sets(_ item: DayComposerItem) -> Int {
            ExerciseCalculator.effectiveSetsCount(scheme: item.scheme, prescription: snapshot.prescriptions[item.id],
                                                  tracking: item.tracking)
        }
        func effort(_ item: DayComposerItem) -> Int { effortSecondsPerSet * (item.unilateral ? 2 : 1) }
        if unit.group != nil {
            let n = unit.items.map(sets).max() ?? 0
            return n * unit.items.map(effort).reduce(0, +) + max(n - 1, 0) * SupersetRest.secondMemberRest(unit.rest)
        }
        return unit.items.map { item in
            let n = sets(item)
            return n * effort(item) + max(n - 1, 0) * (snapshot.restSeconds[item.id] ?? SupersetRest.defaultSeconds)
        }.reduce(0, +)
    }

    /// Somme des unités NON mises de côté.
    static func totalSeconds(_ units: [DayComposerUnit], setAside: Set<DayComposerItemID>,
                             in snapshot: DayComposerSnapshot) -> Int {
        units.filter { !setAside.contains($0.id) }.map { seconds($0, in: snapshot) }.reduce(0, +)
    }

    /// Total affichable : nil quand il ne reste aucune unité requise (jamais « ≈ 0 min »).
    static func totalLabel(_ units: [DayComposerUnit], setAside: Set<DayComposerItemID>,
                           in snapshot: DayComposerSnapshot) -> String? {
        guard !snapshot.isWhollySetAside(setAside) else { return nil }
        return totalLabel(totalSeconds(units, setAside: setAside, in: snapshot))
    }

    /// « ≈ N min », arrondi à la minute, minimum 1 min.
    static func unitLabel(_ seconds: Int) -> String {
        "≈ \(max(1, Int((Double(seconds) / 60).rounded()))) min"
    }

    /// Arrondi aux 5 min : « ≈ 45 min » sous 1 h, « ≈ 1 h 05 » au-delà.
    static func totalLabel(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 300).rounded()) * 5
        return minutes < 60 ? "≈ \(minutes) min" : "≈ \(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }
}

/// Durée réelle envoyée (duration_min), par séance. Calcul pur, sans horloge ni stockage.
/// T = maintenant − startedAt. Part de la séance = T × estimé fait / (estimé fait + estimé
/// fait de l'autre séance) ; si l'autre séance a déjà figé d, la seconde reçoit T − d
/// (somme des deux = durée totale). Arrondi au supérieur comme le chronomètre de la Séance.
/// Jamais bloquant : une valeur invalide donne nil, avec la raison à journaliser.
enum DayComposerActualDuration {
    /// Borne backend (`duration_min_implausible` au-delà, api/routes/workout_logging.py).
    static let maxMinutes = 300

    enum Other {
        /// Pas encore finalisée (ou entièrement mise de côté : doneSeconds = 0).
        case open(doneSeconds: Int)
        /// Déjà finalisée avec la durée figée (nil si elle n'a rien pu envoyer).
        case finalized(minutes: Double?, doneSeconds: Int)
    }

    static func minutes(elapsedSeconds: Double, doneSeconds: Int, other: Other) -> (minutes: Double?, warning: String?) {
        guard elapsedSeconds.isFinite, elapsedSeconds > 0 else { return (nil, "temps écoulé ≤ 0 ou invalide") }
        let share: Double
        switch other {
        case .finalized(let sent?, _):
            share = elapsedSeconds - sent * 60
        case .open(let otherDone), .finalized(nil, let otherDone):
            let total = doneSeconds + otherDone
            share = total == 0 ? elapsedSeconds : elapsedSeconds * Double(doneSeconds) / Double(total)
        }
        guard share > 0 else { return (nil, "durée calculée ≤ 0") }
        let minutes = ExerciseCalculator.netDurationMinutes(seconds: share)
        guard minutes <= maxMinutes else { return (nil, "durée calculée \(minutes) min > \(maxMinutes) min") }
        return (Double(minutes), nil)
    }
}
