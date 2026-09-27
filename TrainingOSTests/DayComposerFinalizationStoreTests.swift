import XCTest
import Foundation
#if canImport(TrainingOS)
@testable import TrainingOS
#endif

final class DayComposerFinalizationStoreTests: XCTestCase {
    private var directory: URL!
    private let date = "2026-09-27"
    private let executionID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private let exerciseID = "00000000-0000-4000-8000-000000000002"
    private let instant = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FinalizationTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    private func store() -> DayComposerFinalizationStore {
        DayComposerFinalizationStore(baseDirectory: directory, clock: { self.instant })
    }

    private func identity(program: String = "program-A", execution: UUID? = nil,
                          date: String = "2026-09-27", scheme: String = "3x8",
                          morning: String = "AM", evening: String = "PM") throws -> DayComposerExecutionIdentity {
        let am = try DayComposerPlan(source: .morning, session: morning, schemes: ["Shared": scheme],
            order: ["Shared"], exerciseIDs: ["Shared": exerciseID])
        let pm = try DayComposerPlan(source: .evening, session: evening, schemes: ["Shared": scheme],
            order: ["Shared"], exerciseIDs: ["Shared": exerciseID])
        let snapshot = DayComposerSnapshot(date: date, activeProgramID: program, morning: am, evening: pm,
            morningCompleted: false, eveningCompleted: false)
        return try .init(executionID: execution ?? executionID, context: DayComposerExecutionContext(snapshot: snapshot))
    }

    private func item(_ source: DayComposerSource = .morning, name: String = "Shared", order: Int = 0) -> DayComposerItem {
        .init(id: .init(source: source, name: name, exerciseID: name == "Shared" ? exerciseID : nil),
              name: name, scheme: "3x8", sourceOrder: order, tracking: "reps", unilateral: false)
    }

    private func exerciseBytes(reps: String = "8", notes: String = "private exercise note",
                               source: DayComposerSource = .morning) throws -> Data {
        try WorkoutPayloadBuilder.encode(WorkoutPayloadBuilder.exercise(exercise: "Shared", weight: 50,
            reps: reps, rpe: nil, sets: [], force: true, isSecond: source == .evening, isBonus: false,
            equipmentType: "", painZone: "", notes: notes, date: date))
    }

    private func exercise(_ source: DayComposerSource = .morning, reps: String = "8") throws -> DayComposerExerciseVersion {
        try .init(itemID: item(source).id, date: date, payloadData: exerciseBytes(reps: reps, source: source))
    }

    private func version(_ source: DayComposerSource = .morning, comment: String = "private session comment",
                         reps: String = "8") throws -> DayComposerSourceVersion {
        try .init(source: source, sessionName: source == .morning ? "AM" : "PM", items: [item(source)],
                  exerciseVersions: [exercise(source, reps: reps)], comment: comment)
    }

    private func guardValue(_ source: DayComposerSource = .morning, revision: Int = 0,
                            execution: UUID? = nil) throws -> DayComposerFinalizationGuard {
        try .init(executionID: execution ?? executionID, source: source, revision: revision,
                  integrity: DayComposerFinalizationCoding.hash(Data("inventory-\(revision)".utf8)))
    }

    private func finalBytes(comment: String = "private session comment", rpe: Double = 7,
                            duration: Double? = 30, energy: Int? = 3, date: String = "2026-09-27",
                            source: DayComposerSource = .morning) throws -> Data {
        try WorkoutPayloadBuilder.encode(WorkoutPayloadBuilder.session(exos: [], rpe: rpe, comment: comment,
            durationMin: duration, energyPre: energy, secondSession: source == .evening, bonusSession: false,
            sessionName: source == .morning ? "AM" : "PM", exerciseLogs: [], date: date))
    }

    private func finalVersion() throws -> DayComposerFinalPayloadVersion { try .init(payloadData: finalBytes()) }

    private func seed(_ store: DayComposerFinalizationStore, source: DayComposerSource = .morning) throws {
        let id = try identity()
        try store.recordSourceSnapshot(identity: id, version: version(source), provenanceGuard: guardValue(source))
        try store.recordExerciseIntent(identity: id, version: exercise(source))
    }

    private func seedFinal(_ store: DayComposerFinalizationStore) throws {
        try seed(store)
        try store.recordFinalIntent(identity: identity(), sourceVersion: version(),
            finalPayloadVersion: finalVersion(), provenanceGuard: guardValue())
    }

