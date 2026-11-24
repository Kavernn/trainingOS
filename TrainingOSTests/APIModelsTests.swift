//
//  APIModelsTests.swift
//  TrainingOSTests
//

import XCTest
import UIKit
import HealthKit
@testable import TrainingOS

final class APIModelsTests: XCTestCase {

    func testExerciseSaveConfirmsBackendAcknowledgment() async throws {
        let data = Data(#"{"success":true,"status":"ok","increase":0,"new_weight":80,"1rm":93.3,"is_pr":false,"baseline_count":3,"confidence":"high","achieved":[]}"#.utf8)
        var calls = 0
        let outcome = try await ExerciseSaveOutcome.fromOfflinePost { calls += 1; return data }
        guard case .confirmed(let response) = outcome else { return XCTFail("Expected confirmed") }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(response.success, true)
        XCTAssertEqual(response.newWeight, 80)
        XCTAssertEqual(response.isPR, false)
    }

    func testExerciseSaveRejectsEmptyAndInvalidServerAcknowledgments() async {
        for body in ["{}", #"{"success":false}"#, #"{"success":null}"#,
                     #"{"is_pr":true}"#, #"{"success":"true"}"#, "not JSON"] {
            do {
                _ = try await ExerciseSaveOutcome.fromOfflinePost { Data(body.utf8) }
                XCTFail("Unexpected accepted outcome for \(body)")
            } catch APIError.decodingFailed(let endpoint, _) {
                XCTAssertEqual(endpoint, "/api/log")
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func testExerciseSaveDistinguishesAcceptedOfflineQueue() async throws {
        let suite = "exercise-outcome-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let queue = UserDefaultsSyncQueue(defaults: defaults)
        // Stub offlinePost's existing transport-error → enqueue → nil contract.
        let outcome = try await ExerciseSaveOutcome.fromOfflinePost {
            queue.append(PendingMutation(endpoint: "/api/log", payload: ["exercise": "Squat"]))
            return nil
        }
        guard case .queuedOffline = outcome else { return XCTFail("Must not confirm an offline save") }
        XCTAssertEqual(queue.load().count, 1)
    }

    func testExerciseSavePropagatesHTTPFailure() async {
        do {
            _ = try await ExerciseSaveOutcome.fromOfflinePost {
                throw APIError.serverError(500, "Injected exercise failure")
            }
            XCTFail("HTTP failure must not produce an accepted outcome")
        } catch APIError.serverError(let code, let message) {
            XCTAssertEqual(code, 500)
            XCTAssertEqual(message, "Injected exercise failure")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExerciseSavePropagatesLocalSerializationFailure() async {
        // ExerciseSaveOutcome must propagate a local writer error unchanged.
        // JSONSerialization with NaN raises NSException and kills the runner.
        let failure = NSError(domain: NSCocoaErrorDomain, code: CocoaError.propertyListWriteInvalid.rawValue,
                              userInfo: [NSLocalizedDescriptionKey: "Injected local serialization failure"])
        do {
            _ = try await ExerciseSaveOutcome.fromOfflinePost {
                throw failure
            }
            XCTFail("Invalid local JSON must throw before acceptance")
        } catch {
            XCTAssertTrue((error as NSError) === failure, "The exact local error must propagate without wrapping")
        }
    }

    // MARK: - Dashboard muscle metadata

    func testDashboardMuscleMetadataDecoding() throws {
        let json = dashboardJSON(extraFields: """
            "exercise_muscle_metadata": {
                "Bench Press": {
                    "muscle_group": "Pectoraux",
                    "muscle_specific": "Pectoral majeur — chef sternal",
                    "secondary_muscles": ["Triceps", "Deltoïde antérieur"],
                    "muscles": ["chest", "triceps", "front_delts"]
                }
            },
            """)

        let decoded = try JSONDecoder().decode(DashboardData.self, from: json)
        let metadata = try XCTUnwrap(decoded.exerciseMuscleMetadata["Bench Press"])

        XCTAssertEqual(metadata.muscleGroup, "Pectoraux")
        XCTAssertEqual(metadata.muscleSpecific, "Pectoral majeur — chef sternal")
        XCTAssertEqual(metadata.secondaryMuscles, ["Triceps", "Deltoïde antérieur"])
        XCTAssertEqual(metadata.legacyMuscles, ["chest", "triceps", "front_delts"])
        XCTAssertEqual(decoded.fullProgram["Push A"]?["Bench Press"]?.value, "4x5-7")
    }

    func testDashboardMuscleMetadataDefaultsWhenAbsent() throws {
        let decoded = try JSONDecoder().decode(DashboardData.self, from: dashboardJSON())
        XCTAssertTrue(decoded.exerciseMuscleMetadata.isEmpty)
    }

    func testExerciseMuscleMetadataDefaultsWhenInternalFieldsAreAbsent() throws {
        let decoded = try JSONDecoder().decode(
            ExerciseMuscleMetadata.self,
            from: Data(#"{"muscle_group":"Dos"}"#.utf8)
        )

        XCTAssertEqual(decoded.muscleGroup, "Dos")
        XCTAssertNil(decoded.muscleSpecific)
        XCTAssertTrue(decoded.secondaryMuscles.isEmpty)
        XCTAssertTrue(decoded.legacyMuscles.isEmpty)
    }

    // MARK: - Readiness optionnelle (build 1a)

    private static func readinessJSON(score: String, verdict: String) -> Data {
        let module = #"{"score":null,"label":"X","detail":"Données insuffisantes"}"#
        let modules = ["hrv", "rhr", "acwr", "sleep_quality", "sleep_duration", "subjective",
                       "muscle_rec", "nutrition", "pattern"].map { "\"\($0)\":\(module)" }.joined(separator: ",")
        return Data("""
        {"score":\(score),"verdict":\(verdict),"why":"Pas de HRV, FC repos, sommeil ni ressenti aujourd'hui.",
         "adjustment":null,"progression_modifier":null,"modules":{\(modules)},"muscle_recovery":{},
         "today_session":null,"hrv_status":null,"verdict_method":"absolute_cold_start","downgrade_reason":null}
        """.utf8)
    }

    func testReadinessWithoutDataDecodesWithNoScoreNoVerdict() throws {
        let r = try JSONDecoder().decode(ReadinessResponse.self, from: Self.readinessJSON(score: "null", verdict: "null"))
        XCTAssertNil(r.score)
        XCTAssertNil(r.verdict)
        XCTAssertEqual(r.verdictLabel, "—")
        XCTAssertEqual(r.verdictEmoji, "")
        XCTAssertEqual(r.verdictColor, "gray")
    }

    func testReadinessWithScoreStillDecodes() throws {
        let r = try JSONDecoder().decode(ReadinessResponse.self, from: Self.readinessJSON(score: "72", verdict: "\"go\""))
        XCTAssertEqual(r.score, 72)
        XCTAssertEqual(r.verdictLabel, "Prêt")
    }

    func testRestVerdictStaysRestButUnknownNeverBecomesRest() throws {
        let rest = try JSONDecoder().decode(ReadinessResponse.self, from: Self.readinessJSON(score: "30", verdict: "\"rest\""))
        XCTAssertEqual(rest.verdictLabel, "Repos")
        XCTAssertEqual(rest.verdictEmoji, "🔴")
        let unknown = try JSONDecoder().decode(ReadinessResponse.self, from: Self.readinessJSON(score: "50", verdict: "\"bizarre\""))
        XCTAssertEqual(unknown.verdictLabel, "—")
        XCTAssertNotEqual(unknown.verdictEmoji, "🔴")
    }

    // MARK: - Brief du matin & badge « Parfait » (build 2a)

    @MainActor
    func testMorningRevealIsNeutralWithoutRealRecommendation() {
        for missing in [nil, "unknown", "bizarre", ""] as [String?] {
            let r = MorningRevealView.reveal(for: missing)
            XCTAssertEqual(r.title, "Données insuffisantes", "\(String(describing: missing))")
            XCTAssertNotEqual(r.icon, "moon.zzz.fill")
        }
        XCTAssertEqual(MorningRevealView.reveal(for: "defer").title, "Journée de repos")
        XCTAssertEqual(MorningRevealView.reveal(for: "go").title, "Journée optimale")
        XCTAssertEqual(MorningRevealView.reveal(for: "go_caution").title, "Forme correcte")
        XCTAssertEqual(MorningRevealView.reveal(for: "reduce").title, "Intensité réduite")
    }

    @MainActor
    func testGreatDayBadgeNeedsRealGoAndLoadedDeloadAtZero() {
        XCTAssertTrue(DashboardView.showsGreatDayBadge(recommendation: "go", fatigueLevel: 0, sessionLoggedToday: true))
        // Deload pas chargé : plus compté comme « aucune fatigue ».
        XCTAssertFalse(DashboardView.showsGreatDayBadge(recommendation: "go", fatigueLevel: nil, sessionLoggedToday: true))
        XCTAssertFalse(DashboardView.showsGreatDayBadge(recommendation: "go", fatigueLevel: 1, sessionLoggedToday: true))
        XCTAssertFalse(DashboardView.showsGreatDayBadge(recommendation: "unknown", fatigueLevel: 0, sessionLoggedToday: true))
        XCTAssertFalse(DashboardView.showsGreatDayBadge(recommendation: nil, fatigueLevel: 0, sessionLoggedToday: true))
        XCTAssertFalse(DashboardView.showsGreatDayBadge(recommendation: "go", fatigueLevel: 0, sessionLoggedToday: false))
    }

    // MARK: - Stats : moyenne d'équilibre de vie sans données

    @MainActor
    func testBalanceAverageIsNilWithoutDataNeverZero() throws {
        func points(_ json: String) throws -> [MoodTrendPoint] {
            try JSONDecoder().decode([MoodTrendPoint].self, from: Data(json.utf8))
        }
        XCTAssertNil(MoodStressTrendView.averageBalance([]))
        XCTAssertNil(MoodStressTrendView.averageBalance(try points(#"[{"date":"2026-11-20","mood_score":6,"life_stress_score":null}]"#)))
        XCTAssertEqual(MoodStressTrendView.averageBalance(try points(#"[{"date":"2026-11-20","mood_score":null,"life_stress_score":60},{"date":"2026-11-21","mood_score":null,"life_stress_score":80}]"#)), 70)
    }

    // MARK: - Sommeil : union des intervalles (diagnostic 2026-11-23)

    @MainActor
    func testSleepUnionCountsOverlapsOnceAndClampsToWindow() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func at(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }
        let window = (at(0), at(18))
        // Phases core/deep/rem (7 h) + « endormi sans phase » qui les recouvre (7 h) : 7 h, pas 14.
        let night: [(start: Date, end: Date)] = [(at(6), at(9)), (at(9), at(11)), (at(11), at(13)), (at(6), at(13))]
        XCTAssertEqual(HealthKitService.unionSeconds(night, within: window.0, window.1) / 3600, 7, accuracy: 0.001)
        // Doublon exact : compté une fois.
        XCTAssertEqual(HealthKitService.unionSeconds([(at(1), at(2)), (at(1), at(2))], within: window.0, window.1) / 3600, 1, accuracy: 0.001)
        // Trou réel (réveil) conservé ; débordement hors fenêtre coupé.
        XCTAssertEqual(HealthKitService.unionSeconds([(at(-2), at(1)), (at(3), at(4))], within: window.0, window.1) / 3600, 2, accuracy: 0.001)
        XCTAssertEqual(HealthKitService.unionSeconds([], within: window.0, window.1), 0)
    }

    // MARK: - Sommeil : épisodes, Apple Watch prioritaire, union interne (correctif v2)

    private static let mtl: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Toronto")!; return c
    }()

    /// "2026-11-23 05:39" → Date (heure de Montréal).
    private static func at(_ s: String) -> Date {
        let f = DateFormatter(); f.calendar = mtl; f.timeZone = mtl.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    private typealias S = HealthKitService.SleepSampleInput
    private static let watchID = "com.apple.health.watch", otherID = "com.example.sleepapp"

    private static func w(_ v: HKCategoryValueSleepAnalysis, _ from: String, _ to: String) -> S {
        S(value: v.rawValue, start: at(from), end: at(to), sourceID: watchID, isAppleWatch: true)
    }
    private static func app(_ v: HKCategoryValueSleepAnalysis, _ from: String, _ to: String, id: String = otherID) -> S {
        S(value: v.rawValue, start: at(from), end: at(to), sourceID: id, isAppleWatch: false)
    }

    @MainActor
    private func main(_ samples: [S], day: String) -> SleepWindow? {
        HealthKitService.daySleep(samples, day: Self.at("\(day) 12:00"), calendar: Self.mtl)
    }

    @MainActor
    private func assertNight(_ n: SleepWindow?, hours: Double, bed: String, wake: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let n else { return XCTFail("aucun épisode", file: file, line: line) }
        XCTAssertEqual(n.hours, hours, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(n.bedtime, Self.at(bed), file: file, line: line)
        XCTAssertEqual(n.wakeTime, Self.at(wake), file: file, line: line)
    }

    /// Nuit du 22-23 nov (reconstituée d'après l'audit : montre 7,08 h, 22:10 → 05:39) + app tierce.
    @MainActor
    func testSleepNight23NovWatchOnly() {
        let samples = [
            Self.w(.asleepCore, "2026-11-22 22:10", "2026-11-22 23:40"),
            Self.w(.awake,      "2026-11-22 23:40", "2026-11-22 23:52"),
            Self.w(.asleepDeep, "2026-11-22 23:52", "2026-11-23 02:30"),
            Self.w(.awake,      "2026-11-23 02:30", "2026-11-23 02:42"),
            Self.w(.asleepREM,  "2026-11-23 02:42", "2026-11-23 05:39"),
            Self.app(.asleepUnspecified, "2026-11-22 21:50", "2026-11-23 06:00"),
        ]
        assertNight(main(samples, day: "2026-11-23"), hours: 7.08, bed: "2026-11-22 22:10", wake: "2026-11-23 05:39")
    }

    /// Nuit du 20-21 nov (reconstituée : montre 7,51 h, 01:51 → 10:54, réveil 02:19 → 03:42
    /// pendant que l'app tierce voit « endormi » — l'union le compterait à tort).
    @MainActor
    func testSleepNight21NovWatchOnlyKeepsWatchAwakePeriod() {
        let samples = [
            Self.w(.asleepCore, "2026-11-21 01:51", "2026-11-21 02:19"),
            Self.w(.awake,      "2026-11-21 02:19", "2026-11-21 03:42"),
            Self.w(.asleepDeep, "2026-11-21 03:42", "2026-11-21 06:00"),
            Self.w(.asleepREM,  "2026-11-21 06:09", "2026-11-21 10:54"),
            Self.app(.asleepUnspecified, "2026-11-21 01:30", "2026-11-21 10:54"),
        ]
        assertNight(main(samples, day: "2026-11-21"), hours: 7.51, bed: "2026-11-21 01:51", wake: "2026-11-21 10:54")
    }

    @MainActor
    func testSleepLateNightWakingAfterNoonIsNotTruncated() {
        let samples = [Self.w(.asleepCore, "2026-11-08 04:00", "2026-11-08 13:00")]
        assertNight(main(samples, day: "2026-11-08"), hours: 9, bed: "2026-11-08 04:00", wake: "2026-11-08 13:00")
    }

    @MainActor
    func testSleepTravelBedtimeBefore18hIsNotTruncated() {
        // Décalage horaire : couché à 16:00 la veille, levé à 00:30.
        let samples = [Self.w(.asleepCore, "2026-09-13 16:00", "2026-09-14 00:30")]
        assertNight(main(samples, day: "2026-09-14"), hours: 8.5, bed: "2026-09-13 16:00", wake: "2026-09-14 00:30")
    }

    /// 11 nov (reconstitué d'après l'audit) : fragment 22:54 → 23:24, réveil > 3 h, nuit
    /// 02:35 → 06:35 (3,75 h dormies). Somme des épisodes nocturnes : 4,25 h, coucher 22:54.
    @MainActor
    func testSleepNight11NovEveningFragmentIsAdded() {
        let samples = [
            Self.w(.asleepCore, "2026-11-10 22:54", "2026-11-10 23:24"),
            Self.w(.asleepCore, "2026-11-11 02:35", "2026-11-11 04:00"),
            Self.w(.awake,      "2026-11-11 04:00", "2026-11-11 04:15"),
            Self.w(.asleepREM,  "2026-11-11 04:15", "2026-11-11 06:35"),
        ]
        assertNight(main(samples, day: "2026-11-11"), hours: 4.25, bed: "2026-11-10 22:54", wake: "2026-11-11 06:35")
        XCTAssertEqual(HealthKitService.sleepEpisodes(samples).count, 2)
    }

    /// 9 nov (reconstitué) : fin de la nuit tardive du 8 (→ 13:46) dans la plage lue mais rattachée
    /// au 8 ; fragment 23:02 → 23:20 le 8 au soir + nuit 02:51 → 10:44 (7,22 h). Le 9 = 7,52 h.
    @MainActor
    func testSleepNight9NovKeepsFragmentAndExcludesPreviousLateMorning() {
        let samples = [
            Self.w(.asleepCore, "2026-11-08 02:41", "2026-11-08 13:46"),   // nuit du 8 (non comptée le 9)
            Self.w(.asleepCore, "2026-11-08 23:02", "2026-11-08 23:20"),   // fragment
            Self.w(.asleepCore, "2026-11-09 02:51", "2026-11-09 06:00"),
            Self.w(.awake,      "2026-11-09 06:00", "2026-11-09 06:40"),
            Self.w(.asleepREM,  "2026-11-09 06:40", "2026-11-09 10:44"),
        ]
        assertNight(main(samples, day: "2026-11-09"), hours: 7.52, bed: "2026-11-08 23:02", wake: "2026-11-09 10:44")
        assertNight(main(samples, day: "2026-11-08"), hours: 11.083, bed: "2026-11-08 02:41", wake: "2026-11-08 13:46")
    }

    /// Synchro pendant le sommeil puis plus tard : la règle est sans état, la relecture plus tard
    /// donne la nuit complète (le blocage éventuel est côté stockage, pas côté lecture).
    @MainActor
    func testSleepLaterReadGivesTheFullNight() {
        let full = [Self.w(.asleepCore, "2026-11-08 02:41", "2026-11-08 13:46")]
        let at1205 = [Self.w(.asleepCore, "2026-11-08 02:41", "2026-11-08 12:05")]   // vu à 12:05
        assertNight(main(at1205, day: "2026-11-08"), hours: 9.4, bed: "2026-11-08 02:41", wake: "2026-11-08 12:05")
        assertNight(main(full, day: "2026-11-08"), hours: 11.083, bed: "2026-11-08 02:41", wake: "2026-11-08 13:46")
    }

    @MainActor
    func testSleepAfternoonNapIsSeparateWhenGapExceeds3h() {
        let samples = [
            Self.w(.asleepCore, "2026-10-01 23:00", "2026-10-02 07:00"),
            Self.w(.asleepCore, "2026-10-02 14:00", "2026-10-02 15:00"),   // sieste, écart 7 h
        ]
        assertNight(main(samples, day: "2026-10-02"), hours: 8, bed: "2026-10-01 23:00", wake: "2026-10-02 07:00")
        XCTAssertEqual(HealthKitService.sleepEpisodes(samples).count, 2)
    }

    @MainActor
    func testSleepGapUnder3hStaysInTheSameEpisode() {
        let samples = [
            Self.w(.asleepCore, "2026-10-01 23:00", "2026-10-02 02:00"),
            Self.w(.asleepCore, "2026-10-02 03:30", "2026-10-02 07:00"),   // réveil 1 h 30
        ]
        assertNight(main(samples, day: "2026-10-02"), hours: 6.5, bed: "2026-10-01 23:00", wake: "2026-10-02 07:00")
    }

    @MainActor
    func testSleepUnionInsideTheRetainedSource() {
        // Phases + « endormi sans phase » qui les recouvre + doublon, même source : 7 h, pas 14.
        let samples = [
            Self.w(.asleepCore, "2026-10-17 00:00", "2026-10-17 03:00"),
            Self.w(.asleepDeep, "2026-10-17 03:00", "2026-10-17 05:00"),
            Self.w(.asleepREM,  "2026-10-17 05:00", "2026-10-17 07:00"),
            Self.w(.asleepUnspecified, "2026-10-17 00:00", "2026-10-17 07:00"),
            Self.w(.asleepREM,  "2026-10-17 05:00", "2026-10-17 07:00"),
            Self.w(.inBed,      "2026-10-16 23:30", "2026-10-17 07:30"),
        ]
        assertNight(main(samples, day: "2026-10-17"), hours: 7, bed: "2026-10-17 00:00", wake: "2026-10-17 07:00")
    }

    @MainActor
    func testSleepWithoutWatchPicksLongestSourceNeverAddsThem() {
        let samples = [
            Self.app(.asleepUnspecified, "2026-10-10 00:00", "2026-10-10 06:00", id: "app.a"),
            Self.app(.asleepUnspecified, "2026-10-10 00:30", "2026-10-10 07:30", id: "app.b"),
        ]
        assertNight(main(samples, day: "2026-10-10"), hours: 7, bed: "2026-10-10 00:30", wake: "2026-10-10 07:30")
    }

    @MainActor
    func testSleepEpisodeEndingPreviousDayIsNotCountedAndEmptyIsNil() {
        let previousNap = [Self.w(.asleepCore, "2026-10-09 13:00", "2026-10-09 14:00")]
        XCTAssertNil(main(previousNap, day: "2026-10-10"))
        XCTAssertNil(main([Self.w(.inBed, "2026-10-10 00:00", "2026-10-10 07:00")], day: "2026-10-10"))
        XCTAssertNil(main([], day: "2026-10-10"))
    }

    // MARK: - Fiche récupération : seuls les champs HealthKit modifiés sont déclarés (manual_fields)

    @MainActor
    func testRecoverySheetDeclaresOnlyEditedHealthKitFields() {
        let baseline = ["hrv": "26", "resting_hr": "77", "sleep_hours": "7.1", "steps": "416",
                        "bedtime": "22:10", "wake_time": "05:39", "hr_evening": ""]
        // Rien touché : aucun champ déclaré (la synchro garde la main, précision complète).
        XCTAssertEqual(LogRecoverySheet.editedHKFields(current: baseline, baseline: baseline), [])
        // HRV et coucher modifiés, FC soir saisie (vide au départ).
        var current = baseline
        current["hrv"] = "31"; current["bedtime"] = "22:30"; current["hr_evening"] = "58"
        XCTAssertEqual(LogRecoverySheet.editedHKFields(current: current, baseline: baseline), ["hrv", "bedtime", "hr_evening"])
        // Champ vidé : rien à déclarer (pas de valeur saisie).
        current = baseline; current["resting_hr"] = ""
        XCTAssertEqual(LogRecoverySheet.editedHKFields(current: current, baseline: baseline), [])
        // Pré-remplissage pas encore arrivé (baseline vide) : une valeur présente compte comme saisie.
        XCTAssertEqual(LogRecoverySheet.editedHKFields(current: ["hrv": "40"], baseline: [:]), ["hrv"])
    }

    // MARK: - Build 3a : readiness rechargée après check-in, séance, tirer-pour-rafraîchir

    @MainActor
    func testAnalyticsReloadWhenForcedEvenIfAlreadyLoadedToday() {
        XCTAssertFalse(DashboardViewModel.shouldLoadAnalytics(forced: false, loadedDate: "2026-11-23", today: "2026-11-23"))
        XCTAssertTrue(DashboardViewModel.shouldLoadAnalytics(forced: true, loadedDate: "2026-11-23", today: "2026-11-23"))
        XCTAssertTrue(DashboardViewModel.shouldLoadAnalytics(forced: false, loadedDate: "2026-11-22", today: "2026-11-23"))
        XCTAssertTrue(DashboardViewModel.shouldLoadAnalytics(forced: false, loadedDate: "", today: "2026-11-23"))
    }

    func testRecoveryLoggedNotificationName() {
        XCTAssertEqual(Notification.Name.recoveryLogged.rawValue, "trainingos.recoveryLogged")
    }

    // MARK: - Build 3c : invitation au check-in seulement sans score

    @MainActor
    func testHeroAsksForCheckInOnlyWhenReadinessHasNoScore() throws {
        let empty = try JSONDecoder().decode(ReadinessResponse.self, from: Self.readinessJSON(score: "null", verdict: "null"))
        let scored = try JSONDecoder().decode(ReadinessResponse.self, from: Self.readinessJSON(score: "72", verdict: "\"go\""))
        XCTAssertTrue(DashboardHeroState.needsCheckIn(empty))
        XCTAssertFalse(DashboardHeroState.needsCheckIn(scored))
        XCTAssertFalse(DashboardHeroState.needsCheckIn(nil))   // chargement / erreur : pas d'invitation
    }

    // MARK: - Build 8 : tuile Entraînement = règle de la streak ; build 5 : grille sans trou

    @MainActor
    func testTrainingTileFollowsStreakRule() throws {
        let json = #"{"weekly_target":5,"weekly_streak_current":3,"weekly_streak_best":13,"week_at_risk":false,"current_week":{"week_start":"2026-11-23","days_active":2,"success":null},"weeks":[]}"#
        let streak = try JSONDecoder().decode(StreakResponse.self, from: Data(json.utf8))
        XCTAssertEqual(DashboardDomainGrid.trainingValue(streak), "2 / 5 jours actifs")
        XCTAssertEqual(DashboardDomainGrid.trainingValue(nil), "—")
    }

    @MainActor
    func testCardioColumnOnlyWhenSomethingToShow() {
        XCTAssertFalse(DashboardView.showsCardioColumn(hasCardio: false, hasError: false))
        XCTAssertTrue(DashboardView.showsCardioColumn(hasCardio: true, hasError: false))
        XCTAssertTrue(DashboardView.showsCardioColumn(hasCardio: false, hasError: true))
    }

    // MARK: - Build 9 : chaque information une seule fois

    private func hrvAnalysis(avg7: String, trend: String) throws -> HRVAnalysis {
        let json = #"{"today_rmssd":25.7,"hrv_7d_avg":"# + avg7 + #","hrv_30d_avg":46,"hrv_cv":null,"hrv_score":62.5,"hrv_zone":"red","hrv_trend":"# + trend + #","consecutive_low_days":2,"streak_alert":false,"contextual_message":null,"history_7d":[],"baseline_available":true,"data_points_7d":7,"data_points_30d":30,"sd_30d":8}"#
        return try JSONDecoder().decode(HRVAnalysis.self, from: Data(json.utf8))
    }

    @MainActor
    func testRecoveryTileShowsSevenDayTrendNotTodayValue() throws {
        let down = try hrvAnalysis(avg7: "41.4", trend: "\"down\"")
        XCTAssertEqual(DashboardDomainGrid.recoveryValue(down), "HRV 7 j : 41 ms")
        XCTAssertEqual(DashboardDomainGrid.recoverySubtext(down), "En baisse sur 7 j")
        XCTAssertFalse(DashboardDomainGrid.recoveryValue(down).contains("26"))   // valeur du jour : hero seulement
        let unknown = try hrvAnalysis(avg7: "null", trend: "null")
        XCTAssertEqual(DashboardDomainGrid.recoveryValue(unknown), "HRV 7 j : —")
        XCTAssertEqual(DashboardDomainGrid.recoverySubtext(unknown), "Tendance insuffisante")
        XCTAssertEqual(DashboardDomainGrid.recoveryValue(nil), "HRV 7 j : —")
    }

    @MainActor
    func testDashboardAlertSkipsAlertsAlreadyShownByATile() {
        func alert(_ id: String) -> ProactiveAlert {
            ProactiveAlert(id: id, type: "nutrition", severity: "info", title: id, message: "", action: "open_nutrition")
        }
        let alerts = [alert("no_log_today"), alert("low_protein")]
        XCTAssertEqual(AlertService.dashboardAlert(from: alerts, dismissed: [], today: "2026-11-23")?.id, "low_protein")
        XCTAssertNil(AlertService.dashboardAlert(from: [alert("no_log_today")], dismissed: [], today: "2026-11-23"))
        XCTAssertNil(AlertService.dashboardAlert(from: alerts, dismissed: ["low_protein_2026-11-23"], today: "2026-11-23"))
    }

    // MARK: - Build 10 : finances masquées par défaut

    @MainActor
    func testFinanceAmountMaskedUntilRevealed() {
        XCTAssertEqual(DashboardDomainGrid.financeText(cents: 123_456, revealed: false), "•••• $")
        XCTAssertNotEqual(DashboardDomainGrid.financeText(cents: 123_456, revealed: true), "•••• $")
        XCTAssertTrue(DashboardDomainGrid.financeText(cents: 123_456, revealed: true).contains("234"))
        XCTAssertEqual(DashboardDomainGrid.financeText(cents: nil, revealed: true), "—")
        XCTAssertEqual(DashboardDomainGrid.financeText(cents: nil, revealed: false), "—")
    }

    // MARK: - Incohérence de planning ≠ panne réseau (incident 23 nov 2026)

    @MainActor
    private func context(schedule: String, date: String = "2026-11-23") throws -> DashboardContextRead {
        let json = """
        {"schema_version":1,"date":"\(date)","active_program_id":"p1","current_program_id":"p1",
         "schedule":\(schedule),"evening_schedule":{},
         "full_program":{"Lundi Push A":{"Bench Press":"4x6"}},
         "session_order":["Lundi Push A"],"exercise_order":{"Lundi Push A":["Bench Press"]}}
        """
        return try JSONDecoder().decode(DashboardContextRead.self, from: Data(json.utf8))
    }

    @MainActor
    func testPlanningCitingSessionsOutsideActiveProgramIsPlanningMismatch() throws {
        // 23 nov : « Hiver 2027 » actif (1 séance), planning resté sur GymProgramme v4.
        let stale = try context(schedule: #"{"Lun":"Lundi AM — Push A","Mar":"Repos"}"#)
        XCTAssertThrowsError(try stale.validate(date: "2026-11-23")) { error in
            XCTAssertEqual(error as? DashboardContextError, .planningMismatch)
            XCTAssertNil(error as? URLError)                       // plus jamais -1017
        }
        XCTAssertNoThrow(try context(schedule: #"{"Lun":"Lundi Push A","Mar":"Repos"}"#).validate(date: "2026-11-23"))
        XCTAssertThrowsError(try context(schedule: "{}", date: "2026-11-22").validate(date: "2026-11-23")) { error in
            XCTAssertEqual(error as? DashboardContextError, .incompatible)
        }
    }

    @MainActor
    func testDashboardErrorMessagesAreReadableFrench() {
        XCTAssertEqual(APILoadingState.message(for: DashboardContextError.planningMismatch),
                       "Ton planning ne correspond pas au programme actif.")
        XCTAssertEqual(APILoadingState.message(for: URLError(.notConnectedToInternet)), "Pas de connexion internet.")
        XCTAssertEqual(APILoadingState.message(for: URLError(.cannotParseResponse)), "Réponse du serveur illisible — réessaie.")
        let generic = APILoadingState.message(for: URLError(.unknown))
        XCTAssertFalse(generic.contains("operation"))                 // jamais le texte système anglais
        XCTAssertEqual(generic, "Une erreur est survenue — réessaie.")
    }

    @MainActor
    func testNoActiveProgramIsAnExplicitStateNotAnOutage() {
        func body(_ s: String) -> Data { Data(s.utf8) }
        XCTAssertEqual(DashboardContextError.fromContextResponse(status: 409, body: body(#"{"error":"no_active_program"}"#)), .noActiveProgram)
        XCTAssertEqual(DashboardContextError.fromContextResponse(status: 404, body: body(#"{"error":"active_program_not_found"}"#)), .noActiveProgram)
        XCTAssertNil(DashboardContextError.fromContextResponse(status: 503, body: body(#"{"error":"dashboard_context_unavailable"}"#)))
        XCTAssertNil(DashboardContextError.fromContextResponse(status: 409, body: body("pas du json")))
        XCTAssertEqual(DashboardView.fullPageTitle(.noActiveProgram), "Aucun programme actif")
        XCTAssertEqual(DashboardView.fullPageTitle(.planningMismatch), "Planning à mettre à jour")
        XCTAssertEqual(DashboardView.fullPageTitle(nil), "Connexion impossible")
        XCTAssertEqual(APILoadingState.message(for: DashboardContextError.noActiveProgram), "Aucun programme actif.")
    }

    // MARK: - Photo de profil (build 6c)

    func testUserProfileReadsPhotoURLAndIgnoresLegacyBase64() throws {
        let json = Data(#"{"name":"Vince","photo_url":"https://x.co/profile-photos/user_1/a.jpg","photo_b64":"data:image/jpeg;base64,/9j/AAAA"}"#.utf8)
        let profile = try JSONDecoder().decode(UserProfile.self, from: json)
        XCTAssertEqual(profile.photoUrl, "https://x.co/profile-photos/user_1/a.jpg")
        let withoutPhoto = try JSONDecoder().decode(UserProfile.self, from: Data(#"{"name":"Vince","photo_b64":null}"#.utf8))
        XCTAssertNil(withoutPhoto.photoUrl)
    }

    @MainActor
    func testProfileAvatarCacheServesStoredImageWithoutNetwork() async {
        // Hôte .invalid : un accès réseau échouerait → load() rendrait nil.
        let url = URL(string: "https://avatar.invalid/user_1/\(UUID().uuidString).jpg")!
        XCTAssertNil(ProfileAvatarCache.cached(url))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }
        ProfileAvatarCache.store(image, for: url)
        XCTAssertTrue(ProfileAvatarCache.cached(url) === image)
        let loaded = await ProfileAvatarCache.load(url)
        XCTAssertTrue(loaded === image)
    }

    func testAvatarJPEGShrinks4000x3000ToAtMost512PixelsUnder150KB() throws {
        let data = try XCTUnwrap(Self.photoLike(width: 4000, height: 3000).avatarJPEG())
        let decoded = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(decoded.width, 512)
        XCTAssertEqual(decoded.height, 384)
        XCTAssertLessThan(data.count, 150 * 1024)
        // Format envoyé : sous la limite serveur de 800 000 caractères (routes/profile.py).
        XCTAssertLessThan(("data:image/jpeg;base64," + data.base64EncodedString()).count, 800_000)
    }

    func testAvatarJPEGAppliesEXIFOrientation() throws {
        let landscape = try XCTUnwrap(Self.photoLike(width: 4000, height: 3000).cgImage)
        let portrait = UIImage(cgImage: landscape, scale: 1, orientation: .right)  // photo prise en portrait
        let decoded = try XCTUnwrap(UIImage(data: XCTUnwrap(portrait.avatarJPEG()))?.cgImage)
        XCTAssertEqual(decoded.width, 384)
        XCTAssertEqual(decoded.height, 512)
    }

    func testAvatarJPEGNeverUpscalesSmallImages() throws {
        let decoded = try XCTUnwrap(UIImage(data: XCTUnwrap(Self.photoLike(width: 200, height: 100).avatarJPEG()))?.cgImage)
        XCTAssertEqual(decoded.width, 200)
        XCTAssertEqual(decoded.height, 100)
    }

    /// Image en pixels (scale 1) avec dégradés + motifs, plus réaliste qu'un aplat.
    private static func photoLike(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            let colors = [UIColor.systemOrange.cgColor, UIColor.systemIndigo.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil)!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
            for i in stride(from: 0, to: width, by: 97) {
                UIColor(white: CGFloat(i % 7) / 7, alpha: 0.5).setFill()
                ctx.fill(CGRect(x: i, y: (i * 13) % height, width: 60, height: 60))
            }
        }
    }

    @MainActor
    func testProfileAvatarCacheLoadFailureReturnsNil() async {
        let url = URL(string: "https://avatar.invalid/user_1/\(UUID().uuidString).jpg")!
        let loaded = await ProfileAvatarCache.load(url)
        XCTAssertNil(loaded)
        XCTAssertNil(ProfileAvatarCache.cached(url))
    }

    // MARK: - SeanceData

    func testSeanceDataDecoding() throws {
        let json = Fixtures.seanceDataJSON(
            today: "Push A",
            todayDate: "2026-03-15",
            exerciseName: "Bench Press"
        )
        let decoded = try JSONDecoder().decode(SeanceData.self, from: json)
        XCTAssertEqual(decoded.today, "Push A")
        XCTAssertEqual(decoded.todayDate, "2026-03-15")
        XCTAssertFalse(decoded.alreadyLogged)
        XCTAssertEqual(decoded.week, 1)
        XCTAssertNotNil(decoded.fullProgram["Push A"])
    }

    /// L6 : la séance lit SES prescriptions (prescriptions_by_session[today]) ; l'ancienne
    /// clé indexée par nom n'est jamais lue (un même exercice y prend la fourchette d'une autre séance).
    func testPrescriptionsComeFromTodaySessionNeverLegacyKey() throws {
        func payload(_ bySession: String) -> Data {
            Data(#"""
            {"today":"Lundi AM","today_date":"2026-11-24","already_logged":false,"schedule":{},
             "full_program":{"Lundi AM":{"Dips":"3x6-10"},"Vendredi AM":{"Dips":"3x8-12"}},
             "weights":{},"week":1,"inventory_types":{},"exercise_order":{},
             "prescriptions":{"Dips":{"sets":3,"rep_min":8,"rep_max":12}}\#(bySession)}
            """#.utf8)
        }
        let fresh = try JSONDecoder().decode(SeanceData.self, from: payload(#"""
            ,"prescriptions_by_session":{"Lundi AM":{"Dips":{"sets":3,"rep_min":6,"rep_max":10}},
             "Vendredi AM":{"Dips":{"sets":3,"rep_min":8,"rep_max":12}}}
            """#))
        XCTAssertEqual(fresh.prescriptions?["Dips"]?.repMin, 6)
        XCTAssertEqual(fresh.prescriptions?["Dips"]?.repMax, 10)
        let legacyOnly = try JSONDecoder().decode(SeanceData.self, from: payload(""))
        XCTAssertNil(legacyOnly.prescriptions, "Sans la nouvelle clé : pas de prescription, la carte utilise le schéma")
    }

    // MARK: - SafeString

    func testSafeStringFromString() throws {
        let json = Data("\"foo\"".utf8)
        let s = try JSONDecoder().decode(SafeString.self, from: json)
        XCTAssertEqual(s.value, "foo")
    }

    func testSafeStringFromNull() throws {
        let json = Data("null".utf8)
        let s = try JSONDecoder().decode(SafeString.self, from: json)
        XCTAssertEqual(s.value, "")
    }

    func testSafeStringFromArray() throws {
        let json = Data("[\"a\",\"b\"]".utf8)
        let s = try JSONDecoder().decode(SafeString.self, from: json)
        XCTAssertEqual(s.value, "a, b")
    }

    // MARK: - WeightData

    func testWeightDataDecoding() throws {
        let json = """
        {
            "current_weight": 80.0,
            "last_reps": "5",
            "last_logged": "2026-03-14",
            "history": [
                {"date": "2026-03-14", "weight": 80.0, "reps": "5x5", "1rm": 90.0}
            ]
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WeightData.self, from: json)
        XCTAssertEqual(decoded.currentWeight, 80.0)
        XCTAssertEqual(decoded.history?.first?.date, "2026-03-14")
        XCTAssertEqual(decoded.history?.first?.oneRM, 90.0)
    }

    // MARK: - PagedResponse

    func testPagedResponseDecoding() throws {
        let json = """
        {
            "items": [],
            "offset": 0,
            "limit": 20,
            "total": 42,
            "has_more": true,
            "next_offset": 20
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PagedResponse<HIITEntry>.self, from: json)
        XCTAssertTrue(decoded.hasMore)
        XCTAssertEqual(decoded.nextOffset, 20)
        XCTAssertEqual(decoded.total, 42)
        XCTAssertTrue(decoded.items.isEmpty)
    }

    func testMoodRPEResponseDecoding() throws {
        let json = Data(#"{"rpe_by_date":{"2026-09-08":7.5,"2026-09-06":8.0}}"#.utf8)
        let decoded = try JSONDecoder().decode(MoodRPEResponse.self, from: json)

        XCTAssertEqual(decoded.rpeByDate["2026-09-08"], 7.5)
        XCTAssertEqual(decoded.rpeByDate["2026-09-06"], 8.0)
    }

    func testMoodRPEHTTPFailureThrows() async {
        // fetchMoodRPE alimente un chart affiché (corrélation Mood × RPE) :
        // un 500 DOIT lever pour que le Loadable surface l'erreur dans
        // SectionErrorView, pas la masquer en "aucune donnée".
        let session = makeMockURLSession(statusCode: 500, data: Data(#"{"error":"unavailable"}"#.utf8))

        do {
            _ = try await APIService.shared.fetchMoodRPE(session: session)
            XCTFail("fetchMoodRPE doit lever sur HTTP 500")
        } catch {
            // OK — erreur remontée au caller.
        }
    }

    // MARK: - Stats cockpit contract

    func testStatsCockpitDecodesCompleteContractAndPreservesCivilDatesAndZero() throws {
        let decoded = try JSONDecoder().decode(StatsCockpitResponse.self, from: statsCockpitJSON())

        XCTAssertEqual(decoded.asOf, "2026-09-30")
        XCTAssertEqual(decoded.progression.baselineWindow.start, "2026-08-02")
        XCTAssertEqual(decoded.progression.recentWindow.end, "2026-09-30")
        XCTAssertEqual(decoded.progression.statusCounts.insufficientData, 1)
        XCTAssertEqual(decoded.progression.comparisons.count, 1)
        XCTAssertEqual(decoded.progression.comparisons[0].status, .improving)
        XCTAssertEqual(decoded.progression.comparisons[0].relativeDelta, 0.1)
        XCTAssertEqual(decoded.progression.comparisons[0].insufficiencyReason, nil)
        XCTAssertEqual(decoded.trainingLoad.summary.tonnage.coverage, .complete)
        XCTAssertEqual(decoded.trainingLoad.summary.tonnage.value, 0.0)
        XCTAssertEqual(decoded.trainingLoad.weekly[0].weekStart, "2026-09-28")
        XCTAssertEqual(decoded.muscles.coverage.unmappedExposureCount, 1)
        XCTAssertEqual(decoded.muscles.workloads[0].lastExposureDate, "2026-09-30")
        XCTAssertEqual(decoded.dataQuality.adapter.knownDeloadExposureCount, 0)
    }

    func testStatsCockpitDecodesAllKnownStatusesReasonsAndCoverage() throws {
        let json = statsCockpitJSON(
            comparison: """
            {"exercise_name":"Squat","tracking_type":"reps","status":"insufficientData","baseline_window":{"start":"2026-08-02","end":"2026-08-31"},"recent_window":{"start":"2026-09-01","end":"2026-09-30"},"baseline_best_e1rm":null,"recent_best_e1rm":null,"absolute_delta":null,"relative_delta":null,"baseline_exposure_count":1,"recent_exposure_count":0,"baseline_used_legacy_fallback":false,"recent_used_legacy_fallback":false,"insufficiency_reason":"insufficientBothWindows"}
            """,
            tonnageCoverage: "unavailable",
            tonnageValue: "null",
            attention: """
            {"kind":"noRecentImprovement","exercise_name":"Squat","observation_window":{"start":"2026-09-01","end":"2026-09-30"},"last_exposure_date":"2026-09-10","days_since_last_exposure":20,"valid_exposure_count":3,"covered_days":21,"latest_best_e1rm":100.0}
            """
        )
        let decoded = try JSONDecoder().decode(StatsCockpitResponse.self, from: json)
        XCTAssertEqual(decoded.progression.comparisons[0].status, .insufficientData)
        XCTAssertEqual(decoded.progression.comparisons[0].insufficiencyReason, .insufficientBothWindows)
        XCTAssertEqual(decoded.progression.attention[0].kind, .noRecentImprovement)
        XCTAssertNil(decoded.trainingLoad.summary.tonnage.value)
        XCTAssertEqual(decoded.trainingLoad.summary.tonnage.coverage, .unavailable)
    }

    func testStatsCockpitPreservesUnknownEnumValues() throws {
        let json = statsCockpitJSON(
            comparison: """
            {"exercise_name":"Bench","tracking_type":"futureTracking","status":"rapidlyImproving","baseline_window":{"start":"2026-08-02","end":"2026-08-31"},"recent_window":{"start":"2026-09-01","end":"2026-09-30"},"baseline_best_e1rm":100.0,"recent_best_e1rm":110.0,"absolute_delta":10.0,"relative_delta":0.1,"baseline_exposure_count":2,"recent_exposure_count":2,"baseline_used_legacy_fallback":false,"recent_used_legacy_fallback":false,"insufficiency_reason":"futureReason"}
            """,
            tonnageCoverage: "futureCoverage"
        )
        let decoded = try JSONDecoder().decode(StatsCockpitResponse.self, from: json)
        XCTAssertEqual(decoded.progression.comparisons[0].status, .unknown("rapidlyImproving"))
        XCTAssertEqual(decoded.progression.comparisons[0].insufficiencyReason, .unknown("futureReason"))
        XCTAssertEqual(decoded.trainingLoad.summary.tonnage.coverage, .unknown("futureCoverage"))
    }

    func testStatsCockpitRejectsMissingRequiredKeyAndInvalidType() throws {
        let complete = String(decoding: statsCockpitJSON(), as: UTF8.self)
        let missing = complete.replacingOccurrences(of: "\"data_quality\":", with: "\"removed_data_quality\":")
        XCTAssertThrowsError(try JSONDecoder().decode(StatsCockpitResponse.self, from: Data(missing.utf8)))

        let invalid = complete.replacingOccurrences(of: "\"comparison_window_days\":30", with: "\"comparison_window_days\":\"30\"")
        XCTAssertThrowsError(try JSONDecoder().decode(StatsCockpitResponse.self, from: Data(invalid.utf8)))
    }

    private func statsCockpitJSON(
        comparison: String = """
        {"exercise_name":"Bench Press","tracking_type":"reps","status":"improving","baseline_window":{"start":"2026-08-02","end":"2026-08-31"},"recent_window":{"start":"2026-09-01","end":"2026-09-30"},"baseline_best_e1rm":100.0,"recent_best_e1rm":110.0,"absolute_delta":10.0,"relative_delta":0.1,"baseline_exposure_count":2,"recent_exposure_count":2,"baseline_used_legacy_fallback":false,"recent_used_legacy_fallback":false,"insufficiency_reason":null}
        """,
        tonnageCoverage: String = "complete",
        tonnageValue: String = "0.0",
        attention: String = ""
    ) -> Data {
        Data("""
        {"as_of":"2026-09-30","progression":{"comparison_window_days":30,"baseline_window":{"start":"2026-08-02","end":"2026-08-31"},"recent_window":{"start":"2026-09-01","end":"2026-09-30"},"status_counts":{"improving":1,"stable":0,"declining":0,"insufficient_data":1},"comparisons":[\(comparison)],"top_movers":[],"top_movers_series":{},"attention":[\(attention)]},"training_load":{"period":{"start":"2026-09-01","end":"2026-09-30"},"summary":{"period":{"start":"2026-09-01","end":"2026-09-30"},"exposure_count":1,"session_count":1,"active_day_count":1,"reps_exposure_count":1,"valid_reps_set_count":1,"tonnage":{"value":\(tonnageValue),"applicable_exposure_count":1,"calculable_exposure_count":1,"coverage":"\(tonnageCoverage)"}},"weekly":[{"week_start":"2026-09-28","week_end":"2026-10-04","covered_window":{"start":"2026-09-28","end":"2026-09-30"},"is_partial":true,"exposure_count":0,"session_count":0,"active_day_count":0,"reps_exposure_count":0,"valid_reps_set_count":0,"tonnage":{"value":null,"applicable_exposure_count":0,"calculable_exposure_count":0,"coverage":"unavailable"}}],"daily":[]},"muscles":{"period":{"start":"2026-09-01","end":"2026-09-30"},"coverage":{"total_exposure_count":1,"mapped_exposure_count":0,"unmapped_exposure_count":1,"reps_exposure_count":1,"mapped_reps_exposure_count":0},"workloads":[{"muscle":"Pectoraux","direct_set_count":0,"indirect_set_count":0,"direct_exposure_count":0,"indirect_exposure_count":0,"session_count":0,"active_day_count":0,"last_exposure_date":"2026-09-30","weekly_effective_sets":0.0}],"previous_period":{"start":"2026-08-02","end":"2026-08-31"},"previous_workloads":[],"current_deload_days_excluded":0,"previous_deload_days_excluded":0,"targets_by_muscle":{"Pectoraux":{"mev_week":8,"mav_week":16,"mrv_week":22}}},"data_quality":{"requested_raw_period":{"start":"2026-08-02","end":"2026-09-30"},"adapter":{"queried_exposure_count":1,"analytics_exposure_count":1,"invalid_row_count":0,"missing_tracking_type_count":0,"missing_muscle_mapping_count":1,"legacy_strength_fallback_count":0,"known_deload_exposure_count":0}}}
        """.utf8)
    }

    private func dashboardJSON(extraFields: String = "") -> Data {
        Data("""
        {
            "today": "Push A",
            "week": 1,
            "today_date": "2026-03-15",
            "schedule": {},
            "sessions": {},
            "goals": {},
            "full_program": {"Push A": {"Bench Press": "4x5-7"}},
            \(extraFields)
            "nutrition_totals": {},
            "profile": {}
        }
        """.utf8)
    }

    // MARK: - WorkoutDNA — fixture prod réelle (guards CodingKeys)

    /// Fixture capturée depuis /api/workout_dna?period=90 (prod authentifiée)
    /// post bascule DNA Fiabilité (lots a→f + iOS lot). Toute CodingKey DNA
    /// manquante (ex: nGaps sans mapping "n_gaps") CASSE ce test au lieu
    /// de l'écran DNA.
    func testWorkoutDNADecodingFromProdFixture() throws {
        let data = Data(dnaProd90dJSON.utf8)
        let dna = try JSONDecoder().decode(WorkoutDNAResponse.self, from: data)

        // Les sous-structs ajoutés par le lot DNA Fiabilité DOIVENT décoder
        // leurs champs requis. Faille historique : nGaps sans mapping
        // "n_gaps" → DecodingError.keyNotFound sur l'écran prod.
        let spacing = try XCTUnwrap(dna.sessionSpacing)
        XCTAssertEqual(spacing.nGaps, 56)
        XCTAssertEqual(spacing.nSessions, 57)
        XCTAssertEqual(spacing.medianDays, 1.0)
        XCTAssertEqual(spacing.excludedDeloadSessions, 5)
        XCTAssertEqual(spacing.insufficientData, false)

        // Autres sections lot DNA Fiabilité — garde contre régression
        // sur leurs CodingKeys snake_case.
        let meta = try XCTUnwrap(dna.muscleDominantsMeta)
        XCTAssertEqual(meta.nSessions, 105)
        XCTAssertFalse(meta.insufficientData)

        let lift = try XCTUnwrap(dna.signatureLifts.first)
        XCTAssertEqual(lift.sessionCount, 17)
        XCTAssertEqual(lift.prEIrmLbs, 203.5)
        XCTAssertEqual(lift.firstDate, "2026-07-31")
        XCTAssertEqual(lift.lastDate, "2026-10-19")

        let muscle = try XCTUnwrap(dna.muscleDominants?.first)
        XCTAssertEqual(muscle.muscle, "Dos")
        XCTAssertEqual(muscle.effectiveSets, 15.8)

        XCTAssertEqual(dna.archetype.available, true)
        XCTAssertEqual(dna.ppl.insufficientData, false)
        XCTAssertEqual(dna.intensity.insufficientData, false)
    }

    // MARK: - Nutrition history — fixture prod + synthétique variant null

    /// Fixture capturée depuis /api/stats/nutrition_history?days=10 (prod
    /// authentifiée). Couvre les 3 cas de source :
    ///   - estimated AVEC pct_declared + snapshot (post-migration 098, 2026-10-17 → 22)
    ///   - estimated SANS pct (historique pré-098, 2026-10-23 → 25)
    ///   - source null (jour sans log, aujourd'hui, 2026-10-26)
    /// Note : aucun jour "detailed" dans la fenêtre réelle — couvert par le
    /// test synthétique ci-dessous.
    func testNutritionHistoryDecodingFromProdFixture() throws {
        let data = Data(nutritionHistoryProd10dJSON.utf8)
        let rows = try JSONDecoder().decode([DayNutritionHistory].self, from: data)
        XCTAssertEqual(rows.count, 10)

        // Jour estimé avec pct déclaré (post-098)
        let withPct = rows[0]
        XCTAssertEqual(withPct.date, "2026-10-17")
        XCTAssertEqual(withPct.calories, 2865.0)
        XCTAssertEqual(withPct.targetCalories, 2865)
        XCTAssertEqual(withPct.source, "estimated")
        XCTAssertTrue(withPct.isEstimated)
        XCTAssertFalse(withPct.isDetailed)
        XCTAssertEqual(withPct.pctCaloriesDeclared, 1.0)
        XCTAssertNil(withPct.pctProteinesDeclared)
        XCTAssertEqual(withPct.targetCaloriesSnapshot, 2865)

        // Jour estimé historique sans pct (pré-098)
        let historical = rows[6]
        XCTAssertEqual(historical.date, "2026-10-23")
        XCTAssertEqual(historical.source, "estimated")
        XCTAssertNil(historical.pctCaloriesDeclared)
        XCTAssertNil(historical.pctProteinesDeclared)
        XCTAssertNil(historical.targetCaloriesSnapshot)

        // Jour vide (aujourd'hui, aucune entrée)
        let empty = rows[rows.count - 1]
        XCTAssertEqual(empty.date, "2026-10-26")
        XCTAssertNil(empty.calories)
        XCTAssertNil(empty.proteines)
        XCTAssertNil(empty.source)
        XCTAssertEqual(empty.targetCalories, 3111)
    }

    /// Fixture synthétique couvrant les variants que la prod n'a pas
    /// aujourd'hui : jour "detailed" + jour sans target_calories.
    func testNutritionHistoryDecodingSyntheticVariants() throws {
        let data = Data(nutritionHistorySyntheticJSON.utf8)
        let rows = try JSONDecoder().decode([DayNutritionHistory].self, from: data)
        XCTAssertEqual(rows.count, 4)

        // Jour détaillé pleinement loggé (glucides/lipides retirés du modèle)
        XCTAssertEqual(rows[0].source, "detailed")
        XCTAssertTrue(rows[0].isDetailed)
        XCTAssertEqual(rows[0].calories, 2500.0)
        XCTAssertEqual(rows[0].targetCalories, 2800)
        XCTAssertNil(rows[0].pctCaloriesDeclared)
        XCTAssertNil(rows[0].targetCaloriesSnapshot)

        // Jour estimé AVEC pct (ratio 0.9)
        XCTAssertEqual(rows[1].source, "estimated")
        XCTAssertEqual(rows[1].pctCaloriesDeclared, 0.9)
        XCTAssertEqual(rows[1].pctProteinesDeclared, 0.95)
        XCTAssertEqual(rows[1].targetCaloriesSnapshot, 2800)

        // Jour sans log, target présent
        XCTAssertNil(rows[2].calories)
        XCTAssertNil(rows[2].source)
        XCTAssertEqual(rows[2].targetCalories, 2810)

        // Jour sans log ET sans target (<7j TDEE antérieurs)
        XCTAssertNil(rows[3].calories)
        XCTAssertNil(rows[3].source)
        XCTAssertNil(rows[3].targetCalories)
    }
}

private let nutritionHistoryProd10dJSON = #"""
[{"calories":2865.0,"date":"2026-10-17","glucides":0.0,"lipides":0.0,"pct_calories_declared":1,"pct_proteines_declared":null,"proteines":180.0,"source":"estimated","target_calories":2865,"target_calories_snapshot":2865},{"calories":2856.0,"date":"2026-10-18","glucides":0.0,"lipides":0.0,"pct_calories_declared":1,"pct_proteines_declared":null,"proteines":180.0,"source":"estimated","target_calories":2856,"target_calories_snapshot":2856},{"calories":2913.0,"date":"2026-10-19","glucides":0.0,"lipides":0.0,"pct_calories_declared":1,"pct_proteines_declared":null,"proteines":180.0,"source":"estimated","target_calories":2913,"target_calories_snapshot":2913},{"calories":2962.0,"date":"2026-10-20","glucides":0.0,"lipides":0.0,"pct_calories_declared":1,"pct_proteines_declared":null,"proteines":135.0,"source":"estimated","target_calories":2962,"target_calories_snapshot":2962},{"calories":2916.0,"date":"2026-10-21","glucides":0.0,"lipides":0.0,"pct_calories_declared":1,"pct_proteines_declared":null,"proteines":126.0,"source":"estimated","target_calories":2916,"target_calories_snapshot":2916},{"calories":2937.0,"date":"2026-10-22","glucides":0.0,"lipides":0.0,"pct_calories_declared":1,"pct_proteines_declared":null,"proteines":180.0,"source":"estimated","target_calories":2937,"target_calories_snapshot":2937},{"calories":2938.0,"date":"2026-10-23","glucides":0.0,"lipides":0.0,"pct_calories_declared":null,"pct_proteines_declared":null,"proteines":180.0,"source":"estimated","target_calories":2938,"target_calories_snapshot":null},{"calories":3572.0,"date":"2026-10-24","glucides":0.0,"lipides":0.0,"pct_calories_declared":null,"pct_proteines_declared":null,"proteines":198.0,"source":"estimated","target_calories":3106,"target_calories_snapshot":null},{"calories":3092.0,"date":"2026-10-25","glucides":0.0,"lipides":0.0,"pct_calories_declared":null,"pct_proteines_declared":null,"proteines":63.0,"source":"estimated","target_calories":3092,"target_calories_snapshot":null},{"calories":null,"date":"2026-10-26","glucides":null,"lipides":null,"pct_calories_declared":null,"pct_proteines_declared":null,"proteines":null,"source":null,"target_calories":3111,"target_calories_snapshot":null}]
"""#

private let nutritionHistorySyntheticJSON = #"""
[{"date":"2026-10-20","calories":2500.0,"proteines":180.0,"glucides":300.0,"lipides":80.0,"target_calories":2800,"source":"detailed","pct_calories_declared":null,"pct_proteines_declared":null,"target_calories_snapshot":null},{"date":"2026-10-21","calories":2520.0,"proteines":171.0,"glucides":0.0,"lipides":0.0,"target_calories":2810,"source":"estimated","pct_calories_declared":0.9,"pct_proteines_declared":0.95,"target_calories_snapshot":2800},{"date":"2026-10-22","calories":null,"proteines":null,"glucides":null,"lipides":null,"target_calories":2810,"source":null,"pct_calories_declared":null,"pct_proteines_declared":null,"target_calories_snapshot":null},{"date":"2026-10-23","calories":null,"proteines":null,"glucides":null,"lipides":null,"target_calories":null,"source":null,"pct_calories_declared":null,"pct_proteines_declared":null,"target_calories_snapshot":null}]
"""#

private let dnaProd90dJSON = #"""
{"archetype":{"available":true,"key":"grinder","label":"The Grinder","tagline":"Never misses. Never quits."},"computed_at":"2026-10-20T13:28:15.956360+00:00","consistency":{"active_weeks_pct":100,"archetype":"Warrior","cv":0.36,"score":88,"sessions_per_week":4.6,"weekly_counts":[5,7,4,5,5,4,6,4,2,7,5,5,1],"weekly_streak_best":13,"weekly_streak_current":3},"dna_seed":"f0ffdfb7","intensity":{"compound_pct":46,"endurance_pct":23,"excluded_no_load_profile":23,"force_pct":21,"hypertrophy_pct":56,"insufficient_data":false,"invalid_dates":0,"isolation_pct":54,"label":"Power Builder","n_sessions":56,"score":57},"intensity_timeline":[{"endurance_pct":12,"hypertrophy_pct":66,"month":"2026-05","strength_pct":22,"total_sets":213},{"endurance_pct":11,"hypertrophy_pct":62,"month":"2026-06","strength_pct":28,"total_sets":349},{"endurance_pct":18,"hypertrophy_pct":56,"month":"2026-07","strength_pct":26,"total_sets":416},{"endurance_pct":28,"hypertrophy_pct":50,"month":"2026-08","strength_pct":22,"total_sets":491},{"endurance_pct":29,"hypertrophy_pct":58,"month":"2026-09","strength_pct":13,"total_sets":249},{"endurance_pct":14,"hypertrophy_pct":66,"month":"2026-10","strength_pct":20,"total_sets":253}],"movement_patterns":{"diversity_score":118,"excluded_no_pattern":0,"has_data":true,"insufficient_data":false,"invalid_dates":0,"n_sessions":56,"patterns":[{"pattern":"Horizontal Push","pct":13,"sets":137},{"pattern":"Horizontal Pull","pct":12,"sets":126},{"pattern":"Elbow Flexion","pct":11,"sets":122},{"pattern":"Gainage","pct":9,"sets":102},{"pattern":"pull_vertical","pct":9,"sets":95},{"pattern":"Elbow Extension","pct":8,"sets":90},{"pattern":"Vertical Pull","pct":8,"sets":85},{"pattern":"Isolation","pct":8,"sets":81},{"pattern":"Vertical Push","pct":7,"sets":75},{"pattern":"pull_horizontal","pct":3,"sets":34},{"pattern":"Rotation","pct":3,"sets":33},{"pattern":"Hip Hinge","pct":2,"sets":21},{"pattern":"Squat","pct":2,"sets":21},{"pattern":"Plyometric","pct":2,"sets":18},{"pattern":"push_vertical","pct":1,"sets":12},{"pattern":"hinge","pct":1,"sets":9},{"pattern":"push_horizontal","pct":1,"sets":6},{"pattern":"rotation","pct":0,"sets":4},{"pattern":"Cardio","pct":0,"sets":2},{"pattern":"Carry","pct":0,"sets":1}],"ratios":{"push_horiz_vert":0.5},"total_sets":1074},"muscle_dominants":[{"effective_sets":15.8,"muscle":"Dos","pct":17,"sets":16},{"effective_sets":11.0,"muscle":"Pectoraux","pct":12,"sets":11},{"effective_sets":9.4,"muscle":"Triceps brachial","pct":10,"sets":9},{"effective_sets":7.6,"muscle":"Biceps brachial","pct":8,"sets":8},{"effective_sets":6.2,"muscle":"Épaules","pct":7,"sets":6},{"effective_sets":5.4,"muscle":"Arrière d'épaule","pct":6,"sets":5}],"muscle_dominants_meta":{"excluded_full_deload":0,"insufficient_data":false,"n_sessions":105},"period":{"from":"2026-07-22","to":"2026-10-20"},"ppl":{"balance_score":67,"core_pct":3,"insufficient_data":false,"invalid_dates":0,"legs_pct":9,"n_sessions":56,"other_pct":6,"pull_pct":52,"push_pct":39,"verdict":"Push-déficit"},"recovery":{"avg_rest_days":null,"optimal_rest_days":null,"ratio":null,"score":null,"verdict":null},"session_spacing":{"excluded_deload_sessions":5,"insufficient_data":false,"invalid_dates":0,"median_days":1.0,"n_gaps":56,"n_sessions":57,"p25_days":1.0,"p75_days":1.0},"signature_lifts":[{"first_date":"2026-07-31","last_date":"2026-10-19","name":"Triceps Pushdown","pr_date":"2026-08-17","pr_e1rm_lbs":203.5,"pr_lbs":130.0,"pr_reps":11,"progression_pct":-0.9,"session_count":17},{"first_date":"2026-07-27","last_date":"2026-10-19","name":"Bench Press","pr_date":"2026-08-06","pr_e1rm_lbs":234.3,"pr_lbs":185.0,"pr_reps":5,"progression_pct":0.0,"session_count":11},{"first_date":"2026-07-30","last_date":"2026-10-19","name":"Overhead Triceps Extension","pr_date":"2026-10-05","pr_e1rm_lbs":147.3,"pr_lbs":90.0,"pr_reps":15,"progression_pct":9.1,"session_count":11},{"first_date":"2026-07-24","last_date":"2026-10-18","name":"T-Bar Row","pr_date":"2026-07-17","pr_e1rm_lbs":120.0,"pr_lbs":90.0,"pr_reps":9,"progression_pct":-10.0,"session_count":11},{"first_date":"2026-07-24","last_date":"2026-10-13","name":"Face Pull","pr_date":"2026-08-05","pr_e1rm_lbs":229.1,"pr_lbs":140.0,"pr_reps":13,"progression_pct":8.3,"session_count":11}]}
"""#
