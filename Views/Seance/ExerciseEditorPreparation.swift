import Foundation
import Combine

/// Ephemeral, card-local capability. It is deliberately not a source freeze or a draft store.
@MainActor
final class ExerciseEditorMutationGate: ObservableObject {
    @Published var allowsOrdinaryMutation = true
    struct PreparationToken: Equatable { fileprivate let value = UUID() }
    private var preparation: PreparationToken?

    func allowsPreparationMutation(_ token: PreparationToken) -> Bool { preparation == token }

    @discardableResult
    func performOrdinaryMutation(_ mutation: () -> Void) -> Bool {
        guard allowsOrdinaryMutation else { return false }
        mutation()
        return true
    }

    fileprivate func preparing<T>(_ body: (PreparationToken) -> T) -> T {
        let previous = preparation
        let token = PreparationToken()
        preparation = token
        defer { preparation = previous }
        return body(token)
    }
}

enum ExerciseEditorPreparationFailure: Error, Equatable {
    case unresolvedPrivateState(String)
    case missingEditor(String)
    case instanceChanged
    case failedPreparation(String)
}

struct ExerciseChildPreparationReceipt: Equatable {
    let identity: String
    let instance: UUID
    let generation: UInt64
    let value: String
}

@MainActor
protocol ExerciseChildPreparing: AnyObject {
    var instance: UUID { get }
    func prepare(identity: String, token: ExerciseEditorMutationGate.PreparationToken)
        -> Result<ExerciseChildPreparationReceipt, ExerciseEditorPreparationFailure>
    func verify(_ receipt: ExerciseChildPreparationReceipt) -> Bool
}

struct ExerciseEditorPreparationReceipt {
    fileprivate let instance: UUID
    let editorGeneration: UInt64
    let registryGeneration: UInt64
    let childReceipts: [ExerciseChildPreparationReceipt]
    let equipmentType: String
    fileprivate let mode: ExerciseEditorMode
}

fileprivate struct ExerciseEditorMode: Equatable {
    let logged: Bool
    let editing: Bool
    let setBySet: Bool
    let counter: Bool
    let setIndex: Int

    @MainActor init(_ vm: ExerciseViewModel) {
        logged = vm.isLogged; editing = vm.isEditing
        setBySet = vm.setBySetMode; counter = vm.repCountMode; setIndex = vm.currentSetIndex
    }
}

struct ExerciseCardStabilizationReceipt {
    let editors: ExerciseEditorPreparationReceipt
    let persistence: ExerciseLocalFlushReceipt
}

enum ExerciseCardStabilizationOutcome {
    case stable(ExerciseCardStabilizationReceipt)
    case editorFailure(ExerciseEditorPreparationFailure)
    case persistenceFailure(ExerciseLocalFlushOutcome)
}

/// Owned by StateObject in one ExerciseCard. Children are weak: child closures cannot
/// keep the card alive through the registry. Disappearing children do not erase signals.
@MainActor
final class ExerciseEditorPreparationController: ObservableObject {
    @MainActor private final class Entry {
        weak var child: (any ExerciseChildPreparing)?
        let token: UUID
        init(_ child: any ExerciseChildPreparing) { self.child = child; token = child.instance }
    }
    let gate: ExerciseEditorMutationGate
    let instance = UUID()
    private weak var vm: ExerciseViewModel?
    private var attached = false
    private var equipmentBaseline: String?
    private var initialEquipment: String?
    private var children: [String: [UUID: Entry]] = [:]
    private var unresolved: [String: String] = [:]
    private var counts: [String: Int] = [:]
    private var enduranceInspected = false
    private var gateObservation: AnyCancellable?
    private(set) var editorGeneration: UInt64 = 0
    private(set) var registryGeneration: UInt64 = 0

