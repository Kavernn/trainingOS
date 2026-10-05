import Foundation
import Combine

enum DayComposerStabilizationError: Error, Equatable {
    case busy, contextRejected, missingParticipant, unexpectedParticipant, duplicateParticipant
    case participantSetChanged, missingComment, commentFailed, persistenceFailed, staleEvidence
    case editor(ExerciseEditorPreparationFailure), nonRepresentablePain
    case sourceFrozen
}

/// Type-erased, attempt-local receipts. Closures retain no business state copies.
@MainActor
struct DayComposerPreparedCard {
    let verify: () -> Bool
    let flush: () throws -> DayComposerVerifiedCard
}

@MainActor
struct DayComposerVerifiedCard {
    let verify: () -> Bool
}

@MainActor
protocol DayComposerCardParticipant: AnyObject {
    var instance: UUID { get }
    var gate: ExerciseEditorMutationGate { get }
    func prepareForSource() throws -> DayComposerPreparedCard
}

extension ExerciseEditorPreparationController: DayComposerCardParticipant {
    func prepareForSource() throws -> DayComposerPreparedCard {
        let editors: ExerciseEditorPreparationReceipt
        switch prepareEditorsForStabilization() {
        case .success(let value): editors = value
        case .failure(let failure): throw DayComposerStabilizationError.editor(failure)
        }
        return .init(verify: { [weak self] in self?.verifyEditors(editors) == true }, flush: { [weak self] in
            guard let self else { throw DayComposerStabilizationError.missingParticipant }
            switch self.flushPreparedEditors(editors) {
            case .stable(let receipt):
                return .init(verify: { [weak self] in self?.verifyCardStabilization(receipt) == true })
            case .editorFailure(let failure): throw DayComposerStabilizationError.editor(failure)
            case .persistenceFailure(.rejectedContext): throw DayComposerStabilizationError.contextRejected
            case .persistenceFailure(.nonRepresentableState): throw DayComposerStabilizationError.nonRepresentablePain
            case .persistenceFailure: throw DayComposerStabilizationError.persistenceFailed
            }
        })
    }
}

/// Transient UI text only. Persistence remains exclusively with the source owner.
@MainActor
final class DayComposerCommentParticipant: ObservableObject {
    let source: DayComposerSource
    let instance = UUID()
    @Published private(set) var text: String
    @Published private(set) var outcome: LocalPersistenceResult?
    private(set) var generation: UInt64 = 0

    init(source: DayComposerSource, text: String) { self.source = source; self.text = text }

    fileprivate func update(_ value: String) {
        if value != text { generation &+= 1; text = value }
    }
    fileprivate func report(_ value: LocalPersistenceResult) { outcome = value }
}

/// Only valid during its originating synchronous operation. Never persist/cache as an ACK.
@MainActor
struct DayComposerStableSourceEvidence {
    let source: DayComposerSource
    let identity: DayComposerExecutionIdentity
    let guardValue: DayComposerFinalizationGuard
    let comment: String
    let expectedParticipantIDs: [DayComposerExecutionItemIdentity]
    let registryGeneration: UInt64
    fileprivate let isLive: () -> Bool
    var isCurrentAttempt: Bool { isLive() }
    var stabilization: DayComposerLocalStabilizationState {
        isCurrentAttempt ? .stableAccepted(guardValue) : .unknown
    }
}

/// Non-optional final-input proof, valid only inside the originating final closure.
/// Does not establish readiness, a snapshot binding or permission to submit.
@MainActor
struct DayComposerStableFinalSourceEvidence {
    let local: DayComposerStableSourceEvidence
    let finalInputs: DayComposerFinalInputsReceipt
    fileprivate let verifyInputs: () throws -> Void
    /// Read-only expiry witness. Unlike live evidence this can outlive the
    /// closure, but cannot capture, flush, bind, or authorize a new snapshot.
    let verifyUnchanged: () throws -> Void
    var isCurrentAttempt: Bool { local.isCurrentAttempt }

    func verifyCurrent() throws {
        guard isCurrentAttempt else { throw DayComposerStabilizationError.staleEvidence }
        try verifyInputs()
    }
}

