import Foundation
import Combine

struct DayComposerExecutionItemIdentity: Hashable {
    let executionID: UUID
    let version: Int
    let date: String
    let activeProgramID: String
    let sourceFingerprint: String
    let itemID: DayComposerItemID
    var routingSource: DayComposerSource? = nil
    var source: DayComposerSource { routingSource ?? itemID.source }
}

/// Internal Phase E only. No public route, finalization, networking or clocks.
@MainActor
final class DayComposerExecutionCoordinator: ObservableObject {
    enum Failure: Error { case invalidPlan, incompatible, invalidItem, invalidResult, readOnlyItem }
    enum Status: Equatable { case localLogged, serverObserved, draftOnly, unknown, unsupported }
    struct ItemState: Equatable {
        let status: Status
        let draft: ExerciseDraftPersistence.Presence
        let serverObserved: Bool
        var hasDraft: Bool { draft != .absent }
        var draftCorrupt: Bool { draft == .presentUnreadable }
        var draftServerConflict: Bool { hasDraft && serverObserved }
        var isActionable: Bool {
            // An unreadable draft needs inspection, never automatic replacement.
            !draftCorrupt && (status == .draftOnly || status == .unknown)
        }
    }

    let input: DayComposerValidatedExecutionInput
    let morningVM: SeanceViewModel
    let eveningVM: SeanceViewModel
    private let finalInputsIdentity: DayComposerExecutionIdentity
    private let finalInputsStore: DayComposerFinalInputsStore
    private var finishCoordinator: DayComposerFinishCoordinator?
    private(set) lazy var morningFinalInputs = makeFinalInputsParticipant(.morning)
    private(set) lazy var eveningFinalInputs = makeFinalInputsParticipant(.evening)
    private let morningAuthorization: DayComposerProvenanceStore.Authorization
    private let eveningAuthorization: DayComposerProvenanceStore.Authorization
    private let currentDate: () -> String
    private var subscriptions = Set<AnyCancellable>()
    // Host owns the barrier; weak here avoids a coordinator/barrier ownership cycle.
    private(set) weak var stabilizationBarrier: DayComposerLocalStabilizationBarrier?
    private var permitsNavigation: Bool { stabilizationBarrier?.isInteractionFrozen != true }
    @Published private(set) var isLocked = false
    @Published private(set) var localPersistenceIssue: LocalPersistenceResult?
    private var awaitingAdvance: Set<DayComposerItemID> = []
    @Published private(set) var currentUnitID: DayComposerItemID?
    @Published private(set) var currentMemberID: DayComposerItemID?
    /// Unités mises de côté pour la journée (têtes d'unité). Le plan reste figé.
    @Published private(set) var setAside: Set<DayComposerItemID>
    private let orderStore: DayComposerStore
    private let finalizationStore: DayComposerFinalizationStore

    var context: DayComposerExecutionContext { input.context }

    /// Seul point de filtrage côté exécution (délègue à DayComposerSnapshot.requiredItems).
    func requiredItems(_ source: DayComposerSource) -> [DayComposerItem] {
        input.snapshot.requiredItems(source, setAside: setAside)
    }
    func isSetAside(_ id: DayComposerItemID) -> Bool {
        orderedUnits.contains { setAside.contains($0.id) && $0.items.contains { $0.id == id } }
    }
    private func isActionable(_ id: DayComposerItemID) -> Bool {
        !isSetAside(id) && status(for: id)?.isActionable == true
    }

    func canOfferFinish(_ source: DayComposerSource) -> Bool {
        let required = requiredItems(source)
        return !isLocked && !required.isEmpty && required.allSatisfy { item in
            guard let state = status(for: item.id) else { return false }
            if !WorkoutCompletion.tracks(item.tracking) { return state.draft != .presentUnreadable }
            guard !state.hasDraft else { return false }
            return consultationResult(for: item.id) != nil || state.serverObserved
        }
    }
    var orderedUnits: [DayComposerUnit] { input.orderedUnits }
    private var items: [DayComposerItem] { orderedUnits.flatMap(\.items) }

    static func isSupported(_ tracking: String) -> Bool {
        ["reps", "time", "carry", "plyo", "protocol", "mobility"].contains(tracking)
    }

