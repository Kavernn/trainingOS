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
              saved.version == 1, saved.date == snapshot.date,
              saved.activeProgramID == snapshot.activeProgramID,
              saved.sourceFingerprint == (try snapshot.fingerprint),
              let units = snapshot.units(for: saved.orderedItemIDs) else { return .incompatible }
        return .restored(units)
    }

    func save(_ units: [DayComposerUnit], for snapshot: DayComposerSnapshot) throws {
        let ids = units.flatMap { $0.items.map(\.id) }
        guard snapshot.units(for: ids) != nil else { throw DayComposerError.invalidPlan }
        let state = DayComposerState(version: 1, date: snapshot.date,
                                     activeProgramID: snapshot.activeProgramID,
                                     sourceFingerprint: try snapshot.fingerprint, orderedItemIDs: ids)
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: key(date: snapshot.date, program: snapshot.activeProgramID))
    }

    func reset(_ snapshot: DayComposerSnapshot) throws {
        try save(snapshot.initialUnits, for: snapshot)
    }

    func clear(date: String, program: String) {
        defaults.removeObject(forKey: key(date: date, program: program))
    }
}
