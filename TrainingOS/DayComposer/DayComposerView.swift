import SwiftUI

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
    @State private var launch: DayComposerLaunch?
    @State private var starting = false
    @State private var executionAllowed = false

    var body: some View {
        List {
            if loading {
                ProgressView("Chargement de la journée…")
            } else if let snapshot {
                Section {
                    Text("2 séances · \(snapshot.initialIDs.count) exercices")
                        .font(.appBody.weight(.semibold))
                    Text("Choisis l’ordre d’aujourd’hui. Chaque exercice reste rattaché à sa séance du matin ou du soir.")
                        .font(.appCaption).foregroundColor(.appTextSecondary)
                    if incompatible {
                        Text("La journée a changé ou l’ordre sauvegardé est incompatible. L’ordre source est affiché. Réinitialise-le pour reprendre la préparation.")
                            .foregroundColor(.appTextSecondary)
                    }
                    if !executionAllowed {
                        Text("Des données de séance doivent être vérifiées avant de démarrer cette journée. Les saisies existantes sont conservées.")
                            .font(.appCaption).foregroundColor(.appTextSecondary)
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
                    Button(starting ? "Préparation…" : "Commencer") {
                        Task { await start() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(starting || !executionAllowed || !snapshot.canStart(orderedIDs: units.flatMap { $0.items.map(\.id) },
                        activeProgram: activeProgramID, date: DateFormatter.isoDate.string(from: Date()),
                        loading: loading, incompatible: incompatible))
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
        .disabled(starting)
        .fullScreenCover(item: $launch, onDismiss: { refresh = UUID() }) { session in
            NavigationStack {
                DayComposerActiveView(coordinator: session.coordinator, stabilizationBarrier: session.barrier,
                    finishCoordinator: session.finish, onDismiss: { launch = nil })
            }
        }
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

    @MainActor private func start() async {
        guard !starting, executionAllowed, let snapshot,
              snapshot.canStart(orderedIDs: units.flatMap { $0.items.map(\.id) }, activeProgram: activeProgramID,
                date: DateFormatter.isoDate.string(from: Date()), loading: loading, incompatible: incompatible) else { return }
        starting = true
        defer { starting = false }
        do {
            try store.save(units, for: snapshot)
            let input = try await DayComposerLoader.loadExecution(program: activeProgramID, orderStore: store)
            guard !Task.isCancelled, input.context.date == snapshot.date,
                  try input.snapshot.fingerprint == snapshot.fingerprint else { throw DayComposerError.contextChanged }
            let coordinator = try DayComposerExecutionCoordinator.make(validatedInput: input)
            let barrier = try coordinator.makeStabilizationBarrier()
            let finish = try coordinator.makeFinishCoordinator()
            launch = .init(coordinator: coordinator, barrier: barrier, finish: finish)
        } catch {
            self.error = "La journée n’est plus prête à démarrer. Tes données sont conservées. Recharge la journée pour vérifier son contenu."
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
        executionAllowed = false
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
            let context = try DayComposerExecutionContext(snapshot: fresh)
            let provenance = DayComposerProvenanceStore.shared
            switch (provenance.admission(context: context, source: .morning),
                    provenance.admission(context: context, source: .evening)) {
            case (.fresh, .fresh): executionAllowed = true
            case (.validated(let a, _), .validated(let b, _)): executionAllowed = a == b
            default: executionAllowed = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "La préparation nécessite deux séances compatibles et le programme actif actuel. Reviens à Aujourd’hui ou réessaie."
        }
        loading = false
    }
}

private struct DayComposerLaunch: Identifiable {
    let id = UUID()
    let coordinator: DayComposerExecutionCoordinator
    let barrier: DayComposerLocalStabilizationBarrier
    let finish: DayComposerFinishCoordinator
}
