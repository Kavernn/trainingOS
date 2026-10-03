import SwiftUI

/// Transient editor buffers, not a second recovery store. Each write captures its source.
struct DayComposerCommentBuffers {
    struct Buffer {
        var text: String
        var outcome: LocalPersistenceResult?
    }
    var morning: Buffer
    var evening: Buffer

    subscript(source: DayComposerSource) -> Buffer {
        get { source == .morning ? morning : evening }
        set {
            if source == .morning { morning = newValue } else { evening = newValue }
        }
    }

    mutating func edit(_ text: String, source: DayComposerSource,
                       write: (String, DayComposerSource) -> LocalPersistenceResult) {
        self[source] = Buffer(text: text, outcome: write(text, source))
    }
}

/// The preparation screen owns and injects the fully prepared execution context.
struct DayComposerActiveView: View {
    @ObservedObject var coordinator: DayComposerExecutionCoordinator
    @ObservedObject var stabilizationBarrier: DayComposerLocalStabilizationBarrier
    @ObservedObject var finishCoordinator: DayComposerFinishCoordinator
    let bodyWeight: Double
    let onDismiss: () -> Void
    @ObservedObject private var timer = RestTimerManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var morningComment: DayComposerCommentParticipant
    @StateObject private var eveningComment: DayComposerCommentParticipant
    @ObservedObject private var coaching: DayComposerCoachingCoordinator
    @ObservedObject private var progression: ProgressionFlow
    private enum Decision: Equatable, Identifiable {
        case rpe(DayComposerSource), recap(DayComposerSource), coaching(DayComposerSource)
        var id: String { String(describing: self) }
    }
    @State private var decision: Decision?
    @State private var presentedDecision: Decision?
    @State private var finishAfterDismiss: (DayComposerSource, Int)?
    private var rpeSource: DayComposerSource? {
        if case .rpe(let source) = presentedDecision { return source }
        return nil
    }
    @State private var selectedRPE: Int?
    @State private var operations: [DayComposerSource: Task<Void, Never>] = [:]
    @State private var refreshOperation: Task<Void, Never>?

