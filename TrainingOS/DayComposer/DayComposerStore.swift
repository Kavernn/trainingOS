import Foundation

struct DayComposerStore {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(date: String, program: String) -> String {
        // Length-prefixed components avoid delimiter collisions.
        "day_composer_order.\(date.utf8.count):\(date).\(program.utf8.count):\(program)"
    }

    /// Ordre sauvegardé = état écrit par `save` (affectations présentes ; v1/v2 n'étaient écrits
    /// que par `save`), jamais par `saveSetAside` seul. Illisible → compté présent : `load` le
    /// signalera incompatible au lieu de le cacher.
    func hasSavedOrder(date: String, program: String) -> Bool {
        guard let raw = defaults.object(forKey: key(date: date, program: program)) else { return false }
        guard let data = raw as? Data,
              let saved = try? JSONDecoder().decode(DayComposerState.self, from: data) else { return true }
        return saved.version < 3 || saved.assignments != nil
    }

    enum Resolution {
        case initial, restored([DayComposerUnit]), incompatible
    }

    func load(_ snapshot: DayComposerSnapshot) throws -> Resolution {
        let key = key(date: snapshot.date, program: snapshot.activeProgramID)
        guard let raw = defaults.object(forKey: key) else { return .initial }
        guard let data = raw as? Data,
              let saved = try? JSONDecoder().decode(DayComposerState.self, from: data),
              (1...3).contains(saved.version), saved.date == snapshot.date,
              saved.activeProgramID == snapshot.activeProgramID,
              saved.sourceFingerprint == (try snapshot.fingerprint) else { return .incompatible }
        let savedIDs = Set(saved.orderedItemIDs)
        guard savedIDs.count == saved.orderedItemIDs.count,
              savedIDs.isSubset(of: Set(snapshot.initialIDs)) else { return .incompatible }
        // An order is not a whitelist. Keep compatible items absent from an
        // older/partial order; execution/save validation remains exhaustive.
        let mergedIDs = saved.orderedItemIDs + snapshot.initialIDs.filter { !savedIDs.contains($0) }
        guard let units = snapshot.units(for: mergedIDs) else { return .incompatible }
        // v1, ou v3 créé par saveSetAside sans état préalable : aucune affectation Matin/Soir.
        if saved.version == 1 || (saved.version == 3 && saved.assignments == nil) { return .restored(units) }
        guard let assignments = saved.assignments,
              Set(assignments.map(\.id)).count == assignments.count,
              Set(assignments.map(\.id)).isSubset(of: Set(snapshot.initialIDs)) else { return .incompatible }
        let mapping = Dictionary(uniqueKeysWithValues: assignments.map { ($0.id, $0.source) })
        let assigned = units.map { unit in
            DayComposerUnit(items: unit.items.map { item in
                var value = item; value.assignedSourceOverride = mapping[item.id]; return value
            }, group: unit.group, rest: unit.rest)
        }
        guard (try? snapshot.assigning(assigned)) != nil else { return .incompatible }
        return .restored(assigned)
    }

    /// Réordonner ou déplacer conserve les mises de côté. Un état présent mais incompatible
    /// échoue fort (contextChanged) : seul `reset` le remplace.
    func save(_ units: [DayComposerUnit], for snapshot: DayComposerSnapshot) throws {
        let existing = try compatibleState(date: snapshot.date, program: snapshot.activeProgramID,
                                           fingerprint: try snapshot.fingerprint)
        try write(units, for: snapshot, setAside: Set(existing?.setAside ?? []), startedAt: existing?.startedAt)
    }