    /// All asynchronous reads are already complete. Keep prepare/create/bind in
    /// one non-suspending MainActor operation, publishing nothing on failure.
    /// Narrow owner/bind seams allow failure tests without a second store universe.
    static func make(
        validatedInput input: DayComposerValidatedExecutionInput,
        currentDate: @escaping () -> String = { DateFormatter.isoDate.string(from: Date()) },
        finalInputsStore: DayComposerFinalInputsStore = DayComposerFinalInputsStore(),
        orderStore: DayComposerStore = DayComposerStore(),
        finalizationStore: DayComposerFinalizationStore = DayComposerFinalizationStore(),
        makeOwner: @MainActor (DayComposerSource) throws -> SeanceViewModel = {
            $0 == .morning ? SeanceViewModel(draftSessionType: "morning") : SeanceSoirViewModel()
        },
        bind: @MainActor (SeanceViewModel, DayComposerProvenanceStore.Authorization) throws -> Void = {
            try $0.bindProvenanceAuthorization($1)
        }
    ) throws -> DayComposerExecutionCoordinator {
        try validate(input)
        guard currentDate() == input.context.date else { throw Failure.incompatible }
        let store = DayComposerProvenanceStore.shared
        let am = store.admission(context: input.context, source: .morning)
        let pm = store.admission(context: input.context, source: .evening)
        let fresh: Bool
        switch (am, pm) {
        case (.fresh, .fresh): fresh = true
        case (.validated(let a, _), .validated(let b, _)) where a == b: fresh = false
        default: throw Failure.incompatible
        }

        let morning = try makeOwner(.morning)
        try morning.prepareForDayComposer(data: input.morningData, sessionDate: input.context.date,
            source: "morning", sessionName: input.context.morningSession,
            contextToken: input.context.sourceFingerprint, recoveryAdmission: .allowCurrentScopedRecovery)
        let evening = try makeOwner(.evening)
        guard morning !== evening else { throw Failure.invalidPlan }
        try evening.prepareForDayComposer(data: input.eveningData, sessionDate: input.context.date,
            source: "evening", sessionName: input.context.eveningSession,
            contextToken: input.context.sourceFingerprint, recoveryAdmission: .allowCurrentScopedRecovery)

        // Preparation is read-only. Recheck its admitted inputs before creating
        // a record or binding tokens; never recertify a changed recovery.
        guard store.admission(context: input.context, source: .morning) == am,
              store.admission(context: input.context, source: .evening) == pm else {
            throw Failure.incompatible
        }
        try validateResults(morning, plan: input.snapshot.morning)
        try validateResults(evening, plan: input.snapshot.evening)
        let setAside = try orderStore.loadSetAside(date: input.context.date, program: input.context.activeProgramID,
                                                   fingerprint: input.planningFingerprint)
        try validateSetAside(setAside, input: input, morning: morning, evening: evening)
        if fresh { try store.create(context: input.context) }
        let morningToken = try store.authorize(context: input.context, source: .morning)
        let eveningToken = try store.authorize(context: input.context, source: .evening)
        try bind(morning, morningToken)
        try bind(evening, eveningToken)
        let coordinator = DayComposerExecutionCoordinator(input: input, morning: morning, evening: evening,
            morningToken: morningToken, eveningToken: eveningToken, currentDate: currentDate,
            finalInputsIdentity: try DayComposerExecutionIdentity(executionID: morningToken.executionID, context: input.context),
            finalInputsStore: finalInputsStore, setAside: setAside, orderStore: orderStore,
            finalizationStore: finalizationStore)
        guard coordinator.revalidateExecutionContext() else { throw Failure.incompatible }
        // Eagerly restore both lazy participants after self is fully initialized.
        // Missing/corrupt inputs remain source-local projections, not a local-only lock.
        _ = coordinator.morningFinalInputs
        _ = coordinator.eveningFinalInputs
        coordinator.selectFirstActionable()
        coordinator.observeOwners()
        return coordinator
    }

    private init(input: DayComposerValidatedExecutionInput, morning: SeanceViewModel, evening: SeanceViewModel,
                 morningToken: DayComposerProvenanceStore.Authorization,
                 eveningToken: DayComposerProvenanceStore.Authorization, currentDate: @escaping () -> String,
                 finalInputsIdentity: DayComposerExecutionIdentity, finalInputsStore: DayComposerFinalInputsStore,
                 setAside: Set<DayComposerItemID>, orderStore: DayComposerStore,
                 finalizationStore: DayComposerFinalizationStore) {
        self.input = input
        morningVM = morning
        eveningVM = evening
        morningAuthorization = morningToken
        eveningAuthorization = eveningToken
        self.currentDate = currentDate
        self.finalInputsIdentity = finalInputsIdentity
        self.finalInputsStore = finalInputsStore
        self.setAside = setAside
        self.orderStore = orderStore
        self.finalizationStore = finalizationStore
    }

    /// Une mise de côté désigne une tête d'unité de la journée, sans log local ni brouillon.
    /// L'interface rend l'inverse impossible : un tel état est une corruption → échec fort.
    private static func validateSetAside(_ setAside: Set<DayComposerItemID>, input: DayComposerValidatedExecutionInput,
                                         morning: SeanceViewModel, evening: SeanceViewModel) throws {
        for id in setAside {
            guard let unit = input.orderedUnits.first(where: { $0.id == id }) else { throw Failure.incompatible }
            for item in unit.items {
                let owner = item.assignedSource == .morning ? morning : evening
                guard owner.logResults[item.storageKey] == nil,
                      ExerciseDraftPersistence(date: input.context.date, sessionType: item.assignedSource.rawValue,
                          exerciseName: item.storageKey).presence() == .absent else { throw Failure.incompatible }
            }
        }
    }

    // MARK: - Mise de côté