    private func assertError(_ expected: DayComposerFinalizationError, file: StaticString = #filePath,
                             line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? DayComposerFinalizationError, expected, file: file, line: line)
        }
    }

    private func bytes(_ store: DayComposerFinalizationStore) throws -> Data {
        try Data(contentsOf: store.recordURL(identity: identity()))
    }

    private func replaceJSON(_ store: DayComposerFinalizationStore, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes(store)) as? [String: Any])
        change(&json)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try data.write(to: store.recordURL(identity: identity()), options: .atomic)
        return data
    }

    func testExerciseHashesExactF2ABytesAndDoesNotReencode() throws {
        let id = try identity()
        let original = try exercise()
        XCTAssertEqual(try original.digest, try exercise().digest)
        XCTAssertNotEqual(try original.digest, try exercise(reps: "9").digest)
        let changedNote = try DayComposerExerciseVersion(itemID: item().id, date: date,
            payloadData: exerciseBytes(notes: "different note"))
        XCTAssertNotEqual(try original.digest, try changedNote.digest)
        let spaced = try DayComposerExerciseVersion(itemID: item().id, date: date,
            payloadData: exerciseBytes() + Data(" ".utf8))
        XCTAssertNotEqual(try original.digest, try spaced.digest)
        let result = ExerciseLogResult(name: "Shared", weight: 50, reps: "8", notes: "private exercise note")
        let request = try NeutralExerciseSubmissionRequest(itemIdentity: item().id.exercise, source: .morning,
            date: date, result: result, operationKey: original.operationKey(identity: id))
        XCTAssertEqual(original.payloadDigest, DayComposerFinalizationCoding.hash(request.payloadData))
        var localMetadata = result
        localMetadata.trackingType = "local only"
        localMetadata.scheme = "5x5"
        let changed = try NeutralExerciseSubmissionRequest(itemIdentity: item().id.exercise, source: .morning,
            date: date, result: localMetadata, operationKey: original.operationKey(identity: id))
        XCTAssertEqual(request.payloadData, changed.payloadData)
    }

    func testSourceCanonicalOrderingIncludesStableTieBreakerAndIgnoresDictionaryInsertion() throws {
        let a = item(name: "A", order: 0), b = item(name: "B", order: 0)
        let ea = try DayComposerExerciseVersion(itemID: a.id, date: date, payloadData: exerciseBytes())
        let eb = try DayComposerExerciseVersion(itemID: b.id, date: date, payloadData: exerciseBytes())
        var first: [DayComposerItemID: DayComposerExerciseVersion] = [:]
        first[a.id] = ea; first[b.id] = eb
        var second: [DayComposerItemID: DayComposerExerciseVersion] = [:]
        second[b.id] = eb; second[a.id] = ea
        let v1 = try DayComposerSourceVersion(source: .morning, sessionName: "AM", items: [b, a],
            exerciseVersions: Array(first.values), comment: "")
        let v2 = try DayComposerSourceVersion(source: .morning, sessionName: "AM", items: [a, b],
            exerciseVersions: Array(second.values), comment: "")
        XCTAssertEqual(try v1.digest, try v2.digest)
        XCTAssertEqual(v1.orderedItems.map(\.itemID), [a.id, b.id])
        let reordered = try DayComposerSourceVersion(source: .morning, sessionName: "AM", items: [item(name: "A", order: 1), b],
            exerciseVersions: [ea, eb], comment: "")
        XCTAssertNotEqual(try v1.digest, try reordered.digest)
    }

    func testCommentOnlyEditChangesSourceAndFinalButNotExerciseKey() throws {
        let id = try identity(), a = try version(comment: "A"), b = try version(comment: "B")
        XCTAssertEqual(a.exerciseVersions, b.exerciseVersions)
        XCTAssertNotEqual(try a.digest, try b.digest)
        XCTAssertEqual(try a.exerciseVersions[0].operationKey(identity: id), try b.exerciseVersions[0].operationKey(identity: id))
        let fa = try DayComposerFinalPayloadVersion(payloadData: finalBytes(comment: "A"))
        let fb = try DayComposerFinalPayloadVersion(payloadData: finalBytes(comment: "B"))
        XCTAssertNotEqual(fa, fb)
        XCTAssertNotEqual(try fa.operationKey(identity: id, sourceVersion: a), try fb.operationKey(identity: id, sourceVersion: b))
        XCTAssertNotEqual(try version(comment: "").commentDigest, try version(comment: " ").commentDigest)
        XCTAssertEqual(try version(comment: "").commentDigest, DayComposerFinalizationCoding.hash(Data()))
        XCTAssertNotEqual(try version().digest, try version(reps: "9").digest)
    }

    func testFinalInputsChangeOnlyFinalPayloadVersionAndKey() throws {
        let source = try version(), id = try identity(), original = try finalVersion()
        for data in [try finalBytes(rpe: 8), try finalBytes(duration: 31), try finalBytes(energy: 4),
                     try finalBytes(comment: "edited"), try finalBytes(date: "2026-09-28"), try finalBytes(source: .evening)] {
            let changed = try DayComposerFinalPayloadVersion(payloadData: data)
            XCTAssertNotEqual(original, changed)
            XCTAssertNotEqual(try original.operationKey(identity: id, sourceVersion: source), try changed.operationKey(identity: id, sourceVersion: source))
        }
        XCTAssertEqual(try source.digest, try version().digest)
        XCTAssertEqual(source.exerciseVersions, try version().exerciseVersions)
        XCTAssertEqual(original, try finalVersion())
        let request = try NeutralSourceFinalizationRequest(source: .morning, date: date, sessionName: "AM",
            resultsByIdentity: [:], comment: "private session comment", rpe: 7, durationMin: 30, energyPre: 3,
            operationKey: original.operationKey(identity: id, sourceVersion: source), dependencies: .satisfied)
        XCTAssertEqual(original.payloadDigest, DayComposerFinalizationCoding.hash(request.payloadData))
    }

    func testKeysAndPathsRecreateDeterministicallyAndAllContextFieldsMatter() throws {
        let id = try identity(), exercise = try exercise(), final = try finalVersion(), source = try version()
        let roundTrip = try JSONDecoder().decode(DayComposerExecutionIdentity.self, from: DayComposerFinalizationCoding.encode(id))
        XCTAssertEqual(try id.digest, try roundTrip.digest)
        XCTAssertEqual(try store().recordURL(identity: id), try store().recordURL(identity: roundTrip))
        XCTAssertEqual(try exercise.operationKey(identity: id), try exercise.operationKey(identity: roundTrip))
        XCTAssertEqual(try final.operationKey(identity: id, sourceVersion: source), try final.operationKey(identity: roundTrip, sourceVersion: source))
        for other in [try identity(program: "B"), try identity(execution: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!),
                      try identity(scheme: "4x8"), try identity(evening: "PM changed")] {
            XCTAssertNotEqual(try id.digest, try other.digest)
            XCTAssertNotEqual(try store().recordURL(identity: id), try store().recordURL(identity: other))
            XCTAssertNotEqual(try exercise.operationKey(identity: id), try exercise.operationKey(identity: other))
            XCTAssertNotEqual(try final.operationKey(identity: id, sourceVersion: source), try final.operationKey(identity: other, sourceVersion: source))
        }
        XCTAssertNotEqual(try id.digest, try identity(date: "2026-09-28").digest)
        XCTAssertNotEqual(try id.digest, try identity(morning: "Other").digest)
        let anotherItem = try DayComposerExerciseVersion(itemID: item(name: "Other").id, date: date, payloadData: exerciseBytes())
        XCTAssertNotEqual(try exercise.operationKey(identity: id), try anotherItem.operationKey(identity: id))
        XCTAssertNotEqual(try exercise.operationKey(identity: id), try self.exercise(reps: "9").operationKey(identity: id))
        XCTAssertNotEqual(try final.operationKey(identity: id, sourceVersion: source), try final.operationKey(identity: id, sourceVersion: version(comment: "changed")))
    }

    func testSnapshotReloadAndGuardRecaptureRetainHistory() throws {
        let s = store(), id = try identity(), v1 = try version(), v2 = try version(comment: "B")
        try s.recordSourceSnapshot(identity: id, version: v1, provenanceGuard: guardValue())
        let original = try XCTUnwrap(store().load(identity: id))
        XCTAssertEqual(original.sourceSnapshots[0].sourceVersion, v1)
        try s.recordSourceSnapshot(identity: id, version: v2, provenanceGuard: guardValue(revision: 1))
        try s.recordSourceSnapshot(identity: id, version: v1, provenanceGuard: guardValue(revision: 2))
        let restored = try XCTUnwrap(store().load(identity: id))
        XCTAssertEqual(restored.sourceSnapshots.count, 3)
        XCTAssertEqual(restored.sourceSnapshots[0], original.sourceSnapshots[0])
        XCTAssertEqual(restored.sourceSnapshots[0].relation(to: restored.sourceSnapshots[1]), .stale)
        XCTAssertEqual(restored.sourceSnapshots[0].relation(to: restored.sourceSnapshots[2]), .revalidationRequired)
        XCTAssertEqual(restored.sourceSnapshots[0].relation(to: restored.sourceSnapshots[0]), .current)
        XCTAssertEqual(restored.sourceSnapshots[0].relation(to: nil), .unknown)
        let other = try DayComposerSourceSnapshotRecord(identity: identity(program: "B"), sourceVersion: v1,
            provenanceGuard: guardValue(), createdAt: instant)
        XCTAssertEqual(restored.sourceSnapshots[0].relation(to: other), .contextMismatch)
    }

    func testExerciseIntentMarkerAndApplicationPersistAsSeparateBoundaries() throws {
        let s = store(), id = try identity(), e = try exercise(), key = try e.operationKey(identity: id)
        XCTAssertNil(try s.load(identity: id))
        try s.recordExerciseIntent(identity: id, version: e)
        XCTAssertEqual(try store().load(identity: id)?.exerciseIntents[0].submissionPhase, .intentRecorded)
        XCTAssertEqual(try store().load(identity: id)?.exerciseIntents[0].applicationState, .unknown)
        assertError(.invalidRecord) { try s.recordExerciseApplication(identity: id, version: e, state: .confirmed) }
        try s.markSubmissionMayHaveStarted(identity: id, operationKey: key)
        XCTAssertEqual(try store().load(identity: id)?.exerciseIntents[0].submissionPhase, .submissionMayHaveStarted)
        XCTAssertNil(try store().exerciseEvidence(identity: id, version: e)) // online response lost before recording
        try s.recordExerciseApplication(identity: id, version: e, state: .confirmed)
        XCTAssertEqual(try store().exerciseEvidence(identity: id, version: e), .confirmed)
        XCTAssertNil(try store().exerciseEvidence(identity: id, version: exercise(reps: "9")))
    }

    func testFinalIntentMarkerAndExactApplicationPersist() throws {
        let s = store(), id = try identity(), v = try version(), f = try finalVersion()
        try seedFinal(s)
        XCTAssertEqual(try store().load(identity: id)?.finalIntents[0].submissionPhase, .intentRecorded)
        XCTAssertEqual(try store().finalEvidence(identity: id, sourceVersion: v, finalPayloadVersion: f), .unknown)
        assertError(.invalidRecord) { try s.recordFinalApplication(identity: id, sourceVersion: v, finalPayloadVersion: f, state: .confirmed) }
        try s.markSubmissionMayHaveStarted(identity: id, operationKey: f.operationKey(identity: id, sourceVersion: v))
        XCTAssertEqual(try store().load(identity: id)?.finalIntents[0].submissionPhase, .submissionMayHaveStarted)
        XCTAssertEqual(try store().finalEvidence(identity: id, sourceVersion: v, finalPayloadVersion: f), .unknown)
        try s.recordFinalApplication(identity: id, sourceVersion: v, finalPayloadVersion: f, state: .confirmed)
        XCTAssertEqual(try store().finalEvidence(identity: id, sourceVersion: v, finalPayloadVersion: f), .confirmed)
        let f2 = try DayComposerFinalPayloadVersion(payloadData: finalBytes(rpe: 8))
        XCTAssertNil(try s.finalEvidence(identity: id, sourceVersion: v, finalPayloadVersion: f2))
        XCTAssertNil(try s.finalEvidence(identity: id, sourceVersion: version(comment: "B"), finalPayloadVersion: f))
    }

    func testObservationsAreIndependentIdempotentFactsNotApplicationEvidence() throws {
        let s = store(), id = try identity()
        for result in [DayComposerCompletionObservationRecord.Result.observed, .unconfirmed, .lookupFailure, .unsupportedDate] {
            let observation = try DayComposerCompletionObservationRecord(source: .morning, date: date,
                result: result, observedAt: instant, sourceVersion: version())
            try s.recordCompletionObservation(identity: id, observation: observation)
            try s.recordCompletionObservation(identity: id, observation: observation)
        }
        let reobserved = try DayComposerCompletionObservationRecord(source: .morning, date: date,
            result: .observed, observedAt: instant.addingTimeInterval(1))
        try s.recordCompletionObservation(identity: id, observation: reobserved)
        let record = try XCTUnwrap(store().load(identity: id))
        XCTAssertEqual(record.completionObservations.count, 5)
        XCTAssertTrue(record.exerciseIntents.isEmpty)
        XCTAssertTrue(record.finalIntents.isEmpty)
        XCTAssertNil(try s.exerciseEvidence(identity: id, version: exercise()))
    }

    func testCommentV2AndABAExposeHistoricalEvidenceWithoutCertifyingNewFinal() throws {
        let s = store(), id = try identity(), e1 = try exercise(), e2 = try exercise(reps: "9")
        try seedFinal(s)
        try s.markSubmissionMayHaveStarted(identity: id, operationKey: e1.operationKey(identity: id))
        try s.recordExerciseApplication(identity: id, version: e1, state: .confirmed)
        let f1 = try finalVersion(), v1 = try version()
        try s.markSubmissionMayHaveStarted(identity: id, operationKey: f1.operationKey(identity: id, sourceVersion: v1))
        try s.recordFinalApplication(identity: id, sourceVersion: v1, finalPayloadVersion: f1, state: .confirmed)
        let commentV2 = try version(comment: "B")
        try s.recordSourceSnapshot(identity: id, version: commentV2, provenanceGuard: guardValue(revision: 1))
        XCTAssertEqual(try s.exerciseEvidence(identity: id, version: commentV2.exerciseVersions[0]), .confirmed)
        XCTAssertNil(try s.finalEvidence(identity: id, sourceVersion: commentV2, finalPayloadVersion: f1))
        try s.recordExerciseIntent(identity: id, version: e2)
        try s.recordSourceSnapshot(identity: id, version: version(reps: "9"), provenanceGuard: guardValue(revision: 2))
        try s.recordSourceSnapshot(identity: id, version: v1, provenanceGuard: guardValue(revision: 3))
        let record = try XCTUnwrap(store().load(identity: id))
        XCTAssertEqual(record.exerciseIntents.count, 2)
        XCTAssertEqual(record.sourceSnapshots.count, 4)
        XCTAssertEqual(record.sourceSnapshots[0].relation(to: record.sourceSnapshots[3]), .revalidationRequired)
        XCTAssertEqual(try s.exerciseEvidence(identity: id, version: e1), .confirmed)
        XCTAssertEqual(try s.finalEvidence(identity: id, sourceVersion: v1, finalPayloadVersion: f1), .confirmed) // historical, not permission
        assertError(.conflict) {
            try s.recordFinalIntent(identity: id, sourceVersion: v1, finalPayloadVersion: f1, provenanceGuard: guardValue(revision: 3))
        }
    }

    func testAMPMIdenticalUUIDNameAndBytesRemainIsolatedAcrossTwoStores() throws {
        let s1 = store(), s2 = store(), id = try identity(), data = try exerciseBytes()
        let am = try DayComposerExerciseVersion(itemID: item(.morning).id, date: date, payloadData: data)
        let pm = try DayComposerExerciseVersion(itemID: item(.evening).id, date: date, payloadData: data)
        XCTAssertNotEqual(try am.digest, try pm.digest)
        XCTAssertNotEqual(try am.operationKey(identity: id), try pm.operationKey(identity: id))
        try s1.recordExerciseIntent(identity: id, version: am)
        _ = try s1.load(identity: id) // a caller holding an old snapshot cannot overwrite PM
        try s2.recordExerciseIntent(identity: id, version: pm)
        try s1.markSubmissionMayHaveStarted(identity: id, operationKey: am.operationKey(identity: id))
        try s1.recordExerciseApplication(identity: id, version: am, state: .confirmed)
        let record = try XCTUnwrap(store().load(identity: id))
        XCTAssertEqual(record.exerciseIntents.count, 2)
        XCTAssertEqual(try s2.exerciseEvidence(identity: id, version: am), .confirmed)
        XCTAssertNil(try s2.exerciseEvidence(identity: id, version: pm))
        XCTAssertEqual(record.exerciseIntents.first { $0.exerciseVersion == pm }?.submissionPhase, .intentRecorded)
        try seed(s1, source: .morning)
        // Use the real PM bytes for its source snapshot, separate from collision fixture above.
        try seed(s2, source: .evening)
        XCTAssertEqual(try store().load(identity: id)?.sourceSnapshots.count, 2)
        XCTAssertEqual(try s1.candidateRecords(date: date, source: .morning).count, 1)
        XCTAssertEqual(try s1.candidateRecords(date: date, source: .evening).count, 1)
    }

    func testExecutionIsolationAndCandidateScanIncludesOldPrograms() throws {
        let s = store(), a = try identity(), b = try identity(program: "new-program"), e = try exercise()
        try s.recordExerciseIntent(identity: a, version: e)
        try s.markSubmissionMayHaveStarted(identity: a, operationKey: e.operationKey(identity: a))
        try s.recordExerciseApplication(identity: a, version: e, state: .confirmed)
        XCTAssertNil(try s.load(identity: b))
        XCTAssertNil(try s.exerciseEvidence(identity: b, version: e))
        try s.recordExerciseIntent(identity: b, version: e)
        XCTAssertNil(try s.exerciseEvidence(identity: b, version: e))
        let records = try s.candidateRecords(date: date, source: .morning)
        XCTAssertEqual(Set(records.map(\.executionIdentity)), [a, b])
        XCTAssertEqual(try s.candidateRecords(date: date, source: .evening).count, 0)
        XCTAssertEqual(try s.candidateRecords(date: "2026-09-28", source: .morning).count, 0)
    }

    func testSameSessionNameAndFinalBytesStillProduceIndependentAMPMFinalFacts() throws {
        let a = store(), b = store(), id = try identity(morning: "Shared session", evening: "Shared session")
        let final = try finalVersion()
        var versions: [DayComposerSourceVersion] = []
        for source in [DayComposerSource.morning, .evening] {
            let e = try DayComposerExerciseVersion(itemID: item(source).id, date: date, payloadData: exerciseBytes())
            let v = try DayComposerSourceVersion(source: source, sessionName: "Shared session", items: [item(source)],
                exerciseVersions: [e], comment: "same")
            versions.append(v)
            let s = source == .morning ? a : b
            try s.recordSourceSnapshot(identity: id, version: v, provenanceGuard: guardValue(source))
            try s.recordExerciseIntent(identity: id, version: e)
            try s.recordFinalIntent(identity: id, sourceVersion: v, finalPayloadVersion: final, provenanceGuard: guardValue(source))
        }
        let amKey = try final.operationKey(identity: id, sourceVersion: versions[0])
        let pmKey = try final.operationKey(identity: id, sourceVersion: versions[1])
        XCTAssertNotEqual(amKey, pmKey)
        XCTAssertNotEqual(try versions[0].digest, try versions[1].digest)
        try a.markSubmissionMayHaveStarted(identity: id, operationKey: amKey)
        try a.recordFinalApplication(identity: id, sourceVersion: versions[0], finalPayloadVersion: final, state: .confirmed)
        XCTAssertEqual(try b.load(identity: id)?.finalIntents.count, 2)
        XCTAssertEqual(try b.finalEvidence(identity: id, sourceVersion: versions[1], finalPayloadVersion: final), .unknown)
        XCTAssertEqual(try b.load(identity: id)?.finalIntents.last?.submissionPhase, .intentRecorded)
    }

    func testSameProgramDifferentExecutionCannotAdoptHistoricalEvidence() throws {
        let s = store(), a = try identity()
        let b = try identity(execution: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!)
        let e = try exercise()
        try s.recordExerciseIntent(identity: a, version: e)
        try s.markSubmissionMayHaveStarted(identity: a, operationKey: e.operationKey(identity: a))
        try s.recordExerciseApplication(identity: a, version: e, state: .confirmed)
        try s.recordExerciseIntent(identity: b, version: e)
        XCTAssertNil(try s.exerciseEvidence(identity: b, version: e))
        XCTAssertEqual(try s.candidateRecords(date: date, source: .morning).count, 2)
    }

    func testEveryIdempotentWritePreservesBytesTimestampsAndPhase() throws {
        let s = store(), id = try identity(), e = try exercise(), v = try version(), f = try finalVersion()
        try seedFinal(s)
        let observation = try DayComposerCompletionObservationRecord(source: .morning, date: date, result: .observed, observedAt: instant)
        try s.recordCompletionObservation(identity: id, observation: observation)
        for key in [try e.operationKey(identity: id), try f.operationKey(identity: id, sourceVersion: v)] {
            try s.markSubmissionMayHaveStarted(identity: id, operationKey: key)
        }
        try s.recordExerciseApplication(identity: id, version: e, state: .confirmed)
        try s.recordFinalApplication(identity: id, sourceVersion: v, finalPayloadVersion: f, state: .confirmed)
        let before = try bytes(s)
        let later = DayComposerFinalizationStore(baseDirectory: directory, clock: { self.instant.addingTimeInterval(999) },
            writeRecord: { _, _ in XCTFail("An exact repeat must not write") })
        try later.recordSourceSnapshot(identity: id, version: v, provenanceGuard: guardValue())
        try later.recordExerciseIntent(identity: id, version: e)
        try later.recordFinalIntent(identity: id, sourceVersion: v, finalPayloadVersion: f, provenanceGuard: guardValue())
        try later.recordCompletionObservation(identity: id, observation: observation)
        try later.markSubmissionMayHaveStarted(identity: id, operationKey: e.operationKey(identity: id))
        try later.markSubmissionMayHaveStarted(identity: id, operationKey: f.operationKey(identity: id, sourceVersion: v))
        try later.recordExerciseApplication(identity: id, version: e, state: .confirmed)
        try later.recordFinalApplication(identity: id, sourceVersion: v, finalPayloadVersion: f, state: .confirmed)
        XCTAssertEqual(try bytes(s), before)
        for state in [DayComposerApplicationState.failure, .invalidResponse] {
            assertError(.conflict) { try s.recordExerciseApplication(identity: id, version: e, state: state) }
            assertError(.conflict) { try s.recordFinalApplication(identity: id, sourceVersion: v, finalPayloadVersion: f, state: state) }
        }
        XCTAssertEqual(try bytes(s), before)
    }

    func testFailureAndInvalidResponseAreDurableAndCannotContradictEachOther() throws {
        let s = store(), id = try identity(), am = try exercise(), pm = try exercise(.evening)
        try seedFinal(s)
        try s.recordExerciseIntent(identity: id, version: pm)
        for e in [am, pm] { try s.markSubmissionMayHaveStarted(identity: id, operationKey: e.operationKey(identity: id)) }
        try s.recordExerciseApplication(identity: id, version: am, state: .failure)
        try s.recordExerciseApplication(identity: id, version: pm, state: .invalidResponse)
        XCTAssertEqual(try store().exerciseEvidence(identity: id, version: am), .failure)
        XCTAssertEqual(try store().exerciseEvidence(identity: id, version: pm), .invalidResponse)
        assertError(.conflict) { try s.recordExerciseApplication(identity: id, version: am, state: .invalidResponse) }
        let f = try finalVersion(), v = try version()
        try s.markSubmissionMayHaveStarted(identity: id, operationKey: f.operationKey(identity: id, sourceVersion: v))
        try s.recordFinalApplication(identity: id, sourceVersion: v, finalPayloadVersion: f, state: .invalidResponse)
        XCTAssertEqual(try store().finalEvidence(identity: id, sourceVersion: v, finalPayloadVersion: f), .invalidResponse)
        assertError(.conflict) { try s.recordFinalApplication(identity: id, sourceVersion: v, finalPayloadVersion: f, state: .failure) }
    }

    func testWriteFailurePreservesOldFileAndDoesNotExposeNewIntentOrMarker() throws {
        let s = store(), id = try identity()
        try seed(s)
        let before = try bytes(s)
        let failing = DayComposerFinalizationStore(baseDirectory: directory, writeRecord: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        assertError(.writeFailed) { try failing.recordExerciseIntent(identity: id, version: exercise(.evening)) }
        assertError(.writeFailed) { try failing.markSubmissionMayHaveStarted(identity: id, operationKey: exercise().operationKey(identity: id)) }
        XCTAssertEqual(try bytes(s), before)
        XCTAssertEqual(try store().load(identity: id)?.exerciseIntents.count, 1)
        XCTAssertEqual(try store().load(identity: id)?.exerciseIntents[0].submissionPhase, .intentRecorded)
    }

    func testMalformedJSONRefusesLoadWriteAndScanWithoutReplacingBytes() throws {
        let s = store(), id = try identity(), corrupt = Data("{ broken JSON".utf8)
        try corrupt.write(to: s.recordURL(identity: id))
        assertError(.corrupt) { _ = try s.load(identity: id) }
        assertError(.corrupt) { try s.recordExerciseIntent(identity: id, version: exercise()) }
        assertError(.corrupt) { _ = try s.candidateRecords(date: date, source: .morning) }
        XCTAssertEqual(try bytes(s), corrupt)
    }

    func testUnknownSchemaIsRejectedBeforeFullDecodeAndNeverOverwritten() throws {
        let s = store(), id = try identity(), future = Data("{\"schemaVersion\":2}".utf8)
        try future.write(to: s.recordURL(identity: id))
        assertError(.unsupportedVersion) { _ = try s.load(identity: id) }
        assertError(.unsupportedVersion) { try s.recordExerciseIntent(identity: id, version: exercise()) }
        assertError(.unsupportedVersion) { _ = try s.candidateRecords(date: date, source: .morning) }
        XCTAssertEqual(try bytes(s), future)
    }

    func testValidRecordInWrongContextPathFailsLoadUpdateAndScan() throws {
        let s = store(), a = try identity(), b = try identity(program: "B")
        try seed(s)
        let original = try bytes(s)
        try original.write(to: s.recordURL(identity: b))
        assertError(.contextMismatch) { _ = try s.load(identity: b) }
        assertError(.contextMismatch) { try s.recordExerciseIntent(identity: b, version: exercise()) }
        assertError(.contextMismatch) { _ = try s.candidateRecords(date: date, source: .morning) }
        XCTAssertEqual(try Data(contentsOf: s.recordURL(identity: b)), original)
        XCTAssertEqual(try s.load(identity: a)?.executionIdentity, a)
        XCTAssertEqual(try bytes(s), original)
    }

    func testInvalidReferencesFromDecodedFileBlockFurtherWrites() throws {
        let s = store(), id = try identity()
        try seedFinal(s)
        let malformed = try replaceJSON(s) { $0["exerciseIntents"] = [] }
        assertError(.invalidRecord) { _ = try s.load(identity: id) }
        assertError(.invalidRecord) { try s.recordExerciseIntent(identity: id, version: exercise()) }
        assertError(.invalidRecord) { _ = try s.candidateRecords(date: date, source: .morning) }
        XCTAssertEqual(try bytes(s), malformed)
    }

    func testInvalidSnapshotFinalDependencyAndDigestAreNotSilentlyRepaired() throws {
        let s = store(), id = try identity()
        try seedFinal(s)
        let original = try bytes(s)
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["sourceSnapshots"] = [] },
            { json in
                var intents = json["finalIntents"] as! [[String: Any]]
                intents[0]["dependencies"] = []
                json["finalIntents"] = intents
            },
            { json in
                var snapshots = json["sourceSnapshots"] as! [[String: Any]]
                var source = snapshots[0]["sourceVersion"] as! [String: Any]
                source["commentDigest"] = ""
                snapshots[0]["sourceVersion"] = source
                json["sourceSnapshots"] = snapshots
            },
            { json in
                var intents = json["exerciseIntents"] as! [[String: Any]]
                intents[0]["applicationEvidence"] = "confirmed" // no submission marker
                json["exerciseIntents"] = intents
            },
            { json in
                let intents = json["exerciseIntents"] as! [[String: Any]]
                json["exerciseIntents"] = intents + intents
            }
        ]
        for change in changes {
            try original.write(to: s.recordURL(identity: id))
            let malformed = try replaceJSON(s, change)
            assertError(.invalidRecord) { _ = try s.load(identity: id) }
            assertError(.invalidRecord) { try s.recordExerciseIntent(identity: id, version: exercise(.evening)) }
            XCTAssertEqual(try bytes(s), malformed)
        }
    }

    func testWrongSourceAndForgedKeyDecodedRecordsAreRejected() throws {
        let s = store(), id = try identity()
        try seed(s)
        let valid = try bytes(s)
        for mutate in [
            { (json: inout [String: Any]) in
                var intents = json["exerciseIntents"] as! [[String: Any]]
                var version = intents[0]["exerciseVersion"] as! [String: Any]
                version["source"] = "evening"
                intents[0]["exerciseVersion"] = version
                json["exerciseIntents"] = intents
            },
            { (json: inout [String: Any]) in
                var intents = json["exerciseIntents"] as! [[String: Any]]
                intents[0]["operationKey"] = ["rawValue": ""]
                json["exerciseIntents"] = intents
            }
        ] {
            try valid.write(to: s.recordURL(identity: id))
            let malformed = try replaceJSON(s, mutate)
            assertError(.invalidRecord) { _ = try s.load(identity: id) }
            assertError(.invalidRecord) { try s.recordExerciseIntent(identity: id, version: exercise(.evening)) }
            XCTAssertEqual(try bytes(s), malformed)
        }
    }

    func testApplicationWithoutIntentAndFinalWithoutDependenciesAreRejected() throws {
        let s = store(), id = try identity()
        assertError(.invalidRecord) { try s.recordExerciseApplication(identity: id, version: exercise(), state: .confirmed) }
        assertError(.invalidRecord) { try s.recordFinalApplication(identity: id, sourceVersion: version(), finalPayloadVersion: finalVersion(), state: .confirmed) }
        assertError(.invalidRecord) { try s.markSubmissionMayHaveStarted(identity: id, operationKey: .init(rawValue: "")) }
        assertError(.invalidRecord) { try s.recordFinalIntent(identity: id, sourceVersion: version(), finalPayloadVersion: finalVersion(), provenanceGuard: guardValue()) }
        XCTAssertNil(try s.load(identity: id))
        try s.recordSourceSnapshot(identity: id, version: version(), provenanceGuard: guardValue())
        let before = try bytes(s)
        assertError(.invalidRecord) { try s.recordFinalIntent(identity: id, sourceVersion: version(), finalPayloadVersion: finalVersion(), provenanceGuard: guardValue()) }
        XCTAssertEqual(try bytes(s), before)
        assertError(.invalidRecord) { try s.recordSourceSnapshot(identity: id, version: version(), provenanceGuard: guardValue(.evening)) }
    }

    func testInvalidBuildersRejectContradictoryReferencesAndInvalidDates() throws {
        assertError(.invalidRecord) { _ = try identity(program: "") }
        assertError(.invalidRecord) { _ = try identity(date: "2026-02-30") }
        assertError(.invalidRecord) { _ = try DayComposerExerciseVersion(itemID: item().id, date: date, payloadData: Data()) }
        assertError(.invalidRecord) { _ = try DayComposerFinalPayloadVersion(payloadData: Data()) }
        assertError(.invalidRecord) { _ = try DayComposerExerciseVersion(itemID: .init(source: .morning, name: "", exerciseID: nil), date: date, payloadData: exerciseBytes()) }
        assertError(.invalidRecord) { _ = try DayComposerFinalizationGuard(executionID: executionID, source: .morning, revision: -1, integrity: "") }
        assertError(.invalidRecord) {
            _ = try DayComposerSourceVersion(source: .morning, sessionName: "AM", items: [item(), item()], exerciseVersions: [exercise()], comment: "")
        }
        assertError(.invalidRecord) {
            _ = try DayComposerSourceVersion(source: .morning, sessionName: "AM", items: [item()], exerciseVersions: [exercise(), exercise(reps: "9")], comment: "")
        }
        assertError(.invalidRecord) {
            _ = try DayComposerSourceVersion(source: .morning, sessionName: "AM", items: [item()], exerciseVersions: [exercise(.evening)], comment: "")
        }
        assertError(.invalidRecord) { _ = try exercise().operationKey(identity: identity(date: "2026-09-28")) }
    }

    func testScanAbsentDirectoryIgnoresUnrelatedFilesButRejectsNamespaceCorruption() throws {
        let absent = DayComposerFinalizationStore(baseDirectory: directory.appendingPathComponent("absent"))
        XCTAssertTrue(try absent.candidateRecords(date: date, source: .morning).isEmpty)
        let s = store()
        try seed(s)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("unrelated.txt"))
        XCTAssertEqual(try s.candidateRecords(date: date, source: .morning).count, 1)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("day_composer_finalization.bad.json"))
        assertError(.corrupt) { _ = try s.candidateRecords(date: date, source: .morning) }
    }

    func testScanRejectsNamespaceSymlinkRatherThanFollowingIt() throws {
        let s = store()
        try seed(s)
        let link = directory.appendingPathComponent("day_composer_finalization.link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: s.recordURL(identity: identity()))
        assertError(.invalidRecord) { _ = try s.candidateRecords(date: date, source: .morning) }
    }

    func testUnreadableDirectoryIsNotAnEmptyCandidateList() throws {
        let file = directory.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: file)
        let s = DayComposerFinalizationStore(baseDirectory: file)
        assertError(.storageUnavailable) { _ = try s.candidateRecords(date: date, source: .morning) }
    }

    func testPersistedFactsContainNoRawCommentsPayloadsOrTransportAuthority() throws {
        let s = store()
        try seedFinal(s)
        let text = try XCTUnwrap(String(data: bytes(s), encoding: .utf8))
        for forbidden in ["private session comment", "private exercise note", "payloadData", "pending", "delivered",
                          "discarded", "uncertain", "isCurrent", "isResolved", "isUnresolved", "resolvedAt", "attemptNumber"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
        // No source-file reads here: these tests must also work in an iPhone
        // test host. Production dependency/call absence is checked statically.
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.map(\.lastPathComponent), [try s.recordURL(identity: identity()).lastPathComponent])
    }
}