/// Optional lifecycle endpoint supplied only to Day Composer cards.
@MainActor
struct DayComposerCardRegistration {
    weak var barrier: DayComposerLocalStabilizationBarrier?
    let identity: DayComposerExecutionItemIdentity
    func appear(_ handle: ExerciseEditorPreparationController) { barrier?.register(handle, identity: identity) }
    func disappear(_ handle: ExerciseEditorPreparationController) {
        barrier?.unregister(identity: identity, token: handle.instance)
    }
}

/// Caller owns this alongside its coordinator, then injects the SAME instance into
/// ActiveView/future local finalization caller. No network or durable store ownership.
@MainActor
final class DayComposerLocalStabilizationBarrier: ObservableObject {
    enum Phase: Equatable { case idle, preparingEditors, stabilizing, frozenForSnapshot }
    struct Dependencies {
        let identity: DayComposerExecutionIdentity
        let expected: (DayComposerSource) -> [DayComposerExecutionItemIdentity]
        let validate: () -> Bool
        let guardValue: (DayComposerSource) throws -> DayComposerFinalizationGuard
        let writeComment: (String, DayComposerSource) -> LocalPersistenceResult
        let commentMatches: (String, DayComposerSource) -> Bool
        let rejected: () -> Void
    }
    @MainActor private final class CardEntry {
        weak var handle: (any DayComposerCardParticipant)?
        let token: UUID
        init(_ handle: any DayComposerCardParticipant) { self.handle = handle; token = handle.instance }
    }
    private final class CommentEntry {
        weak var holder: DayComposerCommentParticipant?
        init(_ holder: DayComposerCommentParticipant) { self.holder = holder }
    }
    private final class FinalInputsEntry {
        weak var participant: DayComposerFinalInputsParticipant?
        init(_ participant: DayComposerFinalInputsParticipant) { self.participant = participant }
    }
    private struct CommentReceipt {
        let instance: UUID
        let generation: UInt64
        let text: String
    }
    let identity: DayComposerExecutionIdentity
    private let dependencies: Dependencies
    private var cards: [DayComposerExecutionItemIdentity: [UUID: CardEntry]] = [:]
    private var comments: [DayComposerSource: [UUID: CommentEntry]] = [:]
    private var generations: [DayComposerSource: UInt64] = [:]
    private var finalInputs: [DayComposerSource: [UUID: FinalInputsEntry]] = [:]
    private var finalInputsGenerations: [DayComposerSource: UInt64] = [:]
    private var activeAttempt: UUID?
    private var frozenSource: DayComposerSource?
    @Published private(set) var phases: [DayComposerSource: Phase] = [:]
    var isInteractionFrozen: Bool { activeAttempt != nil }
    func phase(for source: DayComposerSource) -> Phase { phases[source] ?? .idle }
    func permitsOrdinaryMutation(for source: DayComposerSource) -> Bool { frozenSource != source }
    func registryGeneration(for source: DayComposerSource) -> UInt64 { generations[source, default: 0] }

    init(dependencies: Dependencies) { self.dependencies = dependencies; identity = dependencies.identity }

    @discardableResult
    func performNavigation(_ action: () -> Void) -> Bool {
        guard !isInteractionFrozen else { return false }
        action(); return true
    }

    @discardableResult
    func register(_ handle: any DayComposerCardParticipant, identity: DayComposerExecutionItemIdentity) -> Bool {
        if let entry = cards[identity]?[handle.instance] {
            return entry.handle === handle && cards[identity]?.count == 1
        }
        // Explicit replacement can retire dead entries; unexplained dead entries fail coverage.
        var entries = cards[identity, default: [:]].filter { $0.value.handle != nil }
        entries[handle.instance] = CardEntry(handle)
        cards[identity] = entries
        generations[identity.source, default: 0] &+= 1
        return entries.count == 1
    }

    func unregister(identity: DayComposerExecutionItemIdentity, token: UUID) {
        guard cards[identity]?.removeValue(forKey: token) != nil else { return }
        if cards[identity]?.isEmpty == true { cards.removeValue(forKey: identity) }
        generations[identity.source, default: 0] &+= 1
    }

