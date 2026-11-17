import SwiftUI

/// Pure presentation of Programme's validated planning. No eligibility request.
struct DayComposerTodayEntry: View {
    let candidate: DayComposerPreparationCandidate

    var body: some View {
        VStack(spacing: 0) {
            if candidate.canPresent(on: DateFormatter.isoDate.string(from: Date())) {
                NavigationLink {
                    DayComposerView(candidate: candidate)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("Réorganiser ma journée", systemImage: "arrow.up.arrow.down")
                            Spacer()
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        Text("Aujourd’hui seulement · ton programme reste inchangé")
                            .font(.appCaption).foregroundColor(.appTextSecondary)
                    }
                        .font(.appLabel.weight(.semibold))
                        .foregroundColor(.forge)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(14)
                        .background(Color.appCard, in: RoundedRectangle(cornerRadius: .appCardRadius))
                        .overlay(RoundedRectangle(cornerRadius: .appCardRadius)
                            .stroke(Color.forge.opacity(0.3), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Change l’ordre et les créneaux pour aujourd’hui seulement. Ton programme reste inchangé.")
            }
        }
    }
}

struct DayComposerView: View {
    let candidate: DayComposerPreparationCandidate
    private var activeProgramID: String { candidate.preview.activeProgramID }
    @ObservedObject private var appTheme = AppTheme.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: DayComposerSnapshot?
    @State private var units: [DayComposerUnit] = []
    @State private var incompatible = false
    @State private var loading = true
    @State private var error: String?
    @State private var refresh = UUID()
    private let store = DayComposerStore()
    private var fixtureOnly = false
    @State private var launch: DayComposerLaunch?
    @State private var starting = false
    @State private var executionAllowed = false
    @State private var verified = false
    @State private var refreshing = false
    @State private var sourcesLocked = true
    @State private var didValidate = false
    @State private var validationToken = UUID()
    @State private var representedCandidateID: UUID
    /// Mises de côté du jour (têtes d'unité), lues/écrites via DayComposerStore v3.
    @State private var setAside: Set<DayComposerItemID> = []
    @State private var setAsideMessage: (unit: DayComposerItemID, text: String)?
    @State private var setAsideToggles = 0

    init(candidate: DayComposerPreparationCandidate) {
        self.candidate = candidate
        _representedCandidateID = State(initialValue: candidate.id)
        let initial = candidate.initialPresentation()
        _snapshot = State(initialValue: initial.snapshot)
        _units = State(initialValue: initial.units)
        _incompatible = State(initialValue: initial.incompatible)
        _verified = State(initialValue: initial.verified)
        _loading = State(initialValue: false)
    }

    #if DEBUG
    static func preparationFixture(moved: Bool, locked: Bool = false, superset: Bool = false) throws -> DayComposerView {
        let date = DateFormatter.isoDate.string(from: Date())
        let snapshot = try DayComposerSnapshot(date: date, activeProgramID: "r13-visual-fixture",
            morning: .init(source: .morning, session: "AM",
                schemes: superset ? ["Curl": "3×8", "Press": "3×8", "Squat": "3×5"] : ["Curl": "3×8", "Squat": "3×5"],
                order: ["Curl", "Press", "Squat"],
                pairs: superset ? [.init(group: "SS", a: "Curl", b: "Press", rest: 90)] : []),
            evening: .init(source: .evening, session: "PM", schemes: ["Curl": "3×8", "Row": "3×8"], order: ["Curl", "Row"]),
            morningCompleted: false, eveningCompleted: false)
        let candidate = DayComposerPreparationCandidate(preview: snapshot, enrich: { snapshot })
        var view = DayComposerView(candidate: candidate)
        view.fixtureOnly = true
        view._verified = State(initialValue: true)
        view._executionAllowed = State(initialValue: true)
        view._sourcesLocked = State(initialValue: locked)
        view._units = State(initialValue: moved ? try DayComposerSnapshot.transferring(snapshot.initialUnits,
            id: snapshot.evening.units[0].id, locked: false) : snapshot.initialUnits)
        return view
    }
    #endif

    var body: some View {
        List {
            if loading {
                ProgressView("Chargement de la journée…")
            } else if let snapshot {
                Section {
                    Text("2 séances · \(snapshot.initialIDs.count) exercices\(totalDurationSuffix(snapshot))")
                        .font(.appBody.weight(.semibold))
                    Text(countsLine)
                        .font(.appCaption)
                    if sourcesLocked {
                        Text("Les créneaux ne peuvent plus être modifiés après le début de la journée.")
                            .font(.appCaption).foregroundColor(.appTextSecondary)
                        Text(DayComposerSetAsidePresentation.lockedPreparationHint)
                            .font(.appCaption).foregroundColor(.appTextSecondary)
                    }
                    if refreshing {
                        ProgressView("Vérification des identifiants et supersets…")
                            .font(.appCaption)
                    }
                    Text("Ton programme reste inchangé. Change l’ordre ou déplace une unité vers Matin ou Soir, pour aujourd’hui seulement.")
                        .font(.appCaption).foregroundColor(.appTextSecondary)
                    ForEach(snapshot.initialUnits.flatMap(\.items).filter {
                        !DayComposerExecutionCoordinator.isSupported($0.tracking)
                    }, id: \.id) { item in
                        Text("Commencer indisponible : \(item.name) · \(item.assignedSource.title) · type non pris en charge : \(item.tracking)")
                            .font(.appCaption).foregroundColor(.appTextSecondary)
                    }
                    if incompatible {
                        Text("La journée a changé ou l’ordre sauvegardé est incompatible. L’ordre source est affiché. Réinitialise-le pour reprendre la préparation.")
                            .foregroundColor(.appTextSecondary)
                    }
                    if !executionAllowed && !refreshing {
                        Text("Des données de séance doivent être vérifiées avant de démarrer cette journée. Les saisies existantes sont conservées.")
                            .font(.appCaption).foregroundColor(.appTextSecondary)
                    }
                }
                .listRowBackground(Color.appCard)
                Section("Ordre du jour") {
                    Text("Glisse les poignées ou utilise les flèches. Les supersets se déplacent ensemble.")
                        .font(.appCaption).foregroundColor(.appTextSecondary)
                    ForEach(Array(units.enumerated()), id: \.element.id) { index, unit in
                        unitRow(unit, index: index, snapshot: snapshot)
                            .moveDisabled(incompatible || loading || !verified || sourcesLocked)
                    }
                    .onMove { offsets, destination in
                        move(from: offsets, to: destination)
                    }
                }
                .listRowBackground(Color.appCard)
                Section {
                    Button(starting ? "Préparation…" : "Commencer") {
                        Task { await start() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderedProminent).tint(Color.forge)
                    .accessibilityHint("Ouvre l’entraînement dans l’ordre affiché, sans changer ton programme.")
                    .disabled(starting || !executionAllowed || snapshot.isWhollySetAside(setAside)
                        || !snapshot.canStart(orderedIDs: units.flatMap { $0.items.map(\.id) },
                        activeProgram: activeProgramID, date: DateFormatter.isoDate.string(from: Date()),
                        loading: loading, incompatible: incompatible))
                    Button("Restaurer la journée") { reset(snapshot) }
                        .frame(minHeight: 44)
                        .foregroundColor(.forge)
                        .buttonStyle(.borderless)
                        .disabled(!verified || sourcesLocked)
                }
                .listRowBackground(Color.appCard)
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
        .task(id: "\(candidate.id):\(refresh)") { if !fixtureOnly { await reload() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh = UUID() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .planOverridesDidChange)) { _ in
            refresh = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .activeProgrammePlanningDidChange)) { _ in refresh = UUID() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refresh = UUID() }
        .sensoryFeedback(.impact(weight: .light), trigger: setAsideToggles)
    }

    /// Durées estimées : uniquement sur un snapshot vérifié (repos et prescriptions réels) ;
    /// l'aperçu non vérifié n'affiche rien plutôt qu'une valeur inventée.
    private func totalDurationSuffix(_ snapshot: DayComposerSnapshot) -> String {
        guard verified else { return "" }
        return " · " + DayComposerDuration.totalLabel(
            DayComposerDuration.totalSeconds(units, setAside: setAside, in: snapshot))
    }

    private func unitDurationLabel(_ unit: DayComposerUnit, snapshot: DayComposerSnapshot) -> String? {
        guard verified, !setAside.contains(unit.id) else { return nil }
        return DayComposerDuration.unitLabel(DayComposerDuration.seconds(unit, in: snapshot))
    }

    /// Compteurs hors mises de côté, plus le nombre d'exercices mis de côté s'il y en a.
    private var countsLine: String {
        func count(_ source: DayComposerSource) -> Int {
            units.filter { $0.source == source && !setAside.contains($0.id) }.flatMap(\.items).count
        }
        let asideCount = units.filter { setAside.contains($0.id) }.flatMap(\.items).count
        let base = "Matin : \(count(.morning)) · Soir : \(count(.evening))"
        // Incompatible : mises de côté inconnues, jamais affichées comme « aucune ».
        return asideCount == 0 || incompatible ? base : base + " · \(asideCount) mis de côté"
    }

    /// Invariant : la préparation n'agit que créneaux NON verrouillés. `sourcesLocked` couvre
    /// séance terminée, provenance d'exécution, candidats de finalisation, inventaire local
    /// (DayComposerStore.sourcesLocked) et logs observés côté serveur (positivelyObserved,
    /// voir reload). Aucun log n'existe donc ici → anyLogged = false pour la règle commune.
    private func toggleSetAside(_ unit: DayComposerUnit) {
        guard verified, !loading, !incompatible, let snapshot,
              snapshot.date == DateFormatter.isoDate.string(from: Date()) else { return }
        guard !sourcesLocked, !DayComposerStore.sourcesLocked(snapshot) else { return }
        var next = setAside
        if next.contains(unit.id) {
            next.remove(unit.id)
        } else {
            guard !snapshot.setAsideEmptiesUnloggedDay(unit.id, setAside: setAside, anyLogged: false) else {
                setAsideMessage = (unit.id, DayComposerSetAsidePresentation.message(for: .lastUnitOfDay))
                return
            }
            next.insert(unit.id)
        }
        do {
            try store.saveSetAside(next, date: snapshot.date, program: snapshot.activeProgramID,
                fingerprint: try snapshot.fingerprint, orderedIDs: units.flatMap { $0.items.map(\.id) })
            setAside = next
            setAsideMessage = nil
            setAsideToggles += 1
        } catch DayComposerError.contextChanged {
            setAsideMessage = (unit.id, DayComposerSetAsidePresentation.message(for: .locked))
        } catch {
            setAsideMessage = (unit.id, DayComposerSetAsidePresentation.message(for: .persistence))
        }
    }

    @MainActor private func start() async {
        guard !starting, executionAllowed, let snapshot, !snapshot.isWhollySetAside(setAside),
              snapshot.canStart(orderedIDs: units.flatMap { $0.items.map(\.id) }, activeProgram: activeProgramID,
                date: DateFormatter.isoDate.string(from: Date()), loading: loading, incompatible: incompatible) else { return }
        starting = true
        defer { starting = false }
        do {
            if !DayComposerStore.sourcesLocked(snapshot) { try store.save(units, for: snapshot) }
            let input = try await DayComposerLoader.loadExecution(program: activeProgramID, orderStore: store)
            guard !Task.isCancelled, input.context.date == snapshot.date,
                  input.planningFingerprint == (try snapshot.fingerprint),
                  input.snapshot.morning.session == snapshot.morning.session,
                  input.snapshot.evening.session == snapshot.evening.session else { throw DayComposerError.contextChanged }
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
                Text("\(index + 1)").font(.appCaption.monospacedDigit()).foregroundColor(.appTextSecondary)
                DayComposerSourceChip(source: unit.source)
                if unit.group != nil { Text("Superset").font(.appCaption) }
                if snapshot.completed(unit.source) {
                    Label("Séance terminée", systemImage: "checkmark.circle")
                        .font(.appCaption).foregroundColor(.appTextSecondary)
                }
                if let label = unitDurationLabel(unit, snapshot: snapshot) {
                    Text(label).font(.appCaption).foregroundColor(.appTextSecondary)
                }
                Spacer(minLength: 8)
                if !incompatible {
                    Button(DayComposerSetAsidePresentation.toggleTitle(isSetAside: setAside.contains(unit.id))) {
                        toggleSetAside(unit)
                    }
                    .font(.appCaption.weight(.semibold))
                    .buttonStyle(.borderless).foregroundColor(.forge)
                    .frame(minHeight: 44).contentShape(Rectangle())
                    .disabled(sourcesLocked || !verified || loading)
                }
            }
            if let message = setAsideMessage, message.unit == unit.id {
                Text(message.text).font(.appCaption).foregroundColor(.appTextSecondary)
            }
            if setAside.contains(unit.id) {
                Text("Mis de côté aujourd’hui").font(.appCaption).foregroundColor(.appTextSecondary)
            }
            ForEach(unit.items) { item in
                Text(item.name).font(.appBody)
                    .foregroundColor(setAside.contains(unit.id) ? .appTextSecondary : .appTextPrimary)
            }
            Button("Déplacer vers \(unit.source == .morning ? "Soir" : "Matin")") { transfer(unit) }
                .buttonStyle(.borderless).frame(minHeight: 44)
                .disabled(sourcesLocked || !verified || incompatible)
            if unit.group != nil {
                Text("Tout le superset sera déplacé.").font(.appCaption).foregroundColor(.appTextSecondary)
            }
            if unit.items.contains(where: { $0.originSource != $0.assignedSource }) {
                Text("Déplacé depuis \(unit.items[0].originSource.title)").font(.appCaption).foregroundColor(.appTextSecondary)
            }
            // Visible alternatives support keyboard use without dragging.
            HStack {
                Button { move(from: IndexSet(integer: index), to: index - 1) } label: {
                    Label("Monter", systemImage: "arrow.up")
                }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(index == 0 || incompatible || !verified || sourcesLocked)
                Button { move(from: IndexSet(integer: index), to: index + 2) } label: {
                    Label("Descendre", systemImage: "arrow.down")
                }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(index == units.count - 1 || incompatible || !verified || sourcesLocked)
            }
            .font(.appCaption).buttonStyle(.borderless)
            .frame(minHeight: 44).accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.appCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unit.items.map(\.name).joined(separator: ", ")). \(unit.source.title). \(unit.group == nil ? "" : "Superset. ")Position \(index + 1) sur \(units.count).\(snapshot.completed(unit.source) ? " Séance terminée." : "")\(setAside.contains(unit.id) ? " Mis de côté aujourd’hui." : "")\(unitDurationLabel(unit, snapshot: snapshot).map { " Durée estimée \($0)." } ?? "")")
        .accessibilityActions {
            if verified && !incompatible && !sourcesLocked && !loading {
                Button(DayComposerSetAsidePresentation.toggleTitle(isSetAside: setAside.contains(unit.id))) {
                    toggleSetAside(unit)
                }
            }
            if verified && !incompatible && !sourcesLocked {
                Button("Déplacer \(unit.items.map(\.name).joined(separator: ", ")) vers \(unit.source == .morning ? "Soir" : "Matin")") { transfer(unit) }
            }
            if verified && !incompatible && !sourcesLocked && index > 0 {
                Button("Monter") { move(from: IndexSet(integer: index), to: index - 1) }
            }
            if verified && !incompatible && !sourcesLocked && index < units.count - 1 {
                Button("Descendre") { move(from: IndexSet(integer: index), to: index + 2) }
            }
        }
    }

    private func transfer(_ unit: DayComposerUnit) {
        guard verified, !loading, !incompatible, let snapshot,
              snapshot.date == DateFormatter.isoDate.string(from: Date()) else { return }
        do {
            sourcesLocked = sourcesLocked || DayComposerStore.sourcesLocked(snapshot)
            let updated = try DayComposerSnapshot.transferring(units, id: unit.id, locked: sourcesLocked)
            try store.save(updated, for: snapshot)
            units = updated
            error = nil
        } catch DayComposerError.emptySource {
            error = "Garde au moins un exercice dans chaque séance."
        } catch DayComposerError.executionStarted {
            error = "Les créneaux ne peuvent plus être modifiés après le début de la journée."
        } catch { self.error = "Ce groupe ne peut pas être déplacé en sécurité. Les données sont conservées." }
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        guard verified, !loading, !incompatible, let snapshot,
              snapshot.date == DateFormatter.isoDate.string(from: Date()) else { return }
        guard !sourcesLocked, !DayComposerStore.sourcesLocked(snapshot) else { return }
        let updated = DayComposerSnapshot.moving(units, from: offsets, to: destination)
        guard updated != units else { return }
        do {
            try store.save(updated, for: snapshot)
            units = updated
            error = nil
        } catch { self.error = "Impossible de sauvegarder cet ordre local." }
    }

    private func reset(_ snapshot: DayComposerSnapshot) {
        guard verified, !loading, snapshot.date == DateFormatter.isoDate.string(from: Date()) else { return }
        guard !sourcesLocked, !DayComposerStore.sourcesLocked(snapshot) else { return }
        do {
            try store.reset(snapshot)
            units = snapshot.initialUnits
            setAside = []
            setAsideMessage = nil
            incompatible = false
            error = nil
        } catch { self.error = "Impossible de réinitialiser cet ordre local." }
    }

    @MainActor
    private func reload() async {
        let token = UUID()
        validationToken = token
        defer { if validationToken == token { refreshing = false } }
        if representedCandidateID != candidate.id {
            let initial = candidate.initialPresentation()
            snapshot = initial.snapshot
            units = initial.units
            incompatible = initial.incompatible
            verified = initial.verified
            representedCandidateID = candidate.id
            didValidate = false
            setAside = []
            setAsideMessage = nil
        }
        refreshing = true
        sourcesLocked = true
        executionAllowed = false
        error = nil
        do {
            let refreshValidated = didValidate
            didValidate = true
            let fresh = try await candidate.resolve(refresh: refreshValidated)
            guard !Task.isCancelled else { return }
            guard fresh.isRelevant(hasSavedOrder: store.hasSavedOrder(date: fresh.date, program: fresh.activeProgramID)) else {
                throw DayComposerError.unavailable
            }
            let resolution = try store.load(fresh)
            snapshot = fresh
            verified = true
            units = fresh.initialUnits
            incompatible = false
            switch resolution {
            case .initial: break
            case .restored(let saved): units = saved
            case .incompatible: incompatible = true
            }
            // Échec fort : un état d'un autre plan n'est jamais lu comme « aucune mise de côté ».
            do {
                setAside = try store.loadSetAside(date: fresh.date, program: fresh.activeProgramID,
                                                  fingerprint: try fresh.fingerprint)
            } catch { setAside = []; incompatible = true }
            let history = try await DayComposerServerProjection.load(date: fresh.date)
            guard !Task.isCancelled else { return }
            sourcesLocked = DayComposerStore.sourcesLocked(fresh) || !history.positivelyObserved.isEmpty
            let context = try DayComposerExecutionContext(snapshot: units.flatMap(\.items).contains { $0.assignedSourceOverride != nil } ? fresh.assigning(units) : fresh)
            let provenance = DayComposerProvenanceStore.shared
            switch (provenance.admission(context: context, source: .morning),
                    provenance.admission(context: context, source: .evening)) {
            case (.fresh, .fresh): executionAllowed = true
            case (.validated(let a, _), .validated(let b, _)): executionAllowed = a == b
            default: executionAllowed = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            verified = false
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
