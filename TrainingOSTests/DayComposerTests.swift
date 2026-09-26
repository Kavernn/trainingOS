import XCTest
#if canImport(TrainingOS)
@testable import TrainingOS
#endif

final class DayComposerTests: XCTestCase {
    // Isolated dates keep the real legacy primitives and shared provenance hooks
    // under test, without touching user recovery or depending on test order.
    private func withProvenance(_ body: (DayComposerProvenanceStore, DayComposerExecutionContext) throws -> Void) throws {
        let date = "provenance-\(UUID().uuidString)"
        let context = try DayComposerExecutionContext(snapshot: snapshot(date: date))
        let store = DayComposerProvenanceStore.shared
        defer {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            try? store.clear(date: date)
        }
        try body(store, context)
    }

    private func assertValidated(_ store: DayComposerProvenanceStore, _ context: DayComposerExecutionContext,
                                 _ source: DayComposerSource, file: StaticString = #filePath, line: UInt = #line) {
        guard case .validated = store.admission(context: context, source: source) else {
            return XCTFail("Expected validated \(source)", file: file, line: line)
        }
    }

    func testProvenanceFreshAndEmptyProvenanceAreReadOnly() throws {
        try withProvenance { store, context in
            XCTAssertEqual(store.admission(context: context, source: .morning), .fresh)
            XCTAssertEqual(store.admission(context: context, source: .evening), .fresh)
            XCTAssertNil(try store.load(date: context.date))
            let id = try store.create(context: context)
            let before = try Data(contentsOf: store.recordURL(date: context.date))
            XCTAssertEqual(store.admission(context: context, source: .morning), .validated(executionID: id, revision: 0))
            assertValidated(store, context, .evening)
            XCTAssertFalse(try store.inventory(date: context.date, source: .morning).hasState)
            XCTAssertEqual(try Data(contentsOf: store.recordURL(date: context.date)), before)
            XCTAssertThrowsError(try store.create(context: context))
        }
    }

    func testProvenanceLegacyInventoryIncludesEmptyCorruptCardsAndTiming() throws {
        try withProvenance { store, context in
            let d = context.date
            for key in ["session_draft_morning_\(d)", "session_comment_morning_\(d)",
                        "session_draft_protection_morning_\(d)", "exo_draft_\(d)_morning_Outside plan",
                        "session_started_at_morning_\(d)", "session_chrono_paused_morning_\(d)",
                        "session_chrono_is_paused_morning_\(d)", "session_chrono_paused_at_morning_\(d)"] {
                UserDefaults.standard.set("", forKey: key)
                XCTAssertEqual(store.admission(context: context, source: .morning), .denied(.legacyWithoutProvenance))
                XCTAssertThrowsError(try store.create(context: context))
                XCTAssertNotNil(UserDefaults.standard.object(forKey: key))
                UserDefaults.standard.removeObject(forKey: key)
            }
            XCTAssertEqual(store.admission(context: context, source: .morning), .fresh)
        }
    }

