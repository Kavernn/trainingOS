import Foundation
import Combine

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
    private let morningAuthorization: DayComposerProvenanceStore.Authorization
    private let eveningAuthorization: DayComposerProvenanceStore.Authorization
    private let currentDate: () -> String
    private var subscriptions = Set<AnyCancellable>()
    @Published private(set) var isLocked = false
    @Published private(set) var currentUnitID: DayComposerItemID?
    @Published private(set) var currentMemberID: DayComposerItemID?

    var context: DayComposerExecutionContext { input.context }
    var orderedUnits: [DayComposerUnit] { input.orderedUnits }
    private var items: [DayComposerItem] { orderedUnits.flatMap(\.items) }

    static func isSupported(_ tracking: String) -> Bool {
        ["reps", "time", "carry", "plyo", "protocol"].contains(tracking)
    }

    /// All asynchronous reads are already complete. Keep prepare/create/bind in
    /// one non-suspending MainActor operation, publishing nothing on failure.
    /// Narrow owner/bind seams allow failure tests without a second store universe.
    static func make(
        validatedInput input: DayComposerValidatedExecutionInput,
        currentDate: @escaping () -> String = { DateFormatter.isoDate.string(from: Date()) },
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
        if fresh { try store.create(context: input.context) }
        let morningToken = try store.authorize(context: input.context, source: .morning)
        let eveningToken = try store.authorize(context: input.context, source: .evening)
        try bind(morning, morningToken)
        try bind(evening, eveningToken)
        let coordinator = DayComposerExecutionCoordinator(input: input, morning: morning, evening: evening,
            morningToken: morningToken, eveningToken: eveningToken, currentDate: currentDate)
        guard coordinator.revalidateExecutionContext() else { throw Failure.incompatible }
        coordinator.selectFirstActionable()
        coordinator.observeOwners()
        return coordinator
    }

    private init(input: DayComposerValidatedExecutionInput, morning: SeanceViewModel, evening: SeanceViewModel,
                 morningToken: DayComposerProvenanceStore.Authorization,
                 eveningToken: DayComposerProvenanceStore.Authorization, currentDate: @escaping () -> String) {
        self.input = input
        morningVM = morning
        eveningVM = evening
        morningAuthorization = morningToken
        eveningAuthorization = eveningToken
        self.currentDate = currentDate
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
                      unit.items.allSatisfy({ $0.id.source == plan.source }),
                      unit.group == nil || unit.items.allSatisfy({ isSupported($0.tracking) }) else {
                    throw Failure.invalidPlan
                }
            }
        }
    }

    private static func validateResults(_ owner: SeanceViewModel, plan: DayComposerPlan) throws {
        let names = Set(plan.units.flatMap { $0.items.map(\.name) })
        guard owner.logResults.allSatisfy({ key, result in
            names.contains(key) && result.name == key && !result.isBonus
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
        return sourceOwner(id.source)
    }
    func authorization(for source: DayComposerSource) throws -> DayComposerProvenanceStore.Authorization {
        guard revalidateExecutionContext() else { throw Failure.incompatible }
        return source == .morning ? morningAuthorization : eveningAuthorization
    }
    func result(for id: DayComposerItemID) throws -> ExerciseLogResult? {
        guard let item = item(for: id) else { throw Failure.invalidItem }
        return try owner(for: id).logResults[item.name]
    }
    func setResult(_ result: ExerciseLogResult?, for id: DayComposerItemID) throws {
        guard let item = item(for: id) else { throw Failure.invalidItem }
        let owner = try owner(for: id)
        guard Self.isSupported(item.tracking), let state = status(for: id),
              !state.draftCorrupt, state.status != .serverObserved else { throw Failure.readOnlyItem }
        if let result {
            guard result.name == item.name, result.isSecond == (id.source == .evening), !result.isBonus else {
                throw Failure.invalidResult
            }
        }
        owner.logResults[item.name] = result
        guard revalidateExecutionContext() else { throw Failure.incompatible }
        refreshSelectionAfterChange()
    }
    func comment(for source: DayComposerSource) -> String { sourceOwner(source).sessionComment }
    func setComment(_ comment: String, for source: DayComposerSource) throws {
        guard revalidateExecutionContext() else { throw Failure.incompatible }
        sourceOwner(source).sessionComment = comment
        guard revalidateExecutionContext() else { throw Failure.incompatible }
    }

    /// Read-only projection. No synthetic logs, cleanup, ACK or copies of owner state.
    func status(for id: DayComposerItemID) -> ItemState? {
        guard let item = item(for: id) else { return nil }
        let draft = ExerciseDraftPersistence(date: context.date, sessionType: id.source.rawValue,
                                             exerciseName: item.name).presence()
        let observed = input.serverProjection.presence(of: item.name, source: id.source) == .observed
        let status: Status
        if !Self.isSupported(item.tracking) { status = .unsupported }
        else if sourceOwner(id.source).logResults[item.name] != nil { status = .localLogged }
        else if observed { status = .serverObserved }
        else if draft != .absent { status = .draftOnly }
        else { status = .unknown }
        return ItemState(status: status, draft: draft, serverObserved: observed)
    }
    var executableCount: Int { items.filter { Self.isSupported($0.tracking) }.count }
    var treatedCount: Int {
        items.filter { item in
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
        guard revalidateExecutionContext() else { throw Failure.incompatible }
        guard let unit = orderedUnits.first(where: { $0.items.contains(where: { $0.id == id }) }) else {
            throw Failure.invalidItem
        }
        currentUnitID = unit.id
        currentMemberID = id
    }
    func selectFirstActionable() {
        guard revalidateExecutionContext() else { return }
        setSelection(items.first(where: { status(for: $0.id)?.isActionable == true })?.id)
    }
    func next() {
        guard revalidateExecutionContext() else { return }
        let start = currentMemberID.flatMap { id in items.firstIndex(where: { $0.id == id }) }.map { $0 + 1 } ?? 0
        setSelection(items.dropFirst(start).first(where: { status(for: $0.id)?.isActionable == true })?.id)
    }
    func previous() {
        guard revalidateExecutionContext() else { return }
        let index = currentMemberID.flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? items.count
        if index > 0 { setSelection(items[index - 1].id) }
    }
    private func setSelection(_ id: DayComposerItemID?) {
        currentMemberID = id
        currentUnitID = id.flatMap { id in orderedUnits.first(where: { $0.items.contains(where: { $0.id == id }) })?.id }
    }
    private func refreshSelectionAfterChange() {
        objectWillChange.send()
        if let id = currentMemberID {
            if status(for: id)?.isActionable == false { next() }
        } else { selectFirstActionable() }
    }
    private func observeOwners() {
        // @Published fires before didSet persistence. Schedule a later MainActor
        // read, discard emitted values, and never use publication as a disk ACK.
        for owner in [morningVM, eveningVM] {
            owner.$logResults.dropFirst().sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.revalidateExecutionContext() else { return }
                    self.refreshSelectionAfterChange()
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