    init(coordinator: DayComposerExecutionCoordinator, stabilizationBarrier: DayComposerLocalStabilizationBarrier,
         finishCoordinator: DayComposerFinishCoordinator,
         bodyWeight: Double = 0,
         onDismiss: @escaping () -> Void) {
        precondition(coordinator.stabilizationBarrier === stabilizationBarrier, "Inject the coordinator's retained barrier")
        self.coordinator = coordinator
        self.stabilizationBarrier = stabilizationBarrier
        self.finishCoordinator = finishCoordinator
        self.coaching = finishCoordinator.coaching
        self.progression = finishCoordinator.coaching.flow
        self.bodyWeight = bodyWeight
        self.onDismiss = onDismiss
        _morningComment = StateObject(wrappedValue: .init(source: .morning, text: coordinator.comment(for: .morning)))
        _eveningComment = StateObject(wrappedValue: .init(source: .evening, text: coordinator.comment(for: .evening)))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DayComposerActiveHeader(coordinator: coordinator)
                    DayComposerNavigator(coordinator: coordinator, select: select)
                        .disabled(stabilizationBarrier.isInteractionFrozen)
                    rootMessage
                    units
                    commentPanel
                    finishPanel
                    if !finishCoordinator.dayCompleted {
                        DayComposerActiveCommands(coordinator: coordinator, navigate: navigate, dismiss: leave)
                            .disabled(stabilizationBarrier.isInteractionFrozen)
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                if timer.isVisible { FloatingRestTimerCard() }
            }
            .onChange(of: coordinator.currentMemberID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
        .background(Color.appSurfaceInset)
        .sheet(item: $decision, onDismiss: decisionDismissed) { value in
            switch value {
            case .rpe: rpeSheet
            case .recap(let source):
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        DayComposerFinishStatus(source: source, state: .completed)
                        Text(source == .morning ? coordinator.context.morningSession : coordinator.context.eveningSession)
                            .font(.appHeadline)
                        Button("Continuer après le récapitulatif") { decision = nil }
                            .frame(minHeight: 44).buttonStyle(.borderedProminent)
                    }
                    .padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color.appBg).tint(Color.forge)
                    .navigationTitle("Récap · \(source.title)")
                }
            case .coaching(let source):
                if let context = progression.context {
                    ProgressionSuggestionsSheet(suggestions: progression.suggestions, context: context,
                        onDone: { decision = nil }, sourceTitle: source.title)
                }
            }
        }
        .onChange(of: coaching.activeSource) { _, _ in presentCoachingDecision() }
        .onChange(of: progression.phase) { _, _ in presentCoachingDecision() }
        .onChange(of: coordinator.isLocked) { _, locked in
            if locked { coaching.suspend(); decision = nil }
        }
        .onAppear {
            coordinator.revalidateExecutionContext()
            coaching.resume()
            presentCoachingDecision()
            stabilizationBarrier.registerComment(morningComment)
            stabilizationBarrier.registerComment(eveningComment)
        }
        .onDisappear {
            coaching.suspend()
            refreshOperation?.cancel()
            refreshOperation = nil
            for operation in operations.values { operation.cancel() }
            stabilizationBarrier.unregisterComment(source: .morning, token: morningComment.instance)
            stabilizationBarrier.unregisterComment(source: .evening, token: eveningComment.instance)
        }
        .task {
            // Cards/comment participants register on appearance before this async read.
            await finishCoordinator.refreshSources()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                coordinator.revalidateExecutionContext()
                coaching.resume()
                if refreshOperation == nil {
                    refreshOperation = Task {
                        defer { refreshOperation = nil }
                        await finishCoordinator.refreshSources()
                    }
                }
            } else if phase == .background && progression.phase == .loading {
                coaching.suspend()
            }
        }
    }

    private func present(_ value: Decision) {
        guard decision == nil, presentedDecision == nil else { return }
        presentedDecision = value
        decision = value
    }

    private func presentCoachingDecision() {
        guard !coordinator.isLocked, let source = coaching.activeSource else { return }
        switch progression.phase {
        case .recap: present(.recap(source))
        case .coaching: present(.coaching(source))
        default: break
        }
    }

    private func decisionDismissed() {
        let dismissed = presentedDecision
        presentedDecision = nil
        decision = nil
        switch dismissed {
        case .rpe:
            if let (source, rpe) = finishAfterDismiss {
                finishAfterDismiss = nil
                operations[source] = Task { await finishCoordinator.finishSource(source, rpe: Double(rpe)) }
            }
        case .recap(let source):
            if coaching.activeSource == source { fetchCoaching(); return }
        case .coaching(let source):
            if coaching.activeSource == source { coaching.finishDecision(for: source) }
        case nil: break
        }
        presentCoachingDecision()
    }

    private func fetchCoaching() {
        guard let source = coaching.activeSource else { return }
        operations[source] = Task {
            await coaching.fetch { await APIService.shared.fetchProgressionSuggestions(context: $0) }
        }
    }

    @ViewBuilder private var coachingStatus: some View {
        if coaching.contextRejected {
            Text("Le programme du Coaching a changé. La séance reste enregistrée. Reviens au Programme avant de poursuivre.")
                .font(.subheadline).foregroundStyle(Color.appTextSecondary)
            Button("Revenir au Programme", action: leave).frame(minHeight: 44)
        }
        if let source = coaching.activeSource {
            if progression.phase == .loading {
                ProgressView("Chargement du Coaching · \(source.title)…")
            } else if case .failed(let error) = progression.phase {
                if error != .cancelled && error != .staleContext {
                    Text("Séance \(source.title) terminée. \(error.message)")
                        .font(.subheadline).foregroundStyle(Color.appTextSecondary)
                    Button("Réessayer le Coaching · \(source.title)", action: fetchCoaching)
                        .frame(minHeight: 44)
                    Button("Continuer sans Coaching") { coaching.finishDecision(for: source) }
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private var finishPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if finishCoordinator.dayCompleted {
                DayComposerCompletedSummary(leave: leave)
            } else {
                coachingStatus
                ForEach([DayComposerSource.morning, .evening], id: \.self) { source in
                    let state = finishCoordinator.productState(source)
                    let copy = DayComposerFinishPresentation(state: state)
                    VStack(alignment: .leading, spacing: 6) {
                        DayComposerFinishStatus(source: source, state: state)
                        if state == .pending || state == .review || state == .failed {
                            Button("\(copy.checkTitle) · \(source.title)") {
                                operations[source] = Task { await finishCoordinator.refreshSource(source) }
                            }.frame(minHeight: 44)
                        }
                        if state == .ready {
                            Button("Terminer \(source.title)") { selectedRPE = nil; present(.rpe(source)) }
                                .frame(minHeight: 44)
                                .buttonStyle(.borderedProminent)
                                .disabled(!coordinator.canOfferFinish(source) || coaching.activeSource != nil)
                            if !coordinator.canOfferFinish(source) {
                                Text("Enregistre les exercices de cette séance avant de la terminer.")
                                    .font(.subheadline).foregroundStyle(Color.appTextSecondary)
                            }
                        }
                    }
                }
            }
        }
        .foregroundStyle(Color.appTextPrimary).tint(Color.forge).dayComposerSurface()
    }

    private var rpeSheet: some View {
        NavigationStack {
            Form {
                if let source = rpeSource {
                    DayComposerRPEChoices(source: source, selection: $selectedRPE)
                }
                Button("Confirmer et terminer \(rpeSource?.title ?? "la séance")") {
                    guard let source = rpeSource, let selectedRPE else { return }
                    endEditing()
                    finishAfterDismiss = (source, selectedRPE)
                    decision = nil
                }
                .frame(minHeight: 44).disabled(selectedRPE == nil)
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.appCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBg)
            .navigationTitle("RPE de la séance")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { decision = nil } } }
            .tint(Color.forge)
        }
    }

    @ViewBuilder private var rootMessage: some View {
        if coordinator.isLocked {
            DayComposerLockedState(close: leave)
                .disabled(stabilizationBarrier.isInteractionFrozen)
        } else if !finishCoordinator.dayCompleted && (!coordinator.hasActionableItems || coordinator.currentMemberID == nil) {
            DayComposerSummaryState()
        }
        if coordinator.localPersistenceIssue == .failed {
            Text("Enregistrement local non confirmé. Conserve ta saisie et réessaie depuis l’exercice ou le commentaire concerné.")
                .foregroundStyle(Color.appDanger)
                .dayComposerSurface()
        }
    }

    private var units: some View {
        // Intentionally NOT lazy, NOT filtered by selection. Collapse keeps each
        // mutable ExerciseCard's StateObject/debounce alive at a stable location.
        VStack(alignment: .leading, spacing: 16) {
            ForEach(coordinator.orderedUnits) { unit in
                DayComposerUnitContent(coordinator: coordinator, unit: unit,
                                       barrier: stabilizationBarrier, bodyWeight: bodyWeight, select: select, logged: logged)
                    .disabled(finishCoordinator.productState(unit.source) == .completed)
            }
        }
    }

    @ViewBuilder private var commentPanel: some View {
        if let source = coordinator.selectedSource {
            let holder = source == .morning ? morningComment : eveningComment
            DayComposerSourceCommentSection(holder: holder,
                locked: coordinator.isLocked || finishCoordinator.productState(source) == .completed,
                frozen: !stabilizationBarrier.permitsOrdinaryMutation(for: source),
                edit: { text in writeComment(text, source: source) },
                retry: { writeComment(holder.text, source: source) })
                .id(source)
        }
    }

    private func writeComment(_ text: String, source: DayComposerSource) {
        guard !coordinator.isLocked else { return }
        stabilizationBarrier.editComment(source == .morning ? morningComment : eveningComment, text: text)
    }
    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    private func select(_ id: DayComposerItemID) {
        guard !stabilizationBarrier.isInteractionFrozen else { return }
        endEditing()
        coordinator.revalidateExecutionContext()
        coordinator.consult(id)
    }
    private func navigate(_ offset: Int) {
        guard !stabilizationBarrier.isInteractionFrozen else { return }
        endEditing()
        coordinator.revalidateExecutionContext()
        coordinator.consultAdjacent(offset: offset)
    }
    private func logged(_ id: DayComposerItemID) {
        guard !stabilizationBarrier.isInteractionFrozen else { return }
        endEditing()
        coordinator.advanceAfterAcceptedLog(itemID: id)
    }
    private func leave() {
        guard !stabilizationBarrier.isInteractionFrozen else { return }
        endEditing()
        onDismiss() // No cleanup, finish, timer reset or network request.
    }
}