    private func write(_ units: [DayComposerUnit], for snapshot: DayComposerSnapshot,
                       setAside: Set<DayComposerItemID>, startedAt: Date?) throws {
        let ids = units.flatMap { $0.items.map(\.id) }
        guard snapshot.units(for: ids) != nil else { throw DayComposerError.invalidPlan }
        _ = try snapshot.assigning(units)
        let fingerprint = try snapshot.fingerprint
        let state = DayComposerState(version: 3, date: snapshot.date,
                                     activeProgramID: snapshot.activeProgramID,
                                     sourceFingerprint: fingerprint, orderedItemIDs: ids,
                                     assignments: units.flatMap(\.items).map { .init(id: $0.id, source: $0.assignedSource) },
                                     setAside: Self.sorted(setAside), startedAt: startedAt)
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: key(date: snapshot.date, program: snapshot.activeProgramID))
    }

    private static func sorted(_ ids: Set<DayComposerItemID>) -> [DayComposerItemID] {
        ids.sorted { $0.occurrenceKey < $1.occurrenceKey }
    }

    /// Mises de côté du jour. Absent = aucune. Un état présent mais d'une autre journée,
    /// d'un autre programme ou d'un autre plan (empreinte BRUTE) échoue fort.
    func loadSetAside(date: String, program: String, fingerprint: String) throws -> Set<DayComposerItemID> {
        Set(try compatibleState(date: date, program: program, fingerprint: fingerprint)?.setAside ?? [])
    }

    /// Absent = nil. Présent mais d'une autre journée, d'un autre programme, d'un autre plan
    /// (empreinte BRUTE) ou illisible : échec fort, jamais lu comme « absent ».
    private func compatibleState(date: String, program: String, fingerprint: String) throws -> DayComposerState? {
        guard let raw = defaults.object(forKey: key(date: date, program: program)) else { return nil }
        guard let data = raw as? Data, let saved = try? JSONDecoder().decode(DayComposerState.self, from: data),
              (1...3).contains(saved.version), saved.date == date, saved.activeProgramID == program,
              saved.sourceFingerprint == fingerprint else { throw DayComposerError.contextChanged }
        return saved
    }

    /// Heure de lancement de la journée (v3). nil = pas encore lancée, ou lancée avant v3.
    func loadStartedAt(date: String, program: String, fingerprint: String) throws -> Date? {
        try compatibleState(date: date, program: program, fingerprint: fingerprint)?.startedAt
    }

    /// Lancement : réécrit à chaque lancement tant que la journée n'est pas verrouillée
    /// (l'appelant le garantit), figé ensuite. Exige l'état écrit par `save` juste avant.
    func markStarted(_ now: Date, for snapshot: DayComposerSnapshot) throws {
        // Seconde entière : relecture exacte après l'aller-retour JSON (durée en minutes).
        let startedAt = Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate.rounded(.down))
        let fingerprint = try snapshot.fingerprint
        guard var state = try compatibleState(date: snapshot.date, program: snapshot.activeProgramID,
                                              fingerprint: fingerprint) else { throw DayComposerError.contextChanged }
        state.startedAt = startedAt
        defaults.set(try JSONEncoder().encode(state), forKey: key(date: snapshot.date, program: snapshot.activeProgramID))
        guard try loadStartedAt(date: snapshot.date, program: snapshot.activeProgramID,
                                fingerprint: fingerprint) == startedAt else { throw DayComposerError.contextChanged }
    }

    /// Écriture dédiée : ne touche ni l'ordre ni les affectations Matin/Soir, n'est donc pas
    /// soumise au verrouillage des créneaux. `orderedIDs` sert seulement si aucun état n'existe.
    func saveSetAside(_ ids: Set<DayComposerItemID>, date: String, program: String, fingerprint: String,
                      orderedIDs: [DayComposerItemID]) throws {
        let storageKey = key(date: date, program: program)
        var state: DayComposerState
        if let saved = try compatibleState(date: date, program: program, fingerprint: fingerprint) {
            state = DayComposerState(version: 3, date: date, activeProgramID: program, sourceFingerprint: fingerprint,
                                     orderedItemIDs: saved.orderedItemIDs, assignments: saved.assignments,
                                     startedAt: saved.startedAt)
        } else {
            state = DayComposerState(version: 3, date: date, activeProgramID: program, sourceFingerprint: fingerprint,
                                     orderedItemIDs: orderedIDs)
        }
        state.setAside = Self.sorted(ids)
        defaults.set(try JSONEncoder().encode(state), forKey: storageKey)
        guard try loadSetAside(date: date, program: program, fingerprint: fingerprint) == ids else {
            throw DayComposerError.contextChanged
        }
    }

    @MainActor
    static func sourcesLocked(_ snapshot: DayComposerSnapshot) -> Bool {
        if snapshot.morningCompleted || snapshot.eveningCompleted { return true }
        let provenance = DayComposerProvenanceStore.shared
        do {
            if try provenance.load(date: snapshot.date) != nil { return true }
            if try !DayComposerFinalizationStore().candidateRecords(date: snapshot.date, source: .morning).isEmpty
                || !DayComposerFinalizationStore().candidateRecords(date: snapshot.date, source: .evening).isEmpty { return true }
            return try provenance.inventory(date: snapshot.date, source: .morning).hasState
                || provenance.inventory(date: snapshot.date, source: .evening).hasState
        } catch { return true }
    }

    /// « Restaurer la journée » : état neuf, mises de côté effacées. Ne relit rien, donc
    /// remplace aussi explicitement un état incompatible (autre plan, illisible).
    func reset(_ snapshot: DayComposerSnapshot) throws {
        try write(snapshot.initialUnits, for: snapshot, setAside: [], startedAt: nil)
    }

    func clear(date: String, program: String) {
        defaults.removeObject(forKey: key(date: date, program: program))
    }
}
