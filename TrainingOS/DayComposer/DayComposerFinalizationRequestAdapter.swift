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
            let version = try DayComposerExerciseVersion(itemID: item.id, date: local.identity.date, payloadData: bytes)
            guard snapshot.exerciseVersions.contains(version),
                  local.itemFacts.first(where: { $0.itemID == item.id })?.local.payload == bytes,
                  let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let weight = json["weight"] as? NSNumber, let reps = json["reps"] as? String,
                  projection[item.name] == nil else { throw DayComposerFinalizationError.invalidRecord }
            requests.append(try .init(itemIdentity: item.name, source: local.source, date: local.identity.date,
                payloadData: bytes, operationKey: version.operationKey(identity: local.identity)))
            projection[item.name] = .init(name: item.name, weight: weight.doubleValue, reps: reps)
        }
        let expected = try DayComposerSourceVersion(source: local.source, sessionName: local.identity.session(for: local.source),
            items: items, exerciseVersions: snapshot.exerciseVersions, comment: local.comment)
        guard expected == snapshot.sourceVersion, requests.count == snapshot.exerciseVersions.count,
              requests.count == snapshot.payloads.count else { throw DayComposerFinalizationError.invalidRecord }
        let summary = WorkoutPayloadBuilder.summaries(projection)
        let exos = projection.keys.sorted().compactMap { name -> String? in
            guard let value = projection[name] else { return nil }
            if items.contains(where: { $0.name == name && $0.tracking == "mobility" }) {
                return "\(name) · mobilité réalisée"
            }
            return "\(value.name) \(value.weight)lbs \(value.reps)"
        }
        let bytes = try WorkoutPayloadBuilder.encode(WorkoutPayloadBuilder.session(
            exos: exos, rpe: capture.finalInputs.values.rpe, comment: local.comment,
            durationMin: nil, energyPre: nil, secondSession: local.source == .evening,
            bonusSession: false, sessionName: local.identity.session(for: local.source),
            exerciseLogs: summary.exerciseLogs, date: local.identity.date))
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