private struct DayComposerActiveHeader: View {
    @ObservedObject var coordinator: DayComposerExecutionCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ma journée").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            HStack {
                if let source = coordinator.selectedSource { DayComposerSourceChip(source: source) }
                Spacer()
                Text("\(coordinator.treatedCount) / \(coordinator.executableCount) enregistrés")
                    .font(.appCaption.monospacedDigit())
                    .accessibilityLabel("\(coordinator.treatedCount) sur \(coordinator.executableCount) exercices enregistrés")
            }
            ProgressView(value: Double(coordinator.treatedCount), total: Double(max(1, coordinator.executableCount)))
                .tint(Color.forge).accessibilityHidden(true)
            if let index = coordinator.orderedUnits.flatMap(\.items).firstIndex(where: { $0.id == coordinator.currentMemberID }) {
                Text(coordinator.orderedUnits.flatMap(\.items)[index].name)
                    .font(.appHeadline)
                Text("Exercice \(index + 1) sur \(coordinator.orderedUnits.flatMap(\.items).count)")
                    .font(.subheadline)
            }
            Text("\(max(0, coordinator.executableCount - coordinator.treatedCount)) exercices restants")
                .font(.appCaption).foregroundStyle(Color.appTextSecondary)
        }
        .foregroundStyle(Color.appTextPrimary)
    }
}