    enum SetAsideRefusal: Error, Equatable {
        case locked, busy, invalidUnit, logged, pendingEdits, sourceFinished, lastUnitOfDay
        case draftRequiresConfirmation, persistence
    }
    enum SetAsideCheck: Equatable { case allowed, requiresDraftDiscard, refused(SetAsideRefusal) }

    /// Source terminée (serveur) ou finalisation déjà engagée (intention finale) : figée.
    /// Une lecture locale illisible ferme aussi (fail closed).
    private func sourceFinished(_ source: DayComposerSource) -> Bool {
        if input.snapshot.completed(source) { return true }
        do {
            return try finalizationStore.load(identity: finalInputsIdentity)?.finalIntents
                .contains { $0.sourceVersion.source == source } ?? false
        } catch { return true }
    }

    private func commonSetAsideRefusal(_ unitID: DayComposerItemID) -> SetAsideRefusal? {
        guard !isLocked, revalidateExecutionContext() else { return .locked }
        guard permitsNavigation else { return .busy }
        guard let unit = orderedUnits.first(where: { $0.id == unitID }) else { return .invalidUnit }
        return sourceFinished(unit.source) ? .sourceFinished : nil
    }

    private func isLogged(_ item: DayComposerItem) -> Bool {
        let status = status(for: item.id)?.status
        return status == .localLogged || status == .serverObserved
    }

    /// Ordre des règles validé : logué → refus ; saisie en attente → refus temporaire ;
    /// dernière unité requise sans aucun log dans la journée → refus ; brouillon → confirmation.
    func setAsideCheck(_ unitID: DayComposerItemID) -> SetAsideCheck {
        if let refusal = commonSetAsideRefusal(unitID) { return .refused(refusal) }
        guard !setAside.contains(unitID), let unit = orderedUnits.first(where: { $0.id == unitID }) else {
            return .refused(.invalidUnit)
        }
        if unit.items.contains(where: isLogged) { return .refused(.logged) }
        if unit.items.contains(where: { item in
            executionIdentity(for: item.id).map { stabilizationBarrier?.hasUnpersistedEdits($0) == true } ?? false
        }) { return .refused(.pendingEdits) }
        let remaining = (requiredItems(.morning) + requiredItems(.evening)).filter { item in
            !unit.items.contains { $0.id == item.id }
        }
        if remaining.isEmpty && !items.contains(where: isLogged) { return .refused(.lastUnitOfDay) }
        if unit.items.contains(where: { status(for: $0.id)?.draft != .absent }) { return .requiresDraftDiscard }
        return .allowed
    }

    /// Invariant à la sortie : ni brouillon ni saisie en attente pour l'unité. Les brouillons
    /// supprimés sont ceux de CETTE unité uniquement (une clé par exercice/occurrence).
    func setAsideUnit(_ unitID: DayComposerItemID, discardingDrafts: Bool) throws {
        switch setAsideCheck(unitID) {
        case .refused(let refusal): throw refusal
        case .requiresDraftDiscard where !discardingDrafts: throw SetAsideRefusal.draftRequiresConfirmation
        case .allowed, .requiresDraftDiscard: break
        }
        guard let unit = orderedUnits.first(where: { $0.id == unitID }) else { throw SetAsideRefusal.invalidUnit }
        for item in unit.items where status(for: item.id)?.draft != .absent {
            let token = item.assignedSource == .morning ? morningAuthorization : eveningAuthorization
            let draft = ExerciseDraftPersistence(date: context.date, sessionType: item.assignedSource.rawValue,
                                                 exerciseName: item.storageKey, authorization: token)
            let result = draft.clear()
            guard result == .accepted, draft.presence() == .absent else {
                report(result == .accepted ? .failed : result)
                throw SetAsideRefusal.persistence
            }
        }
        try persistSetAside(setAside.union([unitID]))
        if let current = currentMemberID, isSetAside(current) { selectFirstActionable() }
    }

    /// Annulable tant que la source n'est ni terminée ni engagée en finalisation.
    func cancelSetAside(_ unitID: DayComposerItemID) throws {
        if let refusal = commonSetAsideRefusal(unitID) { throw refusal }
        guard setAside.contains(unitID) else { throw SetAsideRefusal.invalidUnit }
        try persistSetAside(setAside.subtracting([unitID]))
    }

    private func persistSetAside(_ updated: Set<DayComposerItemID>) throws {
        do {
            try orderStore.saveSetAside(updated, date: context.date, program: context.activeProgramID,
                fingerprint: input.planningFingerprint, orderedIDs: items.map(\.id))
        } catch { throw SetAsideRefusal.persistence }
        setAside = updated
        refreshDerivedState()
    }

    private func makeFinalInputsParticipant(_ source: DayComposerSource) -> DayComposerFinalInputsParticipant {
        DayComposerFinalInputsParticipant(identity: finalInputsIdentity, source: source, store: finalInputsStore,
            authorizeMutation: { [weak self] in
                guard let self, self.revalidateExecutionContext() else {
                    throw DayComposerStabilizationError.contextRejected
                }
                guard self.stabilizationBarrier?.permitsOrdinaryMutation(for: source) != false else {
                    throw DayComposerStabilizationError.sourceFrozen
                }
            })
    }

