import Foundation

struct DayComposerStore {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(date: String, program: String) -> String {
        // Length-prefixed components avoid delimiter collisions.
        "day_composer_order.\(date.utf8.count):\(date).\(program.utf8.count):\(program)"
    }

    func hasSavedOrder(date: String, program: String) -> Bool {
        defaults.object(forKey: key(date: date, program: program)) != nil
    }

    enum Resolution {
        case initial, restored([DayComposerUnit]), incompatible
    }

    func load(_ snapshot: DayComposerSnapshot) throws -> Resolution {
        let key = key(date: snapshot.date, program: snapshot.activeProgramID)
        guard let raw = defaults.object(forKey: key) else { return .initial }
        guard let data = raw as? Data,
              let saved = try? JSONDecoder().decode(DayComposerState.self, from: data),
              (saved.version == 1 || saved.version == 2), saved.date == snapshot.date,
              saved.activeProgramID == snapshot.activeProgramID,
              saved.sourceFingerprint == (try snapshot.fingerprint),
              let units = snapshot.units(for: saved.orderedItemIDs) else { return .incompatible }
        if saved.version == 1 { return .restored(units) }
        guard let assignments = saved.assignments, assignments.count == snapshot.initialIDs.count,
              Set(assignments.map(\.id)) == Set(snapshot.initialIDs) else { return .incompatible }
        let mapping = Dictionary(uniqueKeysWithValues: assignments.map { ($0.id, $0.source) })
        let assigned = units.map { unit in
            DayComposerUnit(items: unit.items.map { item in
                var value = item; value.assignedSourceOverride = mapping[item.id]; return value
            }, group: unit.group, rest: unit.rest)
        }
        guard (try? snapshot.assigning(assigned)) != nil else { return .incompatible }
        return .restored(assigned)
    }

    func save(_ units: [DayComposerUnit], for snapshot: DayComposerSnapshot) throws {
        let ids = units.flatMap { $0.items.map(\.id) }
        guard snapshot.units(for: ids) != nil else { throw DayComposerError.invalidPlan }
        _ = try snapshot.assigning(units)
        let state = DayComposerState(version: 2, date: snapshot.date,
                                     activeProgramID: snapshot.activeProgramID,
                                     sourceFingerprint: try snapshot.fingerprint, orderedItemIDs: ids,
                                     assignments: units.flatMap(\.items).map { .init(id: $0.id, source: $0.assignedSource) })
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: key(date: snapshot.date, program: snapshot.activeProgramID))
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

    func reset(_ snapshot: DayComposerSnapshot) throws {
        try save(snapshot.initialUnits, for: snapshot)
    }

    func clear(date: String, program: String) {
        defaults.removeObject(forKey: key(date: date, program: program))
    }
}