    init(gate: ExerciseEditorMutationGate? = nil) {
        self.gate = gate ?? ExerciseEditorMutationGate()
        gateObservation = self.gate.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func attach(_ vm: ExerciseViewModel, requiresEnduranceInspection: Bool = false) {
        guard !attached else { return }
        if let previous = self.vm, previous !== vm { return }
        self.vm = vm
        attached = true
        if equipmentBaseline == nil {
            equipmentBaseline = vm.equipmentType
            initialEquipment = vm.equipmentType
            if requiresEnduranceInspection && !enduranceInspected { unresolved["endurance"] = "Timer non inspecté" }
        }
    }

    func detach() { attached = false; editorGeneration &+= 1 }
    func didMutatePrivateState() { editorGeneration &+= 1 }

    func setEquipment(_ value: String) {
        guard gate.allowsOrdinaryMutation, let vm, vm.equipmentType != value else { return }
        vm.equipmentType = value
        didMutatePrivateState()
    }

    func acceptedEquipmentLog(_ loggedEquipment: String? = nil) {
        guard let vm else { return }
        equipmentBaseline = loggedEquipment ?? vm.equipmentType
        didMutatePrivateState()
    }

    func removedEquipmentLog() {
        equipmentBaseline = initialEquipment
        didMutatePrivateState()
    }

    @discardableResult
    func register(_ child: any ExerciseChildPreparing, identity: String) -> Bool {
        if children[identity]?[child.instance] != nil { return children[identity]?.count == 1 }
        // An explicit replacement may supersede a dead instance. An unexplained
        // dead entry without replacement still fails prepare as missingEditor.
        var entries = children[identity, default: [:]].filter { $0.value.child != nil }
        entries[child.instance] = Entry(child)
        children[identity] = entries
        registryGeneration &+= 1
        didMutatePrivateState()
        return entries.count == 1
    }

    func unregister(identity: String, token: UUID) {
        guard var entries = children[identity], entries.removeValue(forKey: token) != nil else { return }
        children[identity] = entries.isEmpty ? nil : entries
        registryGeneration &+= 1
        didMutatePrivateState()
    }

    func signal(identity: String, unresolved reason: String?) {
        unresolved[identity] = reason
        didMutatePrivateState()
    }

    func count(identity: String) -> Int { counts[identity, default: 0] }
    func inspectEnduranceIdle() {
        if !enduranceInspected {
            enduranceInspected = true
            signal(identity: "endurance", unresolved: nil)
        }
        // A remounted idle child must not erase an earlier undelivered completion.
    }

    func enduranceTransition(_ state: ExerciseEndurancePreparationState) {
        enduranceInspected = true
        signal(identity: "endurance", unresolved: state.unresolvedReason)
    }
    func setCount(_ value: Int, identity: String, explicitlyResolved: Bool = false) {
        counts[identity] = value
        // Merely decrementing to zero is not an explicit discard/confirmation.
        if explicitlyResolved { unresolved.removeValue(forKey: identity) }
        else if value > 0 { unresolved[identity] = "Répétitions non confirmées" }
        didMutatePrivateState()
    }

    func prepareEditorsForStabilization()
        -> Result<ExerciseEditorPreparationReceipt, ExerciseEditorPreparationFailure> {
        guard attached, let vm, equipmentBaseline != nil else {
            return .failure(.failedPreparation("Carte non hydratée ou démontée"))
        }
        guard !vm.isSkipped else { return .failure(.failedPreparation("Exercice sauté")) }
        guard children.values.allSatisfy({ $0.count == 1 }) else { return .failure(.instanceChanged) }
        let registry = registryGeneration
        var receipts: [ExerciseChildPreparationReceipt] = []
        for identity in children.keys.sorted() {
            guard let child = children[identity]?.values.first?.child else { return .failure(.missingEditor(identity)) }
            let result = gate.preparing { child.prepare(identity: identity, token: $0) }
            switch result {
            case .failure(let failure): return .failure(failure)
            case .success(let receipt): receipts.append(receipt)
            }
        }
        guard registry == registryGeneration else { return .failure(.instanceChanged) }
        if let identity = unresolved.keys.sorted().first, let reason = unresolved[identity] {
            return .failure(.unresolvedPrivateState("\(identity): \(reason)"))
        }
        guard vm.equipmentType == equipmentBaseline else {
            return .failure(.unresolvedPrivateState("equipmentType"))
        }
        let receipt = ExerciseEditorPreparationReceipt(instance: instance,
            editorGeneration: editorGeneration, registryGeneration: registry,
            childReceipts: receipts, equipmentType: vm.equipmentType, mode: ExerciseEditorMode(vm))
        return verifyEditors(receipt) ? .success(receipt) : .failure(.instanceChanged)
    }

    func verifyEditors(_ receipt: ExerciseEditorPreparationReceipt) -> Bool {
        guard attached, let vm, receipt.instance == instance,
              !vm.isSkipped, receipt.mode == ExerciseEditorMode(vm),
              receipt.editorGeneration == editorGeneration,
              receipt.registryGeneration == registryGeneration,
              receipt.equipmentType == vm.equipmentType, equipmentBaseline == vm.equipmentType,
              unresolved.isEmpty, children.values.allSatisfy({ $0.count == 1 }),
              receipt.childReceipts.count == children.count else { return false }
        return receipt.childReceipts.allSatisfy { childReceipt in
            guard let entry = children[childReceipt.identity]?[childReceipt.instance],
                  let child = entry.child else { return false }
            return child.verify(childReceipt)
        }
    }

    func prepareAndFlush() -> ExerciseCardStabilizationOutcome {
        switch prepareEditorsForStabilization() {
        case .failure(let failure): return .editorFailure(failure)
        case .success(let editors):
            return flushPreparedEditors(editors)
        }
    }

    /// Consumes an already prepared receipt; never re-prepares another child.
    func flushPreparedEditors(_ editors: ExerciseEditorPreparationReceipt) -> ExerciseCardStabilizationOutcome {
        guard verifyEditors(editors), let vm else { return .editorFailure(.instanceChanged) }
        let result = vm.flushPendingLocalPersistence()
        guard case .stable(let persistence) = result else { return .persistenceFailure(result) }
        let receipt = ExerciseCardStabilizationReceipt(editors: editors, persistence: persistence)
        return verifyCardStabilization(receipt) ? .stable(receipt) : .editorFailure(.instanceChanged)
    }

    func verifyCardStabilization(_ receipt: ExerciseCardStabilizationReceipt) -> Bool {
        verifyEditors(receipt.editors) && vm?.verifyLocalPersistence(receipt.persistence) == true
    }
}

/// Only this field's normalization write can use the preparation capability.
@MainActor
struct ExerciseStepperPreparationContext {
    let controller: ExerciseEditorPreparationController
    let identity: String
    private let write: (String) -> Void
    var isAvailable: () -> Bool = { true }
    var normalization: ((String) -> String)? = nil