    func testProvenanceEachContextMismatchPreservesBytes() throws {
        try withProvenance { store, context in
            try store.create(context: context)
            let before = try Data(contentsOf: store.recordURL(date: context.date))
            let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any])
            for key in ["activeProgramID", "sourceFingerprint", "morningSession", "eveningSession"] {
                var json = original
                json[key] = "different"
                let other = try JSONDecoder().decode(DayComposerExecutionContext.self, from: JSONSerialization.data(withJSONObject: json))
                XCTAssertEqual(store.admission(context: other, source: .morning), .denied(.contextMismatch))
                XCTAssertEqual(store.admission(context: other, source: .evening), .denied(.contextMismatch))
            }
            XCTAssertEqual(try Data(contentsOf: store.recordURL(date: context.date)), before)
            let token = try store.authorize(context: context, source: .morning)
            var wrote = false
            XCTAssertFalse(store.mutate(date: context.date + "other", sessionType: "morning", authorization: token) { wrote = true })
            XCTAssertFalse(wrote)
        }
    }

    func testProvenanceAuthorizedLogsCommentsDraftsAndRevisionNoACK() throws {
        try withProvenance { store, context in
            try store.create(context: context)
            let token = try store.authorize(context: context, source: .morning)
            let evening = try store.load(date: context.date)?.evening
            let log = PersistedExerciseLogResult(name: "Bench Press", weight: 80, reps: "5", rpe: nil,
                isSecond: false, isBonus: false, equipmentType: "machine", painZone: "", sets: [], notes: "Private note")
            SessionDraftStore.save(date: context.date, values: [log], authorization: token)
            SessionDraftStore.saveComment("Private comment", date: context.date, sessionType: "morning", authorization: token)
            SessionDraftStore.saveComment("", date: context.date, sessionType: "morning", authorization: token)
            let card = ExerciseDraftPersistence(date: context.date, sessionType: "morning", exerciseName: "Bench Press", authorization: token)
            XCTAssertTrue(card.save([], sessionNote: "Private draft"))
            card.clear()
            assertValidated(store, context, .morning)
            XCTAssertEqual(try store.load(date: context.date)?.morning.revision, 5)
            XCTAssertEqual(try store.load(date: context.date)?.evening, evening)
            XCTAssertEqual(SessionDraftStore.recoveryProtection(date: context.date, sessionType: "morning")?.generation, 3)
            XCTAssertEqual(SessionDraftStore.recoveryProtection(date: context.date, sessionType: "morning")?.hasUnacknowledgedLocalChanges, true)
            let bytes = try Data(contentsOf: store.recordURL(date: context.date))
            let text = String(decoding: bytes, as: UTF8.self)
            for forbidden in ["Private note", "Private comment", "Private draft", "hasUnacknowledgedLocalChanges", "generation", "HealthKit"] {
                XCTAssertFalse(text.contains(forbidden))
            }
            let recreated = DayComposerProvenanceStore()
            assertValidated(recreated, context, .morning)
            XCTAssertEqual(SessionDraftStore.loadComment(date: context.date, sessionType: "morning"), "")
            XCTAssertEqual(try Data(contentsOf: store.recordURL(date: context.date)), bytes)
        }
    }

    func testProvenanceClassicMutationsInvalidateOnlyTheirSource() throws {
        for source in [DayComposerSource.morning, .evening] {
            for operation in 0..<9 {
                try withProvenance { store, context in
                    try store.create(context: context)
                    let other: DayComposerSource = source == .morning ? .evening : .morning
                    let before = try store.load(date: context.date)?[other]
                    switch operation {
                    case 0: SessionDraftStore.save(date: context.date, sessionType: source.rawValue, values: [])
                    case 1: SessionDraftStore.saveComment("", date: context.date, sessionType: source.rawValue)
                    case 2: XCTAssertTrue(ExerciseDraftPersistence(date: context.date, sessionType: source.rawValue, exerciseName: "Bench Press").save([], sessionNote: "Note"))
                    case 3: ExerciseDraftPersistence(date: context.date, sessionType: source.rawValue, exerciseName: "Bench Press").clear()
                    case 4: SessionDraftStore.saveStartedAt(date: context.date, sessionType: source.rawValue, startedAt: Date())
                    case 5: SessionDraftStore.saveChronoPausedDuration(date: context.date, sessionType: source.rawValue, duration: 2)
                    case 6: SessionDraftStore.saveChronoIsPaused(date: context.date, sessionType: source.rawValue, isPaused: true)
                    case 7: SessionDraftStore.saveChronoPausedAt(date: context.date, sessionType: source.rawValue, pausedAt: Date())
                    default: SessionDraftStore.clear(date: context.date, sessionType: source.rawValue)
                    }
                    XCTAssertEqual(store.admission(context: context, source: source), .denied(.invalidated))
                    XCTAssertEqual(try store.load(date: context.date)?[other], before)
                    assertValidated(store, context, other)
                }
            }
        }
    }

    func testProvenanceInterruptedBeginAndRecoveryWriteFailClosed() throws {
        for writeRecovery in [false, true] {
            try withProvenance { store, context in
                try store.create(context: context)
                let token = try store.authorize(context: context, source: .morning)
                _ = try store.begin(token)
                if writeRecovery { UserDefaults.standard.set("Partial write", forKey: "session_comment_morning_\(context.date)") }
                let reopened = DayComposerProvenanceStore()
                XCTAssertEqual(reopened.admission(context: context, source: .morning), .denied(.interruptedWrite))
                assertValidated(reopened, context, .evening)
                XCTAssertThrowsError(try reopened.authorize(context: context, source: .morning))
            }
        }
    }

    func testProvenanceWriteFailuresAndPersistenceReorderingFailClosed() throws {
        try withProvenance { store, context in
            try store.create(context: context)
            let token = try store.authorize(context: context, source: .morning)
            let failing = DayComposerProvenanceStore(writeRecord: { _, _ in throw CocoaError(.fileWriteNoPermission) })
            var wrote = false
            XCTAssertFalse(failing.mutate(date: context.date, sessionType: "morning", authorization: token) { wrote = true })
            XCTAssertFalse(wrote) // Failure before begin: recovery untouched.
            assertValidated(store, context, .morning)
            let mutation = try store.begin(token)
            UserDefaults.standard.set("New", forKey: "session_comment_morning_\(context.date)")
            XCTAssertThrowsError(try failing.finish(mutation))
            XCTAssertEqual(store.admission(context: context, source: .morning), .denied(.interruptedWrite))
            try store.finish(mutation)
            // Simulate UserDefaults not retaining the last write, despite stable metadata.
            UserDefaults.standard.removeObject(forKey: "session_comment_morning_\(context.date)")
            XCTAssertEqual(store.admission(context: context, source: .morning), .denied(.integrityMismatch))
        }
    }

    func testProvenanceFullClearRecreateAndOrderResetNeverRecertify() throws {
        try withProvenance { store, context in
            try store.create(context: context)
            for source in [DayComposerSource.morning, .evening] {
                let token = try store.authorize(context: context, source: source)
                SessionDraftStore.saveComment("same", date: context.date, sessionType: source.rawValue, authorization: token)
            }
            let evening = try store.load(date: context.date)?.evening
            SessionDraftStore.clear(date: context.date, sessionType: "morning")
            XCTAssertNil(SessionDraftStore.loadComment(date: context.date, sessionType: "morning"))
            SessionDraftStore.saveComment("same", date: context.date, sessionType: "morning")
            XCTAssertEqual(store.admission(context: context, source: .morning), .denied(.invalidated))
            XCTAssertEqual(try store.load(date: context.date)?.evening, evening)
            let before = try Data(contentsOf: store.recordURL(date: context.date))
            try withStore { order in try order.reset(snapshot(date: context.date)) }
            XCTAssertEqual(try Data(contentsOf: store.recordURL(date: context.date)), before)
            XCTAssertThrowsError(try store.clear(date: context.date))
            XCTAssertEqual(SessionDraftStore.loadComment(date: context.date, sessionType: "evening"), "same")
        }
    }

    func testProvenanceCorruptUnknownVersionAndWrongStoredDateNeverBecomeFresh() throws {
        try withProvenance { store, context in
            try store.create(context: context)
            let bytes = try Data(contentsOf: store.recordURL(date: context.date))
            let original = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            var future = original
            future["schemaVersion"] = 99
            var wrongDate = original
            var nested = try XCTUnwrap(wrongDate["context"] as? [String: Any])
            nested["date"] = "wrong-date"
            wrongDate["context"] = nested
            for (data, reason) in [(Data("broken".utf8), DayComposerSourceAdmission.Denial.corrupt),
                                   (try JSONSerialization.data(withJSONObject: future), .unsupportedVersion),
                                   (try JSONSerialization.data(withJSONObject: wrongDate), .corrupt)] {
                try data.write(to: store.recordURL(date: context.date), options: .atomic)
                XCTAssertEqual(store.admission(context: context, source: .morning), .denied(reason))
                SessionDraftStore.saveComment("classic still works", date: context.date, sessionType: "morning")
                XCTAssertEqual(try Data(contentsOf: store.recordURL(date: context.date)), data)
                XCTAssertThrowsError(try store.create(context: context))
            }
        }
    }

    func testProvenanceClassicWithoutRecordAndRapidAuthorizedWrites() throws {
        try withProvenance { store, context in
            SessionDraftStore.saveComment("", date: context.date, sessionType: "morning")
            let card = ExerciseDraftPersistence(date: context.date, sessionType: "evening", exerciseName: "Bench Press")
            XCTAssertTrue(card.save([], sessionNote: "Draft"))
            XCTAssertEqual(card.loadCard()?.sessionNote, "Draft")
            XCTAssertNil(try store.load(date: context.date))
            card.clear()
            SessionDraftStore.clear(date: context.date, sessionType: "morning")
            try store.create(context: context)
            let token = try store.authorize(context: context, source: .morning)
            for n in 0..<30 {
                SessionDraftStore.saveComment("\(n)", date: context.date, sessionType: "morning", authorization: token)
            }
            XCTAssertEqual(try store.load(date: context.date)?.morning.revision, 30)
            XCTAssertNil(try store.load(date: context.date)?.morning.pendingMutation)
            assertValidated(store, context, .morning)
            assertValidated(store, context, .evening)
        }
    }

    func testProvenanceIdenticalRestorationIsReadOnlyAndHomonymousCardsStaySeparate() throws {
        try withProvenance { store, context in
            try store.create(context: context)
            let sets = [DraftSet(weight: "80", reps: "5", rir: 2, duration: 0)]
            for source in [DayComposerSource.morning, .evening] {
                let token = try store.authorize(context: context, source: source)
                let card = ExerciseDraftPersistence(date: context.date, sessionType: source.rawValue, exerciseName: "Bench Press", authorization: token)
                XCTAssertTrue(card.save(sets, sessionNote: "Same note"))
                SessionDraftStore.saveComment("same", date: context.date, sessionType: source.rawValue, authorization: token)
            }
            let before = try Data(contentsOf: store.recordURL(date: context.date))
            let morning = ExerciseDraftPersistence(date: context.date, sessionType: "morning", exerciseName: "Bench Press")
            XCTAssertEqual(morning.loadCard()?.sets.first?.weight, "80")
            XCTAssertTrue(morning.save(sets, sessionNote: "Same note"))
            SessionDraftStore.saveComment("same", date: context.date, sessionType: "morning")
            XCTAssertEqual(try Data(contentsOf: store.recordURL(date: context.date)), before)
            XCTAssertTrue(morning.save(sets, sessionNote: "Edited note"))
            XCTAssertEqual(store.admission(context: context, source: .morning), .denied(.invalidated))
            assertValidated(store, context, .evening)
            XCTAssertEqual(ExerciseDraftPersistence(date: context.date, sessionType: "evening", exerciseName: "Bench Press").loadCard()?.sessionNote, "Same note")
        }
    }

    func testProvenanceWrongSourceStaleExecutionAndNestedMutationAreRejected() throws {
        try withProvenance { store, context in
            try store.create(context: context)
            let token = try store.authorize(context: context, source: .morning)
            var wrote = false
            XCTAssertFalse(store.mutate(date: context.date, sessionType: "evening", authorization: token) { wrote = true })
            XCTAssertFalse(wrote)
            let pending = try store.begin(token)
            XCTAssertThrowsError(try store.begin(token))
            try store.finish(pending)
            XCTAssertThrowsError(try store.finish(pending)) // Receipt cannot be reused.
            try store.clear(date: context.date) // Explicit, no recovery exists.
            try store.create(context: context)
            XCTAssertFalse(store.mutate(date: context.date, sessionType: "morning", authorization: token) { wrote = true })
            XCTAssertFalse(wrote)
            assertValidated(store, context, .morning)
        }
    }

    func testProvenanceInvalidationStorageFailureDoesNotWriteRecovery() throws {
        try withProvenance { store, context in
            try store.create(context: context)
            let failing = DayComposerProvenanceStore(writeRecord: { _, _ in throw CocoaError(.fileWriteNoPermission) })
            var wrote = false
            XCTAssertFalse(failing.mutate(date: context.date, sessionType: "morning") { wrote = true })
            XCTAssertFalse(wrote)
            assertValidated(store, context, .morning)
            try store.invalidateAll(date: context.date)
            XCTAssertEqual(store.admission(context: context, source: .morning), .denied(.invalidated))
            XCTAssertEqual(store.admission(context: context, source: .evening), .denied(.invalidated))
            try store.clear(date: context.date)
            XCTAssertEqual(store.admission(context: context, source: .morning), .fresh)
        }
    }

    func testExecutionProvenanceCompatibilityIsPureAndPreservesOrder() throws {
        let original = try snapshot()
        let context = try DayComposerExecutionContext(snapshot: original)
        try withStore { store in
            try store.save(original.initialUnits, for: original)
            let before = store.defaults.dictionaryRepresentation()
            XCTAssertEqual(context.compatibility(with: context), .compatible)
            XCTAssertEqual(context.compatibility(with: try .init(snapshot: snapshot(program: "B"))), .differentProgram)
            XCTAssertEqual(context.compatibility(with: try .init(snapshot: snapshot(date: "2026-09-27"))), .differentDate)
            XCTAssertEqual(context.compatibility(with: try .init(snapshot: snapshot(morning: ["Changed"]))), .differentSources)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any])
            json["version"] = 99
            let future = try JSONDecoder().decode(DayComposerExecutionContext.self,
                from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(future.compatibility(with: context), .unsupportedVersion)
            XCTAssertEqual(NSDictionary(dictionary: before), NSDictionary(dictionary: store.defaults.dictionaryRepresentation()))
        }
    }

    func testSourceProjectionKeepsHomonymsAndIdenticalSetsSeparate() throws {
        let data = Data(#"{"session_list":[{"date":"2026-09-26","session_type":"morning","exos":[{"exercise":"A"},{"exercise":"Bench Press","sets":[{"weight":80,"reps":5}]}]},{"date":"2026-09-26","session_type":"evening","exos":[{"exercise":"B"},{"exercise":"Bench Press","sets":[{"weight":80,"reps":5}]}]},{"date":"2026-09-26","session_type":"bonus","exos":[{"exercise":"C"}]},{"date":"2026-09-25","session_type":"morning","exos":[{"exercise":"D"}]}],"has_more":true}"#.utf8)
        let projection = try DayComposerServerProjection(date: "2026-09-26", historyData: data)
        XCTAssertEqual(projection.positivelyObserved.count, 4)
        XCTAssertEqual(projection.positivelyObserved.filter { $0.exactName == "Bench Press" }.count, 2)
        XCTAssertEqual(projection.presence(of: "Bench Press", source: .morning), .observed)
        XCTAssertEqual(projection.presence(of: "Bench Press", source: .evening), .observed)
        XCTAssertEqual(projection.presence(of: "A", source: .morning), .observed)
        XCTAssertEqual(projection.presence(of: "A", source: .evening), .unknown)
        XCTAssertEqual(projection.presence(of: "B", source: .morning), .unknown)
        XCTAssertEqual(projection.presence(of: "B", source: .evening), .observed)
        XCTAssertEqual(projection.presence(of: "C", source: .morning), .unknown)
        XCTAssertEqual(projection.presence(of: "D", source: .morning), .unknown)
    }

    private func snapshot(date: String = "2026-09-26", program: String = "A",
                          morning: [String] = ["A", "B"], evening: [String] = ["C", "D"],
                          completed: Bool = false) throws -> DayComposerSnapshot {
        try DayComposerSnapshot(date: date, activeProgramID: program,
            morning: DayComposerPlan(source: .morning, session: "AM",
                schemes: Dictionary(uniqueKeysWithValues: morning.map { ($0, "3x10") }), order: morning),
            evening: DayComposerPlan(source: .evening, session: "PM",
                schemes: Dictionary(uniqueKeysWithValues: evening.map { ($0, "3x10") }), order: evening),
            morningCompleted: completed, eveningCompleted: false)
    }

    private func withStore(_ body: (DayComposerStore) throws -> Void) rethrows {
        let suite = "DayComposerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(DayComposerStore(defaults: defaults))
    }

    private func names(_ units: [DayComposerUnit]) -> [String] { units.flatMap { $0.items.map(\.name) } }

    func testInitialMerge() throws {
        let s = try snapshot()
        XCTAssertEqual(names(s.initialUnits), ["A", "B", "C", "D"])
        XCTAssertEqual(s.initialIDs.map(\.source), [.morning, .morning, .evening, .evening])
    }

    func testDuplicateNameIsSourceScopedEvenWithSameUUID() throws {
        let uuid = UUID().uuidString
        let a = DayComposerItemID(source: .morning, name: "Bench Press", exerciseID: uuid)
        let b = DayComposerItemID(source: .evening, name: "Bench Press", exerciseID: uuid)
        XCTAssertNotEqual(a, b)
        let s = try snapshot(morning: ["Bench Press"], evening: ["Bench Press"])
        XCTAssertEqual(s.initialIDs.count, 2)
        XCTAssertEqual(Set(s.initialIDs).count, 2)
    }

    func testIdentityFallbackIsTaggedAndExact() {
        XCTAssertNotEqual(DayComposerItemID(source: .morning, name: "A", exerciseID: nil),
                          DayComposerItemID(source: .morning, name: "a", exerciseID: nil))
        let uuid = UUID().uuidString
        XCTAssertEqual(DayComposerItemID(source: .morning, name: "A", exerciseID: uuid.lowercased()),
                       DayComposerItemID(source: .morning, name: "Renamed", exerciseID: uuid))
    }

    func testLocalReorderDoesNotMutateSource() throws {
        let s = try snapshot()
        let moved = DayComposerSnapshot.moving(s.initialUnits, from: IndexSet(integer: 2), to: 1)
        XCTAssertEqual(names(moved), ["A", "C", "B", "D"])
        XCTAssertEqual(names(s.morning.units), ["A", "B"])
        XCTAssertEqual(names(s.evening.units), ["C", "D"])
        try withStore { store in
            try store.save(moved, for: s)
            guard case .restored(let restored) = try store.load(s) else { return XCTFail("Not restored") }
            XCTAssertEqual(restored, moved)
        }
    }

    func testRestoreWithRecreatedStore() throws {
        let s = try snapshot()
        try withStore { store in
            let moved = DayComposerSnapshot.moving(s.initialUnits, from: IndexSet(integer: 2), to: 1)
            try store.save(moved, for: s)
            let recreated = DayComposerStore(defaults: store.defaults)
            guard case .restored(let restored) = try recreated.load(s) else { return XCTFail("Not restored") }
            XCTAssertEqual(restored, moved)
        }
    }

    func testDateIsolation() throws {
        try withStore { store in
            try store.save(snapshot().initialUnits, for: snapshot())
            guard case .initial = try store.load(snapshot(date: "2026-09-27")) else { return XCTFail("Cross-date order") }
        }
    }

    func testActiveProgramIsolationAndReturn() throws {
        try withStore { store in
            let s = try snapshot()
            let moved = DayComposerSnapshot.moving(s.initialUnits, from: IndexSet(integer: 2), to: 1)
            try store.save(moved, for: s)
            guard case .initial = try store.load(snapshot(program: "B")) else { return XCTFail("Cross-program order") }
            guard case .restored(let restored) = try store.load(s) else { return XCTFail("Lost A") }
            XCTAssertEqual(restored, moved)
        }
    }

    func testFingerprintMismatchPreservesSavedBytes() throws {
        try withStore { store in
            let s = try snapshot()
            try store.save(s.initialUnits.reversed(), for: s)
            let before = store.defaults.dictionaryRepresentation()
            let changed = try snapshot(morning: ["A", "B", "X"])
            guard case .incompatible = try store.load(changed) else { return XCTFail("Stale order accepted") }
            XCTAssertEqual(names(changed.initialUnits), ["A", "B", "X", "C", "D"])
            XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: store.defaults.dictionaryRepresentation()))
        }
    }

    func testResetOnlyTouchesComposer() throws {
        try withStore { store in
            store.defaults.set("keep", forKey: "session_recovery")
            let s = try snapshot()
            try store.save(s.initialUnits.reversed(), for: s)
            try store.reset(s)
            guard case .restored(let restored) = try store.load(s) else { return XCTFail("Missing reset") }
            XCTAssertEqual(restored, s.initialUnits)
            XCTAssertEqual(store.defaults.string(forKey: "session_recovery"), "keep")
        }
    }

    func testSupersetAtomicReorderAndValidation() throws {
        let morning = try DayComposerPlan(source: .morning, session: "AM",
            schemes: ["A": "3x10", "B": "3x10", "X": "3x10"], order: ["A", "X", "B"],
            pairs: [.init(group: "SS1", a: "A", b: "B", rest: 60)])
        let s = try DayComposerSnapshot(date: "2026-09-26", activeProgramID: "A", morning: morning,
            evening: snapshot().evening, morningCompleted: false, eveningCompleted: false)
        XCTAssertEqual(names(s.initialUnits), ["A", "B", "X", "C", "D"])
        let moved = DayComposerSnapshot.moving(s.initialUnits, from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(names(moved), ["X", "A", "B", "C", "D"])
        XCTAssertNotNil(s.units(for: moved.flatMap { $0.items.map(\.id) }))
        var split = s.initialIDs
        split.swapAt(1, 2)
        XCTAssertNil(s.units(for: split))
    }

    func testBrokenSupersetFailsClosed() {
        XCTAssertThrowsError(try DayComposerPlan(source: .morning, session: "AM",
            schemes: ["A": "3x10"], order: ["A"],
            pairs: [.init(group: "SS1", a: "A", b: "B", rest: nil)]))
    }

    func testAccessibleMoveMatchesDragAndBounds() throws {
        let initial = try snapshot().initialUnits
        let up = DayComposerSnapshot.moving(initial, from: IndexSet(integer: 2), to: 1)
        let down = DayComposerSnapshot.moving(initial, from: IndexSet(integer: 1), to: 3)
        XCTAssertEqual(up, down)
        XCTAssertEqual(DayComposerSnapshot.moving(initial, from: IndexSet(integer: 0), to: -1), initial)
        XCTAssertEqual(DayComposerSnapshot.moving(initial, from: IndexSet(integer: 3), to: 5), initial)
    }

    func testIrrelevantEntry() throws {
        XCTAssertFalse(try snapshot(evening: []).isRelevant(hasSavedOrder: false))
        XCTAssertFalse(try snapshot(morning: []).isRelevant(hasSavedOrder: true))
        XCTAssertFalse(try snapshot(completed: true).isRelevant(hasSavedOrder: false))
        XCTAssertTrue(try snapshot(completed: true).isRelevant(hasSavedOrder: true))
        XCTAssertTrue(try snapshot().isRelevant(hasSavedOrder: false))
        XCTAssertFalse(try snapshot(program: "").isRelevant(hasSavedOrder: false))
    }

    func testInheritedPMRequiresAssignedContent() {
        let schemes = ["A": "3x10", "B": "3x10"]
        XCTAssertTrue(DayComposerPlan.eveningSchemes(schemes, explicitlyPlanned: false, pushedToEvening: []).isEmpty)
        XCTAssertEqual(DayComposerPlan.eveningSchemes(schemes, explicitlyPlanned: false, pushedToEvening: ["B"]), ["B": "3x10"])
        XCTAssertEqual(DayComposerPlan.eveningSchemes(schemes, explicitlyPlanned: true, pushedToEvening: []), schemes)
    }

    func testReadAndEligibilityNeverPersist() throws {
        try withStore { store in
            let s = try snapshot()
            let before = store.defaults.dictionaryRepresentation()
            _ = s.isRelevant(hasSavedOrder: store.hasSavedOrder(date: s.date, program: s.activeProgramID))
            guard case .initial = try store.load(s) else { return XCTFail("Unexpected saved state") }
            XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: store.defaults.dictionaryRepresentation()))
        }
    }

    func testFingerprintDeterministicAndConfigurationSensitive() throws {
        let a = try DayComposerPlan(source: .morning, session: "AM", schemes: ["B": "3x10", "A": "3x10"], order: ["A", "B"])
        let b = try DayComposerPlan(source: .morning, session: "AM", schemes: ["A": "3x10", "B": "3x10"], order: ["A", "B"])
        let base = try snapshot()
        func fingerprint(_ plan: DayComposerPlan) throws -> String {
            try DayComposerSnapshot(date: base.date, activeProgramID: base.activeProgramID, morning: plan,
                evening: base.evening, morningCompleted: false, eveningCompleted: false).fingerprint
        }
        XCTAssertEqual(try fingerprint(a), fingerprint(b))
        let changed = try DayComposerPlan(source: .morning, session: "AM", schemes: ["A": "4x10", "B": "3x10"], order: ["A", "B"])
        XCTAssertNotEqual(try fingerprint(a), fingerprint(changed))
        XCTAssertEqual(try base.fingerprint, snapshot(completed: true).fingerprint)
    }

    func testInvalidOrderRejectedWithoutOverwriting() throws {
        try withStore { store in
            let s = try snapshot()
            XCTAssertNil(s.units(for: Array(s.initialIDs.dropFirst())))
            XCTAssertNil(s.units(for: [s.initialIDs[0], s.initialIDs[0], s.initialIDs[2], s.initialIDs[3]]))
            XCTAssertThrowsError(try store.save([s.initialUnits[0]], for: s))
            XCTAssertFalse(store.hasSavedOrder(date: s.date, program: s.activeProgramID))
        }
    }

    func testClearIsScoped() throws {
        try withStore { store in
            let a = try snapshot(), b = try snapshot(program: "B")
            try store.reset(a)
            try store.reset(b)
            store.clear(date: a.date, program: a.activeProgramID)
            XCTAssertFalse(store.hasSavedOrder(date: a.date, program: a.activeProgramID))
            XCTAssertTrue(store.hasSavedOrder(date: b.date, program: b.activeProgramID))
        }
    }

    func testUnknownVersionAndCorruptPayloadStayIncompatible() throws {
        try withStore { store in
            let s = try snapshot()
            try store.reset(s)
            let key = try XCTUnwrap(store.defaults.dictionaryRepresentation().keys.first { $0.hasPrefix("day_composer_order.") })
            let future = DayComposerState(version: 99, date: s.date, activeProgramID: s.activeProgramID,
                                          sourceFingerprint: try s.fingerprint, orderedItemIDs: s.initialIDs)
            store.defaults.set(try JSONEncoder().encode(future), forKey: key)
            guard case .incompatible = try store.load(s) else { return XCTFail("Unknown version accepted") }
            store.defaults.set(Data("broken".utf8), forKey: key)
            guard case .incompatible = try store.load(s) else { return XCTFail("Corruption accepted") }
            XCTAssertEqual(store.defaults.data(forKey: key), Data("broken".utf8))
        }
    }
}