private struct DayComposerNavigator: View {
    @ObservedObject var coordinator: DayComposerExecutionCoordinator
    @State private var expanded = false
    let select: (DayComposerItemID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup("Parcourir la journée", isExpanded: $expanded) {
            ForEach(coordinator.orderedUnits) { unit in
                ForEach(unit.items) { item in
                    if let presentation = coordinator.presentation(for: item.id) {
                        Button { select(item.id) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                let logged = coordinator.status(for: item.id)?.status == .localLogged || coordinator.status(for: item.id)?.status == .serverObserved
                                Image(systemName: logged ? "checkmark.circle.fill" : coordinator.currentMemberID == item.id ? "arrow.right.circle.fill" : "circle")
                                    .foregroundStyle(Color.forge).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).foregroundStyle(Color.appTextPrimary)
                                    DayComposerSourceChip(source: item.id.source)
                                    Text("\(coordinator.currentMemberID == item.id ? "En cours · " : "")\(presentation.label)\(unit.group == nil ? "" : " · Superset")")
                                        .font(.subheadline).foregroundStyle(Color.appTextSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(coordinator.currentMemberID == item.id ? .isSelected : [])
                    }
                }
            }
            }.tint(Color.forge).font(.appLabel)
        }
        .dayComposerSurface()
    }
}

private struct DayComposerUnitContent: View {
    @ObservedObject var coordinator: DayComposerExecutionCoordinator
    let unit: DayComposerUnit
    let barrier: DayComposerLocalStabilizationBarrier
    let bodyWeight: Double
    let select: (DayComposerItemID) -> Void
    let logged: (DayComposerItemID) -> Void
    var body: some View {
        if unit.group != nil {
            DayComposerSupersetContent(coordinator: coordinator, unit: unit,
                                      barrier: barrier, bodyWeight: bodyWeight, select: select, logged: logged)
        } else {
            ForEach(unit.items) { item in member(item) }
        }
    }
    private func member(_ item: DayComposerItem) -> some View {
        DayComposerExerciseContent(coordinator: coordinator, item: item, barrier: barrier, bodyWeight: bodyWeight,
                                   select: select, logged: logged).id(item.id)
    }
}

private struct DayComposerSupersetContent: View {
    @ObservedObject var coordinator: DayComposerExecutionCoordinator
    let unit: DayComposerUnit
    let barrier: DayComposerLocalStabilizationBarrier
    let bodyWeight: Double
    let select: (DayComposerItemID) -> Void
    let logged: (DayComposerItemID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Superset · \(unit.source.title)").font(.headline)
                .foregroundStyle(Color.appTextPrimary)
                .accessibilityLabel("Superset \(unit.source.title), 2 exercices")
                .accessibilityAddTraits(.isHeader)
            ForEach(unit.items) { item in
                DayComposerExerciseContent(coordinator: coordinator, item: item, barrier: barrier, bodyWeight: bodyWeight,
                                           select: select, logged: logged).id(item.id)
            }
        }
    }
}