    init(controller: ExerciseEditorPreparationController, identity: String,
         writeNormalized: @escaping (String) -> Void, isAvailable: @escaping () -> Bool = { true },
         normalization: ((String) -> String)? = nil) {
        self.controller = controller; self.identity = identity; self.write = writeNormalized
        self.isAvailable = isAvailable; self.normalization = normalization
    }

    fileprivate func writeNormalized(_ value: String, token: ExerciseEditorMutationGate.PreparationToken) -> Bool {
        guard isAvailable(), controller.gate.allowsPreparationMutation(token) else { return false }
        write(value)
        return true
    }
}

/// Shared by the real Stepper and unit tests. No sleep/runloop acknowledgment.
@MainActor
final class ExerciseStepperEditor: ObservableObject, ExerciseChildPreparing {
    let instance = UUID()
    private(set) var callbackEpoch: UInt64 = 0
    private(set) var holdEpoch: UInt64 = 0
    var holdTask: Task<Void, Never>?
    private var mounted = false
    private var read: () -> String = { "" }
    private var write: (String) -> Void = { _ in }
    private var normalize: (String) -> String = { $0 }
    private var context: ExerciseStepperPreparationContext?
    private var gateObservation: AnyCancellable?
    private func normalized(_ raw: String) -> String { context?.normalization?(raw) ?? normalize(raw) }

    func mount(read: @escaping () -> String, write: @escaping (String) -> Void,
               minimum: Double, isInteger: Bool, context: ExerciseStepperPreparationContext?) {
        if self.context?.identity != context?.identity { unmount() }
        self.read = read; self.write = write
        normalize = { Self.normalized($0, minimum: minimum, isInteger: isInteger) }
        self.context = context
        gateObservation = context?.controller.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        mounted = true
        if let context { _ = context.controller.register(self, identity: context.identity) }
    }

    static func formatted(_ value: Double, isInteger: Bool) -> String {
        if isInteger || value.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }

    static func normalized(_ raw: String, minimum: Double, isInteger: Bool) -> String {
        guard !raw.isEmpty else { return raw }
        let value = Double(raw.replacingOccurrences(of: ",", with: ".")) ?? minimum
        return formatted(max(minimum, value), isInteger: isInteger)
    }

    var allowsOrdinaryMutation: Bool { context?.controller.gate.allowsOrdinaryMutation ?? true }
    func callbackIsCurrent(_ epoch: UInt64) -> Bool {
        mounted && callbackEpoch == epoch && allowsOrdinaryMutation
    }
    func holdIsCurrent(_ epoch: UInt64) -> Bool {
        mounted && holdEpoch == epoch && allowsOrdinaryMutation
    }
    func stopHold() { holdEpoch &+= 1; holdTask?.cancel(); holdTask = nil }
    func invalidateCallbacks() { callbackEpoch &+= 1; stopHold() }

