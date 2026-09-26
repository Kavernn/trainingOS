import SwiftUI

/// Fresh, read-only projections through existing endpoints. No cache fallback can
/// associate a previous active program's payload with today's captured program.
@MainActor
private enum DayComposerLoader {
    private struct Context: Decodable {
        let active_program_id: String
        let current_program_id: String
        let full_program: [String: [String: SafeString]]
        let schedule: [String: String]
        let exercise_order: [String: [String]]
    }
    private struct Completion: Decodable {
        let today_date: String
        let second_session_completed: Bool
    }

    private static func read<T: Decodable>(_ path: String) async throws -> T {
        let url = try APIService.shared.buildURL(path: path)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await URLSession.authed.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DayComposerError.unavailable
        }
        return try APIService.decoder.decode(T.self, from: data)
    }

    static func load(program: String) async throws -> DayComposerSnapshot {
        guard !program.isEmpty else { throw DayComposerError.contextChanged }
        let date = DateFormatter.isoDate.string(from: Date())
        let before: Context = try await read("/api/programme_data")
        guard before.active_program_id == program, before.current_program_id == program else {
            throw DayComposerError.contextChanged
        }
        let morning: SeanceData = try await read("/api/seance_data")
        let eveningResponse: SeanceSoirData = try await read("/api/seance_soir_data")
        guard let evening = eveningResponse.asSeanceData() else { throw DayComposerError.unavailable }
        let completion: Completion = try await read("/api/dashboard")
        let after: Context = try await read("/api/programme_data")
        guard after.active_program_id == program, after.current_program_id == program,
              morning.todayDate == date, evening.todayDate == date, completion.today_date == date,
              DateFormatter.isoDate.string(from: Date()) == date,
              before.full_program.mapValues({ $0.mapValues(\.value) }) == after.full_program.mapValues({ $0.mapValues(\.value) }),
              before.schedule == after.schedule, before.exercise_order == after.exercise_order,
              morning.exerciseSupersets == evening.exerciseSupersets else {
            throw DayComposerError.contextChanged
        }
        func plan(_ data: SeanceData, source: DayComposerSource) throws -> DayComposerPlan {
            var schemes = (data.fullProgram[data.today] ?? [:]).mapValues(\.value)
            if source == .evening {
                let index = (Calendar.mtl.component(.weekday, from: Date()) + 5) % 7
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
        return try DayComposerSnapshot(date: date, activeProgramID: program,
                                       morning: plan(morning, source: .morning), evening: plan(evening, source: .evening),
                                       morningCompleted: morning.alreadyLogged,
                                       eveningCompleted: completion.second_session_completed)
    }
}

/// Merely displaying Today reads eligibility; it never creates a saved order.
struct DayComposerTodayEntry: View {
    let activeProgramID: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var eligible = false
    @State private var refresh = UUID()

    var body: some View {
        Group {
            if eligible {
                NavigationLink {
                    DayComposerView(activeProgramID: activeProgramID)
                } label: {
                    Label("Réorganiser ma journée", systemImage: "arrow.up.arrow.down")
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.forge)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Prépare un ordre local pour les séances du matin et du soir.")
            }
        }
        .task(id: "\(activeProgramID):\(refresh)") {
            eligible = false
            do {
                let snapshot = try await DayComposerLoader.load(program: activeProgramID)
                guard !Task.isCancelled else { return }
                eligible = snapshot.isRelevant(hasSavedOrder: DayComposerStore().hasSavedOrder(
                    date: snapshot.date, program: snapshot.activeProgramID))
            } catch { eligible = false }
        }
        .onAppear { refresh = UUID() }
        .onChange(of: scenePhase) { _, phase in
            eligible = false
            if phase == .active { refresh = UUID() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .planOverridesDidChange)) { _ in
            eligible = false
            refresh = UUID()
        }
    }
}

struct DayComposerView: View {
    let activeProgramID: String
    @ObservedObject private var appTheme = AppTheme.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: DayComposerSnapshot?
    @State private var units: [DayComposerUnit] = []
    @State private var incompatible = false
    @State private var loading = true
    @State private var error: String?
    @State private var refresh = UUID()
    private let store = DayComposerStore()

    var body: some View {
        List {
            if loading {
                ProgressView("Chargement de la journée…")
            } else if let snapshot {
                Section {
                    Text("2 séances · \(snapshot.initialIDs.count) exercices")
                        .font(.appBody.weight(.semibold))
                    Text("Prépare l’ordre pour aujourd’hui. L’exécution reste disponible séparément dans Matin et Soir.")
                        .font(.appCaption).foregroundColor(.appTextSecondary)
                    if incompatible {
                        Text("La journée a changé ou l’ordre sauvegardé est incompatible. L’ordre source est affiché. Réinitialise-le pour reprendre la préparation.")
                            .foregroundColor(.appTextSecondary)
                    }
                }
                Section("Ordre du jour") {
                    ForEach(Array(units.enumerated()), id: \.element.id) { index, unit in
                        unitRow(unit, index: index, snapshot: snapshot)
                            .moveDisabled(incompatible || loading)
                    }
                    .onMove { offsets, destination in
                        move(from: offsets, to: destination)
                    }
                }
                Section {
                    Button("Réinitialiser l’ordre") { reset(snapshot) }
                        .frame(minHeight: 44)
                        .foregroundColor(.forge)
                }
            }
            if let error {
                Section {
                    Text(error).foregroundColor(.appTextSecondary)
                    Button("Réessayer") { refresh = UUID() }.frame(minHeight: 44)
                }
            }
        }
        .foregroundColor(.appTextPrimary)
        .scrollContentBackground(.hidden)
        .background(Color.appBg)
        .navigationTitle("Ma journée")
        .environment(\.editMode, .constant(.active))
        .task(id: refresh) { await reload() }
        .onChange(of: scenePhase) { _, phase in
            loading = true
            if phase == .active { refresh = UUID() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .planOverridesDidChange)) { _ in
            loading = true
            refresh = UUID()
        }
    }

    private func unitRow(_ unit: DayComposerUnit, index: Int, snapshot: DayComposerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(unit.source.title)
                    .font(.appCaption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.appSurfaceInset).clipShape(Capsule())
                if unit.group != nil { Text("Superset").font(.appCaption) }
                if snapshot.completed(unit.source) {
                    Label("Séance terminée", systemImage: "checkmark.circle")
                        .font(.appCaption).foregroundColor(.appTextSecondary)
                }
            }
            ForEach(unit.items) { item in
                Text(item.name).font(.appBody)
            }
            // Visible alternatives support keyboard use without dragging.
            HStack {
                Button("Monter") { move(from: IndexSet(integer: index), to: index - 1) }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(index == 0 || incompatible)
                Button("Descendre") { move(from: IndexSet(integer: index), to: index + 2) }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(index == units.count - 1 || incompatible)
            }
            .font(.appCaption).buttonStyle(.borderless)
            .frame(minHeight: 44).accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.appCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unit.items.map(\.name).joined(separator: ", ")). \(unit.source.title). \(unit.group == nil ? "" : "Superset. ")Position \(index + 1) sur \(units.count).\(snapshot.completed(unit.source) ? " Séance terminée." : "")")
        .accessibilityActions {
            if !incompatible && index > 0 {
                Button("Monter") { move(from: IndexSet(integer: index), to: index - 1) }
            }
            if !incompatible && index < units.count - 1 {
                Button("Descendre") { move(from: IndexSet(integer: index), to: index + 2) }
            }
        }
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        guard !loading, !incompatible, let snapshot,
              snapshot.date == DateFormatter.isoDate.string(from: Date()) else { return }
        let updated = DayComposerSnapshot.moving(units, from: offsets, to: destination)
        guard updated != units else { return }
        do {
            try store.save(updated, for: snapshot)
            units = updated
            error = nil
        } catch { self.error = "Impossible de sauvegarder cet ordre local." }
    }

    private func reset(_ snapshot: DayComposerSnapshot) {
        guard !loading, snapshot.date == DateFormatter.isoDate.string(from: Date()) else { return }
        do {
            try store.reset(snapshot)
            units = snapshot.initialUnits
            incompatible = false
            error = nil
        } catch { self.error = "Impossible de réinitialiser cet ordre local." }
    }

    @MainActor
    private func reload() async {
        loading = true
        snapshot = nil
        error = nil
        do {
            let fresh = try await DayComposerLoader.load(program: activeProgramID)
            guard !Task.isCancelled else { return }
            guard fresh.isRelevant(hasSavedOrder: store.hasSavedOrder(date: fresh.date, program: fresh.activeProgramID)) else {
                throw DayComposerError.unavailable
            }
            let resolution = try store.load(fresh)
            snapshot = fresh
            units = fresh.initialUnits
            incompatible = false
            switch resolution {
            case .initial: break
            case .restored(let saved): units = saved
            case .incompatible: incompatible = true
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "La préparation nécessite deux séances compatibles et le programme actif actuel. Reviens à Aujourd’hui ou réessaie."
        }
        loading = false
    }
}
