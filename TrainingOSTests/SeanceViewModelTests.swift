//
//  SeanceViewModelTests.swift
//  TrainingOSTests
//
//  Strategy: pre-load the injected CacheService with SeanceData JSON,
//  then call load() — network fetch fails (no real server) and is silently
//  ignored since seanceData is already set from cache.

import XCTest
import SwiftUI
@testable import TrainingOS

@MainActor
final class SeanceViewModelTests: XCTestCase {

    // MARK: - R10.0e1 passive owner preparation

    private func preparationBytes(_ date: String) -> NSDictionary {
        NSDictionary(dictionary: UserDefaults.standard.dictionaryRepresentation().filter { $0.key.contains(date) })
    }

    private func seedPreparationRecovery(_ date: String, source: String, weight: Double,
                                         name: String = "Bench Press", comment: String = "Comment") {
        SessionDraftStore.save(date: date, sessionType: source, values: [
            .init(name: name, weight: weight, reps: "5", rpe: 7,
                  isSecond: source == "evening", isBonus: false, equipmentType: "machine", painZone: "",
                  sets: [], notes: "Note \(source)")
        ])
        SessionDraftStore.saveComment(comment, date: date, sessionType: source)
        SessionDraftStore.saveStartedAt(date: date, sessionType: source, startedAt: Date(timeIntervalSince1970: 100))
        SessionDraftStore.saveChronoPausedDuration(date: date, sessionType: source, duration: 12)
        SessionDraftStore.saveChronoIsPaused(date: date, sessionType: source, isPaused: true)
        SessionDraftStore.saveChronoPausedAt(date: date, sessionType: source, pausedAt: Date(timeIntervalSince1970: 200))
    }

    private func prepare(_ vm: SeanceViewModel, _ data: SeanceData,
                         token: String = "validated-context-A",
                         admission: SeanceViewModel.RecoveryAdmission = .allowCurrentScopedRecovery) throws {
        try vm.prepareForDayComposer(data: data, sessionDate: data.todayDate, source: vm.draftSessionType,
            sessionName: data.today, contextToken: token, recoveryAdmission: admission)
    }

    private final class PassiveMorningSpy: SeanceViewModel {
        var externalCalls = 0
        override func load() async { externalCalls += 1 }
        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome {
            externalCalls += 1
            throw URLError(.cancelled)
        }
        override func sendMorningSession(exos: [String], rpe: Double, comment: String, date: String,
                                         durationMin: Double?, energyPre: Int?, sessionName: String?,
                                         exerciseLogs: [[String: Any]]) async throws -> SessionSaveOutcome {
            externalCalls += 1
            throw URLError(.cancelled)
        }
    }

    private final class PassiveEveningSpy: SeanceSoirViewModel {
        var externalCalls = 0
        override func load() async { externalCalls += 1 }
        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome {
            externalCalls += 1
            throw URLError(.cancelled)
        }
        override func sendEveningSession(exos: [String], rpe: Double, comment: String,
                                         durationMin: Double?, energyPre: Int?, sessionName: String?,
                                         exerciseLogs: [[String: Any]]) async throws -> SessionSaveOutcome {
            externalCalls += 1
            throw URLError(.cancelled)
        }
        override func refreshEveningDashboard() async { externalCalls += 1 }
        override func observeEveningCompletion(date: String) async -> Bool { externalCalls += 1; return true }
        override func recordEveningWorkout() async { externalCalls += 1 }
    }

    func testPassivePreparationRestoresBothSourcesWithoutWritesOrTiming() async throws {
        let date = "passive-\(UUID().uuidString)"
        let cardDraft = ExerciseDraftPersistence(date: date, sessionType: "morning", exerciseName: "Bench Press")
        defer {
            SessionDraftStore.clear(date: date, sessionType: "morning")
            SessionDraftStore.clear(date: date, sessionType: "evening")
            cardDraft.clear()
        }
        seedPreparationRecovery(date, source: "morning", weight: 80, comment: "AM")
        seedPreparationRecovery(date, source: "evening", weight: 60, comment: "")
        cardDraft.save([], sessionNote: "Existing card note")
        let before = preparationBytes(date)
        let morning = PassiveMorningSpy(draftSessionType: "morning")
        let evening = PassiveEveningSpy(sessionName: "Override must not be loaded")
        let morningStart = morning.sessionStart
        let eveningStart = evening.sessionStart
        let data = try extraData(date)
        try prepare(morning, data)
        try prepare(evening, data)
        XCTAssertEqual(morning.logResults["Bench Press"]?.weight, 80)
        XCTAssertEqual(evening.logResults["Bench Press"]?.weight, 60)
        XCTAssertEqual(morning.logResults["Bench Press"]?.notes, "Note morning")
        XCTAssertEqual(evening.logResults["Bench Press"]?.notes, "Note evening")
        XCTAssertEqual(morning.sessionComment, "AM")
        XCTAssertEqual(evening.sessionComment, "")
        XCTAssertEqual(evening.draftSessionType, "evening")
        // Longer than the chrono's one-second tick; no delayed preparation writes.
        try await Task.sleep(nanoseconds: 1_200_000_000)
        for vm in [morning as SeanceViewModel, evening] {
            XCTAssertTrue(vm.isDayComposerLocal)
            XCTAssertEqual(vm.seanceData?.todayDate, date)
            XCTAssertFalse(vm.sessionStarted)
            XCTAssertFalse(vm.chrono.hasTimingContext)
            XCTAssertEqual(vm.chrono.elapsedSeconds, 0)
            XCTAssertFalse(vm.showSuccess)
            XCTAssertFalse(vm.canRetryFinish)
            XCTAssertNil(vm.finishSourceDate)
        }
        XCTAssertEqual(morning.sessionStart, morningStart)
        XCTAssertEqual(evening.sessionStart, eveningStart)
        XCTAssertEqual(morning.externalCalls + evening.externalCalls, 0)
        XCTAssertEqual(preparationBytes(date), before)
    }

    func testPassiveAdmissionDenyPreservesRecoveryAndRejectsWrites() throws {
        let date = "denied-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "morning") }
        seedPreparationRecovery(date, source: "morning", weight: 80)
        let before = preparationBytes(date)
        let vm = SeanceViewModel(draftSessionType: "morning")
        try prepare(vm, extraData(date), admission: .deny)
        XCTAssertTrue(vm.logResults.isEmpty)
        XCTAssertEqual(vm.sessionComment, "")
        vm.restoreSessionComment()
        vm.logResults["Other"] = .init(name: "Other", weight: 10, reps: "5")
        vm.sessionComment = "Must not overwrite denied comment"
        XCTAssertTrue(vm.logResults.isEmpty)
        XCTAssertEqual(vm.sessionComment, "")
        XCTAssertEqual(preparationBytes(date), before)
    }