    @discardableResult
    func registerComment(_ holder: DayComposerCommentParticipant) -> Bool {
        if let entry = comments[holder.source]?[holder.instance] {
            return entry.holder === holder && comments[holder.source]?.count == 1
        }
        var entries = comments[holder.source, default: [:]].filter { $0.value.holder != nil }
        entries[holder.instance] = CommentEntry(holder)
        comments[holder.source] = entries
        generations[holder.source, default: 0] &+= 1
        return entries.count == 1
    }

    func unregisterComment(source: DayComposerSource, token: UUID) {
        guard comments[source]?.removeValue(forKey: token) != nil else { return }
        generations[source, default: 0] &+= 1
    }

    @discardableResult
    func registerFinalInputsParticipant(_ participant: DayComposerFinalInputsParticipant) -> Bool {
        let source = participant.source
        if let entry = finalInputs[source]?[participant.instance] {
            return entry.participant === participant && finalInputs[source]?.count == 1
                && participant.identity == identity
        }
        var entries = finalInputs[source, default: [:]].filter { $0.value.participant != nil }
        entries[participant.instance] = FinalInputsEntry(participant)
        finalInputs[source] = entries
        finalInputsGenerations[source, default: 0] &+= 1
        return entries.count == 1 && participant.identity == identity
    }

    func unregisterFinalInputsParticipant(source: DayComposerSource, token: UUID) {
        guard finalInputs[source]?.removeValue(forKey: token) != nil else { return }
        finalInputsGenerations[source, default: 0] &+= 1
    }

    private func finalInputsHolder(_ source: DayComposerSource) throws -> DayComposerFinalInputsParticipant {
        guard let entries = finalInputs[source], !entries.isEmpty else {
            throw DayComposerStabilizationError.missingParticipant
        }
        guard entries.count == 1 else { throw DayComposerStabilizationError.duplicateParticipant }
        guard let participant = entries.values.first?.participant else {
            throw DayComposerStabilizationError.missingParticipant
        }
        guard participant.identity == identity else { throw DayComposerFinalInputsError.contextMismatch }
        guard participant.source == source else { throw DayComposerFinalInputsError.sourceMismatch }
        return participant
    }

    /// Gate BEFORE changing the UI buffer, including retry of identical content.
    @discardableResult
    func editComment(_ holder: DayComposerCommentParticipant, text: String) -> Bool {
        guard permitsOrdinaryMutation(for: holder.source), dependencies.validate() else { return false }
        holder.update(text)
        let result = dependencies.writeComment(text, holder.source)
        holder.report(result)
        if result == .rejectedContext { dependencies.rejected() }
        return true
    }

    private func validateContext() throws {
        guard dependencies.validate() else {
            dependencies.rejected(); throw DayComposerStabilizationError.contextRejected
        }
    }

    private func coverage(_ source: DayComposerSource,
                          expected: [DayComposerExecutionItemIdentity]) throws -> [any DayComposerCardParticipant] {
        guard Set(expected).count == expected.count, expected.allSatisfy({ id in
            id.source == source && id.executionID == identity.executionID && id.date == identity.date
                && id.version == identity.contextVersion && id.activeProgramID == identity.activeProgramID
                && id.sourceFingerprint == identity.sourceFingerprint
        }) else { throw DayComposerStabilizationError.contextRejected }
        let registered = Set(cards.keys.filter { $0.source == source })
        guard Set(expected).isSubset(of: registered) else { throw DayComposerStabilizationError.missingParticipant }
        guard registered == Set(expected) else { throw DayComposerStabilizationError.unexpectedParticipant }
        return try expected.map { id in
            guard let entries = cards[id], entries.count == 1 else { throw DayComposerStabilizationError.duplicateParticipant }
            guard let entry = entries.values.first, let handle = entry.handle, handle.instance == entry.token else {
                throw DayComposerStabilizationError.missingParticipant
            }
            return handle
        }
    }

