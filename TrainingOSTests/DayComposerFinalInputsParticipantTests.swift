import Foundation
import XCTest
@testable import TrainingOS

@MainActor
final class DayComposerFinalInputsParticipantTests: XCTestCase {
    private func withStore(_ body: (DayComposerFinalInputsStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(DayComposerFinalInputsStore(baseDirectory: directory), directory)
    }

    private func identity() throws -> DayComposerExecutionIdentity {
        let plan = try DayComposerSnapshot(date: "2091-01-02", activeProgramID: "A",
            morning: DayComposerPlan(source: .morning, session: "AM", schemes: ["A": "3x8"], order: ["A"]),
            evening: DayComposerPlan(source: .evening, session: "PM", schemes: ["A": "3x8"], order: ["A"]),
            morningCompleted: false, eveningCompleted: false)
        return try .init(executionID: UUID(), context: DayComposerExecutionContext(snapshot: plan))
    }

    private func participant(_ store: DayComposerFinalInputsStore, _ id: DayComposerExecutionIdentity,
                             _ source: DayComposerSource = .morning,
                             authorize: @escaping () throws -> Void = {}) -> DayComposerFinalInputsParticipant {
        .init(identity: id, source: source, store: store, authorizeMutation: authorize)
    }

    private func fails(_ error: DayComposerFinalInputsError, _ body: () throws -> Void,
                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? DayComposerFinalInputsError, error, file: file, line: line)
        }
    }

    func testMissingLoadAndPrepareNeverWriteOrDefault() throws {
        try withStore { store, directory in
            let p = participant(store, try identity())
            XCTAssertEqual(p.state, .missing)
            XCTAssertNil(try p.reload())
            fails(.missingRequiredRPE) { _ = try p.prepare() }
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    func testCreateUpdateNoOpAndSourceIsolation() throws {
        try withStore { store, _ in
            let id = try identity()
            var checks = 0
            let am = participant(store, id, authorize: { checks += 1 })
            let pm = participant(store, id, .evening)
            let first = try am.setRPE(7)
            XCTAssertEqual(first.revision, 1)
            XCTAssertEqual(am.state, .loaded(first))
            XCTAssertNil(try store.load(executionIdentity: id, source: .evening))
            let evening = try pm.setRPE(9)
            let pmURL = try store.recordURL(executionIdentity: id, source: .evening)
            let pmBytes = try Data(contentsOf: pmURL)
            let amURL = try store.recordURL(executionIdentity: id, source: .morning)
            let before = try Data(contentsOf: amURL)
            let checkCount = checks
            XCTAssertEqual(try am.setRPE(7), first)
            XCTAssertGreaterThan(checks, checkCount)
            XCTAssertEqual(try Data(contentsOf: amURL), before)
            let next = try am.setRPE(8)
            XCTAssertEqual(next.revision, 2)
            XCTAssertNotEqual(next.finalInputsVersion, first.finalInputsVersion)
            XCTAssertEqual(am.state, .loaded(next))
            XCTAssertEqual(pm.state, .loaded(evening))
            XCTAssertEqual(try Data(contentsOf: pmURL), pmBytes)
            let amBytes = try Data(contentsOf: amURL)
            _ = try pm.setRPE(10)
            XCTAssertEqual(try Data(contentsOf: amURL), amBytes)
        }
    }

    func testStaleCASRequiresExplicitReloadEvenForSameContent() throws {
        try withStore { store, directory in
            let id = try identity(), p = participant(store, id)
            let first = try p.setRPE(7)
            let external = DayComposerFinalInputsStore(baseDirectory: directory)
            let next = try external.save(executionIdentity: id, source: .morning,
                values: DayComposerFinalInputs(rpe: 8), expectedRevision: first.revision)
            for rpe in [7.0, 8, 9] {
                fails(.staleInputs) { _ = try p.setRPE(rpe) }
                XCTAssertEqual(p.state, .loaded(first))
                XCTAssertTrue(try external.verify(next))
            }
            XCTAssertEqual(try p.reload(), next)
            XCTAssertEqual(try p.setRPE(8), next)
        }
    }

    func testMissingProjectionCannotOverwriteExternalCreate() throws {
        try withStore { store, _ in
            let id = try identity(), p = participant(store, id)
            let created = try store.save(executionIdentity: id, source: .morning,
                values: DayComposerFinalInputs(rpe: 9), expectedRevision: nil)
            fails(.staleInputs) { _ = try p.setRPE(7) }
            XCTAssertEqual(p.state, .missing)
            XCTAssertTrue(try store.verify(created))
        }
    }

    func testInvalidRPEPreservesAcceptedProjectionAndBytes() throws {
        try withStore { store, _ in
            let id = try identity(), p = participant(store, id)
            let receipt = try p.setRPE(7)
            let url = try store.recordURL(executionIdentity: id, source: .morning)
            let bytes = try Data(contentsOf: url)
            for value in [6.5, 5, 11, .nan, .infinity] {
                fails(.invalidRPE) { _ = try p.setRPE(value) }
                XCTAssertEqual(p.state, .loaded(receipt))
                XCTAssertEqual(try Data(contentsOf: url), bytes)
            }
        }
    }

    func testFrozenOrRejectedContextPrecedesReadsAndProjectionChanges() throws {
        try withStore { store, _ in
            let id = try identity()
            var refusal: DayComposerStabilizationError?
            let p = participant(store, id, authorize: { if let refusal { throw refusal } })
            let receipt = try p.setRPE(7)
            let url = try store.recordURL(executionIdentity: id, source: .morning)
            // A disk read would now fail as corrupt: the gate must win first.
            try Data("{".utf8).write(to: url)
            for error in [DayComposerStabilizationError.sourceFrozen, .contextRejected] {
                refusal = error
                XCTAssertThrowsError(try p.setRPE(7)) { XCTAssertEqual($0 as? DayComposerStabilizationError, error) }
                XCTAssertEqual(p.state, .loaded(receipt))
            }
            XCTAssertEqual(try Data(contentsOf: url), Data("{".utf8))
        }
    }

    func testCorruptionIsTypedAndNeverRepaired() throws {
        try withStore { store, _ in
            let id = try identity(), p = participant(store, id)
            _ = try p.setRPE(7)
            let url = try store.recordURL(executionIdentity: id, source: .morning)
            try Data("{".utf8).write(to: url)
            fails(.corruptPersistence) { _ = try p.prepare() }
            XCTAssertEqual(p.state, .failed(.corruptPersistence))
            let recreated = participant(store, id)
            XCTAssertEqual(recreated.state, .failed(.corruptPersistence))
            fails(.corruptPersistence) { _ = try recreated.setRPE(8) }
            XCTAssertEqual(try Data(contentsOf: url), Data("{".utf8))
        }
    }

    func testDurabilityFailureDoesNotProjectUnpersistedValue() throws {
        try withStore { store, directory in
            let id = try identity(), first = try participant(store, id).setRPE(7)
            let failing = DayComposerFinalInputsStore(baseDirectory: directory, writeRecord: { _, _ in
                throw DayComposerFinalInputsError.durabilityFailure
            })
            let p = participant(failing, id)
            fails(.durabilityFailure) { _ = try p.setRPE(8) }
            XCTAssertEqual(p.state, .loaded(first))
            XCTAssertTrue(try store.verify(first))
        }
    }

    func testVerifyDetectsExternalABAAndIdentityMismatches() throws {
        try withStore { store, _ in
            let id = try identity(), p = participant(store, id)
            let first = try p.setRPE(7)
            let second = try store.save(executionIdentity: id, source: .morning,
                values: DayComposerFinalInputs(rpe: 8), expectedRevision: first.revision)
            let third = try store.save(executionIdentity: id, source: .morning,
                values: DayComposerFinalInputs(rpe: 7), expectedRevision: second.revision)
            XCTAssertEqual(first.finalInputsVersion, third.finalInputsVersion)
            fails(.staleInputs) { try p.verify(first) }
            XCTAssertEqual(try p.prepare(), third)
            fails(.sourceMismatch) { try participant(store, id, .evening).verify(third) }
            fails(.contextMismatch) { try participant(store, identity()).verify(third) }
        }
    }

    func testRecreationReloadsBothSourcesWithoutWritesOrExtraRevision() throws {
        try withStore { store, directory in
            let id = try identity()
            var am: DayComposerFinalInputsParticipant? = participant(store, id)
            var pm: DayComposerFinalInputsParticipant? = participant(store, id, .evening)
            let a = try XCTUnwrap(am).setRPE(8), b = try XCTUnwrap(pm).setRPE(9)
            weak var oldAM = am
            am = nil; pm = nil
            XCTAssertNil(oldAM)
            let readOnly = DayComposerFinalInputsStore(baseDirectory: directory, writeRecord: { _, _ in XCTFail("Unexpected write") })
            XCTAssertEqual(try participant(readOnly, id).prepare(), a)
            XCTAssertEqual(try participant(readOnly, id, .evening).prepare(), b)
        }
    }

    func testExistingBindingIsPreservedByLoadPrepareNoOpAndClearedByEdit() throws {
        try withStore { store, _ in
            let id = try identity(), p = participant(store, id), receipt = try p.setRPE(7)
            // p1 fixture setup only. The participant/barrier never creates bindings.
            let version = try DayComposerSourceVersion(source: .morning, sessionName: id.session(for: .morning),
                items: [], exerciseVersions: [], comment: "")
            let guardValue = try DayComposerFinalizationGuard(executionID: id.executionID, source: .morning,
                revision: 0, integrity: String(repeating: "a", count: 64))
            let binding = try store.bindCapture(executionIdentity: id, source: .morning, expectedReceipt: receipt,
                snapshotReference: DayComposerFinalInputsSnapshotReference(executionIdentity: id, source: .morning,
                    sourceVersion: version, provenanceGuard: guardValue),
                finalPayloadVersion: DayComposerFinalPayloadVersion(payloadData: Data("fixture".utf8)))
            XCTAssertEqual(try p.reload(), receipt)
            XCTAssertEqual(try p.prepare(), receipt)
            XCTAssertEqual(try p.setRPE(7), receipt)
            XCTAssertTrue(try store.verifyCaptureBinding(binding))
            _ = try p.setRPE(8)
            XCTAssertNil(try store.load(executionIdentity: id, source: .morning)?.captureBinding)
        }
    }
}
