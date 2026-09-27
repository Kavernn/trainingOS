import Foundation

/// The snapshot and DTOs are produced together, never reconstructed by owners.
struct DayComposerLoadedBundle {
    let snapshot: DayComposerSnapshot
    let morningData: SeanceData
    let eveningData: SeanceData
    fileprivate init(snapshot: DayComposerSnapshot, morningData: SeanceData, eveningData: SeanceData) {
        self.snapshot = snapshot
        self.morningData = morningData
        self.eveningData = eveningData
    }
}

struct DayComposerValidatedExecutionInput {
    let snapshot: DayComposerSnapshot
    let orderedUnits: [DayComposerUnit]
    let context: DayComposerExecutionContext
    let morningData: SeanceData
    let eveningData: SeanceData
    let serverProjection: DayComposerServerProjection

    init(bundle: DayComposerLoadedBundle, orderedItemIDs: [DayComposerItemID],
         serverProjection: DayComposerServerProjection) throws {
        guard let units = bundle.snapshot.units(for: orderedItemIDs),
              serverProjection.date == bundle.snapshot.date else {
            throw DayComposerError.contextChanged
        }
        snapshot = bundle.snapshot
        orderedUnits = units
        context = try DayComposerExecutionContext(snapshot: snapshot)
        morningData = bundle.morningData
        eveningData = bundle.eveningData
        self.serverProjection = serverProjection
    }
}

/// Fresh, read-only projections through existing endpoints. No cache fallback can
/// associate a previous active program's payload with today's captured program.
@MainActor
enum DayComposerLoader {
    struct Context: Decodable {
        let active_program_id: String
        let current_program_id: String
        let full_program: [String: [String: SafeString]]
        let schedule: [String: String]
        let exercise_order: [String: [String]]
    }
    struct Completion: Decodable {
        let today_date: String
        let second_session_completed: Bool
    }

