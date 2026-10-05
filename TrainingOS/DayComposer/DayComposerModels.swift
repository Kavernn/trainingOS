import Foundation
import CryptoKit

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
            morningCompleted: morningCompleted, eveningCompleted: eveningCompleted)
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
    struct Assignment: Codable {
        let id: DayComposerItemID
        let source: DayComposerSource
    }
}