private struct DayComposerExerciseContent: View {
    @ObservedObject var coordinator: DayComposerExecutionCoordinator
    let item: DayComposerItem
    let barrier: DayComposerLocalStabilizationBarrier
    let bodyWeight: Double
    let select: (DayComposerItemID) -> Void
    let logged: (DayComposerItemID) -> Void
    var body: some View {
        if let presentation = coordinator.presentation(for: item.id) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    DayComposerSourceChip(source: item.id.source)
                    Text(presentation.label).font(.appCaption).foregroundStyle(Color.appTextSecondary)
                }
                if presentation.rendering == .mutable, let token = presentation.authorization {
                    mutableCard(presentation, token: token).id(presentation.identity)
                } else {
                    DayComposerReadOnlyContent(presentation: presentation)
                }
            }
        }
    }

    private func mutableCard(_ p: DayComposerExecutionCoordinator.Presentation,
                             token: DayComposerProvenanceStore.Authorization) -> some View {
        let data = coordinator.data(for: item.id.source)
        return ExerciseCard(name: item.name, scheme: item.scheme, weightData: data.weights[item.name],
            equipmentType: p.equipment, trackingType: item.tracking, isUnilateral: item.unilateral,
            bodyWeight: bodyWeight, isSecondSession: item.id.source == .evening, isBonusSession: false,
            restSeconds: p.restSeconds, prescription: data.prescriptions?[item.name],
            suggestion: data.exerciseSuggestions?[item.name], hint: data.inventoryHints[item.name],
            logResult: Binding(get: { coordinator.consultationResult(for: item.id) }, set: { value in
                let outcome = coordinator.submit(candidate: value, for: item.id)
                if outcome != .accepted { coordinator.reportPersistenceRefusal(outcome) }
            }),
            onLogged: { logged(item.id) },
            isExpanded: coordinator.selectedUnit?.items.contains(where: { $0.id == item.id }) == true,
            isFocused: coordinator.currentMemberID == item.id, onToggle: { select(item.id) },
            nextExerciseName: coordinator.nextActionableName(after: item.id),
            sessionDate: coordinator.context.date, recoveredInitialState: p.hydration,
            reconstructionMetadata: .init(scheme: item.scheme,
                trackingType: data.inventoryTracking[item.name], isUnilateral: data.inventoryUnilateral[item.name]),
            draftAuthorization: token,
            validateLocalPersistence: { coordinator.validateLocalPersistence() },
            onSubmitLogCandidate: { coordinator.submit(candidate: $0, for: item.id) },
            onPersistenceRefused: { coordinator.reportPersistenceRefusal($0) },
            allowsManualRest: p.allowsManualRest,
            onDraftPersisted: { coordinator.refreshDerivedState() },
            sourceRegistration: .init(barrier: barrier, identity: p.identity))
    }
}

private struct DayComposerReadOnlyContent: View {
    let presentation: DayComposerExecutionCoordinator.Presentation
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.item.name).font(.headline)
            Text(message).font(.subheadline)
            if let result = presentation.result {
                DayComposerLocalSummary(result: result, tracking: result.trackingType ?? presentation.item.tracking)
            }
        }
        .foregroundStyle(Color.appTextPrimary)
        .dayComposerSurface()
        .accessibilityElement(children: .contain)
    }
    private var message: String {
        switch presentation.rendering {
        case .observed: return "Observé dans l’historique"
        case .corruptDraft: return "Brouillon local à vérifier. Données conservées."
        case .conflict: return "Observé dans l’historique. Brouillon local conservé."
        case .unsupported: return "Cet exercice ne peut pas être saisi dans Ma journée. Consulte-le depuis sa séance habituelle."
        case .locked: return "La journée a changé. Tes saisies enregistrées restent disponibles."
        case .localReadOnly: return "Saisie conservée sur cet appareil, disponible en consultation."
        case .mutable: return ""
        }
    }
}

