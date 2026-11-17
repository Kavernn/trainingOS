import Foundation

enum DayComposerFinalInputsError: Error, Equatable {
    case missingRequiredRPE, invalidRPE, unsupportedOptionalInput
    case corruptPersistence, unsupportedSchema, contextMismatch, sourceMismatch
    case staleInputs, durabilityFailure, revisionOverflow, invalidCaptureBinding
    case unsafePath
}

struct DayComposerFinalInputs: Codable, Equatable {
    /// nil = aucun RPE choisi (jamais imposé, 5c). 0 = marqueur hérité « checklist », lu seulement.
    let rpe: Double?
    let durationMin: Double?
    let energyPre: Int?

    init(rpe: Double?, durationMin: Double? = nil, energyPre: Int? = nil) throws {
        self.rpe = rpe
        self.durationMin = durationMin
        self.energyPre = energyPre
        try validate()
    }

    func validate() throws {
        // nil = non choisi ; 0 = marqueur hérité (états persistés avant 5c, plus jamais écrit) ;
        // sinon demi-point 6…10 (une proposition 7.5 doit pouvoir être confirmée).
        if let rpe {
            guard rpe.isFinite, rpe == 0 || ((6...10).contains(rpe) && (rpe * 2).rounded() == rpe * 2) else {
                throw DayComposerFinalInputsError.invalidRPE
            }
        }
        // Durée réelle (Ma journée) : nil ou minutes finies dans 1...maxMinutes (borne backend).
        if let durationMin {
            guard durationMin.isFinite, durationMin >= 1,
                  durationMin <= Double(DayComposerActualDuration.maxMinutes) else {
                throw DayComposerFinalInputsError.unsupportedOptionalInput
            }
        }
        // No producer for energyPre exists.
        guard energyPre == nil else {
            throw DayComposerFinalInputsError.unsupportedOptionalInput
        }
    }

    private enum CodingKeys: String, CodingKey { case rpe, durationMin, energyPre }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Clé absente = aucun RPE choisi (5c) ; un ancien état avec rpe est relu tel quel.
        try self.init(rpe: container.decodeIfPresent(Double.self, forKey: .rpe),
            durationMin: container.decodeIfPresent(Double.self, forKey: .durationMin),
            energyPre: container.decodeIfPresent(Int.self, forKey: .energyPre))
    }

    func canonicalData() throws -> Data {
        try validate()
        struct Content: Encodable {
            let contentVersion: Int
            let rpe: Double?        // nil omis : octets d'un état avec rpe identiques à avant 5c
            let durationMin: Double?
            let energyPre: Int?
        }
        return try DayComposerFinalizationCoding.encode(Content(contentVersion: 1, rpe: rpe,
            durationMin: durationMin, energyPre: energyPre))
    }
}

struct DayComposerFinalInputsVersion: Codable, Equatable {
    let contentVersion: Int
    let digest: String

    init(values: DayComposerFinalInputs) throws {
        contentVersion = 1
        digest = DayComposerFinalizationCoding.hash(try values.canonicalData())
    }
}

/// Reference only: constructing this value neither constructs nor persists a snapshot.
struct DayComposerFinalInputsSnapshotReference: Codable, Equatable {
    let executionIdentity: DayComposerExecutionIdentity
    let source: DayComposerSource
    let sourceVersion: DayComposerSourceVersion
    let provenanceGuard: DayComposerFinalizationGuard

    init(executionIdentity: DayComposerExecutionIdentity, source: DayComposerSource,
         sourceVersion: DayComposerSourceVersion, provenanceGuard: DayComposerFinalizationGuard) throws {
        self.executionIdentity = executionIdentity
        self.source = source
        self.sourceVersion = sourceVersion
        self.provenanceGuard = provenanceGuard
        try validate()
    }

    func validate() throws {
        guard sourceVersion.source == source, provenanceGuard.source == source else {
            throw DayComposerFinalInputsError.sourceMismatch
        }
        guard provenanceGuard.executionID == executionIdentity.executionID else {
            throw DayComposerFinalInputsError.contextMismatch
        }
        do {
            try executionIdentity.validate()
            try sourceVersion.validate(identity: executionIdentity)
            try provenanceGuard.validate(identity: executionIdentity, source: source)
        } catch { throw DayComposerFinalInputsError.invalidCaptureBinding }
    }
}

/// Association only, NOT readiness, a final intent, an ACK or network authorization.
/// The caller must independently establish snapshot existence and currentness in p2.
struct DayComposerFinalInputsCaptureBinding: Codable, Equatable {
    let snapshotReference: DayComposerFinalInputsSnapshotReference
    let revision: UInt64
    let finalInputsVersion: DayComposerFinalInputsVersion
    let finalPayloadVersion: DayComposerFinalPayloadVersion
}

/// Immutable input-content receipt. A binding replacement does not change this receipt.
struct DayComposerFinalInputsReceipt: Equatable {
    let executionIdentity: DayComposerExecutionIdentity
    let source: DayComposerSource
    let revision: UInt64
    let finalInputsVersion: DayComposerFinalInputsVersion
    let values: DayComposerFinalInputs
}

struct DayComposerFinalInputsRecord: Codable, Equatable {
    let schemaVersion: Int
    let executionIdentity: DayComposerExecutionIdentity
    let source: DayComposerSource
    let revision: UInt64
    let values: DayComposerFinalInputs
    let finalInputsVersion: DayComposerFinalInputsVersion
    var captureBinding: DayComposerFinalInputsCaptureBinding?

    var receipt: DayComposerFinalInputsReceipt {
        .init(executionIdentity: executionIdentity, source: source, revision: revision,
              finalInputsVersion: finalInputsVersion, values: values)
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw DayComposerFinalInputsError.unsupportedSchema }
        do {
            try executionIdentity.validate()
            try values.validate()
            guard revision > 0, finalInputsVersion == (try DayComposerFinalInputsVersion(values: values)) else {
                throw DayComposerFinalInputsError.corruptPersistence
            }
        } catch { throw DayComposerFinalInputsError.corruptPersistence }
        if let binding = captureBinding {
            do {
                try binding.snapshotReference.validate()
                try binding.finalPayloadVersion.validate()
                guard binding.snapshotReference.executionIdentity == executionIdentity,
                      binding.snapshotReference.source == source,
                      binding.revision == revision, binding.finalInputsVersion == finalInputsVersion else {
                    throw DayComposerFinalInputsError.invalidCaptureBinding
                }
            } catch { throw DayComposerFinalInputsError.invalidCaptureBinding }
        }
    }
}