    func finalInputsParticipant(for source: DayComposerSource) -> DayComposerFinalInputsParticipant {
        source == .morning ? morningFinalInputs : eveningFinalInputs
    }

    @discardableResult
    func setFinalRPE(_ rpe: Double, for source: DayComposerSource) throws -> DayComposerFinalInputsReceipt {
        try finalInputsParticipant(for: source).setRPE(rpe)
    }

    private static func validate(_ input: DayComposerValidatedExecutionInput) throws {
        let snapshot = input.snapshot
        guard try input.context == DayComposerExecutionContext(snapshot: snapshot),
              input.serverProjection.date == input.context.date,
              snapshot.morning.source == .morning, snapshot.evening.source == .evening,
              input.morningData.todayDate == input.context.date, input.eveningData.todayDate == input.context.date,
              input.morningData.today == input.context.morningSession,
              input.eveningData.today == input.context.eveningSession,
              snapshot.units(for: input.orderedUnits.flatMap { $0.items.map(\.id) }) == input.orderedUnits else {
            throw Failure.invalidPlan
        }
        for plan in [snapshot.morning, snapshot.evening] {
            guard plan.units.flatMap(\.items).contains(where: { isSupported($0.tracking) }) else {
                throw Failure.invalidPlan
            }
            for unit in plan.units {
                guard unit.items.count == (unit.group == nil ? 1 : 2),
                      Set(unit.items.map(\.id)).count == unit.items.count,
                      unit.items.allSatisfy({ $0.assignedSource == plan.source }),
                      unit.group == nil || unit.items.allSatisfy({ isSupported($0.tracking) }) else {
                    throw Failure.invalidPlan
                }
            }
        }
    }

    private static func validateResults(_ owner: SeanceViewModel, plan: DayComposerPlan) throws {
        let planItems = plan.units.flatMap(\.items)
        let names = Set(planItems.map(\.storageKey))
        guard owner.logResults.allSatisfy({ key, result in
            names.contains(key) && result.storageKey == key && planItems.contains { $0.storageKey == key && $0.name == result.name } && !result.isBonus
                && result.isSecond == (plan.source == .evening)
        }) else { throw Failure.invalidResult }
    }

    func item(for id: DayComposerItemID) -> DayComposerItem? { items.first { $0.id == id } }
    func data(for source: DayComposerSource) -> SeanceData {
        source == .morning ? input.morningData : input.eveningData
    }
    private func sourceOwner(_ source: DayComposerSource) -> SeanceViewModel {
        source == .morning ? morningVM : eveningVM
    }
    func owner(for id: DayComposerItemID) throws -> SeanceViewModel {
        guard item(for: id) != nil else { throw Failure.invalidItem }
        guard revalidateExecutionContext() else { throw Failure.incompatible }
        return sourceOwner(item(for: id)!.assignedSource)
    }
    func authorization(for source: DayComposerSource) throws -> DayComposerProvenanceStore.Authorization {
        guard revalidateExecutionContext() else { throw Failure.incompatible }
        return source == .morning ? morningAuthorization : eveningAuthorization
    }
    func result(for id: DayComposerItemID) throws -> ExerciseLogResult? {
        guard let item = item(for: id) else { throw Failure.invalidItem }
        return try owner(for: id).logResults[item.storageKey]
    }
    func setResult(_ result: ExerciseLogResult?, for id: DayComposerItemID) throws {
        guard submit(candidate: result, for: id) == .accepted else { throw Failure.invalidResult }
    }

    @discardableResult
    func submit(candidate result: ExerciseLogResult?, for id: DayComposerItemID) -> LocalPersistenceResult {
        guard revalidateExecutionContext() else { return report(.rejectedContext) }
        guard let item = item(for: id) else { return report(.rejectedContext) }
        guard Self.isSupported(item.tracking),
              let state = status(for: id), !state.draftCorrupt,
              state.status != .serverObserved else { return report(.failed) }
        if let result {
            guard result.occurrenceKey == item.occurrenceKey else { return report(.rejectedContext) }
            if item.tracking == "mobility",
               ExerciseRecoveryHydration.make(result, equipment: result.equipmentType,
                   tracking: item.tracking, unilateral: item.unilateral, displayWeight: { $0 }) == nil {
                return report(.failed)
            }
            guard result.name == item.name, result.isSecond == (item.assignedSource == .evening), !result.isBonus else {
                return report(.rejectedContext)
            }
        }
        let owner = sourceOwner(item.assignedSource)
        let previous = owner.logResults
        owner.logResults[item.storageKey] = result
        let matches = owner.persistedLogsMatchCurrentState()
        guard revalidateExecutionContext() else {
            if !matches { owner.restoreUnacceptedLocalResults(previous) }
            return report(.rejectedContext)
        }
        guard matches else {
            owner.restoreUnacceptedLocalResults(previous)
            return report(.failed)
        }
        if result != nil { awaitingAdvance.insert(id) } else { awaitingAdvance.remove(id) }
        refreshDerivedState()
        return report(.accepted)
    }