private struct DayComposerLocalSummary: View {
    let result: ExerciseLogResult
    let tracking: String
    @ObservedObject private var units = UnitSettings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if tracking == "mobility" {
                Text("Mobilité enregistrée")
            } else if result.sets.isEmpty {
                Text(summaryMetric(result.reps))
                if result.weight.isFinite && result.weight > 0 { Text(units.format(result.weight)) }
            } else {
                ForEach(result.sets.indices, id: \.self) { index in
                    Text("Série \(index + 1) · \(details(result.sets[index]))")
                }
            }
            if let rpe = result.rpe { Text("RPE \(rpe.formatted())") }
            if !result.painZone.isEmpty { Text("Zone douloureuse : \(result.painZone)") }
            if !result.notes.isEmpty { Text(result.notes) }
        }
        .font(.subheadline).foregroundStyle(Color.appTextSecondary)
    }
    private func summaryMetric(_ value: String) -> String {
        switch tracking {
        case "time": return "Durées : \(value) s"
        case "carry": return "Distances : \(value) m"
        case "protocol": return "Protocole enregistré"
        case "reps", "plyo": return "Répétitions : \(value)"
        default: return "Valeur enregistrée : \(value)"
        }
    }
    private func details(_ set: [String: Any]) -> String {
        var parts: [String] = []
        if let weight = (set["weight"] as? NSNumber)?.doubleValue, weight.isFinite, tracking != "protocol" {
            parts.append(units.format(weight))
        }
        if let reps = set.repsString() { parts.append(summaryMetric(reps)) }
        if let distance = set["distance_m"] as? NSNumber { parts.append("Distance : \(distance) m") }
        if let intensity = set["intensity"] as? NSNumber { parts.append("Intensité enregistrée : \(intensity)") }
        for (key, title) in [("left", "Gauche"), ("right", "Droite")] {
            if let time = (set[key] as? [String: Any])?["time"] as? NSNumber {
                parts.append("\(title) : \(time) s")
            }
        }
        if let rir = set["rir"] as? NSNumber { parts.append("RIR \(rir)") }
        if let rpe = set["rpe"] as? NSNumber { parts.append("RPE \(rpe)") }
        if parts.isEmpty && tracking == "protocol" { return "Protocole enregistré" }
        return parts.joined(separator: " · ")
    }
}

private struct DayComposerSourceCommentSection: View {
    @ObservedObject var holder: DayComposerCommentParticipant
    let locked: Bool
    let frozen: Bool
    let edit: (String) -> Void
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Commentaire \(holder.source.title)").font(.headline).accessibilityAddTraits(.isHeader)
            if locked {
                Text(holder.text.isEmpty ? "Aucun commentaire saisi" : holder.text)
            } else {
                TextField("Commentaire \(holder.source.title)", text: Binding(get: { holder.text }, set: edit), axis: .vertical)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Commentaire \(holder.source.title)")
                    .disabled(frozen)
            }
            if let outcome = holder.outcome, outcome != .accepted {
                Text("Non enregistré sur cet appareil").foregroundStyle(Color.appDanger)
                if !locked {
                    Button("Réessayer l’enregistrement local", action: retry).frame(minHeight: 44).disabled(frozen)
                }
            }
        }
        .foregroundStyle(Color.appTextPrimary)
        .dayComposerSurface()
    }
}

private struct DayComposerLockedState: View {
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cette journée a changé.\nTes données enregistrées sont conservées.")
                .accessibilityAddTraits(.isHeader)
            Button("Fermer", action: close).frame(minHeight: 44)
        }
        .foregroundStyle(Color.appTextPrimary).dayComposerSurface()
    }
}

private struct DayComposerSummaryState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Saisies à consulter").font(.headline)
            Text("Vérifie l’état de Matin et Soir ci-dessous pour terminer ta journée.").foregroundStyle(Color.appTextSecondary)
        }
        .foregroundStyle(Color.appTextPrimary).dayComposerSurface()
    }
}

private struct DayComposerActiveCommands: View {
    @ObservedObject var coordinator: DayComposerExecutionCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let navigate: (Int) -> Void
    let dismiss: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                if !dynamicTypeSize.isAccessibilitySize { HStack { previous; next } }
                VStack { previous; next }
            }
            Button("Reprendre plus tard", action: dismiss).frame(maxWidth: .infinity, minHeight: 44)
            Text("Les saisies enregistrées restent sur cet appareil.")
                .font(.subheadline).foregroundStyle(Color.appTextSecondary)
        }
        .tint(Color.forge)
    }
    private var previous: some View {
        Button("Précédent") { navigate(-1) }.frame(maxWidth: .infinity, minHeight: 44)
            .disabled(coordinator.adjacentItem(offset: -1) == nil)
    }
    private var next: some View {
        Button("Suivant") { navigate(1) }.frame(maxWidth: .infinity, minHeight: 44)
            .disabled(coordinator.adjacentItem(offset: 1) == nil)
    }
}

private extension View {
    func dayComposerSurface() -> some View {
        padding(12)
            .background(Color.appCard, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appSeparator, lineWidth: 1))
    }
}