    func normalizeOrdinary() {
        guard allowsOrdinaryMutation else { return }
        let value = normalized(read())
        if read() != value { write(value) }
    }

    @discardableResult
    func step(_ direction: Int, increment: Double, minimum: Double, placeholder: Double, isInteger: Bool) -> Bool {
        guard mounted, allowsOrdinaryMutation else { return false }
        let raw = read()
        let current = raw.isEmpty ? placeholder : Double(raw.replacingOccurrences(of: ",", with: ".")) ?? placeholder
        write(Self.formatted(max(minimum, current + Double(direction) * increment), isInteger: isInteger))
        return true
    }

    func unmount() {
        invalidateCallbacks()
        mounted = false
        if let context {
            context.controller.signal(identity: context.identity,
                unresolved: read() == normalized(read()) ? nil : "Champ numérique non préparé")
            context.controller.unregister(identity: context.identity, token: instance)
        }
        // Release Binding closures when no longer displayed.
        read = { "" }; write = { _ in }; context = nil
        gateObservation = nil
    }

    func prepare(identity: String, token: ExerciseEditorMutationGate.PreparationToken)
        -> Result<ExerciseChildPreparationReceipt, ExerciseEditorPreparationFailure> {
        guard mounted, let context, context.identity == identity, context.isAvailable() else { return .failure(.missingEditor(identity)) }
        guard context.controller.gate.allowsPreparationMutation(token) else {
            return .failure(.failedPreparation("Capacité expirée"))
        }
        invalidateCallbacks()
        let value = normalized(read())
        if read() != value, !context.writeNormalized(value, token: token) {
            return .failure(.failedPreparation("Écriture de préparation refusée"))
        }
        guard read() == value else { return .failure(.failedPreparation("Readback numérique différent")) }
        context.controller.signal(identity: identity, unresolved: nil)
        return .success(ExerciseChildPreparationReceipt(identity: identity, instance: instance,
            generation: callbackEpoch, value: value))
    }

    func verify(_ receipt: ExerciseChildPreparationReceipt) -> Bool {
        mounted && receipt.instance == instance && receipt.generation == callbackEpoch
            && context?.isAvailable() == true && receipt.value == read() && holdTask == nil
    }
}

enum ExerciseEndurancePreparationState: Equatable {
    case countdown, running, warning, paused, completionUndelivered
    case explicitlyStopped, completionDelivered

    var unresolvedReason: String? {
        switch self {
        case .explicitlyStopped, .completionDelivered: return nil
        case .countdown: return "Compte à rebours"
        case .running: return "Timer en cours"
        case .warning: return "Fin de timer en cours"
        case .paused: return "Timer en pause"
        case .completionUndelivered: return "Durée non livrée au modèle"
        }
    }
}

/// Lifecycle receipt for private-state children; the sticky value lives on the card.
@MainActor
final class ExercisePrivateEditor: ObservableObject, ExerciseChildPreparing {
    let instance = UUID()
    private var controller: ExerciseEditorPreparationController?
    private var identity: String?
    private var generation: UInt64 = 0
    var isAvailable: () -> Bool = { true }

    func mount(_ controller: ExerciseEditorPreparationController?, identity: String) {
        if self.identity != identity { unmount() }
        self.controller = controller; self.identity = identity
        if let controller { _ = controller.register(self, identity: identity) }
    }
    func changed() { generation &+= 1; controller?.didMutatePrivateState() }
    func unmount() {
        if let identity { controller?.unregister(identity: identity, token: instance) }
        identity = nil; controller = nil; generation &+= 1
    }
    func prepare(identity: String, token: ExerciseEditorMutationGate.PreparationToken)
        -> Result<ExerciseChildPreparationReceipt, ExerciseEditorPreparationFailure> {
        guard self.identity == identity, isAvailable(), controller?.gate.allowsPreparationMutation(token) == true else {
            return .failure(.instanceChanged)
        }
        return .success(ExerciseChildPreparationReceipt(identity: identity, instance: instance,
            generation: generation, value: "private-state"))
    }
    func verify(_ receipt: ExerciseChildPreparationReceipt) -> Bool {
        isAvailable() && receipt.identity == identity && receipt.instance == instance && receipt.generation == generation
    }
}
