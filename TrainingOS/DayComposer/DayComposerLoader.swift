import Foundation

/// Ephemeral presentation input, owned by Programme. Preview data never enters
/// the order store or execution owners before IDs/supersets are validated.
@MainActor
final class DayComposerPreparationCandidate {
    let id = UUID()
    let preview: DayComposerSnapshot
    private var enrich: () async throws -> DayComposerSnapshot
    private var pending: Task<DayComposerSnapshot, Error>?
    private(set) var validated: DayComposerSnapshot?

    init(preview: DayComposerSnapshot, enrich: @escaping () async throws -> DayComposerSnapshot) {
        self.preview = preview
        self.enrich = enrich
    }

    func matches(_ other: DayComposerSnapshot) -> Bool {
        preview.date == other.date && preview.activeProgramID == other.activeProgramID
            && (try? preview.fingerprint) == (try? other.fingerprint)
    }

    func updateEnrichment(_ enrich: @escaping () async throws -> DayComposerSnapshot) {
        self.enrich = enrich // Keep visible/validated state and any in-flight work.
    }

    func canPresent(on date: String) -> Bool {
        preview.date == date && !preview.morning.units.isEmpty && !preview.evening.units.isEmpty
    }

    struct Presentation {
        let snapshot: DayComposerSnapshot
        let units: [DayComposerUnit]
        let verified: Bool
        let incompatible: Bool
    }

    func initialPresentation(store: DayComposerStore = DayComposerStore()) -> Presentation {
        let snapshot = validated ?? preview
        guard validated != nil else {
            return Presentation(snapshot: snapshot, units: snapshot.initialUnits, verified: false, incompatible: false)
        }
        switch try? store.load(snapshot) {
        case .restored(let units): return Presentation(snapshot: snapshot, units: units, verified: true, incompatible: false)
        case .initial: return Presentation(snapshot: snapshot, units: snapshot.initialUnits, verified: true, incompatible: false)
        default: return Presentation(snapshot: snapshot, units: snapshot.initialUnits, verified: true, incompatible: true)
        }
    }

