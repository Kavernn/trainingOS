import Foundation
import XCTest
#if canImport(TrainingOS)
@testable import TrainingOS
#endif

final class DayComposerFinalInputsTests: XCTestCase {
    private typealias E = DayComposerFinalInputsError
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
        directory = nil
    }

    private func store() -> DayComposerFinalInputsStore { .init(baseDirectory: directory) }
    private func identity(_ execution: UUID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!) throws -> DayComposerExecutionIdentity {
        let am = try DayComposerPlan(source: .morning, session: "AM", schemes: ["A": "3x8"], order: ["A"])
        let pm = try DayComposerPlan(source: .evening, session: "PM", schemes: ["A": "3x8"], order: ["A"])
        let plan = DayComposerSnapshot(date: "2026-09-27", activeProgramID: "program-A", morning: am,
            evening: pm, morningCompleted: false, eveningCompleted: false)
        return try .init(executionID: execution, context: DayComposerExecutionContext(snapshot: plan))
    }
    private func save(_ rpe: Double = 7, revision: UInt64? = nil,
                      source: DayComposerSource = .morning) throws -> DayComposerFinalInputsReceipt {
        try store().save(executionIdentity: identity(), source: source,
            values: DayComposerFinalInputs(rpe: rpe), expectedRevision: revision)
    }
    private func reference(source: DayComposerSource = .morning, execution: UUID? = nil,
                           comment: String = "", guardRevision: Int = 0) throws -> DayComposerFinalInputsSnapshotReference {
        let id = try execution.map { try identity($0) } ?? identity()
        let version = try DayComposerSourceVersion(source: source, sessionName: id.session(for: source),
            items: [], exerciseVersions: [], comment: comment)
        let guardValue = try DayComposerFinalizationGuard(executionID: id.executionID, source: source,
            revision: guardRevision, integrity: String(repeating: "a", count: 64))
        return try .init(executionIdentity: id, source: source, sourceVersion: version, provenanceGuard: guardValue)
    }
    private func bind(_ receipt: DayComposerFinalInputsReceipt, comment: String = "", final: String = "F1",
                      guardRevision: Int = 0) throws -> DayComposerFinalInputsCaptureBinding {
        try store().bindCapture(executionIdentity: receipt.executionIdentity, source: receipt.source,
            expectedReceipt: receipt, snapshotReference: reference(source: receipt.source, comment: comment, guardRevision: guardRevision),
            finalPayloadVersion: DayComposerFinalPayloadVersion(payloadData: Data(final.utf8)))
    }
    private func url() throws -> URL { try store().recordURL(executionIdentity: identity(), source: .morning) }
    private func bytes() throws -> Data { try Data(contentsOf: url()) }
    private func tamper(_ edit: (inout [String: Any]) -> Void) throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes()) as? [String: Any])
        edit(&object)
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url(), options: .atomic)
    }
    private func fails(_ error: E, _ operation: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? E, error, file: file, line: line)
        }
    }

    func testAllowedDoublesAndCanonicalBytes() throws {
        for rpe in [6.0, 7, 8, 9, 10] {
            let value = try DayComposerFinalInputs(rpe: rpe)
            let data = try value.canonicalData()
            XCTAssertEqual(String(data: data, encoding: .utf8), "{\"contentVersion\":1,\"rpe\":\(Int(rpe))}")
            XCTAssertEqual(data, try DayComposerFinalInputs(rpe: rpe).canonicalData())
            let version = try DayComposerFinalInputsVersion(values: value)
            XCTAssertEqual(version.digest, DayComposerFinalizationCoding.hash(data))
            XCTAssertEqual(version, try DayComposerFinalInputsVersion(values: DayComposerFinalInputs(rpe: rpe)))
            let encoded = try DayComposerFinalizationCoding.encode(value)
            XCTAssertEqual(try JSONDecoder().decode(DayComposerFinalInputs.self, from: encoded), value)
            XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("null"))
        }
    }

    func testInvalidMissingAndNonFiniteRPE() throws {
        for rpe in [5.0, 6.5, 7.5, 11, .nan, .infinity, -.infinity] {
            fails(.invalidRPE) { _ = try DayComposerFinalInputs(rpe: rpe) }
        }
        for text in ["{}", "{\"rpe\":null}"] {
            fails(.missingRequiredRPE) { _ = try JSONDecoder().decode(DayComposerFinalInputs.self, from: Data(text.utf8)) }
        }
    }

    func testUnsupportedOptionalsIncludingZeroAndNonFinite() {
        for duration in [0.0, 20, .nan, .infinity, -.infinity] {
            fails(.unsupportedOptionalInput) { _ = try DayComposerFinalInputs(rpe: 7, durationMin: duration) }
        }
        for energy in [0, 3] {
            fails(.unsupportedOptionalInput) { _ = try DayComposerFinalInputs(rpe: 7, energyPre: energy) }
        }
    }

    func testAbsentAndCreateOnlyCAS() throws {
        XCTAssertNil(try store().load(executionIdentity: identity(), source: .morning))
        fails(.staleInputs) { _ = try save(revision: 0) }
        let first = try save()
        XCTAssertEqual(first.revision, 1)
        fails(.staleInputs) { _ = try save() }
        XCTAssertTrue(try store().verify(first))
    }

    func testChangeAndABANeverReviveReceiptOrBinding() throws {
        let first = try save()
        let binding = try bind(first)
        let second = try save(8, revision: first.revision)
        XCTAssertEqual(second.revision, 2)
        XCTAssertNotEqual(first.finalInputsVersion, second.finalInputsVersion)
        XCTAssertNil(try store().load(executionIdentity: identity(), source: .morning)?.captureBinding)
        XCTAssertFalse(try store().verifyCaptureBinding(binding))
        let last = try save(7, revision: second.revision)
        XCTAssertEqual(last.revision, 3)
        XCTAssertEqual(first.finalInputsVersion, last.finalInputsVersion)
        XCTAssertFalse(try store().verify(first))
        XCTAssertTrue(try store().verify(last))
        XCTAssertFalse(try store().verifyCaptureBinding(binding))
        XCTAssertNil(try store().load(executionIdentity: identity(), source: .morning)?.captureBinding)
    }

    func testSameContentAndSameBindingDoNotWrite() throws {
        let receipt = try save()
        let binding = try bind(receipt)
        let old = try bytes()
        let noWrite = DayComposerFinalInputsStore(baseDirectory: directory, writeRecord: { _, _ in XCTFail("No-op wrote") })
        XCTAssertEqual(try noWrite.save(executionIdentity: identity(), source: .morning,
            values: receipt.values, expectedRevision: receipt.revision), receipt)
        XCTAssertEqual(try noWrite.bindCapture(executionIdentity: identity(), source: .morning,
            expectedReceipt: receipt, snapshotReference: binding.snapshotReference,
            finalPayloadVersion: binding.finalPayloadVersion), binding)
        XCTAssertEqual(try bytes(), old)
    }

    func testInterleavedStoresRejectStaleCASEvenForSameContent() throws {
        let a = store(), b = store(), first = try save()
        let second = try a.save(executionIdentity: identity(), source: .morning,
            values: DayComposerFinalInputs(rpe: 8), expectedRevision: first.revision)
        let before = try bytes()
        for rpe in [7.0, 8, 9] {
            fails(.staleInputs) { _ = try b.save(executionIdentity: identity(), source: .morning,
                values: DayComposerFinalInputs(rpe: rpe), expectedRevision: first.revision) }
        }
        XCTAssertEqual(try bytes(), before)
        XCTAssertEqual(try b.load(executionIdentity: identity(), source: .morning)?.receipt, second)
    }

    func testCrossSourceAndExecutionIsolationAndStablePaths() throws {
        let am = try save(), pm = try save(9, source: .evening)
        XCTAssertNotEqual(am.finalInputsVersion, pm.finalInputsVersion)
        XCTAssertTrue(try store().verify(am)); XCTAssertTrue(try store().verify(pm))
        let other = try identity(UUID())
        XCTAssertNil(try store().load(executionIdentity: other, source: .morning))
        let amURL = try url()
        XCTAssertEqual(amURL, try store().recordURL(executionIdentity: identity(), source: .morning))
        XCTAssertNotEqual(amURL, try store().recordURL(executionIdentity: identity(), source: .evening))
        XCTAssertNotEqual(amURL, try store().recordURL(executionIdentity: other, source: .morning))
        XCTAssertFalse(amURL.lastPathComponent.contains("program-A"))
        let otherURL = try store().recordURL(executionIdentity: other, source: .morning)
        try bytes().write(to: otherURL)
        fails(.contextMismatch) { _ = try store().load(executionIdentity: other, source: .morning) }
    }

    func testBindingReloadReplacementAndExactVerification() throws {
        let receipt = try save(8)
        let first = try bind(receipt)
        let reloaded = try XCTUnwrap(store().load(executionIdentity: identity(), source: .morning))
        XCTAssertEqual(reloaded.receipt, receipt)
        XCTAssertEqual(reloaded.captureBinding, first)
        XCTAssertEqual(first.revision, receipt.revision)
        XCTAssertEqual(first.finalInputsVersion, receipt.finalInputsVersion)
        for (comment, payload, guardRevision) in [("new", "F1", 0), ("new", "F2", 0), ("new", "F2", 1)] {
            let binding = try bind(receipt, comment: comment, final: payload, guardRevision: guardRevision)
            XCTAssertTrue(try store().verify(receipt))
            XCTAssertTrue(try store().verifyCaptureBinding(binding))
            XCTAssertFalse(try store().verifyCaptureBinding(first))
            XCTAssertEqual(try store().load(executionIdentity: identity(), source: .morning)?.revision, receipt.revision)
        }
    }

    func testStaleReceiptCannotBind() throws {
        let first = try save()
        _ = try save(8, revision: first.revision)
        let before = try bytes()
        fails(.staleInputs) { _ = try bind(first) }
        XCTAssertEqual(try bytes(), before)
    }

    func testWrongSourceAndExecutionCannotBind() throws {
        let receipt = try save(), before = try bytes()
        for (ref, error) in [(try reference(source: .evening), E.sourceMismatch),
                             (try reference(execution: UUID()), E.contextMismatch)] {
            fails(error) { _ = try store().bindCapture(executionIdentity: identity(), source: .morning,
                expectedReceipt: receipt, snapshotReference: ref,
                finalPayloadVersion: DayComposerFinalPayloadVersion(payloadData: Data("F".utf8))) }
        }
        XCTAssertEqual(try bytes(), before)
    }

    func testMalformedAndUnknownSchemaPreservedEvenOnSave() throws {
        let receipt = try save()
        let good = try bytes()
        for unknown in [false, true] {
            try good.write(to: url())
            if unknown { try tamper { $0["schemaVersion"] = 99 } }
            else { try Data("{".utf8).write(to: url()) }
            let before = try bytes(), expected: E = unknown ? .unsupportedSchema : .corruptPersistence
            fails(expected) { _ = try store().load(executionIdentity: identity(), source: .morning) }
            fails(expected) { _ = try save(revision: receipt.revision) }
            XCTAssertEqual(try bytes(), before)
        }
    }

    func testTamperedVersionAndPersistedInvalidValues() throws {
        _ = try save()
        let good = try bytes()
        let edits: [(inout [String: Any]) -> Void] = [
            { $0["finalInputsVersion"] = ["contentVersion": 1, "digest": String(repeating: "0", count: 64)] },
            { $0["values"] = ["rpe": 7.5] },
            { $0["values"] = [:] },
            { $0["values"] = ["rpe": 7, "durationMin": 0] },
            { $0["values"] = ["rpe": 7, "energyPre": 0] },
            { $0["revision"] = 0 }
        ]
        for edit in edits {
            try good.write(to: url()); try tamper(edit)
            let before = try bytes()
            fails(.corruptPersistence) { _ = try store().load(executionIdentity: identity(), source: .morning) }
            XCTAssertEqual(try bytes(), before)
        }
    }

    func testWrongSourceOnDiskFailsClosed() throws {
        _ = try save()
        try tamper { $0["source"] = "evening" }
        fails(.sourceMismatch) { _ = try store().load(executionIdentity: identity(), source: .morning) }
    }

    func testInvalidIdentityAndForgedReceiptCannotBypassSameContent() throws {
        let receipt = try save(), before = try bytes()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:
            DayComposerFinalizationCoding.encode(receipt.executionIdentity)) as? [String: Any])
        object["date"] = "not-a-date"
        let invalid = try JSONDecoder().decode(DayComposerExecutionIdentity.self,
            from: JSONSerialization.data(withJSONObject: object))
        fails(.contextMismatch) { _ = try store().save(executionIdentity: invalid, source: .morning,
            values: receipt.values, expectedRevision: receipt.revision) }
        let forged = DayComposerFinalInputsReceipt(executionIdentity: receipt.executionIdentity,
            source: receipt.source, revision: receipt.revision, finalInputsVersion: receipt.finalInputsVersion,
            values: try DayComposerFinalInputs(rpe: 8))
        XCTAssertFalse(try store().verify(forged))
        fails(.staleInputs) { _ = try bind(forged) }
        XCTAssertEqual(try bytes(), before)
    }

    func testMissingRecordCannotBindAndReceiptVerificationDoesNotWrite() throws {
        let receipt = DayComposerFinalInputsReceipt(executionIdentity: try identity(), source: .morning,
            revision: 1, finalInputsVersion: try DayComposerFinalInputsVersion(values: DayComposerFinalInputs(rpe: 7)),
            values: try DayComposerFinalInputs(rpe: 7))
        XCTAssertFalse(try store().verify(receipt))
        fails(.missingRequiredRPE) { _ = try bind(receipt) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testReferenceValidationAndInvalidFinalDigestDoNotWrite() throws {
        let receipt = try save(), ref = try reference(), before = try bytes()
        fails(.sourceMismatch) {
            _ = try DayComposerFinalInputsSnapshotReference(executionIdentity: identity(), source: .evening,
                sourceVersion: ref.sourceVersion, provenanceGuard: ref.provenanceGuard)
        }
        let invalid = try JSONDecoder().decode(DayComposerFinalPayloadVersion.self,
            from: Data("{\"payloadDigest\":\"bad\"}".utf8))
        fails(.invalidCaptureBinding) {
            _ = try store().bindCapture(executionIdentity: identity(), source: .morning,
                expectedReceipt: receipt, snapshotReference: ref, finalPayloadVersion: invalid)
        }
        XCTAssertEqual(try bytes(), before)
    }

    func testTamperedBindingFieldsFailClosed() throws {
        let receipt = try save(); _ = try bind(receipt)
        let good = try bytes()
        for field in ["revision", "finalInputsVersion", "finalPayloadVersion", "snapshotReference"] {
            try good.write(to: url())
            try tamper { object in
                var binding = object["captureBinding"] as! [String: Any]
                switch field {
                case "revision": binding[field] = 2
                case "finalInputsVersion": binding[field] = ["contentVersion": 1, "digest": String(repeating: "b", count: 64)]
                case "finalPayloadVersion": binding[field] = ["payloadDigest": "invalid"]
                default:
                    var ref = binding[field] as! [String: Any]
                    ref["source"] = "evening"; binding[field] = ref
                }
                object["captureBinding"] = binding
            }
            let before = try bytes()
            fails(.invalidCaptureBinding) { _ = try store().load(executionIdentity: identity(), source: .morning) }
            XCTAssertEqual(try bytes(), before)
        }
    }

    func testOverflowNeverWrapsButSameContentStillNoOp() throws {
        let receipt = try save()
        let record = DayComposerFinalInputsRecord(schemaVersion: 1, executionIdentity: receipt.executionIdentity,
            source: .morning, revision: UInt64.max, values: receipt.values,
            finalInputsVersion: receipt.finalInputsVersion, captureBinding: nil)
        try DayComposerFinalizationCoding.encode(record).write(to: url())
        XCTAssertEqual(try save(revision: UInt64.max).revision, UInt64.max)
        let before = try bytes()
        fails(.revisionOverflow) { _ = try save(8, revision: UInt64.max) }
        XCTAssertEqual(try bytes(), before)
    }

    func testFailedAtomicWriterPreservesPriorFile() throws {
        let receipt = try save(), before = try bytes()
        let failing = DayComposerFinalInputsStore(baseDirectory: directory, writeRecord: { _, _ in throw E.durabilityFailure })
        fails(.durabilityFailure) { _ = try failing.save(executionIdentity: identity(), source: .morning,
            values: DayComposerFinalInputs(rpe: 8), expectedRevision: receipt.revision) }
        XCTAssertEqual(try bytes(), before)
        XCTAssertTrue(try store().verify(receipt))
    }

    func testWriteSuccessWithoutExactReadbackIsRejected() throws {
        let receipt = try save(), before = try bytes()
        let noWrite = DayComposerFinalInputsStore(baseDirectory: directory, writeRecord: { _, _ in })
        fails(.durabilityFailure) { _ = try noWrite.save(executionIdentity: identity(), source: .morning,
            values: DayComposerFinalInputs(rpe: 8), expectedRevision: receipt.revision) }
        fails(.durabilityFailure) { _ = try noWrite.bindCapture(executionIdentity: identity(), source: .morning,
            expectedReceipt: receipt, snapshotReference: reference(),
            finalPayloadVersion: DayComposerFinalPayloadVersion(payloadData: Data("F".utf8))) }
        XCTAssertEqual(try bytes(), before)
    }

    func testSymlinkFileAndNamespaceIncludingDanglingRefused() throws {
        let file = try url()
        let target = directory.appendingPathComponent("target")
        try Data("untouched".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        fails(.unsafePath) { _ = try save() }
        fails(.unsafePath) { _ = try store().load(executionIdentity: identity(), source: .morning) }
        XCTAssertEqual(try Data(contentsOf: target), Data("untouched".utf8))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: directory.appendingPathComponent("missing"))
        fails(.unsafePath) { _ = try save() }
        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        let aliased = DayComposerFinalInputsStore(baseDirectory: alias)
        fails(.unsafePath) { _ = try aliased.load(executionIdentity: identity(), source: .morning) }
    }
}