    private static func read<T: Decodable>(_ path: String, date: String? = nil) async throws -> T {
        let url = try APIService.shared.buildURL(path: path,
            queryItems: date.map { [URLQueryItem(name: "date", value: $0)] } ?? [])
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await URLSession.authed.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DayComposerError.unavailable
        }
        return try APIService.decoder.decode(T.self, from: data)
    }

    static func load(program: String) async throws -> DayComposerSnapshot {
        try await loadBundle(program: program).snapshot
    }

    static func loadBundle(program: String) async throws -> DayComposerLoadedBundle {
        guard !program.isEmpty else { throw DayComposerError.contextChanged }
        let date = DateFormatter.isoDate.string(from: Date())
        let before: Context = try await read("/api/programme_data")
        guard before.active_program_id == program, before.current_program_id == program else {
            throw DayComposerError.contextChanged
        }
        let morning: SeanceData = try await read("/api/seance_data", date: date)
        let eveningResponse: SeanceSoirData = try await read("/api/seance_soir_data", date: date)
        guard let evening = eveningResponse.asSeanceData() else { throw DayComposerError.unavailable }
        let completion: Completion = try await read("/api/dashboard", date: date)
        let after: Context = try await read("/api/programme_data")
        return try validate(program: program, date: date,
            currentDate: DateFormatter.isoDate.string(from: Date()),
            weekdayIndex: (Calendar.mtl.component(.weekday, from: Date()) + 5) % 7,
            before: before, after: after, morning: morning, evening: evening, completion: completion)
    }

    /// Same pure snapshot builder for preparation, execution and fixture tests.
    static func validate(program: String, date: String, currentDate: String, weekdayIndex: Int,
                         before: Context, after: Context, morning: SeanceData, evening: SeanceData,
                         completion: Completion) throws -> DayComposerLoadedBundle {
        guard !program.isEmpty, before.active_program_id == program, before.current_program_id == program,
              TrainingDoctrine.dayNames.indices.contains(weekdayIndex) else {
            throw DayComposerError.contextChanged
        }
        guard after.active_program_id == program, after.current_program_id == program,
              morning.todayDate == date, evening.todayDate == date, completion.today_date == date,
              currentDate == date,
              before.full_program.mapValues({ $0.mapValues(\.value) }) == after.full_program.mapValues({ $0.mapValues(\.value) }),
              before.schedule == after.schedule, before.exercise_order == after.exercise_order,
              morning.exerciseSupersets == evening.exerciseSupersets else {
            throw DayComposerError.contextChanged
        }
        func plan(_ data: SeanceData, source: DayComposerSource) throws -> DayComposerPlan {
            var schemes = (data.fullProgram[data.today] ?? [:]).mapValues(\.value)
            if source == .evening {
                let index = weekdayIndex
                let planned = data.schedule[TrainingDoctrine.dayNames[index]]
                schemes = DayComposerPlan.eveningSchemes(schemes,
                    explicitlyPlanned: planned != nil && planned != "" && planned != "Repos",
                    pushedToEvening: data.pushedToEvening)
            }
            let originalNames = Set(before.full_program[data.today]?.keys.map { $0 } ?? [])
            let incoming = Set(schemes.keys).subtracting(originalNames)
            var pairs: [DayComposerPlan.Pair] = []
            for session in data.exerciseSupersets.keys.sorted() {
                for group in (data.exerciseSupersets[session] ?? [:]).keys.sorted() {
                    guard let entry = data.exerciseSupersets[session]?[group] else { continue }
                    // Also preserve a group moved into this source by a day override.
                    guard session == data.today || incoming.contains(entry.a) || incoming.contains(entry.b) else { continue }
                    pairs.append(.init(group: "\(session):\(group)", a: entry.a, b: entry.b, rest: entry.rest))
                }
            }
            return try DayComposerPlan(source: source, session: data.today, schemes: schemes,
                                       order: data.exerciseOrder[data.today] ?? [], exerciseIDs: data.exerciseIds,
                                       tracking: data.inventoryTracking, unilateral: data.inventoryUnilateral, pairs: pairs)
        }
        let snapshot = try DayComposerSnapshot(date: date, activeProgramID: program,
                                       morning: plan(morning, source: .morning), evening: plan(evening, source: .evening),
                                       morningCompleted: morning.alreadyLogged,
                                       eveningCompleted: completion.second_session_completed)
        return DayComposerLoadedBundle(snapshot: snapshot, morningData: morning, eveningData: evening)
    }

    /// Explicit Start/reopen path; passive eligibility never prepares owners.
    static func loadExecution(program: String, orderStore: DayComposerStore = DayComposerStore(),
                              projection: (String) async throws -> DayComposerServerProjection = {
                                  try await DayComposerServerProjection.load(date: $0)
                              }) async throws -> DayComposerValidatedExecutionInput {
        let bundle = try await loadBundle(program: program)
        return try await executionInput(bundle: bundle, orderStore: orderStore, projection: projection)
    }

    static func executionInput(bundle: DayComposerLoadedBundle, orderStore: DayComposerStore,
                               projection: (String) async throws -> DayComposerServerProjection,
                               currentDate: () -> String = { DateFormatter.isoDate.string(from: Date()) }) async throws
        -> DayComposerValidatedExecutionInput {
        let ids: [DayComposerItemID]
        switch try orderStore.load(bundle.snapshot) {
        case .initial: ids = bundle.snapshot.initialIDs
        case .restored(let units): ids = units.flatMap { $0.items.map(\.id) }
        case .incompatible: throw DayComposerError.contextChanged
        }
        let observed = try await projection(bundle.snapshot.date)
        guard currentDate() == bundle.snapshot.date else {
            throw DayComposerError.contextChanged
        }
        return try DayComposerValidatedExecutionInput(bundle: bundle, orderedItemIDs: ids,
                                                       serverProjection: observed)
    }
}