    func resolve(refresh: Bool = false) async throws -> DayComposerSnapshot {
        if let pending { return try await pending.value }
        if !refresh, let validated { return validated }
        let task = Task { try await enrich() }
        pending = task
        defer { pending = nil }
        let result = try await task.value
        validated = result
        return result
    }
}

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
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
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

    /// Planning-only representation: no weights, completion or execution reads.
    static func preparationPreview(programme data: Data, evening: [String: String], date: Date) throws -> DayComposerSnapshot? {
        let context = try APIService.decoder.decode(Context.self, from: data)
        guard context.active_program_id == context.current_program_id, !context.active_program_id.isEmpty,
              let am = context.schedule[TrainingDoctrine.dayName(on: date)],
              let pm = evening[TrainingDoctrine.dayName(on: date)],
              let amExercises = context.full_program[am], !amExercises.isEmpty,
              let pmExercises = context.full_program[pm], !pmExercises.isEmpty else { return nil }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let tracking = json["inventory_tracking"] as? [String: String] ?? [:]
        let unilateral = json["inventory_unilateral"] as? [String: Bool] ?? [:]
        return try DayComposerSnapshot(date: DateFormatter.isoDate.string(from: date), activeProgramID: context.active_program_id,
            morning: DayComposerPlan(source: .morning, session: am, schemes: amExercises.mapValues(\.value),
                order: context.exercise_order[am] ?? [], tracking: tracking, unilateral: unilateral),
            evening: DayComposerPlan(source: .evening, session: pm, schemes: pmExercises.mapValues(\.value),
                order: context.exercise_order[pm] ?? [], tracking: tracking, unilateral: unilateral),
            morningCompleted: false, eveningCompleted: false)
    }

    /// Enrichment reuses Programme's AM read. It never refetches the initial
    /// programme or weekly schedule. Execution still uses loadExecution afresh.
    static func enrichPreparation(preview: DayComposerSnapshot, programme: Data,
                                  morning: Task<Data, Error>, transport: @escaping Transport) async throws -> DayComposerSnapshot {
        let before = try APIService.decoder.decode(Context.self, from: programme)
        // Explicit Tasks avoid the async-let lifetime issue documented on iOS beta.
        let pm = Task { () throws -> SeanceSoirData in
            try await read("/api/seance_soir_data", date: preview.date, transport: transport)
        }
        let completion = Task { () throws -> Completion in
            try await read("/api/dashboard", date: preview.date, transport: transport)
        }
        return try await withTaskCancellationHandler {
            defer { pm.cancel(); completion.cancel() }
            let morningData: Data
            do { morningData = try await morning.value }
            catch {
                try Task.checkCancellation()
                // Retry only a failed supporting read; never duplicate a successful one.
                let url = try APIService.shared.buildURL(path: "/api/seance_data", queryItems: [
                    URLQueryItem(name: "date", value: preview.date),
                    URLQueryItem(name: "program_id", value: preview.activeProgramID),
                    URLQueryItem(name: "session_name", value: preview.morning.session)])
                let (bytes, response) = try await transport(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw DayComposerError.unavailable
                }
                morningData = bytes
            }
            let am = try APIService.decoder.decode(SeanceData.self, from: morningData)
            guard let evening = try await pm.value.asSeanceData() else { throw DayComposerError.unavailable }
            let done = try await completion.value
            let after: Context = try await read("/api/programme_data", transport: transport)
            guard am.today == preview.morning.session, evening.today == preview.evening.session,
                  let date = DateFormatter.isoDate.date(from: preview.date),
                  let index = TrainingDoctrine.dayNames.firstIndex(of: TrainingDoctrine.dayName(on: date)) else {
                throw DayComposerError.contextChanged
            }
            let result = try validate(program: preview.activeProgramID, date: preview.date,
                currentDate: DateFormatter.isoDate.string(from: Date()), weekdayIndex: index,
                before: before, after: after, morning: am, evening: evening, completion: done).snapshot
            for (expected, actual) in [(preview.morning, result.morning), (preview.evening, result.evening)] {
                let expectedItems = Dictionary(uniqueKeysWithValues: expected.units.flatMap(\.items).map { ($0.name, $0.scheme) })
                let actualItems = Dictionary(uniqueKeysWithValues: actual.units.flatMap(\.items).map { ($0.name, $0.scheme) })
                guard expectedItems == actualItems else {
                    throw DayComposerError.contextChanged
                }
            }
            return result
        } onCancel: { pm.cancel(); completion.cancel() }
    }

    private static func read<T: Decodable>(_ path: String, date: String? = nil,
                                         transport: Transport) async throws -> T {
        let url = try APIService.shared.buildURL(path: path,
            queryItems: date.map { [URLQueryItem(name: "date", value: $0)] } ?? [])
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DayComposerError.unavailable
        }
        return try APIService.decoder.decode(T.self, from: data)
    }

    static func load(program: String) async throws -> DayComposerSnapshot {
        try await loadBundle(program: program).snapshot
    }

    static func loadBundle(program: String, now: () -> Date = { Date() },
                           transport: Transport = { try await URLSession.authed.data(for: $0) },
                           hasRecovery: (String) throws -> Bool = {
                               try DayComposerProvenanceStore.shared.inventory(date: $0, source: .morning).hasState
                           }) async throws -> DayComposerLoadedBundle {
        guard !program.isEmpty else { throw DayComposerError.contextChanged }
        let capturedDate = now()
        let date = DateFormatter.isoDate.string(from: capturedDate)
        guard let weekdayIndex = TrainingDoctrine.dayNames.firstIndex(of: TrainingDoctrine.dayName(on: capturedDate)) else {
            throw DayComposerError.contextChanged
        }
        let before: Context = try await read("/api/programme_data", transport: transport)
        guard before.active_program_id == program, before.current_program_id == program else {
            throw DayComposerError.contextChanged
        }
        // Same active-program/date resolver as the real Séance tab. Preserve
        // existing recovery; a passive planning refresh must never relabel it.
        let resolved = try await APIService.shared.fetchCurrentPlannedSeance(
            date: capturedDate, preserveRecovery: hasRecovery(date), transport: transport)
        guard resolved.program == program else { throw DayComposerError.contextChanged }
        let morning = resolved.data
        let eveningResponse: SeanceSoirData = try await read("/api/seance_soir_data", date: date, transport: transport)
        guard let evening = eveningResponse.asSeanceData() else { throw DayComposerError.unavailable }
        let completion: Completion = try await read("/api/dashboard", date: date, transport: transport)
        let after: Context = try await read("/api/programme_data", transport: transport)
        return try validate(program: program, date: date,
            currentDate: DateFormatter.isoDate.string(from: now()),
            weekdayIndex: weekdayIndex,
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
