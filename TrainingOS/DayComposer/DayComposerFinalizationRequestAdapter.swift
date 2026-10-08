import Foundation

/// Pure immutable reconstruction; neither a readiness decision nor network permission.
struct DayComposerFinalizationRequestAdapter {
    let snapshot: DayComposerFinalizationSnapshot
    let exercises: [NeutralExerciseSubmissionRequest]
    let finalData: Data
    let finalVersion: DayComposerFinalPayloadVersion
    let finalKey: OfflineOperationKey

    init(capture: DayComposerFinalSourceCapture, snapshot: DayComposerFinalizationSnapshot) throws {
        let local = capture.local
        guard snapshot.identity == local.identity, snapshot.source == local.source,
              snapshot.provenanceGuard == local.guardValue,
              capture.finalInputs.executionIdentity == local.identity,
              capture.finalInputs.source == local.source else {
            throw DayComposerFinalInputsError.contextMismatch
        }
        try capture.finalInputs.values.validate()
        let items = (local.source == .morning ? local.canonicalPlan.morning : local.canonicalPlan.evening)
            .units.flatMap(\.items).sorted {
                $0.sourceOrder != $1.sourceOrder ? $0.sourceOrder < $1.sourceOrder
                    : DayComposerFinalizationCoding.precedes($0.id, $1.id)
            }
        // Reading scalar summary fields never decodes/re-encodes exercise sets.
        var projection: [String: WorkoutPayloadBuilder.Summary] = [:]
        var requests: [NeutralExerciseSubmissionRequest] = []
        for item in items {
            guard let bytes = snapshot.payloads[item.id] else { continue }
            let version = try DayComposerExerciseVersion(itemID: item.id, date: local.identity.date, payloadData: bytes, source: local.source)
            guard snapshot.exerciseVersions.contains(version),
                  local.itemFacts.first(where: { $0.itemID == item.id })?.local.payload == bytes,
                  let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let weight = json["weight"] as? NSNumber, let reps = json["reps"] as? String,
                  projection[item.storageKey] == nil else { throw DayComposerFinalizationError.invalidRecord }
            requests.append(try .init(itemIdentity: item.storageKey, source: local.source, date: local.identity.date,
                payloadData: bytes, operationKey: version.operationKey(identity: local.identity)))
            projection[item.storageKey] = .init(name: item.name, weight: weight.doubleValue, reps: reps, occurrenceKey: item.occurrenceKey)
        }
        let expected = try DayComposerSourceVersion(source: local.source, sessionName: local.identity.session(for: local.source),
            items: items, exerciseVersions: snapshot.exerciseVersions, comment: local.comment)
        guard expected == snapshot.sourceVersion, requests.count == snapshot.exerciseVersions.count,
              requests.count == snapshot.payloads.count else { throw DayComposerFinalizationError.invalidRecord }
        let tracked = projection.filter { key, _ in
            items.contains { $0.storageKey == key && WorkoutCompletion.tracks($0.tracking) }
        }
        let tracksPerformance = items.contains { WorkoutCompletion.tracks($0.tracking) }
        guard !tracksPerformance || capture.finalInputs.values.rpe != 0 else {
            throw DayComposerFinalInputsError.invalidRPE
        }
        let summary = WorkoutPayloadBuilder.summaries(tracked)
        let exos = summary.exos
        let bytes = try WorkoutPayloadBuilder.encode(WorkoutPayloadBuilder.session(
            exos: exos, rpe: capture.finalInputs.values.rpe, comment: local.comment,
            durationMin: nil, energyPre: nil, secondSession: local.source == .evening,
            bonusSession: false, sessionName: local.identity.session(for: local.source),
            exerciseLogs: summary.exerciseLogs, date: local.identity.date, tracksPerformance: tracksPerformance))
        self.snapshot = snapshot
        exercises = requests
        finalData = bytes
        finalVersion = try .init(payloadData: bytes)
        finalKey = try finalVersion.operationKey(identity: local.identity, sourceVersion: snapshot.sourceVersion)
    }

    func finalRequest(dependencies: NeutralSourceDependencies) throws -> NeutralSourceFinalizationRequest {
        try .init(source: snapshot.source, date: snapshot.identity.date,
            sessionName: snapshot.identity.session(for: snapshot.source), payloadData: finalData,
            operationKey: finalKey, dependencies: dependencies)
    }
}
