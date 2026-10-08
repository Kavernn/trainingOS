import Foundation

enum DayComposerFinalInputsError: Error, Equatable {
    case missingRequiredRPE, invalidRPE, unsupportedOptionalInput
    case corruptPersistence, unsupportedSchema, contextMismatch, sourceMismatch
    case staleInputs, durabilityFailure, revisionOverflow, invalidCaptureBinding
    case unsafePath
}

struct DayComposerFinalInputs: Codable, Equatable {
    let rpe: Double
    let durationMin: Double?
    let energyPre: Int?

    init(rpe: Double, durationMin: Double? = nil, energyPre: Int? = nil) throws {
        self.rpe = rpe
        self.durationMin = durationMin
        self.energyPre = energyPre
        try validate()
    }

    func validate() throws {
        // Zero is the local neutral checklist marker; never sent as a performance RPE.
        guard rpe.isFinite, [0.0, 6, 7, 8, 9, 10].contains(rpe) else {
            throw DayComposerFinalInputsError.invalidRPE
        }
        // No producer for either optional exists in p1, including non-finite durations.
        guard durationMin == nil, energyPre == nil else {
            throw DayComposerFinalInputsError.unsupportedOptionalInput
        }
    }

    private enum CodingKeys: String, CodingKey { case rpe, durationMin, energyPre }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rpe = try container.decodeIfPresent(Double.self, forKey: .rpe) else {
            throw DayComposerFinalInputsError.missingRequiredRPE
        }
        try self.init(rpe: rpe,
            durationMin: container.decodeIfPresent(Double.self, forKey: .durationMin),
            energyPre: container.decodeIfPresent(Int.self, forKey: .energyPre))
    }

    func canonicalData() throws -> Data {
        try validate()
        struct Content: Encodable {
            let contentVersion: Int
            let rpe: Double
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