    @discardableResult
    private func report(_ result: LocalPersistenceResult) -> LocalPersistenceResult {
        if result == .rejectedContext { isLocked = true }
        localPersistenceIssue = result == .accepted ? nil : result
        return result
    }

    /// Card cleanup failures also arrive here; generic disk failures remain retryable.
    func reportPersistenceRefusal(_ result: LocalPersistenceResult) {
        guard result != .accepted else { return }
        report(result)
    }

    /// Pass to the future card's generic live gate, alongside its immutable token.
    /// Invoked at write time, never while constructing a SwiftUI body.
    func validateLocalPersistence() -> LocalPersistenceResult {
        revalidateExecutionContext() ? .accepted : report(.rejectedContext)
    }

    /// Called only after accepted owner write AND accepted card cleanup.
    func advanceAfterAcceptedLog(itemID: DayComposerItemID) {
        guard permitsNavigation, revalidateExecutionContext(), currentMemberID == itemID,
              awaitingAdvance.contains(itemID), let item = item(for: itemID),
              ExerciseDraftPersistence(date: context.date, sessionType: item.assignedSource.rawValue,
                exerciseName: item.storageKey).presence() == .absent else { return }
        awaitingAdvance.remove(itemID)
        next()
    }

    func comment(for source: DayComposerSource) -> String { sourceOwner(source).sessionComment }
    @discardableResult
    func setComment(_ comment: String, for source: DayComposerSource) -> LocalPersistenceResult {
        guard revalidateExecutionContext() else { return report(.rejectedContext) }
        sourceOwner(source).sessionComment = comment
        let matches = SessionDraftStore.loadComment(date: context.date, sessionType: source.rawValue) == comment
        guard revalidateExecutionContext() else { return report(.rejectedContext) }
        return report(matches ? .accepted : .failed)
    }

    /// Read-only projection. No synthetic logs, cleanup, ACK or copies of owner state.
    func status(for id: DayComposerItemID) -> ItemState? {
        guard let item = item(for: id) else { return nil }
        let draft = ExerciseDraftPersistence(date: context.date, sessionType: item.assignedSource.rawValue,
                                             exerciseName: item.storageKey).presence()
        let observed = input.serverProjection.presence(of: item.name, source: item.assignedSource, occurrenceKey: item.occurrenceKey) == .observed
        let status: Status
        if !Self.isSupported(item.tracking) { status = .unsupported }
        else if sourceOwner(item.assignedSource).logResults[item.storageKey] != nil { status = .localLogged }
        else if observed { status = .serverObserved }
        else if draft != .absent { status = .draftOnly }
        else { status = .unknown }
        return ItemState(status: status, draft: draft, serverObserved: observed)
    }
    var executableCount: Int {
        items.filter { !isSetAside($0.id) && Self.isSupported($0.tracking) && WorkoutCompletion.tracks($0.tracking) }.count
    }
    var treatedCount: Int {
        items.filter { item in
            guard !isSetAside(item.id) else { return false }
            guard WorkoutCompletion.tracks(item.tracking) else { return false }
            let itemStatus = status(for: item.id)?.status
            return itemStatus == .localLogged || itemStatus == .serverObserved
        }.count
    }

    /// Optional current context is supplied by a future lifecycle reload. This
    /// method does not claim to detect a remote program change without a read.
    @discardableResult
    func revalidateExecutionContext(currentContext: DayComposerExecutionContext? = nil) -> Bool {
        guard !isLocked else { return false }
        let store = DayComposerProvenanceStore.shared
        let contextMatches = currentContext.map { context.compatibility(with: $0) == .compatible } ?? true
        let valid = currentDate() == context.date && contextMatches
            && [morningAuthorization, eveningAuthorization].allSatisfy { token in
                guard token.context == context,
                      case .validated(let id, _) = store.admission(context: context, source: token.source) else { return false }
                return id == token.executionID && id == morningAuthorization.executionID
            }
        if !valid { isLocked = true }
        return valid
    }

    // Position is presentation-only. Never write DayComposerStore here.
    func select(_ id: DayComposerItemID) throws {
        guard permitsNavigation else { throw DayComposerStabilizationError.busy }
        guard revalidateExecutionContext() else { throw Failure.incompatible }
        guard let unit = orderedUnits.first(where: { $0.items.contains(where: { $0.id == id }) }) else {
            throw Failure.invalidItem
        }
        currentUnitID = unit.id
        currentMemberID = id
    }
    func selectFirstActionable() {
        guard permitsNavigation, revalidateExecutionContext() else { return }
        setSelection(items.first(where: { isActionable($0.id) })?.id)
    }
    func next() {
        guard permitsNavigation, revalidateExecutionContext() else { return }
        let start = currentMemberID.flatMap { id in items.firstIndex(where: { $0.id == id }) }.map { $0 + 1 } ?? 0
        setSelection(items.dropFirst(start).first(where: { isActionable($0.id) })?.id)
    }
    func previous() {
        guard permitsNavigation, revalidateExecutionContext() else { return }
        let index = currentMemberID.flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? items.count
        if index > 0 { setSelection(items[index - 1].id) }
    }
    private func setSelection(_ id: DayComposerItemID?) {
        currentMemberID = id
        currentUnitID = id.flatMap { id in orderedUnits.first(where: { $0.items.contains(where: { $0.id == id }) })?.id }
    }
    func refreshDerivedState() {
        objectWillChange.send()
    }

