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

/// Internal only. The caller owns a fully prepared coordinator. No Preview or public route.
struct DayComposerActiveView: View {
    @ObservedObject var coordinator: DayComposerExecutionCoordinator
    @ObservedObject var stabilizationBarrier: DayComposerLocalStabilizationBarrier
    let bodyWeight: Double
    let onDismiss: () -> Void
    @ObservedObject private var timer = RestTimerManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var morningComment: DayComposerCommentParticipant
    @StateObject private var eveningComment: DayComposerCommentParticipant

    init(coordinator: DayComposerExecutionCoordinator, stabilizationBarrier: DayComposerLocalStabilizationBarrier,
         bodyWeight: Double = 0,
         onDismiss: @escaping () -> Void) {
        precondition(coordinator.stabilizationBarrier === stabilizationBarrier, "Inject the coordinator's retained barrier")
        self.coordinator = coordinator
        self.stabilizationBarrier = stabilizationBarrier
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
                    DayComposerActiveCommands(coordinator: coordinator, navigate: navigate, dismiss: leave)
                        .disabled(stabilizationBarrier.isInteractionFrozen)
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
        .onAppear {
            coordinator.revalidateExecutionContext()
            stabilizationBarrier.registerComment(morningComment)
            stabilizationBarrier.registerComment(eveningComment)
        }
        .onDisappear {
            stabilizationBarrier.unregisterComment(source: .morning, token: morningComment.instance)
            stabilizationBarrier.unregisterComment(source: .evening, token: eveningComment.instance)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { coordinator.revalidateExecutionContext() }
        }
    }

    @ViewBuilder private var rootMessage: some View {
        if coordinator.isLocked {
            DayComposerLockedState(close: leave)
                .disabled(stabilizationBarrier.isInteractionFrozen)
        } else if !coordinator.hasActionableItems || coordinator.currentMemberID == nil {
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
            }
        }
    }

    @ViewBuilder private var commentPanel: some View {
        if let source = coordinator.selectedSource {
            let holder = source == .morning ? morningComment : eveningComment
            DayComposerSourceCommentSection(holder: holder,
                locked: coordinator.isLocked,
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
            Text("\(coordinator.treatedCount)/\(coordinator.executableCount) exercices traités")
                .accessibilityLabel("\(coordinator.treatedCount) sur \(coordinator.executableCount) exercices traités")
            Text([coordinator.selectedSource?.title, coordinator.context.date].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(Color.appTextSecondary)
        }
        .foregroundStyle(Color.appTextPrimary)
    }
}

private struct DayComposerNavigator: View {
    @ObservedObject var coordinator: DayComposerExecutionCoordinator
    let select: (DayComposerItemID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Parcourir la journée").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(coordinator.orderedUnits) { unit in
                ForEach(unit.items) { item in
                    if let presentation = coordinator.presentation(for: item.id) {
                        Button { select(item.id) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: coordinator.currentMemberID == item.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Color.forge).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).foregroundStyle(Color.appTextPrimary)
                                    Text("\(item.id.source.title) · \(presentation.label)\(unit.group == nil ? "" : " · Superset")")
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
                Text("\(item.id.source.title) · \(presentation.label)")
                    .font(.subheadline).foregroundStyle(Color.appTextSecondary)
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
        case .unsupported: return "Non pris en charge dans Ma journée · \(presentation.item.tracking)"
        case .locked: return "Lecture seule — contexte modifié"
        case .localReadOnly: return "Récupération locale en lecture seule"
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
            if result.sets.isEmpty {
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
            Text("Aucun exercice à saisir automatiquement ici.").font(.headline)
            Text("Tu peux consulter les éléments de la journée.").foregroundStyle(Color.appTextSecondary)
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