    private func commentHolder(_ source: DayComposerSource) throws -> DayComposerCommentParticipant {
        guard let entries = comments[source], !entries.isEmpty else { throw DayComposerStabilizationError.missingComment }
        guard entries.count == 1 else { throw DayComposerStabilizationError.duplicateParticipant }
        guard let holder = entries.values.first?.holder, holder.source == source else {
            throw DayComposerStabilizationError.missingComment
        }
        return holder
    }

    private func verifyComment(_ receipt: CommentReceipt, holder: DayComposerCommentParticipant) -> Bool {
        holder.instance == receipt.instance && holder.generation == receipt.generation && holder.text == receipt.text
            && dependencies.commentMatches(receipt.text, holder.source)
    }

    /// Synchronous, nonescaping critical segment. No Task creation/network is allowed
    /// in operation. A stored snapshot remains historical if post-verification fails.
    func withStabilizedSource<T>(_ source: DayComposerSource,
                                operation: (DayComposerStableSourceEvidence) throws -> T) throws -> T {
        try stabilize(source, requiresFinalInputs: false) { local, _ in try operation(local) }
    }

    func withStabilizedFinalSource<T>(_ source: DayComposerSource,
        operation: (DayComposerStableFinalSourceEvidence) throws -> T) throws -> T {
        try stabilize(source, requiresFinalInputs: true) { _, final in
            guard let final else { throw DayComposerStabilizationError.missingParticipant }
            return try operation(final)
        }
    }