    // MARK: - Pure shell projections (safe during SwiftUI body evaluation)

    enum Rendering: Equatable {
        case mutable, localReadOnly, observed, corruptDraft, conflict, unsupported, locked, setAside
    }
    struct Presentation {
        let item: DayComposerItem
        let identity: DayComposerExecutionItemIdentity
        let rendering: Rendering
        let label: String
        let result: ExerciseLogResult?
        let hydration: ExerciseRecoveryHydration?
        let authorization: DayComposerProvenanceStore.Authorization?
        let equipment: String
        let restSeconds: Int?
        let allowsManualRest: Bool
    }
    var selectedSource: DayComposerSource? { currentMemberID.flatMap { item(for: $0)?.assignedSource } ?? selectedUnit?.source }
    var selectedUnit: DayComposerUnit? { orderedUnits.first { $0.id == currentUnitID } }
    var hasActionableItems: Bool { items.contains { isActionable($0.id) } }

    func consultationResult(for id: DayComposerItemID) -> ExerciseLogResult? {
        guard let item = item(for: id) else { return nil }
        return sourceOwner(item.assignedSource).logResults[item.storageKey]
    }
    func executionIdentity(for id: DayComposerItemID) -> DayComposerExecutionItemIdentity? {
        guard item(for: id) != nil else { return nil }
        return .init(executionID: morningAuthorization.executionID, version: context.version,
                     date: context.date, activeProgramID: context.activeProgramID,
                     sourceFingerprint: context.sourceFingerprint, itemID: id, routingSource: item(for: id)?.assignedSourceOverride)
    }
    func presentation(for id: DayComposerItemID) -> Presentation? {
        guard let item = item(for: id), let state = status(for: id), let identity = executionIdentity(for: id),
              let unit = orderedUnits.first(where: { $0.items.contains { $0.id == id } }) else { return nil }
        let dto = data(for: item.originSource)
        let equipment = dto.inventoryTypes[item.name] ?? "machine"
        let result = consultationResult(for: id)
        let hydration = result.flatMap {
            ExerciseRecoveryHydration.make($0, equipment: equipment, tracking: item.tracking,
                                          unilateral: item.unilateral, displayWeight: UnitSettings.shared.display)
        }
        let rendering: Rendering
        let label: String
        if isLocked { rendering = .locked; label = "Lecture seule — contexte modifié" }
        else if isSetAside(id) { rendering = .setAside; label = "Mis de côté aujourd’hui" } // sans carte → hors expectedMutableParticipantIDs
        else if state.status == .unsupported { rendering = .unsupported; label = "Non pris en charge" }
        else if state.draftCorrupt { rendering = .corruptDraft; label = "Brouillon local à vérifier" }
        else if result != nil {
            rendering = hydration == nil ? .localReadOnly : .mutable
            label = "Enregistré sur cet appareil"
        } else if state.draftServerConflict { rendering = .conflict; label = "Historique et brouillon local" }
        else if state.serverObserved { rendering = .observed; label = "Observé" }
        else { rendering = .mutable; label = state.hasDraft ? "Brouillon local" : "À vérifier" }
        let firstInPair = unit.group != nil && unit.items.first?.id == id
        let rest = unit.group == nil ? dto.inventoryRest[item.name]
            : (firstInPair ? nil : SupersetRest.secondMemberRest(unit.rest))
        return .init(item: item, identity: identity, rendering: rendering, label: label,
                     result: result, hydration: hydration,
                     authorization: rendering == .mutable ? (item.assignedSource == .morning ? morningAuthorization : eveningAuthorization) : nil,
                     equipment: equipment, restSeconds: rest, allowsManualRest: !firstInPair)
    }
    func nextActionableName(after id: DayComposerItemID) -> String? {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let next = items.dropFirst(index + 1).first(where: { isActionable($0.id) }) else { return nil }
        return "\(next.name) · \(next.assignedSource.title)"
    }