    func testPassivePreparationNeverSynthesizesServerLogsOrCleansOutOfPlanRecovery() throws {
        let date = "no-synthesis-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "morning") }
        seedPreparationRecovery(date, source: "morning", weight: 25, name: "Outside plan")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.seanceDataJSON(
            todayDate: date, alreadyLogged: true, exerciseName: "Server only", historyDate: date)) as? [String: Any])
        json["logged_today_names"] = ["Server only"]
        let data = try APIService.decoder.decode(SeanceData.self, from: JSONSerialization.data(withJSONObject: json))
        let before = preparationBytes(date)
        let vm = SeanceViewModel(draftSessionType: "morning")
        try prepare(vm, data)
        XCTAssertEqual(Set(vm.logResults.keys), ["Outside plan"])
        XCTAssertNil(vm.logResults["Server only"])
        vm.restoreLogResults(from: data, serverSessionType: "morning", serverCompleted: true)
        vm.applyCompletedSessionRecoveryPolicy()
        XCTAssertEqual(preparationBytes(date), before)
        XCTAssertEqual(Set(vm.logResults.keys), ["Outside plan"])
    }

    func testPassiveUserEditsPersistWithoutTimingAndKeepOtherSource() throws {
        let date = "local-edit-\(UUID().uuidString)"
        defer {
            SessionDraftStore.clear(date: date, sessionType: "morning")
            SessionDraftStore.clear(date: date, sessionType: "evening")
        }
        seedPreparationRecovery(date, source: "morning", weight: 80, name: "Outside plan")
        seedPreparationRecovery(date, source: "evening", weight: 60)
        let eveningBefore = SessionDraftStore.load(date: date, sessionType: "evening")
        let vm = SeanceViewModel(draftSessionType: "morning")
        try prepare(vm, extraData(date))
        let generation = try XCTUnwrap(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning")?.generation)
        vm.logResults["Bench Press"] = .init(name: "Bench Press", weight: 85, reps: "6")
        XCTAssertEqual(Set(SessionDraftStore.load(date: date, sessionType: "morning").map(\.name)), ["Outside plan", "Bench Press"])
        XCTAssertEqual(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning")?.generation, generation + 1)
        vm.sessionComment = "Edited"
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "morning"), "Edited")
        vm.sessionComment = ""
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "morning"), "")
        vm.logResults = [:] // Explicit undo must not clear timing metadata either.
        XCTAssertEqual(SessionDraftStore.loadStartedAt(date: date, sessionType: "morning"), Date(timeIntervalSince1970: 100))
        XCTAssertEqual(SessionDraftStore.loadChronoPausedDuration(date: date, sessionType: "morning"), 12)
        XCTAssertTrue(SessionDraftStore.loadChronoIsPaused(date: date, sessionType: "morning"))
        XCTAssertEqual(SessionDraftStore.loadChronoPausedAt(date: date, sessionType: "morning"), Date(timeIntervalSince1970: 200))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(SessionDraftStore.load(date: date, sessionType: "evening")),
                       try encoder.encode(eveningBefore))
        XCTAssertFalse(vm.chrono.hasTimingContext)
        XCTAssertFalse(vm.sessionStarted)
    }

    func testPassivePrepareValidationAndReprepareAreMutationFree() throws {
        let date = "context-\(UUID().uuidString)"
        let data = try extraData(date)
        let before = preparationBytes(date)
        let vm = SeanceViewModel(draftSessionType: "morning")
        for (source, suppliedDate, session, token) in [
            ("bonus", date, data.today, "X"), ("evening", date, data.today, "X"),
            ("morning", "", data.today, "X"), ("morning", "other", data.today, "X"),
            ("morning", date, "Other session", "X"), ("morning", date, data.today, "")
        ] {
            XCTAssertThrowsError(try vm.prepareForDayComposer(data: data, sessionDate: suppliedDate,
                source: source, sessionName: session, contextToken: token, recoveryAdmission: .allowCurrentScopedRecovery))
            XCTAssertNil(vm.seanceData)
            XCTAssertFalse(vm.isDayComposerLocal)
        }
        try prepare(vm, data)
        XCTAssertThrowsError(try prepare(vm, data)) // Explicit harmless rejection, not rehydration.
        XCTAssertThrowsError(try prepare(vm, data, token: "different-program-or-plan"))
        XCTAssertThrowsError(try prepare(vm, extraData("other-date")))
        vm.seanceData = try extraData("other-date")
        vm.draftSessionType = "evening"
        XCTAssertEqual(vm.seanceData?.todayDate, date)
        XCTAssertEqual(vm.draftSessionType, "morning")
        XCTAssertEqual(preparationBytes(date), before)
        let classic = SeanceViewModel(draftSessionType: "morning")
        classic.seanceData = data
        XCTAssertThrowsError(try prepare(classic, data))
        XCTAssertFalse(classic.isDayComposerLocal)
    }

    func testPassiveFirstLogPersistsWithoutStartingEitherOwnerClock() throws {
        let date = "first-local-\(UUID().uuidString)"
        defer {
            SessionDraftStore.clear(date: date, sessionType: "morning")
            SessionDraftStore.clear(date: date, sessionType: "evening")
        }
        let morning = SeanceViewModel(draftSessionType: "morning")
        let evening = SeanceSoirViewModel()
        try prepare(morning, extraData(date))
        try prepare(evening, extraData(date))
        XCTAssertNil(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning"))
        XCTAssertNil(SessionDraftStore.recoveryProtection(date: date, sessionType: "evening"))
        morning.logResults["A"] = .init(name: "A", weight: 80, reps: "5")
        evening.logResults["B"] = .init(name: "B", weight: 60, reps: "8", isSecond: true)
        for vm in [morning, evening] {
            XCTAssertEqual(SessionDraftStore.recoveryProtection(date: date, sessionType: vm.draftSessionType)?.generation, 1)
            XCTAssertNil(SessionDraftStore.loadStartedAt(date: date, sessionType: vm.draftSessionType))
            XCTAssertFalse(vm.chrono.hasTimingContext)
            XCTAssertFalse(vm.sessionStarted)
        }
        let restoredMorning = SeanceViewModel(draftSessionType: "morning")
        let restoredEvening = SeanceSoirViewModel()
        let before = preparationBytes(date)
        try prepare(restoredMorning, extraData(date))
        try prepare(restoredEvening, extraData(date))
        XCTAssertEqual(Set(restoredMorning.logResults.keys), ["A"])
        XCTAssertEqual(Set(restoredEvening.logResults.keys), ["B"])
        XCTAssertEqual(preparationBytes(date), before)
    }

    func testPassiveFinishAndPartialEveningAreBlockedBeforeNetwork() async throws {
        let date = "no-finalize-\(UUID().uuidString)"
        defer {
            SessionDraftStore.clear(date: date, sessionType: "morning")
            SessionDraftStore.clear(date: date, sessionType: "evening")
        }
        seedPreparationRecovery(date, source: "morning", weight: 80)
        seedPreparationRecovery(date, source: "evening", weight: 60)
        let before = preparationBytes(date)
        let morning = PassiveMorningSpy(draftSessionType: "morning")
        let evening = PassiveEveningSpy()
        try prepare(morning, extraData(date))
        try prepare(evening, extraData(date))
        for vm in [morning as SeanceViewModel, evening] {
            vm.startSession()
            await vm.finish(rpe: 7, comment: vm.sessionComment)
            await vm.retryFinish(comment: "Retry")
            let accepted = await vm.saveExercisesForFinish()
            XCTAssertFalse(accepted)
            vm.showSuccess = true
            XCTAssertFalse(vm.showSuccess)
            XCTAssertFalse(vm.isFinishing)
            XCTAssertFalse(vm.canRetryFinish)
            XCTAssertNil(vm.finishSourceDate)
            XCTAssertFalse(vm.chrono.hasTimingContext)
            XCTAssertNotNil(vm.submitError)
        }
        await evening.finish(rpe: 7, comment: "Partial", closeSession: false)
        XCTAssertFalse(evening.partialSaveAccepted)
        XCTAssertEqual(morning.externalCalls + evening.externalCalls, 0)
        XCTAssertEqual(preparationBytes(date), before)
    }

    // MARK: - Helpers

    private func makeViewModel(cacheData: Data? = nil, cacheKey: String = "seance_data") -> SeanceViewModel {
        let cache = makeTempCacheService()
        if let data = cacheData {
            cache.save(data, for: cacheKey)
        }
        let vm = SeanceViewModel(draftSessionType: "morning")
        vm.cacheService = cache
        return vm
    }

    // MARK: - Tests

    private final class BonusOutcomeStub: BonusSeanceViewModel {
        var response: Data? = Data(#"{"success":true}"#.utf8)
        var failure: Int?
        var failExercise = false
        var sessionComments: [String] = []
        var sessionLogs: [[[String: Any]]] = []
        var sentExercises: [ExerciseLogResult] = []
        var recorded = 0

        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome {
            sentExercises.append(result)
            if failExercise { throw APIError.serverError(500, "Exercise failure") }
            return .queuedOffline
        }

        override func sendBonusSession(exos: [String], rpe: Double, comment: String,
                                       durationMin: Double?, energyPre: Int?,
                                       exerciseLogs: [[String: Any]]) async throws -> SessionSaveOutcome {
            sessionComments.append(comment)
            sessionLogs.append(exerciseLogs)
            return try await SessionSaveOutcome.fromOfflinePost {
                if let failure = self.failure { throw APIError.serverError(failure, "Injected") }
                return self.response
            }
        }

        override func refreshBonusDashboard() async {}
        override func recordBonusWorkout() async { recorded += 1 }
    }

    func testBonusFinalOutcomesPreserveRecoveryAndGateHealthKit() async throws {
        let responses: [Data?] = [Data(#"{"success":true}"#.utf8), nil,
                                 Data(#"{"success":false}"#.utf8), Data("invalid".utf8)]
        for (index, response) in responses.enumerated() {
            let date = "bonus-outcome-\(UUID().uuidString)"
            defer { SessionDraftStore.clear(date: date, sessionType: "bonus") }
            let vm = BonusOutcomeStub()
            vm.seanceData = try extraData(date)
            vm.logResults["Bench Press"] = recoveryLog()
            vm.sessionComment = "Latest"
            // A previously observed completion must not acknowledge this local generation.
            vm.restoreLogResults(from: try extraData(date), serverSessionType: "bonus", serverCompleted: true)
            let generation = SessionDraftStore.bonusProtection(date: date)?.generation
            vm.response = response
            await vm.finish(rpe: 7, comment: vm.sessionComment)
            XCTAssertEqual(vm.showSuccess, index == 0)
            XCTAssertEqual(vm.isSessionQueued, index == 1)
            XCTAssertEqual(vm.recorded, index == 0 ? 1 : 0)
            XCTAssertEqual(vm.submitError != nil, index >= 2)
            XCTAssertFalse(vm.isFinishing)
            XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, generation)
            XCTAssertEqual(SessionDraftStore.load(date: date, sessionType: "bonus").count, 1)
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "bonus"), "Latest")
            if index == 1 {
                await vm.retryFinish(comment: "Do not enqueue again")
                await vm.finish(rpe: 7, comment: "Do not enqueue again")
                XCTAssertEqual(vm.sessionComments.count, 1)
                XCTAssertEqual(vm.sentExercises.count, 1)
                XCTAssertEqual(vm.recorded, 0)
            } else if index >= 2 {
                XCTAssertTrue(vm.canRetryFinish)
            }
        }
    }

    func testBonusFinalFailureRetryUsesCurrentPayloadAndComment() async throws {
        let date = "bonus-retry-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "bonus") }
        let vm = BonusOutcomeStub()
        vm.seanceData = try extraData(date)
        vm.logResults["Bench Press"] = recoveryLog()
        vm.response = Data(#"{"success":false}"#.utf8)
        await vm.finish(rpe: 7, comment: "First")
        XCTAssertNotNil(vm.submitError)
        XCTAssertEqual(vm.recorded, 0)
        var changed = recoveryLog()
        changed.notes = "Updated exercise note"
        vm.logResults[changed.name] = changed
        vm.sessionComment = "Latest"
        vm.response = Data(#"{"success":true}"#.utf8)
        await vm.retryFinish(comment: vm.sessionComment)
        XCTAssertEqual(vm.sessionComments, ["First", "Latest"])
        XCTAssertEqual(vm.sentExercises.count, 2)
        XCTAssertEqual(vm.sentExercises.last?.notes, "Updated exercise note")
        XCTAssertEqual(vm.sessionLogs.last?.first?["exercise"] as? String, changed.name)
        XCTAssertTrue(vm.showSuccess)
        XCTAssertFalse(vm.isSessionQueued)
        XCTAssertNil(vm.submitError)
        XCTAssertEqual(vm.recorded, 1)
        XCTAssertEqual(SessionDraftStore.load(date: date, sessionType: "bonus").first?.notes, changed.notes)
    }

    func testBonusHTTPFailureRetryToQueueDoesNotResendAcceptedExercises() async throws {
        let date = "bonus-retry-queue-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "bonus") }
        let vm = BonusOutcomeStub()
        vm.seanceData = try extraData(date)
        vm.logResults["Bench Press"] = recoveryLog()
        vm.failure = 500
        await vm.finish(rpe: 7, comment: "First")
        XCTAssertNotNil(vm.submitError)
        XCTAssertFalse(vm.showSuccess)
        XCTAssertFalse(vm.isSessionQueued)
        vm.failure = nil
        vm.response = nil
        await vm.retryFinish(comment: "New comment")
        XCTAssertEqual(vm.sessionComments, ["First", "New comment"])
        XCTAssertEqual(vm.sentExercises.count, 1)
        XCTAssertTrue(vm.isSessionQueued)
        XCTAssertFalse(vm.showSuccess)
        XCTAssertNil(vm.submitError)
        XCTAssertEqual(vm.recorded, 0)
        await vm.retryFinish(comment: "No duplicate")
        XCTAssertEqual(vm.sessionComments.count, 2)
    }

    func testBonusExerciseFailureStillBlocksFinalOutcomePath() async throws {
        let date = "bonus-gate-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "bonus") }
        let vm = BonusOutcomeStub()
        vm.seanceData = try extraData(date)
        vm.logResults["Bench Press"] = recoveryLog()
        vm.failExercise = true
        await vm.finish(rpe: 7, comment: "Blocked")
        XCTAssertTrue(vm.sessionComments.isEmpty)
        XCTAssertNotNil(vm.submitError)
        XCTAssertFalse(vm.showSuccess)
        XCTAssertFalse(vm.isSessionQueued)
        XCTAssertEqual(vm.recorded, 0)
    }

    func testTrustedBonusMetadataAndFallbackRoundTrip() throws {
        for trusted in [false, true] {
            let date = "metadata-\(UUID().uuidString)"
            defer { SessionDraftStore.clear(date: date, sessionType: "bonus") }
            let metadata = trusted ? ExerciseReconstructionMetadata(
                scheme: "4x6", trackingType: "reps", isUnilateral: false) : nil
            let exercise = ExerciseViewModel(name: "Bench Press", scheme: trusted ? "4x6" : "3x8-12",
                weightData: nil, equipmentType: "machine", isBonusSession: true,
                sessionDate: date, reconstructionMetadata: metadata)
            exercise.sets = [SetInput(weight: "100", reps: "6", rir: 2, rpe: 8)]
            let log = try XCTUnwrap(exercise.logExercise(alreadyLoggedViaBinding: false))
            let owner = ExtraSessionViewModel()
            XCTAssertTrue(owner.adoptSelectedData(try extraData(date)))
            owner.logResults[log.name] = log
            let persisted = try XCTUnwrap(SessionDraftStore.load(date: date, sessionType: "bonus").first)
            XCTAssertEqual(persisted.scheme, trusted ? "4x6" : nil)
            XCTAssertEqual(persisted.trackingType, trusted ? "reps" : nil)
            XCTAssertEqual(persisted.isUnilateral, trusted ? false : nil)
            let reopened = BonusSeanceViewModel()
            reopened.restoreLogResults(from: try extraData(date), serverSessionType: "bonus", serverCompleted: nil)
            let restored = try XCTUnwrap(reopened.logResults[log.name])
            XCTAssertEqual(restored.scheme, persisted.scheme)
            XCTAssertEqual(restored.trackingType, persisted.trackingType)
            XCTAssertEqual(restored.isUnilateral, persisted.isUnilateral)
            XCTAssertEqual(restored.equipmentType, "machine")
        }
    }

    func testIntrinsicTimeAndPlyoMetadataRoundTrip() throws {
        for mode in ["time", "plyo"] {
            let date = "metadata-special-\(UUID().uuidString)"
            defer { SessionDraftStore.clear(date: date, sessionType: "bonus") }
            let exercise = ExerciseViewModel(name: "Special", scheme: "3x8-12", weightData: nil,
                equipmentType: "bodyweight", trackingType: mode, isBonusSession: true, sessionDate: date)
            exercise.sets = [SetInput(weight: "0", reps: "5", duration: 20, intensity: "10")]
            let log = try XCTUnwrap(exercise.logExercise(alreadyLoggedViaBinding: false))
            XCTAssertEqual(log.trackingType, mode)
            XCTAssertNil(log.scheme)
            XCTAssertNil(log.isUnilateral)
            let owner = ExtraSessionViewModel()
            XCTAssertTrue(owner.adoptSelectedData(try extraData(date)))
            owner.logResults[log.name] = log
            let reopened = BonusSeanceViewModel()
            reopened.restoreLogResults(from: try extraData(date), serverSessionType: "bonus", serverCompleted: nil)
            XCTAssertEqual(reopened.logResults[log.name]?.trackingType, mode)
        }
    }

    func testLegacyMetadataDecodeAndResolution() throws {
        let json = #"{"name":"Bench Press","weight":100,"reps":"8","isSecond":false,"isBonus":true,"equipmentType":"machine","painZone":"","sets":[]}"#
        let legacy = try JSONDecoder().decode(PersistedExerciseLogResult.self, from: Data(json.utf8))
        XCTAssertNil(legacy.scheme)
        XCTAssertNil(legacy.trackingType)
        XCTAssertNil(legacy.isUnilateral)
        let log = recoveryLog()
        XCTAssertNotNil(recoveryConfig(log.name, log))
        XCTAssertNil(BonusRecoveryConfiguration.resolve(name: log.name, log: log,
            schemes: [], equipment: [], tracking: [], unilateral: []))
    }

    func testHistoricalMetadataPriorityAndPartialCompletion() throws {
        var log = recoveryLog()
        log.scheme = "4x6"
        log.trackingType = "reps"
        log.isUnilateral = false
        let noCatalog = BonusRecoveryPresentation.reconcile(order: [], snapshotOrder: [log.name],
            local: [:], logs: [log.name: log], resolve: { name, log in
                BonusRecoveryConfiguration.resolve(name: name, log: log, schemes: [],
                    equipment: [], tracking: [], unilateral: [])
            }, displayWeight: { $0 })
        guard case .editable(_, .some(_)) = noCatalog.first?.content else {
            return XCTFail("Complete history must resolve without catalogue")
        }
        let conflict = try XCTUnwrap(BonusRecoveryConfiguration.resolve(name: log.name, log: log,
            schemes: ["9x9"], equipment: ["barbell"], tracking: ["time"], unilateral: [true]))
        XCTAssertEqual(conflict.scheme, "4x6")
        XCTAssertEqual(conflict.tracking, "reps")
        XCTAssertFalse(conflict.unilateral)
        log.scheme = nil
        log.isUnilateral = nil
        let partial = try XCTUnwrap(BonusRecoveryConfiguration.resolve(name: log.name, log: log,
            schemes: ["3x8"], equipment: ["machine"], tracking: ["time"], unilateral: [false]))
        XCTAssertEqual(partial.scheme, "3x8")
        XCTAssertEqual(partial.tracking, "reps")
        log.scheme = "4x6"
        log.isUnilateral = true
        log.trackingType = "time"
        let historicalTime = try XCTUnwrap(BonusRecoveryConfiguration.resolve(name: log.name, log: log,
            schemes: ["3x8"], equipment: ["machine"], tracking: ["reps"], unilateral: [false]))
        XCTAssertEqual(historicalTime.tracking, "time")
        XCTAssertNil(ExerciseRecoveryHydration.make(log, equipment: historicalTime.equipment,
            tracking: historicalTime.tracking, unilateral: historicalTime.unilateral, displayWeight: { $0 }))
    }

    func testFutureMetadataRestoreDoesNotDirtyAfterDebounce() async throws {
        let date = "metadata-no-dirty-\(UUID().uuidString)"
        let cardStore = ExerciseDraftPersistence(date: date, sessionType: "bonus", exerciseName: "Bench Press")
        defer { cardStore.clear(); SessionDraftStore.clear(date: date, sessionType: "bonus") }
        var log = recoveryLog()
        log.scheme = "4x6"
        log.trackingType = "reps"
        log.isUnilateral = false
        let owner = ExtraSessionViewModel()
        XCTAssertTrue(owner.adoptSelectedData(try extraData(date)))
        owner.logResults[log.name] = log
        owner.sessionComment = "Unchanged"
        let generation = SessionDraftStore.bonusProtection(date: date)?.generation
        let before = try JSONEncoder().encode(SessionDraftStore.load(date: date, sessionType: "bonus"))
        let reopened = BonusSeanceViewModel()
        reopened.seanceData = try extraData(date)
        reopened.restoreLogResults(from: try extraData(date), serverSessionType: "bonus", serverCompleted: nil)
        let restored = try XCTUnwrap(reopened.logResults[log.name])
        let config = try XCTUnwrap(BonusRecoveryConfiguration.resolve(name: log.name, log: restored,
            schemes: [], equipment: [], tracking: [], unilateral: []))
        let exercise = ExerciseViewModel(name: log.name, scheme: config.scheme, weightData: nil,
            equipmentType: config.equipment, isBonusSession: true, sessionDate: date)
        exercise.initializeRecovery(try XCTUnwrap(ExerciseRecoveryHydration.make(restored,
            equipment: config.equipment, tracking: config.tracking, unilateral: config.unilateral, displayWeight: { $0 })))
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertNil(cardStore.loadCard())
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, generation)
        let after = try JSONEncoder().encode(SessionDraftStore.load(date: date, sessionType: "bonus"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: before) as? NSArray,
                       try JSONSerialization.jsonObject(with: after) as? NSArray)
        XCTAssertEqual(reopened.logResults[log.name]?.scheme, "4x6")
        XCTAssertEqual(reopened.logResults[log.name]?.notes, log.notes)
        XCTAssertEqual(reopened.sessionComment, "Unchanged")
    }

    private func recoveryLog(_ name: String = "Bench Press") -> ExerciseLogResult {
        ExerciseLogResult(name: name, weight: 100, reps: "8", rpe: 8,
            sets: [["weight": 100.0, "reps": "8", "rir": 2, "rpe": 8.0]],
            isBonus: true, equipmentType: "machine", notes: "Note récupérée")
    }

    private func recoveryConfig(_ name: String, _ log: ExerciseLogResult) -> BonusRecoveryConfiguration? {
        BonusRecoveryConfiguration.resolve(name: name, log: log, schemes: ["3x8"],
            equipment: ["machine"], tracking: ["reps"], unilateral: [false])
    }

    func testBonusRecoveryResolvedAndConflictingConfiguration() throws {
        let log = recoveryLog()
        let config = try XCTUnwrap(recoveryConfig(log.name, log))
        let hydration = try XCTUnwrap(ExerciseRecoveryHydration.make(log,
            equipment: config.equipment, tracking: config.tracking,
            unilateral: config.unilateral, displayWeight: { $0 }))
        XCTAssertEqual(hydration.sets.count, 1) // Not expanded to the three-set scheme.
        XCTAssertEqual(hydration.sets[0].weight, "100.0")
        XCTAssertEqual(hydration.sets[0].reps, "8")
        XCTAssertEqual(hydration.sets[0].rir, 2)
        XCTAssertEqual(hydration.sets[0].rpe, 8)
        XCTAssertEqual(hydration.note, log.notes)
        XCTAssertNil(BonusRecoveryConfiguration.resolve(name: log.name, log: log,
            schemes: ["3x8", "4x10"], equipment: ["machine"], tracking: ["reps"], unilateral: [false]))
        XCTAssertNil(BonusRecoveryConfiguration.resolve(name: log.name, log: log,
            schemes: ["3x8"], equipment: ["machine"], tracking: ["reps", "time"], unilateral: [false]))
        XCTAssertNil(BonusRecoveryConfiguration.resolve(name: log.name, log: log,
            schemes: ["3x8"], equipment: ["machine"], tracking: ["reps"], unilateral: []))
        var incomplete = log
        incomplete.sets[0].removeValue(forKey: "rir")
        XCTAssertNil(ExerciseRecoveryHydration.make(incomplete, equipment: "machine",
            tracking: "reps", unilateral: false, displayWeight: { $0 }))
        let conflict = BonusRecoveryPresentation.reconcile(order: [], snapshotOrder: [log.name],
            local: [:], logs: [log.name: log], resolve: { _, _ in nil }, displayWeight: { $0 })
        guard case .recoveredReadOnly = conflict.first?.content else { return XCTFail("Conflict must stay visible") }
    }

    func testBonusRecoveryMergeIdempotenceAndReadOnlyEmptyState() {
        let logs = ["B": recoveryLog("B"), "C": recoveryLog("C")]
        func reconcile() -> [BonusVisibleExercise] {
            BonusRecoveryPresentation.reconcile(order: ["A", "B"], snapshotOrder: ["B", "C"],
                local: ["A": "3x8", "B": "3x8"], logs: logs,
                resolve: { name, log in name == "B" ? self.recoveryConfig(name, log) : nil },
                displayWeight: { $0 })
        }
        let first = reconcile()
        XCTAssertEqual(first.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(reconcile().map(\.id), first.map(\.id))
        guard case .editable(_, .some(_)) = first[1].content else { return XCTFail("B must be editable") }
        guard case .recoveredReadOnly = first[2].content else { return XCTFail("C must remain visible") }
        let readOnly = BonusRecoveryPresentation.reconcile(order: [], snapshotOrder: ["C"], local: [:],
            logs: ["C": recoveryLog("C")], resolve: { _, _ in nil }, displayWeight: { $0 })
        XCTAssertFalse(readOnly.isEmpty)
        XCTAssertEqual(logs["C"]?.notes, "Note récupérée")
    }

    func testBonusSpecializedRecoverySummaryPreservesFieldsAndZero() {
        var log = recoveryLog()
        log.trackingType = "time"
        log.sets = [["weight": 0.0, "reps": "20", "left": ["time": 0],
                     "right": ["time": 20], "distance_m": 15, "intensity": 0.0]]
        let before = NSDictionary(dictionary: log.sets[0])
        let summary = BonusRecoveryPresentation.summary(log).joined(separator: "\n")
        XCTAssertTrue(summary.contains("Gauche : 0 s"))
        XCTAssertTrue(summary.contains("Droite : 20 s"))
        XCTAssertTrue(summary.contains("Distance : 15 m"))
        XCTAssertTrue(summary.contains("Intensité : 0"))
        XCTAssertTrue(summary.contains("Valeur enregistrée"))
        XCTAssertTrue(summary.contains(log.notes))
        XCTAssertFalse(summary.contains("Protocole complété"))
        XCTAssertEqual(before, NSDictionary(dictionary: log.sets[0]))
        XCTAssertNil(ExerciseRecoveryHydration.make(log, equipment: "machine",
            tracking: "time", unilateral: true, displayWeight: { $0 }))
    }

    func testBonusRecoveryHydrationDoesNotSaveAfterDebounceAndPreservesEdits() async throws {
        let date = "recovery-hydration-\(UUID().uuidString)"
        let log = recoveryLog()
        let store = ExerciseDraftPersistence(date: date, sessionType: "bonus", exerciseName: log.name)
        defer { store.clear(); SessionDraftStore.clear(date: date, sessionType: "bonus") }
        let owner = ExtraSessionViewModel()
        XCTAssertTrue(owner.adoptSelectedData(try extraData(date)))
        owner.logResults[log.name] = log
        let generation = SessionDraftStore.bonusProtection(date: date)?.generation
        let evm = ExerciseViewModel(name: log.name, scheme: "3x8", weightData: nil,
            equipmentType: "machine", isBonusSession: true, sessionDate: date)
        let hydration = try XCTUnwrap(ExerciseRecoveryHydration.make(log, equipment: "machine",
            tracking: "reps", unilateral: false, displayWeight: { $0 }))
        evm.initializeRecovery(hydration)
        evm.syncSetsCount()
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertNil(store.loadCard())
        XCTAssertNil(evm.draftSavedAt)
        XCTAssertEqual(evm.sets.count, 1)
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, generation)
        XCTAssertEqual(owner.logResults[log.name]?.notes, log.notes)
        evm.sets[0].reps = "9"
        evm.sessionNote = "Édition réelle"
        evm.initializeRecovery(hydration)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(evm.sets[0].reps, "9")
        XCTAssertEqual(store.loadCard()?.sets[0].reps, "9")
        XCTAssertEqual(store.loadCard()?.sessionNote, "Édition réelle")
        let recreated = ExerciseViewModel(name: log.name, scheme: "3x8", weightData: nil,
            equipmentType: "machine", isBonusSession: true, sessionDate: date)
        recreated.initializeRecovery(hydration)
        XCTAssertEqual(recreated.sets[0].reps, "9")
        XCTAssertEqual(recreated.sessionNote, "Édition réelle")
    }

    func testExtraToBonusRecoveryPresentationAndExplicitClear() throws {
        let date = "recovery-cross-entry-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "bonus") }
        let extra = ExtraSessionViewModel()
        XCTAssertTrue(extra.adoptSelectedData(try extraData(date)))
        extra.logResults["Bench Press"] = recoveryLog()
        extra.sessionComment = "Commentaire conservé"
        let bonus = BonusSeanceViewModel()
        bonus.seanceData = try extraData(date)
        bonus.restoreLogResults(from: try extraData(date), serverSessionType: "bonus", serverCompleted: true)
        let generation = SessionDraftStore.bonusProtection(date: date)?.generation
        func visible(_ vm: SeanceViewModel) -> [BonusVisibleExercise] {
            BonusRecoveryPresentation.reconcile(order: [],
                snapshotOrder: SessionDraftStore.load(date: date, sessionType: "bonus").map(\.name),
                local: [:], logs: vm.logResults, resolve: { _, _ in nil }, displayWeight: { $0 })
        }
        XCTAssertEqual(visible(bonus).map(\.id), ["Bench Press"])
        XCTAssertEqual(visible(bonus).map(\.id), visible(bonus).map(\.id))
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, generation)
        XCTAssertEqual(bonus.sessionComment, "Commentaire conservé")
        SessionDraftStore.clear(date: date, sessionType: "bonus")
        let reopened = BonusSeanceViewModel()
        reopened.seanceData = try extraData(date)
        reopened.restoreLogResults(from: try extraData(date), serverSessionType: "bonus", serverCompleted: nil)
        XCTAssertTrue(visible(reopened).isEmpty)
    }

    func testExtraSharedCommentPrefillRoundTripAndRecreation() throws {
        let date = "extra-comment-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "bonus") }
        SessionDraftStore.saveComment("A", date: date, sessionType: "bonus")
        let generation = SessionDraftStore.bonusProtection(date: date)?.generation
        let vm = ExtraSessionViewModel()
        XCTAssertTrue(vm.adoptSelectedData(try extraData(date)))
        // Both live surfaces bind the same property, not independently restored copies.
        let workout = Binding(get: { vm.sessionComment }, set: { vm.sessionComment = $0 })
        let exitSheet = Binding(get: { vm.sessionComment }, set: { vm.sessionComment = $0 })
        XCTAssertEqual(exitSheet.wrappedValue, "A")
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, generation)
        exitSheet.wrappedValue = "B"
        XCTAssertEqual(workout.wrappedValue, "B")
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "bonus"), "B")
        workout.wrappedValue = "C"
        XCTAssertEqual(exitSheet.wrappedValue, "C")
        exitSheet.wrappedValue = "Voyage — séance adaptée"
        let savedGeneration = SessionDraftStore.bonusProtection(date: date)?.generation
        // Recreate before any finish submission, including the dedicated Bonus entry.
        let reopened = ExtraSessionViewModel()
        XCTAssertTrue(reopened.adoptSelectedData(try extraData(date)))
        let bonus = BonusSeanceViewModel()
        bonus.seanceData = try extraData(date)
        XCTAssertEqual(reopened.sessionComment, "Voyage — séance adaptée")
        XCTAssertEqual(bonus.sessionComment, reopened.sessionComment)
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "bonus"), reopened.sessionComment)
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, savedGeneration)
    }

    func testSharedExitCommentFinishRetryEmptyAndClear() async throws {
        for type in ["morning", "evening", "bonus"] {
            let date = "exit-retry-\(UUID().uuidString)"
            defer { SessionDraftStore.clear(date: date, sessionType: type) }
            let vm = CommentRetryProbe(draftSessionType: type)
            vm.seanceData = try extraData(date)
            vm.sessionComment = "A"
            await vm.finish(rpe: 7, comment: vm.sessionComment)
            XCTAssertEqual(vm.receivedComment, "A")
            vm.prepareFinishRetry(rpe: 7, comment: vm.sessionComment, durationMin: nil,
                energyPre: nil, sessionName: nil, bonusSession: type == "bonus", closeSession: true)
            vm.submitError = "Échec simulé"
            let sheet = Binding(get: { vm.sessionComment }, set: { vm.sessionComment = $0 })
            sheet.wrappedValue = "B"
            await vm.retryFinish(comment: vm.sessionComment)
            XCTAssertEqual(vm.receivedComment, "B")
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: type), "B")
            sheet.wrappedValue = ""
            await vm.retryFinish(comment: vm.sessionComment)
            XCTAssertEqual(vm.receivedComment, "")
            let reopened = SeanceViewModel(draftSessionType: type)
            reopened.seanceData = try extraData(date)
            XCTAssertEqual(reopened.sessionComment, "")
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: type), "")
            sheet.wrappedValue = "À effacer"
            SessionDraftStore.clear(date: date, sessionType: type)
            vm.restoreSessionComment() // Same refresh used by confirmed workout clear actions.
            XCTAssertEqual(sheet.wrappedValue, "")
            XCTAssertNil(SessionDraftStore.loadComment(date: date, sessionType: type))
            XCTAssertNil(SessionDraftStore.recoveryProtection(date: date, sessionType: type))
            reopened.seanceData = try extraData(date)
            XCTAssertEqual(reopened.sessionComment, "")
        }
    }

    func testRemainingWorkoutCommentUsesLoadedDateAndActualSessionType() throws {
        let date = "remaining-comment-\(UUID().uuidString)"
        let otherDate = "other-\(date)"
        for (type, value) in [("morning", "A"), ("evening", "B"), ("bonus", "C")] {
            SessionDraftStore.saveComment(value, date: date, sessionType: type)
        }
        defer {
            for type in ["morning", "evening", "bonus"] {
                SessionDraftStore.clear(date: date, sessionType: type)
                SessionDraftStore.clear(date: otherDate, sessionType: type)
            }
        }
        for (type, value) in [("morning", "A"), ("evening", "B"), ("bonus", "C")] {
            // FinishRemainingSheet constructs this VM with its supplied sessionType.
            let vm = SeanceViewModel(draftSessionType: type)
            vm.seanceData = try extraData(date)
            XCTAssertEqual(vm.sessionComment, value)
            vm.sessionComment = value + " modifié"
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: type), value + " modifié")
            vm.seanceData = try extraData(otherDate)
            XCTAssertEqual(vm.sessionComment, "")
            XCTAssertNil(SessionDraftStore.loadComment(date: otherDate, sessionType: type))
            XCTAssertNil(SessionDraftStore.recoveryProtection(date: otherDate, sessionType: type))
            vm.seanceData = try extraData(date)
            XCTAssertEqual(vm.sessionComment, value + " modifié")
        }
    }

    func testMorningPriorCompletionPreservesCommentThroughConflictAndCompletionPolicy() throws {
        let date = "morning-comment-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "morning") }
        let vm = SeanceViewModel(draftSessionType: "morning")
        let data = try extraData(date)
        vm.seanceData = data
        vm.restoreLogResults(from: data, serverSessionType: "morning", serverCompleted: true)
        let comment = "Nouvelle note après completion"
        SessionDraftStore.saveComment(comment, date: date, sessionType: "morning")
        let protection = try XCTUnwrap(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning"))
        XCTAssertTrue(protection.hasUnacknowledgedLocalChanges)
        XCTAssertFalse(vm.handleFinishConflict())
        XCTAssertNotNil(vm.submitError)
        XCTAssertFalse(vm.showSuccess)
        vm.applyCompletedSessionRecoveryPolicy()
        XCTAssertTrue(vm.commitWarning?.contains("synchronisation n’est pas confirmée") == true)
        vm.restoreLogResults(from: data, serverSessionType: "morning", serverCompleted: true)
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "morning"), comment)
        XCTAssertEqual(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning")?.generation, protection.generation)
        XCTAssertFalse(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "morning"))
    }

    func testMorningNewLogAfterCompletionSurvivesRecreation() throws {
        let date = "morning-log-\(UUID().uuidString)"
        let vm = SeanceViewModel(draftSessionType: "morning")
        let reopened = SeanceViewModel(draftSessionType: "morning")
        defer {
            _ = vm.chrono.stop(); _ = reopened.chrono.stop()
            SessionDraftStore.clear(date: date, sessionType: "morning")
        }
        let data = try extraData(date)
        vm.seanceData = data
        vm.restoreLogResults(from: data, serverSessionType: "morning", serverCompleted: true)
        vm.logResults["Bench Press"] = ExerciseLogResult(name: "Bench Press", weight: 85, reps: "6", rpe: 8,
            sets: [["weight": 85.0, "reps": "6", "rir": 2, "rpe": 8.0]], notes: "Nouvelle note", trackingType: "reps")
        vm.logResults["Carry"] = ExerciseLogResult(name: "Carry", weight: 20, reps: "",
            sets: [["weight": 20.0, "distance_m": 30]], trackingType: "carry")
        SessionDraftStore.saveComment("Après completion", date: date, sessionType: "morning")
        let generation = SessionDraftStore.recoveryProtection(date: date, sessionType: "morning")?.generation
        vm.applyCompletedSessionRecoveryPolicy()
        reopened.seanceData = data
        reopened.restoreLogResults(from: data, serverSessionType: "morning", serverCompleted: true)
        XCTAssertEqual(reopened.logResults["Bench Press"]?.notes, "Nouvelle note")
        XCTAssertEqual(reopened.logResults["Bench Press"]?.weight, 85)
        XCTAssertEqual(reopened.logResults["Bench Press"]?.sets.first?["rir"] as? Int, 2)
        XCTAssertEqual(reopened.logResults["Carry"]?.sets.first?["distance_m"] as? Int, 30)
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "morning"), "Après completion")
        XCTAssertEqual(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning")?.generation, generation)
        XCTAssertFalse(reopened.handleFinishConflict())
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "morning"))
    }

    func testMorningLegacyRecoveryAndExplicitClearRemainTypeScoped() throws {
        let date = "morning-legacy-\(UUID().uuidString)"
        let vm = SeanceViewModel(draftSessionType: "morning")
        defer {
            _ = vm.chrono.stop()
            for type in ["morning", "evening", "bonus"] { SessionDraftStore.clear(date: date, sessionType: type) }
        }
        let legacy = [PersistedExerciseLogResult(name: "Bench Press", weight: 80, reps: "5", rpe: nil,
            isSecond: false, isBonus: false, equipmentType: "", painZone: "", sets: [])]
        let raw = try APIService.encoder.encode(legacy)
        UserDefaults.standard.set(raw, forKey: "session_draft_morning_\(date)")
        let data = try extraData(date)
        vm.seanceData = data
        vm.restoreLogResults(from: data, serverSessionType: "morning", serverCompleted: true)
        XCTAssertNil(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning"))
        XCTAssertEqual(UserDefaults.standard.data(forKey: "session_draft_morning_\(date)"), raw)
        XCTAssertFalse(vm.handleFinishConflict())
        for type in ["evening", "bonus"] {
            XCTAssertTrue(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: type))
            SessionDraftStore.saveComment(type, date: date, sessionType: type)
        }
        SessionDraftStore.saveComment("Morning", date: date, sessionType: "morning")
        SessionDraftStore.clearLogs(date: date, sessionType: "morning")
        XCTAssertFalse(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "morning"))
        SessionDraftStore.saveStartedAt(date: date, sessionType: "morning", startedAt: Date())
        SessionDraftStore.clear(date: date, sessionType: "morning")
        XCTAssertNil(SessionDraftStore.loadComment(date: date, sessionType: "morning"))
        XCTAssertNil(SessionDraftStore.loadStartedAt(date: date, sessionType: "morning"))
        XCTAssertNil(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning"))
        XCTAssertTrue(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "morning"))
        for type in ["evening", "bonus"] {
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: type), type)
            XCTAssertEqual(SessionDraftStore.recoveryProtection(date: date, sessionType: type)?.generation, 1)
        }
    }

    func testMorningServerRestoreWithoutLocalRecoveryCreatesNoDraft() throws {
        let date = "morning-empty-\(UUID().uuidString)"
        let vm = SeanceViewModel(draftSessionType: "morning")
        defer { _ = vm.chrono.stop(); SessionDraftStore.clear(date: date, sessionType: "morning") }
        let data = try extraData(date)
        vm.seanceData = data
        vm.restoreLogResults(from: data, serverSessionType: "morning", serverCompleted: true)
        vm.applyCompletedSessionRecoveryPolicy()
        XCTAssertTrue(vm.handleFinishConflict())
        XCTAssertNil(vm.submitError)
        XCTAssertFalse(SessionDraftStore.hasDraft(date: date, sessionType: "morning"))
        XCTAssertNil(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning"))
        XCTAssertTrue(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "morning"))
    }

    func testNormalMorningGateAndCompletionPolicyPreserveUnacknowledgedRecovery() async throws {
        let date = "morning-normal-\(UUID().uuidString)"
        let vm = FinishSaveStub(draftSessionType: "morning")
        defer { _ = vm.chrono.stop(); SessionDraftStore.clear(date: date, sessionType: "morning") }
        vm.seanceData = try APIService.decoder.decode(SeanceData.self, from: Fixtures.seanceDataJSON(todayDate: date, alreadyLogged: false))
        vm.logResults["A"] = ExerciseLogResult(name: "A", weight: 80, reps: "5")
        let accepted = await vm.saveExercisesForFinish()
        XCTAssertTrue(accepted)
        vm.applyCompletedSessionRecoveryPolicy()
        XCTAssertNil(vm.submitError)
        XCTAssertNotNil(vm.commitWarning)
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "morning"))
        let retryAccepted = await vm.saveExercisesForFinish()
        XCTAssertTrue(retryAccepted)
        XCTAssertEqual(vm.calls, ["A"])
    }

    func testSessionOutcomeResponseQueueAndErrors() async throws {
        let response = try await SessionSaveOutcome.fromOfflinePost { Data(#"{"success":true}"#.utf8) }
        guard case .serverResponse = response else { return XCTFail("Expected application response") }
        let queued = try await SessionSaveOutcome.fromOfflinePost { nil }
        guard case .queuedOffline = queued else { return XCTFail("Expected queued") }
        for text in ["invalid", "{}", #"{"success":false}"#] {
            do {
                _ = try await SessionSaveOutcome.fromOfflinePost { Data(text.utf8) }
                XCTFail("Invalid response accepted")
            } catch {}
        }
        do {
            _ = try await SessionSaveOutcome.fromOfflinePost { throw APIError.serverError(409, "Conflict") }
            XCTFail("Error swallowed")
        } catch APIError.serverError(let code, _) { XCTAssertEqual(code, 409) }
    }

    private final class EveningOutcomeStub: SeanceSoirViewModel {
        var queued = true
        var failure: Int?
        var completed = false
        var comments: [String] = []
        var dates: [String?] = []
        var recorded = 0
        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome { .queuedOffline }
        override func sendEveningSession(exos: [String], rpe: Double, comment: String,
                                        durationMin: Double?, energyPre: Int?, sessionName: String?,
                                        exerciseLogs: [[String: Any]]) async throws -> SessionSaveOutcome {
            comments.append(comment)
            dates.append(finishSourceDate)
            if let failure { throw APIError.serverError(failure, "Injected") }
            return queued ? .queuedOffline : .serverResponse(LogSessionResponse(success: true))
        }
        override func refreshEveningDashboard() async {}
        override func observeEveningCompletion(date: String) async -> Bool { completed }
        override func recordEveningWorkout() async { recorded += 1 }
    }

    func testEveningFullFinishQueueFailureRetryAndResponsePreserveDraft() async throws {
        let date = "evening-full-\(UUID().uuidString)"
        let vm = EveningOutcomeStub()
        let reopened = SeanceSoirViewModel()
        defer {
            _ = vm.chrono.stop(); _ = reopened.chrono.stop()
            SessionDraftStore.clear(date: date, sessionType: "evening")
        }
        let data = try extraData(date)
        vm.seanceData = data
        vm.logResults["Bench Press"] = ExerciseLogResult(name: "Bench Press", weight: 80, reps: "5", isSecond: true, notes: "Soir")
        SessionDraftStore.saveComment("Initial", date: date, sessionType: "evening")
        await vm.finish(rpe: 7, comment: "Initial")
        XCTAssertNotNil(vm.saveStatusMessage)
        XCTAssertFalse(vm.showSuccess)
        XCTAssertFalse(vm.isFinishing)
        XCTAssertTrue(vm.canRetryFinish)
        XCTAssertEqual(vm.recorded, 0)
        let generation = SessionDraftStore.recoveryProtection(date: date, sessionType: "evening")?.generation
        XCTAssertNotNil(generation)
        reopened.seanceData = data
        reopened.restoreLogResults(from: data, serverSessionType: "evening", serverCompleted: true)
        XCTAssertEqual(reopened.logResults["Bench Press"]?.notes, "Soir")
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "evening"), "Initial")
        XCTAssertEqual(SessionDraftStore.recoveryProtection(date: date, sessionType: "evening")?.generation, generation)
        for code in [500, 409] {
            vm.failure = code
            await vm.retryFinish(comment: "Modifié")
            XCTAssertNotNil(vm.submitError)
            XCTAssertFalse(vm.showSuccess)
            XCTAssertFalse(vm.isFinishing)
            XCTAssertEqual(vm.comments.last, "Modifié")
            XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "evening"))
        }
        vm.failure = nil
        vm.queued = false
        await vm.retryFinish(comment: "Modifié")
        XCTAssertFalse(vm.showSuccess)
        XCTAssertNotNil(vm.saveStatusMessage)
        vm.completed = true
        SessionDraftStore.saveComment("Dernière version", date: date, sessionType: "evening")
        await vm.retryFinish(comment: "Dernière version")
        XCTAssertTrue(vm.showSuccess)
        XCTAssertNotNil(vm.commitWarning)
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "evening"))
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "evening"), "Dernière version")
        XCTAssertFalse(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "evening"))
    }

    func testPrecompletedEveningNewEditSurvivesAnotherCompletionRead() throws {
        let date = "evening-precompleted-\(UUID().uuidString)"
        let vm = SeanceSoirViewModel()
        defer { _ = vm.chrono.stop(); SessionDraftStore.clear(date: date, sessionType: "evening") }
        let data = try extraData(date)
        vm.seanceData = data
        vm.restoreLogResults(from: data, serverSessionType: "evening", serverCompleted: true)
        vm.logResults["Bench Press"] = ExerciseLogResult(name: "Bench Press", weight: 85, reps: "6", isSecond: true, notes: "Nouvelle version")
        SessionDraftStore.saveComment("Après clôture", date: date, sessionType: "evening")
        let protection = SessionDraftStore.recoveryProtection(date: date, sessionType: "evening")
        XCTAssertEqual(protection?.hasUnacknowledgedLocalChanges, true)
        vm.restoreLogResults(from: data, serverSessionType: "evening", serverCompleted: true)
        XCTAssertEqual(vm.logResults["Bench Press"]?.notes, "Nouvelle version")
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "evening"), "Après clôture")
        XCTAssertEqual(SessionDraftStore.recoveryProtection(date: date, sessionType: "evening")?.generation, protection?.generation)
        XCTAssertFalse(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "evening"))
    }

    func testEveningPartialFinishStillSkipsSessionPost() async throws {
        let date = "partial-\(UUID().uuidString)"
        let vm = EveningOutcomeStub()
        defer { _ = vm.chrono.stop(); SessionDraftStore.clear(date: date, sessionType: "evening") }
        vm.seanceData = try extraData(date)
        vm.logResults["Bench Press"] = ExerciseLogResult(name: "Bench Press", weight: 80, reps: "5", isSecond: true)
        SessionDraftStore.saveComment("Plus tard", date: date, sessionType: "evening")
        await vm.finish(rpe: 7, comment: "Plus tard", closeSession: false)
        XCTAssertTrue(vm.partialSaveAccepted)
        XCTAssertTrue(vm.comments.isEmpty)
        XCTAssertFalse(vm.showSuccess)
        XCTAssertEqual(vm.recorded, 0)
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "evening"))
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "evening"), "Plus tard")
    }

    func testEveningLegacyCommentOnlyAndTypeIsolation() throws {
        let date = "evening-legacy-\(UUID().uuidString)"
        let vm = SeanceSoirViewModel()
        defer {
            _ = vm.chrono.stop()
            for type in ["evening", "bonus"] { SessionDraftStore.clear(date: date, sessionType: type) }
        }
        let legacy = [PersistedExerciseLogResult(name: "Bench Press", weight: 80, reps: "5", rpe: nil,
            isSecond: true, isBonus: false, equipmentType: "", painZone: "", sets: [])]
        UserDefaults.standard.set(try APIService.encoder.encode(legacy), forKey: "session_draft_evening_\(date)")
        XCTAssertNil(SessionDraftStore.recoveryProtection(date: date, sessionType: "evening"))
        let data = try extraData(date)
        vm.seanceData = data
        vm.restoreLogResults(from: data, serverSessionType: "evening", serverCompleted: true)
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "evening"))
        SessionDraftStore.clear(date: date, sessionType: "evening")
        vm.logResults.removeAll()
        SessionDraftStore.saveComment("Seul commentaire", date: date, sessionType: "evening")
        vm.restoreLogResults(from: data, serverSessionType: "evening", serverCompleted: true)
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "evening"), "Seul commentaire")
        XCTAssertFalse(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "evening"))
        XCTAssertTrue(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "bonus"))
        XCTAssertTrue(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "morning"))
        SessionDraftStore.saveComment("Bonus", date: date, sessionType: "bonus")
        let bonusGeneration = SessionDraftStore.bonusProtection(date: date)?.generation
        SessionDraftStore.clear(date: date, sessionType: "evening")
        XCTAssertNil(SessionDraftStore.recoveryProtection(date: date, sessionType: "evening"))
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, bonusGeneration)
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "bonus"), "Bonus")
    }

    private func extraData(_ date: String, exercise: String = "Bench Press") throws -> SeanceData {
        try APIService.decoder.decode(SeanceData.self, from:
            Fixtures.seanceDataJSON(todayDate: date, alreadyLogged: true, exerciseName: exercise))
    }

    private func bonusResponse(_ date: String, completed: Bool = true) throws -> SeanceBonusData {
        try JSONDecoder().decode(SeanceBonusData.self, from: JSONSerialization.data(withJSONObject: [
            "has_bonus_session": true, "today_date": date, "already_logged": completed
        ]))
    }

    private final class ExtraProofStub: ExtraSessionViewModel {
        var response: SeanceBonusData?
        override func fetchBonusCompletion() async throws -> SeanceBonusData {
            guard let response else { throw URLError(.notConnectedToInternet) }
            return response
        }
    }

    func testBonusGenerationTracksContentNotOrderingAndClearLogsKeepsProtection() throws {
        let date = "generation-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "bonus") }
        var a = PersistedExerciseLogResult(name: "A", weight: 80, reps: "5", rpe: nil,
            isSecond: false, isBonus: true, equipmentType: "", painZone: "", sets: [], notes: "initial")
        let b = PersistedExerciseLogResult(name: "B", weight: 40, reps: "8", rpe: nil,
            isSecond: false, isBonus: true, equipmentType: "", painZone: "", sets: [])
        SessionDraftStore.save(date: date, sessionType: "bonus", values: [a, b])
        let initial = try XCTUnwrap(SessionDraftStore.bonusProtection(date: date))
        XCTAssertTrue(initial.hasUnacknowledgedLocalChanges)
        SessionDraftStore.save(date: date, sessionType: "bonus", values: [b, a])
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, initial.generation)
        a.notes = "changed"
        SessionDraftStore.save(date: date, sessionType: "bonus", values: [a, b])
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, initial.generation + 1)
        SessionDraftStore.clearLogs(date: date, sessionType: "bonus")
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, initial.generation + 2)
        XCTAssertFalse(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "bonus"))
    }

    func testCompletedBonusWithoutLocalRecoveryAllowsNoOpCleanup() async throws {
        let date = "empty-bonus-\(UUID().uuidString)"
        let vm = BonusSeanceViewModel()
        defer { SessionDraftStore.clear(date: date, sessionType: "bonus") }
        vm.seanceData = try extraData(date)
        XCTAssertTrue(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "bonus"))
        _ = await vm.loadBonusState { request in
            (try JSONEncoder().encode(self.bonusResponse(date)),
             HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertNil(SessionDraftStore.bonusProtection(date: date))
        XCTAssertTrue(vm.logResults.isEmpty)
        XCTAssertFalse(vm.showSuccess)
    }

    func testExtraHydrationRecreationIdenticalRestoreAndTemplateSafety() async throws {
        let date = "extra-\(UUID().uuidString)"
        let nextDate = "next-\(date)"
        let first = ExtraSessionViewModel()
        let second = ExtraSessionViewModel()
        defer {
            _ = first.chrono.stop(); _ = second.chrono.stop()
            SessionDraftStore.clear(date: date, sessionType: "bonus")
            SessionDraftStore.clear(date: nextDate, sessionType: "bonus")
        }
        let data = try extraData(date)
        XCTAssertTrue(first.adoptSelectedData(data))
        XCTAssertEqual(first.seanceData?.todayDate, date)
        var log = ExerciseLogResult(name: "Bench Press", weight: 80, reps: "5")
        log.isBonus = true
        log.notes = "Note durable"
        log.trackingType = "carry"
        log.sets = [["weight": 80.0, "distance_m": 30]]
        first.logResults[log.name] = log
        SessionDraftStore.saveComment("Commentaire durable", date: date, sessionType: "bonus")
        let generation = SessionDraftStore.bonusProtection(date: date)?.generation
        XCTAssertNotNil(generation)
        XCTAssertEqual(SessionDraftStore.load(date: date, sessionType: "bonus").first?.sets.first?.distanceM, 30)
        XCTAssertTrue(second.adoptSelectedData(data))
        XCTAssertEqual(second.logResults[log.name]?.notes, log.notes)
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, generation)
        SessionDraftStore.saveComment("Commentaire durable", date: date, sessionType: "bonus")
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, generation)
        await second.load()
        XCTAssertEqual(second.seanceData?.todayDate, date)
        XCTAssertEqual(second.logResults[log.name]?.notes, log.notes)
        XCTAssertFalse(second.adoptSelectedData(try extraData(date, exercise: "Squat")))
        XCTAssertNotNil(second.error)
        XCTAssertNotNil(second.logResults[log.name])
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, generation)
        XCTAssertTrue(second.adoptSelectedData(try extraData(nextDate)))
        XCTAssertTrue(second.logResults.isEmpty)
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "bonus"))
    }

    func testExtraToDedicatedBonusPreservesDirtyLogsAndComment() async throws {
        let date = "cross-entry-\(UUID().uuidString)"
        let extra = ExtraSessionViewModel()
        let dedicated = BonusSeanceViewModel()
        defer {
            _ = extra.chrono.stop(); _ = dedicated.chrono.stop()
            SessionDraftStore.clear(date: date, sessionType: "bonus")
        }
        let data = try extraData(date)
        XCTAssertTrue(extra.adoptSelectedData(data))
        extra.logResults["Bench Press"] = ExerciseLogResult(name: "Bench Press", weight: 80, reps: "5", isBonus: true)
        SessionDraftStore.saveComment("Nouveau commentaire", date: date, sessionType: "bonus")
        dedicated.seanceData = data
        dedicated.restoreLogResults(from: data, serverSessionType: "bonus", serverCompleted: true)
        _ = await dedicated.loadBonusState { request in
            // A mutation arriving during the GET must remain protected too.
            SessionDraftStore.saveComment("Encore modifié", date: date, sessionType: "bonus")
            return (try JSONEncoder().encode(self.bonusResponse(date)),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertNotNil(dedicated.logResults["Bench Press"])
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "bonus"))
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "bonus"), "Encore modifié")
        XCTAssertFalse(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "bonus"))
    }

    func testLegacyAndCommentOnlyProtectionAndExplicitFullClear() async throws {
        let date = "legacy-bonus-\(UUID().uuidString)"
        let vm = BonusSeanceViewModel()
        defer { _ = vm.chrono.stop(); SessionDraftStore.clear(date: date, sessionType: "bonus") }
        let legacy = [PersistedExerciseLogResult(name: "Bench Press", weight: 80, reps: "5", rpe: nil,
            isSecond: false, isBonus: true, equipmentType: "", painZone: "", sets: [], notes: "")]
        UserDefaults.standard.set(try APIService.encoder.encode(legacy), forKey: "session_draft_bonus_\(date)")
        XCTAssertNil(SessionDraftStore.bonusProtection(date: date))
        XCTAssertFalse(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "bonus"))
        let data = try extraData(date)
        vm.seanceData = data
        vm.restoreLogResults(from: data, serverSessionType: "bonus", serverCompleted: true)
        XCTAssertNotNil(vm.logResults["Bench Press"])
        SessionDraftStore.clear(date: date, sessionType: "bonus")
        vm.logResults.removeAll()
        SessionDraftStore.saveComment("Seul commentaire", date: date, sessionType: "bonus")
        let generation = SessionDraftStore.bonusProtection(date: date)?.generation
        SessionDraftStore.clearLogs(date: date, sessionType: "bonus")
        XCTAssertEqual(SessionDraftStore.bonusProtection(date: date)?.generation, generation)
        _ = await vm.loadBonusState { request in
            (try JSONEncoder().encode(self.bonusResponse(date)),
             HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "bonus"), "Seul commentaire")
        SessionDraftStore.saveStartedAt(date: date, sessionType: "bonus", startedAt: Date())
        SessionDraftStore.clear(date: date, sessionType: "bonus")
        XCTAssertNil(SessionDraftStore.bonusProtection(date: date))
        XCTAssertNil(SessionDraftStore.loadComment(date: date, sessionType: "bonus"))
        XCTAssertNil(SessionDraftStore.loadStartedAt(date: date, sessionType: "bonus"))
        XCTAssertTrue(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "bonus"))
    }

    func testExtraMorningIsolationOfflineWrongDateAndConflictPreserveDraft() async throws {
        let date = "extra-proof-\(UUID().uuidString)"
        let vm = ExtraProofStub()
        defer { _ = vm.chrono.stop(); SessionDraftStore.clear(date: date, sessionType: "bonus") }
        XCTAssertTrue(vm.adoptSelectedData(try extraData(date))) // Morning alreadyLogged=true
        vm.logResults["Bench Press"] = ExerciseLogResult(name: "Bench Press", weight: 80, reps: "5", isBonus: true)
        vm.response = try bonusResponse(date, completed: false)
        let incomplete = await vm.verifyFinishCompletion()
        XCTAssertFalse(incomplete)
        vm.response = nil
        let offline = await vm.verifyFinishCompletion()
        XCTAssertFalse(offline)
        vm.response = try bonusResponse("other-\(date)")
        let wrongDate = await vm.verifyFinishCompletion()
        XCTAssertFalse(wrongDate)
        XCTAssertFalse(vm.handleFinishConflict())
        XCTAssertFalse(vm.showSuccess)
        vm.response = try bonusResponse(date)
        let completed = await vm.verifyFinishCompletion()
        XCTAssertTrue(completed, "Server status is not a local content ACK")
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "bonus"))
        XCTAssertFalse(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "bonus"))
    }

    func testGlobalCommentRoundTripIsolationAndEmptyValues() {
        let date = "comment-\(UUID().uuidString)"
        let types = ["morning", "evening", "bonus"]
        defer { for type in types { SessionDraftStore.clear(date: date, sessionType: type) } }
        for (index, type) in types.enumerated() {
            let text = index == 0 ? "Très bonne séance" : "Commentaire \(type)"
            SessionDraftStore.saveComment(text, date: date, sessionType: type)
        }
        for (index, type) in types.enumerated() {
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: type),
                           index == 0 ? "Très bonne séance" : "Commentaire \(type)")
            XCTAssertNil(SessionDraftStore.loadComment(date: "other-\(date)", sessionType: type))
            SessionDraftStore.saveComment("", date: date, sessionType: type)
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: type), "")
            SessionDraftStore.saveComment("  \n ", date: date, sessionType: type)
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: type), "  \n ")
        }
    }

    func testGlobalCommentSurvivesEmptyLogsAndRestoreButNotFullCleanup() throws {
        let date = "comment-lifecycle-\(UUID().uuidString)"
        for type in ["morning", "evening", "bonus"] {
            defer { SessionDraftStore.clear(date: date, sessionType: type) }
            let data = try APIService.decoder.decode(SeanceData.self, from: Fixtures.seanceDataJSON(todayDate: date))
            SessionDraftStore.saveComment("Très bonne séance", date: date, sessionType: type)
            let vm = SeanceViewModel(draftSessionType: type)
            vm.seanceData = data
            vm.restoreLogResults(from: data, serverSessionType: type, serverCompleted: false)
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: type), "Très bonne séance")
            vm.logResults = ["A": ExerciseLogResult(name: "A", weight: 80, reps: "5")]
            vm.logResults.removeAll()
            XCTAssertTrue(SessionDraftStore.load(date: date, sessionType: type).isEmpty)
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: type), "Très bonne séance")
            _ = vm.chrono.stop()
            vm.restoreLogResults(from: data, serverSessionType: type, serverCompleted: true)
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: type), "Très bonne séance")
            SessionDraftStore.clear(date: date, sessionType: type)
            XCTAssertNil(SessionDraftStore.loadComment(date: date, sessionType: type))
        }
    }

    func testLegacySessionLogArrayRemainsUnchangedWithoutComment() throws {
        let date = "comment-legacy-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "morning") }
        let logs = [PersistedExerciseLogResult(
            name: "A", weight: 80, reps: "5", rpe: nil, isSecond: false,
            isBonus: false, equipmentType: "barbell", painZone: "", sets: []
        )]
        let legacy = try APIService.encoder.encode(logs)
        UserDefaults.standard.set(legacy, forKey: "session_draft_morning_\(date)")
        XCTAssertEqual(SessionDraftStore.load(date: date).first?.name, "A")
        XCTAssertNil(SessionDraftStore.loadComment(date: date, sessionType: "morning"))
        SessionDraftStore.saveComment("Très bonne séance", date: date, sessionType: "morning")
        XCTAssertEqual(UserDefaults.standard.data(forKey: "session_draft_morning_\(date)"), legacy)
    }

    private final class CommentRetryProbe: SeanceViewModel {
        var receivedComment: String?
        var receivedClose: Bool?
        override func finish(rpe: Double, comment: String, durationMin: Double? = nil,
                             energyPre: Int? = nil, sessionName: String? = nil,
                             bonusSession: Bool = false, closeSession: Bool = true) async {
            receivedComment = comment
            receivedClose = closeSession
        }
    }

    func testRetrySuppliesLatestCommentAndPreservesPartialSessionOption() async {
        for type in ["morning", "evening", "bonus"] {
            let vm = CommentRetryProbe(draftSessionType: type)
            vm.prepareFinishRetry(rpe: 7, comment: "Première version", durationMin: 20,
                                  energyPre: 3, sessionName: "Test", bonusSession: type == "bonus",
                                  closeSession: type != "evening")
            vm.isFinishing = true
            await vm.retryFinish(comment: "Version finale")
            XCTAssertNil(vm.receivedComment)
            vm.isFinishing = false
            await vm.retryFinish(comment: "Version finale")
            XCTAssertEqual(vm.receivedComment, "Version finale")
            XCTAssertEqual(vm.receivedClose, type != "evening")
            await vm.retryFinish(comment: "")
            XCTAssertEqual(vm.receivedComment, "")
        }
    }

    private func restoreBonusDraft(date: String) throws -> BonusSeanceViewModel {
        SessionDraftStore.save(date: date, sessionType: "bonus", values: [
            PersistedExerciseLogResult(
                name: "Bench Press", weight: 80, reps: "5", rpe: 7,
                isSecond: false, isBonus: true, equipmentType: "barbell", painZone: "",
                sets: [PersistedSet(weight: 80, reps: "5", rir: 3, rpe: 7)],
                notes: "Bonus draft note"
            )
        ])
        let vm = BonusSeanceViewModel()
        let data = try APIService.decoder.decode(SeanceData.self, from: Fixtures.seanceDataJSON(todayDate: date))
        vm.seanceData = data
        vm.restoreLogResults(from: data, serverSessionType: "morning", serverCompleted: true)
        return vm
    }

    func testBonusCompletionPreservesUnacknowledgedStateAndOtherDrafts() async throws {
        let date = "bonus-reconcile-\(UUID().uuidString)"
        let otherDate = "other-\(date)"
        let vm = try restoreBonusDraft(date: date)
        SessionDraftStore.saveComment("Bonus terminé", date: date, sessionType: "bonus")
        let saved = SessionDraftStore.load(date: date, sessionType: "bonus")
        for type in ["morning", "evening"] {
            SessionDraftStore.save(date: date, sessionType: type, values: saved)
        }
        SessionDraftStore.save(date: otherDate, sessionType: "bonus", values: saved)
        defer {
            _ = vm.chrono.stop()
            for type in ["morning", "evening", "bonus"] {
                SessionDraftStore.clear(date: date, sessionType: type)
            }
            SessionDraftStore.clear(date: otherDate, sessionType: "bonus")
        }
        XCTAssertTrue(vm.isResuming)
        XCTAssertTrue(vm.sessionStarted)
        XCTAssertEqual(vm.logResults["Bench Press"]?.notes, "Bonus draft note")

        let payload: [String: Any] = [
            "has_bonus_session": true, "today_date": date, "already_logged": true,
            "full_program": ["Bonus": ["Squat": "3x8"]], "pushed_to_bonus": ["Squat"]
        ]
        let result = await vm.loadBonusState { request in
            XCTAssertEqual(request.url?.path, "/api/seance_bonus_data")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
            return (try JSONSerialization.data(withJSONObject: payload),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "bonus"))
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "bonus"), "Bonus terminé")
        XCTAssertNotNil(SessionDraftStore.loadStartedAt(date: date, sessionType: "bonus"))
        XCTAssertFalse(vm.logResults.isEmpty)
        XCTAssertTrue(vm.isResuming)
        XCTAssertTrue(vm.sessionStarted)
        XCTAssertFalse(vm.showSuccess, "Reconciliation must not trigger finish side effects")
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "morning"))
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "evening"))
        XCTAssertTrue(SessionDraftStore.hasDraft(date: otherDate, sessionType: "bonus"))
        XCTAssertEqual(result?.pushedToBonus, Set(["Squat"]))
        XCTAssertEqual(result?.fullProgram["Bonus"]?["Squat"]?.value, "3x8")
    }

    func testBonusDraftSurvivesUnprovenAndLaterCompletedRead() async throws {
        let date = "bonus-offline-\(UUID().uuidString)"
        let vm = try restoreBonusDraft(date: date)
        SessionDraftStore.saveComment("Bonus à reprendre", date: date, sessionType: "bonus")
        defer {
            _ = vm.chrono.stop()
            SessionDraftStore.clear(date: date, sessionType: "bonus")
        }
        // A queued POST is not a completion signal. Transport/HTTP/unknown GET
        // results preserve local state; even a later positive read is not a content ACK.
        let failedFetch = await vm.loadBonusState { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertNil(failedFetch)
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "bonus"))
        XCTAssertFalse(vm.logResults.isEmpty)

        let cases: [(Bool?, String?, Bool?, Int)] = [
            (true, date, false, 200), (true, "other-\(date)", true, 200),
            (false, date, true, 200), (nil, date, true, 200),
            (true, nil, true, 200), (true, "", true, 200),
            (true, date, nil, 200), (true, date, true, 500),
            (true, date, true, 302)
        ]
        for (exists, serverDate, completed, status) in cases {
            var payload: [String: Any] = [:]
            if let exists { payload["has_bonus_session"] = exists }
            if let serverDate { payload["today_date"] = serverDate }
            if let completed { payload["already_logged"] = completed }
            _ = await vm.loadBonusState { request in
                (try JSONSerialization.data(withJSONObject: payload),
                 HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "bonus"))
            XCTAssertEqual(vm.logResults["Bench Press"]?.notes, "Bonus draft note")
            XCTAssertTrue(vm.isResuming)
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "bonus"), "Bonus à reprendre")
        }
        let malformed = await vm.loadBonusState { request in
            (Data("not-json".utf8),
             HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertNil(malformed)
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "bonus"))

        _ = await vm.loadBonusState { request in
            (try JSONSerialization.data(withJSONObject: [
                "has_bonus_session": true, "today_date": date, "already_logged": true
            ]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "bonus"))
        XCTAssertFalse(vm.logResults.isEmpty)
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "bonus"), "Bonus à reprendre")
    }

    private final class FinishSaveStub: SeanceViewModel {
        var failures: Set<String> = []
        var queued: Set<String> = []
        var calls: [String] = []
        var sentWeights: [Double] = []
        var sentDates: [String?] = []
        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome {
            calls.append(result.name)
            sentWeights.append(result.weight)
            sentDates.append(finishSourceDate)
            if failures.contains(result.name) { throw APIError.serverError(500, "Injected") }
            if queued.contains(result.name) { return .queuedOffline }
            return .confirmed(LogExerciseResponse(success: true, newWeight: nil, oneRM: nil,
                                                  isPR: false, baselineCount: nil, confidence: nil))
        }
    }

    func testFinishGateRetriesOnlyFailuresAndAcceptsOffline() async throws {
        let vm = FinishSaveStub(draftSessionType: "morning")
        let date = "finish-test-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "morning") }
        vm.seanceData = try APIService.decoder.decode(SeanceData.self, from: Fixtures.seanceDataJSON(todayDate: date))
        vm.logResults = Dictionary(uniqueKeysWithValues: ["A", "B", "C"].map {
            ($0, ExerciseLogResult(name: $0, weight: 80, reps: "5"))
        })
        vm.failures = ["B"]
        vm.queued = ["C"]
        let first = await vm.saveExercisesForFinish()
        XCTAssertFalse(first)
        XCTAssertEqual(vm.calls, ["A", "B", "C"])
        XCTAssertEqual(vm.failedExerciseNames, ["B"])
        XCTAssertFalse(vm.showSuccess)
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "morning"))
        let second = await vm.saveExercisesForFinish()
        XCTAssertFalse(second)
        XCTAssertEqual(vm.calls, ["A", "B", "C", "B"])
        vm.failures = []
        let third = await vm.saveExercisesForFinish()
        XCTAssertTrue(third)
        XCTAssertEqual(vm.calls, ["A", "B", "C", "B", "B"])
        XCTAssertTrue(vm.failedExerciseNames.isEmpty)
        XCTAssertNil(vm.submitError)
        // The gate never cleans the draft; finalization owns cleanup.
        XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: "morning"))
        vm.logResults["A"] = ExerciseLogResult(name: "A", weight: 85, reps: "5")
        let edited = await vm.saveExercisesForFinish()
        XCTAssertTrue(edited)
        XCTAssertEqual(vm.calls.last, "A")
        XCTAssertEqual(vm.sentWeights.last, 85)
        XCTAssertTrue(vm.sentDates.allSatisfy { $0 == date })
    }

    func testFinishGateAllConfirmedAndFreshLifecycleResends() async throws {
        let date = "finish-lifecycle-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "morning") }
        let vm = FinishSaveStub(draftSessionType: "morning")
        defer { _ = vm.chrono.stop() }
        vm.seanceData = try extraData(date)
        vm.logResults = ["A": ExerciseLogResult(name: "A", weight: 80, reps: "5")]
        let accepted = await vm.saveExercisesForFinish()
        XCTAssertTrue(accepted)
        let recreated = FinishSaveStub(draftSessionType: "morning")
        defer { _ = recreated.chrono.stop() }
        recreated.seanceData = vm.seanceData
        recreated.logResults = vm.logResults
        let restoredAccepted = await recreated.saveExercisesForFinish()
        XCTAssertTrue(restoredAccepted)
        XCTAssertEqual(recreated.calls, ["A"])
    }

    func testExercisePayloadKeepsCapturedDateInPersistedReplayBytes() async throws {
        let suite = "date-queue-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = UserDefaultsSyncQueue(defaults: defaults)
        for evening in [false, true] {
            let outcome = try await APIService.shared.logExerciseOutcome(exercise: "Bench Press", weight: 80,
                reps: "5", isSecond: evening, date: "2026-09-26", invalidate: false, post: { payload in
                    XCTAssertEqual(payload["session_date"] as? String, "2026-09-26")
                    XCTAssertEqual(payload["is_second"] as? Bool ?? false, evening)
                    queue.append(PendingMutation(endpoint: "/api/log", payload: payload))
                    return nil
                })
            guard case .queuedOffline = outcome else { return XCTFail("Expected queued exercise") }
        }
        let replayDay = "2026-09-27"
        let recreated = UserDefaultsSyncQueue(defaults: defaults)
        for mutation in recreated.load() {
            var request = URLRequest(url: URL(string: "https://example.invalid/api/log")!)
            request.httpBody = mutation.payloadData // Same byte assignment as SyncManager.send.
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["session_date"] as? String, "2026-09-26")
            XCTAssertNotEqual(body["session_date"] as? String, replayDay)
            XCTAssertEqual(request.httpBody, mutation.payloadData)
        }
        XCTAssertEqual(recreated.load().count, 2)
    }

    private final class DatedMorningStub: SeanceViewModel {
        var failWithConflict = false
        var postedDates: [String] = []
        var postedComments: [String] = []
        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome { .queuedOffline }
        override func sendMorningSession(exos: [String], rpe: Double, comment: String, date: String,
                                         durationMin: Double?, energyPre: Int?, sessionName: String?,
                                         exerciseLogs: [[String: Any]]) async throws -> SessionSaveOutcome {
            postedDates.append(date)
            postedComments.append(comment)
            if failWithConflict { throw APIError.serverError(409, "Prior completion") }
            return .queuedOffline
        }
    }

    func testMorningOwnerQueuedConflictAndChangedDateCannotCompleteOrClear() async throws {
        let date = "morning-owner-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "morning") }
        let vm = DatedMorningStub(draftSessionType: "morning")
        vm.seanceData = try extraData(date)
        vm.sessionComment = "First"
        let generation = SessionDraftStore.recoveryProtection(date: date, sessionType: "morning")?.generation
        await vm.finish(rpe: 7, comment: vm.sessionComment)
        XCTAssertEqual(vm.postedDates, [date])
        XCTAssertFalse(vm.showSuccess)
        XCTAssertNotNil(vm.submitError)
        XCTAssertEqual(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning")?.generation, generation)
        vm.failWithConflict = true
        vm.sessionComment = "Latest"
        await vm.retryFinish(comment: vm.sessionComment)
        XCTAssertEqual(vm.postedDates, [date, date])
        XCTAssertEqual(vm.postedComments, ["First", "Latest"])
        XCTAssertFalse(vm.showSuccess)
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "morning"), "Latest")
        vm.seanceData = try extraData("other-date")
        await vm.retryFinish(comment: "Must not send")
        XCTAssertEqual(vm.postedDates, [date, date])
        XCTAssertFalse(vm.showSuccess)
    }

    func testDatedMorningAndEveningFinalPayloads() async throws {
        _ = try await APIService.shared.logMorningSessionOutcome(exos: ["A"], rpe: 7, comment: "Latest",
            date: "2026-09-26", post: { payload in
                XCTAssertEqual(payload["date"] as? String, "2026-09-26")
                XCTAssertNil(payload["second_session"])
                XCTAssertNil(payload["bonus_session"])
                XCTAssertEqual(payload["comment"] as? String, "Latest")
                return nil
            })
        _ = try await APIService.shared.logEveningSessionOutcome(exos: ["B"], rpe: 7, comment: "PM",
            durationMin: nil, energyPre: nil, sessionName: "PM", exerciseLogs: [], date: "2026-09-26",
            post: { payload in
                XCTAssertEqual(payload["date"] as? String, "2026-09-26")
                XCTAssertEqual(payload["second_session"] as? Bool, true)
                XCTAssertNil(payload["bonus_session"])
                return nil
            })
        _ = try await APIService.shared.logExerciseOutcome(exercise: "Legacy", weight: 1, reps: "1",
            isBonus: true, invalidate: false, post: { payload in
                XCTAssertNil(payload["session_date"])
                XCTAssertEqual(payload["is_bonus"] as? Bool, true)
                return nil
            })
    }

    func testEveningOwnerPassesFrozenDateAndRetainsSecondSessionScope() async throws {
        let date = "evening-date-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "evening") }
        let vm = EveningOutcomeStub()
        vm.seanceData = try extraData(date)
        vm.sessionComment = "PM recovery"
        await vm.finish(rpe: 7, comment: vm.sessionComment)
        await vm.retryFinish(comment: vm.sessionComment)
        XCTAssertEqual(vm.dates, [date, date])
        XCTAssertEqual(vm.draftSessionType, "evening")
        XCTAssertFalse(vm.showSuccess)
        XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "evening"), "PM recovery")
    }

    func testMorningTypedBoundaryDoesNotAcknowledgeRecovery() async throws {
        let date = "morning-typed-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "morning") }
        SessionDraftStore.saveComment("Dirty comment", date: date, sessionType: "morning")
        let generation = try XCTUnwrap(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning")?.generation)
        let replies: [Data?] = [Data(#"{"success":true}"#.utf8), nil,
                                Data(#"{"success":false}"#.utf8), Data("invalid".utf8)]
        for (index, reply) in replies.enumerated() {
            do {
                let outcome = try await APIService.shared.logMorningSessionOutcome(exos: [], rpe: 7,
                    comment: "Dirty comment", date: date, post: { _ in reply })
                switch (index, outcome) {
                case (0, .serverResponse), (1, .queuedOffline): break
                default: XCTFail("Invalid success outcome")
                }
            } catch { XCTAssertGreaterThan(index, 1) }
            XCTAssertEqual(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning")?.generation, generation)
            XCTAssertFalse(SessionDraftStore.isAutomaticCleanupAllowed(date: date, sessionType: "morning"))
            XCTAssertEqual(SessionDraftStore.loadComment(date: date, sessionType: "morning"), "Dirty comment")
        }
        do {
            _ = try await APIService.shared.logMorningSessionOutcome(exos: [], rpe: 7, comment: "",
                date: date, post: { _ in throw APIError.serverError(500, "Injected") })
            XCTFail("HTTP error must propagate")
        } catch APIError.serverError(let code, _) { XCTAssertEqual(code, 500) }
        do {
            _ = try await APIService.shared.logMorningSessionOutcome(exos: [], rpe: 7, comment: "",
                date: date, post: { _ in throw URLError(.timedOut) })
            XCTFail("Transport error must propagate")
        } catch let error as URLError { XCTAssertEqual(error.code, .timedOut) }
        XCTAssertEqual(SessionDraftStore.recoveryProtection(date: date, sessionType: "morning")?.generation, generation)
    }

    func testProjectionAndContextMismatchNeverMutateOwnersOrRecovery() throws {
        let date = "2026-09-26"
        // Isolated source dates for draft storage; the passive projection cannot access these owners.
        let draftDate = "projection-\(UUID().uuidString)"
        let morning = SeanceViewModel(draftSessionType: "morning")
        let evening = SeanceSoirViewModel()
        defer {
            SessionDraftStore.clear(date: draftDate, sessionType: "morning")
            SessionDraftStore.clear(date: draftDate, sessionType: "evening")
        }
        morning.seanceData = try extraData(draftDate)
        evening.seanceData = try extraData(draftDate)
        morning.sessionComment = "AM draft"
        evening.sessionComment = "PM draft"
        let amGeneration = SessionDraftStore.recoveryProtection(date: draftDate, sessionType: "morning")?.generation
        let pmGeneration = SessionDraftStore.recoveryProtection(date: draftDate, sessionType: "evening")?.generation
        let projection = try DayComposerServerProjection(date: date, historyData:
            Data(#"{"session_list":[{"date":"2026-09-26","session_type":"morning","exos":[{"exercise":"Bench Press"}]}]}"#.utf8))
        XCTAssertEqual(projection.presence(of: "Bench Press", source: .morning), .observed)
        XCTAssertTrue(morning.logResults.isEmpty)
        XCTAssertTrue(evening.logResults.isEmpty)
        func context(_ program: String, _ name: String) throws -> DayComposerExecutionContext {
            try .init(snapshot: .init(date: date, activeProgramID: program,
                morning: .init(source: .morning, session: "AM", schemes: [name: "3x10"], order: [name]),
                evening: .init(source: .evening, session: "PM", schemes: [:], order: []),
                morningCompleted: false, eveningCompleted: false))
        }
        let original = try context("A", "Bench Press")
        XCTAssertEqual(original.compatibility(with: try context("B", "Bench Press")), .differentProgram)
        XCTAssertEqual(original.compatibility(with: try context("A", "Changed")), .differentSources)
        XCTAssertEqual(SessionDraftStore.recoveryProtection(date: draftDate, sessionType: "morning")?.generation, amGeneration)
        XCTAssertEqual(SessionDraftStore.recoveryProtection(date: draftDate, sessionType: "evening")?.generation, pmGeneration)
        XCTAssertEqual(morning.sessionComment, "AM draft")
        XCTAssertEqual(evening.sessionComment, "PM draft")
    }

    private final class FailingEveningFinish: SeanceSoirViewModel {
        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome {
            throw APIError.serverError(500, "Injected")
        }
    }
    private final class FailingBonusFinish: BonusSeanceViewModel {
        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome {
            throw APIError.serverError(500, "Injected")
        }
    }

    func testBlockingSaveStopsMorningEveningBonusAndPartialEvening() async throws {
        let morning = FinishSaveStub(draftSessionType: "morning")
        morning.failures = ["A"]
        let cases: [(SeanceViewModel, Bool)] = [
            (morning, true), (FailingEveningFinish(), true),
            (FailingBonusFinish(), true), (FailingEveningFinish(), false)
        ]
        for (vm, close) in cases {
            let date = "blocked-finish-\(UUID().uuidString)"
            defer { SessionDraftStore.clear(date: date, sessionType: vm.draftSessionType) }
            vm.seanceData = try APIService.decoder.decode(SeanceData.self, from: Fixtures.seanceDataJSON(todayDate: date))
            vm.logResults = ["A": ExerciseLogResult(name: "A", weight: 80, reps: "5")]
            SessionDraftStore.saveComment("Très bonne séance", date: date, sessionType: vm.draftSessionType)
            await vm.finish(rpe: 7, comment: "", closeSession: close)
            XCTAssertFalse(vm.showSuccess)
            XCTAssertFalse(vm.partialSaveAccepted)
            XCTAssertFalse(vm.isFinishing)
            XCTAssertEqual(vm.failedExerciseNames, ["A"])
            XCTAssertNotNil(vm.submitError)
            XCTAssertTrue(vm.canRetryFinish)
            XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: vm.draftSessionType))
            await vm.retryFinish(comment: "")
            XCTAssertFalse(vm.showSuccess)
            XCTAssertFalse(vm.partialSaveAccepted)
            XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: vm.draftSessionType))
            let restoredComment = SessionDraftStore.loadComment(date: date, sessionType: vm.draftSessionType)
            XCTAssertEqual(restoredComment, "Très bonne séance")
            let recreated = CommentRetryProbe(draftSessionType: vm.draftSessionType)
            recreated.prepareFinishRetry(rpe: 7, comment: "", durationMin: nil,
                                         energyPre: nil, sessionName: nil,
                                         bonusSession: vm.draftSessionType == "bonus", closeSession: close)
            await recreated.retryFinish(comment: try XCTUnwrap(restoredComment))
            XCTAssertEqual(recreated.receivedComment, "Très bonne séance")
        }
    }

    func testLegacySetDraftsDecodeWithoutSpecializedValues() throws {
        let oldCard = Data(#"{"weight":"80","reps":"5","rir":2,"duration":30,"rpe":8}"#.utf8)
        let card = try APIService.decoder.decode(DraftSet.self, from: oldCard)
        XCTAssertEqual(card.weight, "80")
        XCTAssertEqual(card.reps, "5")
        XCTAssertEqual(card.rir, 2)
        XCTAssertEqual(card.rpe, 8)
        XCTAssertNil(card.distance)
        XCTAssertNil(card.intensity)
        XCTAssertNil(card.durationLeft)
        XCTAssertNil(card.durationRight)
        XCTAssertNil(card.protocolCompleted)
        let oldLog = Data(#"{"weight":80,"reps":"5","rir":2,"rpe":8}"#.utf8)
        let log = try APIService.decoder.decode(PersistedSet.self, from: oldLog)
        XCTAssertEqual(log.weight, 80)
        XCTAssertEqual(log.reps, "5")
        XCTAssertEqual(log.rir, 2)
        XCTAssertEqual(log.rpe, 8)
        XCTAssertNil(log.distanceM)
        XCTAssertNil(log.intensity)
        XCTAssertNil(log.leftTime)
        XCTAssertNil(log.rightTime)
    }

    func testSpecializedLogPayloadsSurviveSessionStoreAndRestore() throws {
        let cases: [(String, [String: Any])] = [
            ("reps", ["weight": 80.0, "reps": "5", "rir": 2, "rpe": 8.0]),
            ("reps", ["weight": 0.0, "reps": "8", "rir": 3, "rpe": 7.0]),
            ("carry", ["weight": 40.0, "distance_m": 25]),
            ("plyo", ["weight": 0.0, "reps": "6", "intensity": 42.5]),
            ("time", ["weight": 0, "reps": "45"]),
            ("time", ["weight": 0, "reps": "65", "left": ["time": 30], "right": ["time": 35]]),
            ("protocol", ["weight": 0])
        ]
        for (tracking, payload) in cases {
            let date = "payload-test-\(UUID().uuidString)"
            defer { SessionDraftStore.clear(date: date, sessionType: "evening") }
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.seanceDataJSON(todayDate: date)) as? [String: Any])
            // Carry/protocol also retain their type when the screen's inventory is not in seanceData.
            json["inventory_tracking"] = ["Bench Press": tracking == "carry" || tracking == "protocol" ? "reps" : tracking]
            let data = try APIService.decoder.decode(SeanceData.self, from: JSONSerialization.data(withJSONObject: json))
            let original = SeanceViewModel(draftSessionType: "evening")
            original.seanceData = data
            original.logResults = ["Bench Press": ExerciseLogResult(
                name: "Bench Press", weight: 40, reps: "1", sets: [payload], isSecond: true,
                trackingType: tracking
            )]
            XCTAssertEqual(SessionDraftStore.load(date: date, sessionType: "evening").first?.sets.count, 1)
            let restored = SeanceViewModel(draftSessionType: "evening")
            restored.seanceData = data
            restored.restoreLogResults(from: data, serverSessionType: "evening", serverCompleted: false)
            let restoredPayload = try XCTUnwrap(restored.logResults["Bench Press"]?.sets.first)
            XCTAssertTrue(NSDictionary(dictionary: payload).isEqual(to: restoredPayload), tracking)
            XCTAssertEqual(SessionDraftStore.load(date: date, sessionType: "evening").first?.sets.count, 1)
        }
        for tracking in ["reps", "carry", "plyo", "time", "protocol"] {
            XCTAssertNil(PersistedSet.preserving([:], trackingType: tracking))
        }
        XCTAssertNil(PersistedSet.preserving(["weight": 0], trackingType: "reps"))
        XCTAssertNil(PersistedSet.preserving(["weight": 0, "distance_m": 0], trackingType: "carry"))
    }

    func testSpecializedCardInputsSurviveDebouncedSaveAndRecreation() async throws {
        let date = "card-test-\(UUID().uuidString)"
        let store = ExerciseDraftPersistence(date: date, sessionType: "morning", exerciseName: "Draft test")
        defer { store.clear() }
        let original = ExerciseViewModel(name: "Draft test", scheme: "1x5", weightData: nil, sessionDate: date)
        original.sets = [SetInput(weight: "12,5", reps: "6", duration: 45,
                                  durationLeft: 20, durationRight: 25, distance: "30",
                                  intensity: "42,5", rir: 2, rpe: 8, protocolCompleted: true)]
        original.sessionNote = "Contrôle lent sur la descente"
        // ExerciseViewModel's production draft save is debounced by 0.5 seconds.
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(store.loadCard()?.sessionNote, "Contrôle lent sur la descente")
        let recreated = ExerciseViewModel(name: "Draft test", scheme: "1x5", weightData: nil, sessionDate: date)
        recreated.initializeSets()
        let restored = try XCTUnwrap(recreated.sets.first)
        XCTAssertEqual(restored.weight, "12,5")
        XCTAssertEqual(restored.reps, "6")
        XCTAssertEqual(restored.duration, 45)
        XCTAssertEqual(restored.durationLeft, 20)
        XCTAssertEqual(restored.durationRight, 25)
        XCTAssertEqual(restored.distance, "30")
        XCTAssertEqual(restored.intensity, "42,5")
        XCTAssertEqual(restored.rir, 2)
        XCTAssertEqual(restored.rpe, 8)
        XCTAssertTrue(restored.protocolCompleted)
        XCTAssertEqual(recreated.sessionNote, "Contrôle lent sur la descente")

        let result = try XCTUnwrap(recreated.logExercise(alreadyLoggedViaBinding: false))
        XCTAssertEqual(result.notes, "Contrôle lent sur la descente")
        XCTAssertEqual(recreated.sessionNote, "")
        XCTAssertNil(store.loadCard())
    }

    func testLegacyExerciseCardDraftRestoresWithoutNote() throws {
        let date = "legacy-card-test-\(UUID().uuidString)"
        let exerciseName = "Legacy draft"
        let store = ExerciseDraftPersistence(date: date, sessionType: "morning", exerciseName: exerciseName)
        defer { store.clear() }
        let legacySets = [DraftSet(weight: "80", reps: "5", rir: 2, duration: 30)]
        let data = try APIService.encoder.encode(legacySets)
        UserDefaults.standard.set(
            data,
            forKey: "\(ExerciseDraftPersistence.keyPrefix)\(date)_morning_\(exerciseName)"
        )

        let restored = try XCTUnwrap(store.loadCard())
        XCTAssertEqual(restored.sets.first?.weight, "80")
        XCTAssertEqual(restored.sets.first?.reps, "5")
        XCTAssertNil(restored.sessionNote)
    }

    func testExerciseNoteSurvivesSessionDraftStoreAndRestore() throws {
        let date = "note-session-test-\(UUID().uuidString)"
        defer { SessionDraftStore.clear(date: date, sessionType: "evening") }
        let data = try APIService.decoder.decode(
            SeanceData.self,
            from: Fixtures.seanceDataJSON(todayDate: date)
        )
        let original = SeanceViewModel(draftSessionType: "evening")
        original.seanceData = data
        original.logResults = [
            "Bench Press": ExerciseLogResult(
                name: "Bench Press", weight: 80, reps: "5",
                sets: [["weight": 80.0, "reps": "5"]],
                isSecond: true, equipmentType: "barbell",
                notes: "Coude stable, aucune douleur"
            )
        ]

        XCTAssertEqual(
            SessionDraftStore.load(date: date, sessionType: "evening").first?.notes,
            "Coude stable, aucune douleur"
        )

        let restored = SeanceViewModel(draftSessionType: "evening")
        restored.seanceData = data
        restored.restoreLogResults(
            from: data,
            serverSessionType: "evening",
            serverCompleted: false
        )
        XCTAssertEqual(restored.logResults["Bench Press"]?.notes, "Coude stable, aucune douleur")
    }

    func testDraftCleanupRequiresMatchingCompletedSession() throws {
        let cases: [(draft: String, source: String, completed: Bool?, clears: Bool)] = [
            ("evening", "morning", true, false),
            ("morning", "evening", true, false),
            ("evening", "evening", false, false),
            ("evening", "evening", nil, false),
            ("evening", "evening", true, false),
            ("morning", "morning", true, false),
            ("bonus", "morning", true, false),
            ("bonus", "evening", true, false)
        ]
        for testCase in cases {
            let date = "draft-cleanup-test-\(UUID().uuidString)"
            defer { SessionDraftStore.clear(date: date, sessionType: testCase.draft) }
            let data = try APIService.decoder.decode(SeanceData.self, from: Fixtures.seanceDataJSON(
                todayDate: date, alreadyLogged: true
            ))
            SessionDraftStore.save(date: date, sessionType: testCase.draft, values: [
                PersistedExerciseLogResult(
                    name: "Bench Press", weight: 80, reps: "5", rpe: 7,
                    isSecond: testCase.draft == "evening", isBonus: testCase.draft == "bonus",
                    equipmentType: "barbell", painZone: "",
                    sets: [PersistedSet(weight: 80, reps: "5", rir: 3, rpe: 7)]
                )
            ])
            let vm = SeanceViewModel(draftSessionType: testCase.draft)
            vm.seanceData = data
            vm.restoreLogResults(from: data, serverSessionType: testCase.source,
                                 serverCompleted: testCase.completed)

            XCTAssertEqual(SessionDraftStore.hasDraft(date: date, sessionType: testCase.draft),
                           !testCase.clears, "\(testCase)")
            XCTAssertEqual(vm.logResults["Bench Press"]?.weight, 80)
            XCTAssertEqual(vm.logResults["Bench Press"]?.reps, "5")
            XCTAssertEqual(vm.logResults["Bench Press"]?.notes, "")

            // A second restore must still find drafts preserved after a foreign/partial state.
            if !testCase.clears {
                vm.restoreLogResults(from: data, serverSessionType: testCase.draft, serverCompleted: nil)
                XCTAssertEqual(vm.logResults["Bench Press"]?.weight, 80)
                XCTAssertTrue(SessionDraftStore.hasDraft(date: date, sessionType: testCase.draft))
            }
        }
    }

    func testRestoreLogResultsFromCache() async throws {
        let todayDate = "2026-03-15"
        let data = Fixtures.seanceDataJSON(
            today: "Push A",
            todayDate: todayDate,
            exerciseName: "Bench Press",
            historyDate: todayDate,   // history entry matches today → should restore
            historyWeight: 80.0,
            historyReps: "5"
        )
        let vm = makeViewModel(cacheData: data)

        await vm.load()

        XCTAssertNotNil(vm.logResults["Bench Press"],
                        "logResults should contain Bench Press because history[0].date == todayDate")
        let result = vm.logResults["Bench Press"]
        XCTAssertEqual(result?.weight, 80.0)
        XCTAssertEqual(result?.reps, "5")
    }

    func testNoRestoreIfHistoryOlderThanToday() async throws {
        let todayDate = "2026-03-15"
        let data = Fixtures.seanceDataJSON(
            today: "Push A",
            todayDate: todayDate,
            exerciseName: "Bench Press",
            historyDate: "2026-03-14",  // yesterday → should NOT restore
            historyWeight: 80.0,
            historyReps: "5"
        )
        let vm = makeViewModel(cacheData: data)

        await vm.load()

        XCTAssertNil(vm.logResults["Bench Press"],
                     "logResults should be empty when history date is older than todayDate")
    }

    func testLoadSetsIsLoadingFalseAfterCompletion() async throws {
        let todayDate = "2026-03-15"
        let data = Fixtures.seanceDataJSON(today: "Push A", todayDate: todayDate)
        let vm = makeViewModel(cacheData: data)

        XCTAssertFalse(vm.isLoading, "isLoading should start false")
        await vm.load()
        XCTAssertFalse(vm.isLoading, "isLoading should be false after load() completes")
    }

    func testNoErrorWhenCachePresent() async throws {
        let todayDate = "2026-03-15"
        let data = Fixtures.seanceDataJSON(today: "Push A", todayDate: todayDate)
        let vm = makeViewModel(cacheData: data)

        await vm.load()

        // Network will fail, but we have cached data so error should not be surfaced
        XCTAssertNil(vm.error, "error should remain nil when cached data is available")
        XCTAssertNotNil(vm.seanceData, "seanceData should be populated from cache")
    }

    func testRestoreMatinIgnoresEveningLogSameDay() async throws {
        // Racine 2026-07-20 : Bench loggué matin ET soir même jour. Backend trie
        // history par (date DESC, len(sets) DESC) — la row soir (plus riche) remonte
        // en tête. Sans le filtre session_type, restoreLogResults matin ramènerait
        // le log soir sous la clé matin, puis finish() le ré-posterait (crime 4).
        let todayDate = "2026-03-15"
        let json = """
        {
            "today": "Push A",
            "today_date": "\(todayDate)",
            "already_logged": false,
            "schedule": {"Lun": "Push A"},
            "full_program": {"Push A": {"Bench Press": "4x5-7"}},
            "weights": {
                "Bench Press": {
                    "current_weight": 195.0,
                    "last_reps": "6,5,3,3",
                    "history": [
                        {"date": "\(todayDate)", "weight": 195.0, "reps": "6,5,3,3",
                         "session_type": "evening",
                         "sets": [
                            {"weight": 195, "reps": "6"},
                            {"weight": 195, "reps": "5"},
                            {"weight": 195, "reps": "3"},
                            {"weight": 195, "reps": "3"}
                         ]},
                        {"date": "\(todayDate)", "weight": 185.0, "reps": "5,5,5",
                         "session_type": "morning"}
                    ]
                }
            },
            "week": 1,
            "inventory_types": {},
            "exercise_order": {}
        }
        """
        let vm = makeViewModel(cacheData: Data(json.utf8))
        await vm.load()

        let result = vm.logResults["Bench Press"]
        XCTAssertNotNil(result,
            "logResults doit contenir Bench Press (entry matin même jour existe)")
        XCTAssertEqual(result?.weight, 185.0,
            "restore matin doit prendre la row session_type=morning (185lbs), pas la row evening (195lbs) même si elle est en tête via tri (date DESC, len(sets) DESC)")
        XCTAssertEqual(result?.reps, "5,5,5")
    }
}
