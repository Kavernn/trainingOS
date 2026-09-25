//
//  SeanceViewModelTests.swift
//  TrainingOSTests
//
//  Strategy: pre-load the injected CacheService with SeanceData JSON,
//  then call load() — network fetch fails (no real server) and is silently
//  ignored since seanceData is already set from cache.

import XCTest
@testable import TrainingOS

@MainActor
final class SeanceViewModelTests: XCTestCase {

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
        var recorded = 0
        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome { .queuedOffline }
        override func sendEveningSession(exos: [String], rpe: Double, comment: String,
                                        durationMin: Double?, energyPre: Int?, sessionName: String?,
                                        exerciseLogs: [[String: Any]]) async throws -> SessionSaveOutcome {
            comments.append(comment)
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
            // Only Morning retains automatic cleanup on completion.
            if type == "morning" {
                vm.restoreLogResults(from: data, serverSessionType: type, serverCompleted: true)
                XCTAssertNil(SessionDraftStore.loadComment(date: date, sessionType: type))
            }
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
        override func sendExerciseForFinish(_ result: ExerciseLogResult) async throws -> ExerciseSaveOutcome {
            calls.append(result.name)
            sentWeights.append(result.weight)
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
    }

    func testFinishGateAllConfirmedAndFreshLifecycleResends() async {
        let vm = FinishSaveStub(draftSessionType: "morning")
        vm.logResults = ["A": ExerciseLogResult(name: "A", weight: 80, reps: "5")]
        let accepted = await vm.saveExercisesForFinish()
        XCTAssertTrue(accepted)
        let recreated = FinishSaveStub(draftSessionType: "morning")
        recreated.logResults = vm.logResults
        let restoredAccepted = await recreated.saveExercisesForFinish()
        XCTAssertTrue(restoredAccepted)
        XCTAssertEqual(recreated.calls, ["A"])
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
            ("morning", "morning", true, true),
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