    // Consultation never authorizes writes, persists position or unlocks an execution.
    func consult(_ id: DayComposerItemID) {
        guard permitsNavigation, item(for: id) != nil else { return }
        setSelection(id)
    }
    func adjacentItem(offset: Int) -> DayComposerItemID? {
        guard offset == -1 || offset == 1 else { return nil }
        guard let current = currentMemberID, let index = items.firstIndex(where: { $0.id == current }) else {
            return offset == 1 ? items.first?.id : items.last?.id
        }
        let target = index + offset
        return items.indices.contains(target) ? items[target].id : nil
    }
    func consultAdjacent(offset: Int) {
        guard permitsNavigation else { return }
        if let id = adjacentItem(offset: offset) { consult(id) }
    }
    /// Host must retain the returned instance and inject it into the internal shell.
    func makeStabilizationBarrier() throws -> DayComposerLocalStabilizationBarrier {
        if let stabilizationBarrier { return stabilizationBarrier }
        guard revalidateExecutionContext() else { throw Failure.incompatible }
        let identity = try DayComposerExecutionIdentity(executionID: morningAuthorization.executionID, context: context)
        let barrier = DayComposerLocalStabilizationBarrier(dependencies: .init(identity: identity,
            expected: { [weak self] in self?.expectedMutableParticipantIDs(for: $0) ?? [] },
            validate: { [weak self] in self?.revalidateExecutionContext() == true },
            guardValue: { [weak self] source in
                guard let self else { throw DayComposerStabilizationError.contextRejected }
                return try self.currentFinalizationGuard(for: source)
            },
            writeComment: { [weak self] in self?.setComment($0, for: $1) ?? .rejectedContext },
            commentMatches: { [weak self] in self?.persistedCommentMatches($0, for: $1) == true },
            rejected: { [weak self] in self?.reportPersistenceRefusal(.rejectedContext) }))
        stabilizationBarrier = barrier
        barrier.registerFinalInputsParticipant(morningFinalInputs)
        barrier.registerFinalInputsParticipant(eveningFinalInputs)
        return barrier
    }

    /// One internal engine per execution host. No public CTA or body-local owner.
    func makeFinishCoordinator() throws -> DayComposerFinishCoordinator {
        if let finishCoordinator { return finishCoordinator }
        let engine = DayComposerFinishCoordinator(execution: self, barrier: try makeStabilizationBarrier(),
            store: DayComposerFinalizationStore(), inputs: finalInputsStore, dependencies: .live)
        finishCoordinator = engine
        return engine
    }

    /// Mirrors actual rendering, including local-log precedence. Selection is irrelevant.
    func expectedMutableParticipantIDs(for source: DayComposerSource) -> [DayComposerExecutionItemIdentity] {
        items.filter { $0.assignedSource == source }.compactMap { item in
            guard let p = presentation(for: item.id), p.rendering == .mutable else { return nil }
            return p.identity
        }
    }

    func persistedCommentMatches(_ text: String, for source: DayComposerSource) -> Bool {
        comment(for: source) == text && SessionDraftStore.loadComment(date: context.date, sessionType: source.rawValue) == text
    }

    /// No repair or write. Admission validates inventory; surrounding reads reject
    /// a record changed during inspection. Invalid provenance follows the existing lock.
    func currentFinalizationGuard(for source: DayComposerSource) throws -> DayComposerFinalizationGuard {
        do {
            guard revalidateExecutionContext() else { throw Failure.incompatible }
            let store = DayComposerProvenanceStore.shared
            let token = source == .morning ? morningAuthorization : eveningAuthorization
            guard let first = try store.load(date: context.date), first.context == context,
                  first.executionID == token.executionID, first[source].validity == .valid,
                  first[source].pendingMutation == nil,
                  case .validated(let id, let revision) = store.admission(context: context, source: source),
                  id == first.executionID, revision == first[source].revision,
                  try store.inventory(date: context.date, source: source).integrity == first[source].integrity,
                  try store.load(date: context.date) == first else { throw Failure.incompatible }
            return try .init(executionID: id, source: source, revision: revision, integrity: first[source].integrity)
        } catch {
            reportPersistenceRefusal(.rejectedContext)
            throw DayComposerStabilizationError.contextRejected
        }
    }

    /// Only callable within the issuing barrier's live closure. Values are deep
    /// encoded now; no mutable owner/Any dictionaries escape as snapshot facts.
    func captureLocalFinalizationFacts(for source: DayComposerSource,
        evidence: DayComposerStableSourceEvidence) throws -> DayComposerLocalFinalizationFacts {
        guard evidence.isCurrentAttempt, evidence.source == source,
              evidence.identity == (try DayComposerExecutionIdentity(executionID: morningAuthorization.executionID, context: context)),
              expectedMutableParticipantIDs(for: source) == evidence.expectedParticipantIDs,
              try currentFinalizationGuard(for: source) == evidence.guardValue,
              persistedCommentMatches(evidence.comment, for: source),
              sourceOwner(source).persistedLogsMatchCurrentState() else { throw DayComposerStabilizationError.staleEvidence }
        let planItems = requiredItems(source)
        let facts: [DayComposerRequiredItemFacts] = try planItems.map { item in
            guard let state = status(for: item.id) else { throw Failure.invalidItem }
            let draft: DayComposerRawDraftFact
            switch state.draft {
            case .absent: draft = .absent
            case .presentDecodable: draft = .present
            case .presentUnreadable: draft = .corrupt
            }
            let result = consultationResult(for: item.id)
            let local: DayComposerLocalResultFact
            if let result {
                if item.tracking == "mobility",
                   ExerciseRecoveryHydration.make(result, equipment: result.equipmentType,
                       tracking: item.tracking, unilateral: item.unilateral, displayWeight: { $0 }) == nil {
                    throw Failure.invalidResult
                }
                guard result.name == item.name, !result.isBonus, result.isSecond == (source == .evening) else {
                    throw Failure.invalidResult
                }
                let bytes = try WorkoutPayloadBuilder.encode(WorkoutPayloadBuilder.exercise(
                    exercise: result.name, weight: result.weight, reps: result.reps, rpe: result.rpe,
                    sets: result.sets, force: true, isSecond: result.isSecond, isBonus: false,
                    equipmentType: result.equipmentType, painZone: result.painZone, notes: result.notes, date: context.date, occurrenceKey: result.occurrenceKey))
                local = .persisted(payload: bytes, readOnly: presentation(for: item.id)?.rendering != .mutable)
            } else { local = .none }
            // Cached name-level observation cannot prove exact payload agreement.
            return .init(itemID: item.id, local: local, draft: draft,
                         localConflictsWithServer: result != nil && state.serverObserved)
        }
        guard evidence.isCurrentAttempt, try currentFinalizationGuard(for: source) == evidence.guardValue,
              sourceOwner(source).persistedLogsMatchCurrentState() else { throw DayComposerStabilizationError.staleEvidence }
        return .init(identity: evidence.identity, source: source, canonicalPlan: input.snapshot,
                     itemFacts: facts, comment: evidence.comment, guardValue: evidence.guardValue, setAside: setAside)
    }