    /// Shared algorithm; local mode never loads or verifies the final-input registry/store.
    private func stabilize<T>(_ source: DayComposerSource, requiresFinalInputs: Bool,
        operation: (DayComposerStableSourceEvidence, DayComposerStableFinalSourceEvidence?) throws -> T) throws -> T {
        guard activeAttempt == nil else { throw DayComposerStabilizationError.busy }
        let attempt = UUID()
        activeAttempt = attempt // BEFORE any callback or publication (reentrance).
        frozenSource = source
        var gated: [(any DayComposerCardParticipant, Bool)] = []
        defer {
            for (handle, previous) in gated { handle.gate.allowsOrdinaryMutation = previous }
            phases[source] = .idle
            frozenSource = nil
            activeAttempt = nil
            objectWillChange.send()
        }
        do {
            try validateContext()
            let generation = registryGeneration(for: source)
            let expected = dependencies.expected(source)
            let handles = try coverage(source, expected: expected)
            let holder = try commentHolder(source)
            let inputsHolder = requiresFinalInputs ? try finalInputsHolder(source) : nil
            let inputsGeneration = requiresFinalInputs ? finalInputsGenerations[source, default: 0] : 0
            for handle in handles {
                gated.append((handle, handle.gate.allowsOrdinaryMutation))
                handle.gate.allowsOrdinaryMutation = false
            }
            func verifyRegistry() throws {
                guard activeAttempt == attempt, registryGeneration(for: source) == generation,
                      dependencies.expected(source) == expected else { throw DayComposerStabilizationError.participantSetChanged }
                let current = try coverage(source, expected: expected)
                guard zip(current, handles).allSatisfy({ pair in pair.0.instance == pair.1.instance }),
                      try commentHolder(source) === holder else { throw DayComposerStabilizationError.participantSetChanged }
                if let inputsHolder {
                    guard finalInputsGenerations[source, default: 0] == inputsGeneration,
                          try finalInputsHolder(source) === inputsHolder else {
                        throw DayComposerStabilizationError.participantSetChanged
                    }
                }
            }
            phases[source] = .preparingEditors
            let prepared = try handles.map { try $0.prepareForSource() }
            let inputsReceipt = try inputsHolder?.prepare()
            func verifyInputs() throws {
                if let inputsHolder, let inputsReceipt {
                    guard finalInputsGenerations[source, default: 0] == inputsGeneration,
                          try finalInputsHolder(source) === inputsHolder else {
                        throw DayComposerStabilizationError.participantSetChanged
                    }
                    try inputsHolder.verify(inputsReceipt)
                }
            }
            guard prepared.allSatisfy({ $0.verify() }) else { throw DayComposerStabilizationError.staleEvidence }
            try verifyInputs()
            try verifyRegistry()
            phases[source] = .stabilizing
            let receipts = try prepared.map { try $0.flush() }
            guard receipts.allSatisfy({ $0.verify() }) else { throw DayComposerStabilizationError.staleEvidence }
            let comment = CommentReceipt(instance: holder.instance, generation: holder.generation, text: holder.text)
            try validateContext()
            let outcome = dependencies.writeComment(comment.text, source)
            holder.report(outcome)
            switch outcome {
            case .accepted: break
            case .failed: throw DayComposerStabilizationError.commentFailed
            case .rejectedContext: throw DayComposerStabilizationError.contextRejected
            }
            try validateContext()
            guard verifyComment(comment, holder: holder), receipts.allSatisfy({ $0.verify() }) else {
                throw DayComposerStabilizationError.staleEvidence
            }
            try verifyInputs()
            try verifyRegistry()
            let guardValue = try dependencies.guardValue(source)
            try verifyInputs()
            try guardValue.validate(identity: identity, source: source)
            guard receipts.allSatisfy({ $0.verify() }), verifyComment(comment, holder: holder) else {
                throw DayComposerStabilizationError.staleEvidence
            }
            phases[source] = .frozenForSnapshot
            // Published transitions may synchronously reenter clients. Never hand
            // evidence to the caller after one of those clients changed the inputs.
            try validateContext()
            try verifyRegistry()
            try verifyInputs()
            guard receipts.allSatisfy({ $0.verify() }), verifyComment(comment, holder: holder),
                  try dependencies.guardValue(source) == guardValue else {
                throw DayComposerStabilizationError.staleEvidence
            }
            try verifyInputs()
            let evidence = DayComposerStableSourceEvidence(source: source, identity: identity, guardValue: guardValue,
                comment: comment.text, expectedParticipantIDs: expected, registryGeneration: generation,
                isLive: { [weak self] in self?.activeAttempt == attempt && self?.phase(for: source) == .frozenForSnapshot })
            let finalEvidence: DayComposerStableFinalSourceEvidence?
            if let inputsHolder, let inputsReceipt {
                finalEvidence = .init(local: evidence, finalInputs: inputsReceipt,
                    verifyInputs: { [weak self, weak inputsHolder] in
                        guard let self, let inputsHolder,
                              self.activeAttempt == attempt,
                              self.finalInputsGenerations[source, default: 0] == inputsGeneration,
                              try self.finalInputsHolder(source) === inputsHolder else {
                            throw DayComposerStabilizationError.staleEvidence
                        }
                        try inputsHolder.verify(inputsReceipt)
                    }, verifyUnchanged: { [weak self, weak holder, weak inputsHolder] in
                        guard let self, let holder, let inputsHolder else {
                            throw DayComposerStabilizationError.staleEvidence
                        }
                        try self.validateContext()
                        guard self.registryGeneration(for: source) == generation,
                              self.dependencies.expected(source) == expected,
                              self.finalInputsGenerations[source, default: 0] == inputsGeneration,
                              try self.commentHolder(source) === holder,
                              try self.finalInputsHolder(source) === inputsHolder,
                              receipts.allSatisfy({ $0.verify() }), self.verifyComment(comment, holder: holder),
                              try self.dependencies.guardValue(source) == guardValue else {
                            throw DayComposerStabilizationError.staleEvidence
                        }
                        _ = try self.coverage(source, expected: expected)
                        try inputsHolder.verify(inputsReceipt)
                    })
            } else { finalEvidence = nil }
            let result = try operation(evidence, finalEvidence)
            do {
                try validateContext()
                try verifyRegistry()
                try verifyInputs()
                guard receipts.allSatisfy({ $0.verify() }), verifyComment(comment, holder: holder),
                      try dependencies.guardValue(source) == guardValue else { throw DayComposerStabilizationError.staleEvidence }
                try verifyInputs()
            } catch { throw DayComposerStabilizationError.staleEvidence }
            return result
        } catch {
            if let failure = error as? DayComposerStabilizationError, failure == .contextRejected { dependencies.rejected() }
            throw error
        }
    }
}
