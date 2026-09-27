import Foundation

/// Source-local projection only. The p1 store remains the durable authority.
/// No editable buffer, extra content generation, binding or finalization side effects.
@MainActor
final class DayComposerFinalInputsParticipant {
    enum State: Equatable {
        case unloaded, missing
        case loaded(DayComposerFinalInputsReceipt)
        case failed(DayComposerFinalInputsError)
    }

    let identity: DayComposerExecutionIdentity
    let source: DayComposerSource
    let instance = UUID()
    private let store: DayComposerFinalInputsStore
    private let authorizeMutation: () throws -> Void
    private(set) var state: State = .unloaded

    init(identity: DayComposerExecutionIdentity, source: DayComposerSource,
         store: DayComposerFinalInputsStore, authorizeMutation: @escaping () throws -> Void) {
        self.identity = identity
        self.source = source
        self.store = store
        self.authorizeMutation = authorizeMutation
        // Restoration failure is a typed projection, not a failure of local-only execution.
        do { try reload() } catch { /* reload preserves the typed failure. */ }
    }

    @discardableResult
    func reload() throws -> DayComposerFinalInputsReceipt? {
        do {
            let receipt = try store.load(executionIdentity: identity, source: source)?.receipt
            state = receipt.map(State.loaded) ?? .missing
            return receipt
        } catch {
            let failure = error as? DayComposerFinalInputsError ?? .durabilityFailure
            state = .failed(failure)
            throw failure
        }
    }

    @discardableResult
    func setRPE(_ rpe: Double) throws -> DayComposerFinalInputsReceipt {
        // Includes same-content edits. Refusal cannot touch disk or the projection.
        try authorizeMutation()
        let expected: DayComposerFinalInputsReceipt?
        switch state {
        case .loaded(let receipt): expected = receipt
        case .missing: expected = nil
        case .failed(let error): throw error
        case .unloaded: throw DayComposerFinalInputsError.staleInputs
        }
        let current = try store.load(executionIdentity: identity, source: source)?.receipt
        // Reconcile without adopting an external edit as this caller's CAS baseline.
        // The caller must explicitly reload after a stale refusal, then retry.
        guard current == expected else { throw DayComposerFinalInputsError.staleInputs }
        let values = try DayComposerFinalInputs(rpe: rpe)
        try authorizeMutation()
        let receipt = try store.save(executionIdentity: identity, source: source,
            values: values, expectedRevision: expected?.revision)
        guard receipt.executionIdentity == identity, receipt.source == source,
              receipt.values == values, try store.verify(receipt) else {
            throw DayComposerFinalInputsError.staleInputs
        }
        state = .loaded(receipt)
        return receipt
    }

    /// Observation only. A final attempt deliberately reloads disk truth, never a default RPE.
    func prepare() throws -> DayComposerFinalInputsReceipt {
        guard let receipt = try reload() else { throw DayComposerFinalInputsError.missingRequiredRPE }
        try verify(receipt)
        return receipt
    }

    func verify(_ receipt: DayComposerFinalInputsReceipt) throws {
        guard receipt.executionIdentity == identity else { throw DayComposerFinalInputsError.contextMismatch }
        guard receipt.source == source else { throw DayComposerFinalInputsError.sourceMismatch }
        guard try store.verify(receipt) else { throw DayComposerFinalInputsError.staleInputs }
    }
}