    /// Immutable local data only. No snapshot write, binding, request or submission.
    func captureFinalSource(for source: DayComposerSource,
        evidence: DayComposerStableFinalSourceEvidence) throws -> DayComposerFinalSourceCapture {
        guard revalidateExecutionContext() else { throw DayComposerStabilizationError.contextRejected }
        guard evidence.local.identity == finalInputsIdentity,
              evidence.finalInputs.executionIdentity == finalInputsIdentity else {
            throw DayComposerFinalInputsError.contextMismatch
        }
        guard evidence.local.source == source, evidence.finalInputs.source == source else {
            throw DayComposerFinalInputsError.sourceMismatch
        }
        try evidence.verifyCurrent()
        try finalInputsParticipant(for: source).verify(evidence.finalInputs)
        let local = try captureLocalFinalizationFacts(for: source, evidence: evidence.local)
        try evidence.verifyCurrent()
        return .init(local: local, finalInputs: evidence.finalInputs)
    }

    /// Read-only expiry check after awaits; no flush, recapture, or silent rebase.
    /// Also checks owner memory, including private restoration paths outside G2.
    func verifyFinalCapture(_ capture: DayComposerFinalSourceCapture) throws {
        let local = capture.local
        guard local.identity == finalInputsIdentity, local.setAside == setAside,
              try currentFinalizationGuard(for: local.source) == local.guardValue,
              persistedCommentMatches(local.comment, for: local.source),
              sourceOwner(local.source).persistedLogsMatchCurrentState() else {
            throw DayComposerStabilizationError.staleEvidence
        }
        for fact in local.itemFacts {
            let bytes: Data?
            if let result = consultationResult(for: fact.itemID) {
                bytes = try WorkoutPayloadBuilder.encode(WorkoutPayloadBuilder.exercise(
                    exercise: result.name, weight: result.weight, reps: result.reps, rpe: result.rpe,
                    sets: result.sets, force: true, isSecond: result.isSecond, isBonus: result.isBonus,
                    equipmentType: result.equipmentType, painZone: result.painZone, notes: result.notes, date: context.date, occurrenceKey: result.occurrenceKey))
            } else { bytes = nil }
            guard bytes == fact.local.payload else { throw DayComposerStabilizationError.staleEvidence }
        }
        try finalInputsParticipant(for: local.source).verify(capture.finalInputs)
    }

    private func observeOwners() {
        // @Published fires before didSet persistence. Schedule a later MainActor
        // read, discard emitted values, and never use publication as a disk ACK.
        for owner in [morningVM, eveningVM] {
            owner.$logResults.dropFirst().sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.revalidateExecutionContext() else { return }
                    self.refreshDerivedState()
                }
            }.store(in: &subscriptions)
            owner.$sessionComment.dropFirst().sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.revalidateExecutionContext() else { return }
                    self.objectWillChange.send()
                }
            }.store(in: &subscriptions)
        }
    }
}

/// Local facts only. Server freshness/completion/history must be supplied independently.
struct DayComposerLocalFinalizationFacts {
    let identity: DayComposerExecutionIdentity
    let source: DayComposerSource
    let canonicalPlan: DayComposerSnapshot
    let itemFacts: [DayComposerRequiredItemFacts]
    let comment: String
    let guardValue: DayComposerFinalizationGuard
    /// Mises de côté au moment de la capture ; revérifiées par verifyFinalCapture.
    var setAside: Set<DayComposerItemID> = []
}

/// A value capture, never a cached authorization. p2b owns reconstruction/binding.
struct DayComposerFinalSourceCapture {
    let local: DayComposerLocalFinalizationFacts
    let finalInputs: DayComposerFinalInputsReceipt
}
