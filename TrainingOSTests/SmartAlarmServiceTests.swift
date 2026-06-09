import XCTest
@testable import TrainingOS

final class SmartAlarmServiceTests: XCTestCase {

    // MARK: - Helpers

    private func date(hour: Int, minute: Int, offsetDays: Int = 0) -> Date {
        let base = offsetDays == 0 ? Date() : Calendar.current.date(byAdding: .day, value: offsetDays, to: Date())!
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
    }

    // MARK: - Test 1 : coucher 23h00, fenêtre 06h30–07h00 → 06h45

    func testCycle_coucher23h_fenetre0630_0700_alarme0645() async {
        let bedtime = date(hour: 23, minute: 0)

        let (points, result) = await MainActor.run {
            let s = SmartAlarmService.shared
            let pts = s.calculateCyclePoints(bedtime: bedtime)
            let wStart = date(hour: 6,  minute: 30, offsetDays: 1)
            let wEnd   = date(hour: 7,  minute: 0,  offsetDays: 1)
            return (pts, s.selectOptimalPoint(from: pts, windowStart: wStart, windowEnd: wEnd))
        }

        let expected = date(hour: 6, minute: 45, offsetDays: 1)
        XCTAssertEqual(result, expected,
            "Coucher 23h00 + latence 15min → cycle n=5 à 06h45 dans fenêtre 06h30–07h00")
        // Vérifie aussi que le point n=5 est bien 06:45 parmi les cycles
        let cycle5 = date(hour: 6, minute: 45, offsetDays: 1)
        XCTAssertTrue(points.contains(cycle5), "Le 5e cycle (23h15 + 7h30) doit tomber à 06h45 demain")
    }

    // MARK: - Test 2 : coucher 23h00, fenêtre 07h00–07h30, aucun cycle → borne FIN 07h30

    func testCycle_coucher23h_fenetre0700_0730_borneFin() async {
        let bedtime = date(hour: 23, minute: 0)

        let result = await MainActor.run {
            let s = SmartAlarmService.shared
            let pts = s.calculateCyclePoints(bedtime: bedtime)
            // 06h45 < 07h00 (avant), 08h15 > 07h30 (après) → aucun cycle dans fenêtre
            let wStart = date(hour: 7,  minute: 0,  offsetDays: 1)
            let wEnd   = date(hour: 7,  minute: 30, offsetDays: 1)
            return s.selectOptimalPoint(from: pts, windowStart: wStart, windowEnd: wEnd)
        }

        XCTAssertEqual(result, date(hour: 7, minute: 30, offsetDays: 1),
            "Aucun cycle dans 07h00–07h30 → alarme à la borne FIN (07h30), pas début")
    }

    // MARK: - Test 3 : coucher 02h00 → alarme même jour (dayOffset=0), date correcte

    func testCycle_coucher02h_alarmeMemeJour() async {
        let bedtime = date(hour: 2, minute: 0)  // aujourd'hui 02h00

        let result = await MainActor.run {
            let s = SmartAlarmService.shared
            let pts = s.calculateCyclePoints(bedtime: bedtime)
            // bedtimeHour=2 < 12 → dayOffset=0 → fenêtre AUJOURD'HUI
            let wStart = date(hour: 6, minute: 30, offsetDays: 0)
            let wEnd   = date(hour: 7, minute: 0,  offsetDays: 0)
            return s.selectOptimalPoint(from: pts, windowStart: wStart, windowEnd: wEnd)
        }

        // 02h15 + 4h30 = 06h45 → dans fenêtre 06h30–07h00, même jour
        let expected = date(hour: 6, minute: 45, offsetDays: 0)
        XCTAssertEqual(result, expected,
            "Coucher 02h00 → cycle n=3 à 06h45 le MÊME jour (dayOffset=0)")

        // Vérification date : même jour que aujourd'hui (pas demain)
        let cal = Calendar.current
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: result),
                       cal.dateComponents([.year, .month, .day], from: Date()),
                       "L'alarme doit être aujourd'hui, pas demain")
    }

    // MARK: - Test 4 : coucher 23h00 → alarme lendemain (date correcte, pas juste heure)

    func testCycle_coucher23h_alarmeLendemain_dateCorrecte() async {
        let bedtime = date(hour: 23, minute: 0)

        let result = await MainActor.run {
            let s = SmartAlarmService.shared
            let pts = s.calculateCyclePoints(bedtime: bedtime)
            // bedtimeHour=23 >= 12 → dayOffset=1 → fenêtre DEMAIN
            let wStart = date(hour: 6, minute: 30, offsetDays: 1)
            let wEnd   = date(hour: 7, minute: 0,  offsetDays: 1)
            return s.selectOptimalPoint(from: pts, windowStart: wStart, windowEnd: wEnd)
        }

        let cal = Calendar.current
        let tomorrowComps = cal.dateComponents([.year, .month, .day],
                                               from: cal.date(byAdding: .day, value: 1, to: Date())!)
        let resultComps   = cal.dateComponents([.year, .month, .day], from: result)

        XCTAssertEqual(resultComps.year,  tomorrowComps.year,  "Alarme doit être l'année du lendemain")
        XCTAssertEqual(resultComps.month, tomorrowComps.month, "Alarme doit être le mois du lendemain")
        XCTAssertEqual(resultComps.day,   tomorrowComps.day,   "Alarme doit être le LENDEMAIN, pas aujourd'hui")
    }

    // MARK: - Test 5 : annulation via pendingAlarmID avant re-schedule

    func testReschedule_annulationViaID_propre() async {
        let fakeID = UUID()
        let key = "smartAlarm.pendingAlarmID"
        UserDefaults.standard.set(fakeID.uuidString, forKey: key)

        await MainActor.run {
            SmartAlarmService.shared.cancelAlarm()
        }

        XCTAssertNil(UserDefaults.standard.string(forKey: key),
            "cancelAlarm() doit supprimer pendingAlarmID de UserDefaults")
    }

    // MARK: - Test 6 : alarmTime <= Date() → guard bloque, rien d'armé

    func testAlarmInPast_guardDetecte() async {
        // Coucher hier 23h00 → cycles aujourd'hui (06h45 etc.)
        // Fenêtre hier 06h30–07h00 (passée) → aucun cycle match → windowEnd hier 07h00
        let bedtime = date(hour: 23, minute: 0, offsetDays: -1)

        let alarmTime = await MainActor.run {
            let s = SmartAlarmService.shared
            let pts = s.calculateCyclePoints(bedtime: bedtime)
            let wStart = date(hour: 6, minute: 30, offsetDays: -1)  // hier 06h30
            let wEnd   = date(hour: 7, minute: 0,  offsetDays: -1)  // hier 07h00
            return s.selectOptimalPoint(from: pts, windowStart: wStart, windowEnd: wEnd)
        }

        XCTAssertLessThan(alarmTime, Date(),
            "alarmTime = wEnd (hier 07h00) doit être dans le passé — guard alarmTime > Date() bloque le scheduling")
    }

    // MARK: - Test 7 : armement 22h30 (soir) → alarme LENDEMAIN, borne FIN 07h00

    func testSchedule_coucher2230_alarmeLendemain_borneFin() async {
        // 22:30 → sleepStart 22:45 → cycles : 00:15/01:45/03:15/04:45/06:15/07:45
        // Fenêtre 06:30–07:00 : n=5 à 06:15 (avant), n=6 à 07:45 (après) → borne FIN = 07:00
        let bedtime = date(hour: 22, minute: 30)

        let (points, result) = await MainActor.run {
            let s = SmartAlarmService.shared
            let pts = s.calculateCyclePoints(bedtime: bedtime)
            let wStart = date(hour: 6, minute: 30, offsetDays: 1)
            let wEnd   = date(hour: 7, minute: 0,  offsetDays: 1)
            return (pts, s.selectOptimalPoint(from: pts, windowStart: wStart, windowEnd: wEnd))
        }

        // Aucun cycle dans la fenêtre 06h30–07h00
        let wStart = date(hour: 6, minute: 30, offsetDays: 1)
        let wEnd   = date(hour: 7, minute: 0,  offsetDays: 1)
        XCTAssertFalse(points.contains { $0 >= wStart && $0 <= wEnd },
            "Aucun cycle 22h30 ne tombe dans 06h30–07h00")
        // Borne FIN appliquée → 07h00 demain
        XCTAssertEqual(result, date(hour: 7, minute: 0, offsetDays: 1),
            "Borne FIN 07h00 demain")
        // Date = LENDEMAIN (bedtimeHour=22 >= 12 → dayOffset=1)
        let cal = Calendar.current
        let tomorrowDay = cal.dateComponents([.day], from: cal.date(byAdding: .day, value: 1, to: Date())!).day
        XCTAssertEqual(cal.dateComponents([.day], from: result).day, tomorrowDay,
            "Coucher 22h30 → alarme le LENDEMAIN")
    }

    // MARK: - Test 8 : armement 00h30 (post-minuit) → alarme MÊME jour 06h45

    func testSchedule_coucher0030_alarme0645_memeJour() async {
        // 00:30 → sleepStart 00:45 → n=4 → 00:45 + 6h = 06:45 → dans fenêtre 06:30–07:00
        // bedtimeHour=0 < 12 → dayOffset=0 → même jour
        let bedtime = date(hour: 0, minute: 30)

        let result = await MainActor.run {
            let s = SmartAlarmService.shared
            let pts = s.calculateCyclePoints(bedtime: bedtime)
            let wStart = date(hour: 6, minute: 30, offsetDays: 0)
            let wEnd   = date(hour: 7, minute: 0,  offsetDays: 0)
            return s.selectOptimalPoint(from: pts, windowStart: wStart, windowEnd: wEnd)
        }

        XCTAssertEqual(result, date(hour: 6, minute: 45, offsetDays: 0),
            "Coucher 00h30 + latence 15min → cycle n=4 à 06h45, même jour")
        let cal = Calendar.current
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: result),
                       cal.dateComponents([.year, .month, .day], from: Date()),
                       "Alarme doit être aujourd'hui, pas demain")
    }

    // MARK: - Test 9 : cancelAlarm() → pendingAlarmID nil + état non armé

    func testCancelAlarm_nePlusArme() async {
        let fakeID = UUID()
        UserDefaults.standard.set(fakeID.uuidString, forKey: "smartAlarm.pendingAlarmID")

        await MainActor.run { SmartAlarmService.shared.cancelAlarm() }

        XCTAssertNil(UserDefaults.standard.string(forKey: "smartAlarm.pendingAlarmID"),
            "cancelAlarm() doit supprimer pendingAlarmID")
        // État ne doit plus être .armed(at:) quelle que soit la valeur de isEnabled
        let state = await MainActor.run { SmartAlarmService.shared.state }
        if case .armed = state {
            XCTFail("État ne doit pas être .armed après cancelAlarm() — obtenu \(state)")
        }
    }

    // MARK: - Test 10 : scheduleAlarm(bedtimeDate:) quand disabled → retour sans throw, sans armer
    // @MainActor requis — SmartAlarmService est @MainActor, les surcharges async de MainActor.run
    // ne sont pas résolues correctement dans ce contexte XCTest (Swift 6).

    @MainActor
    func testScheduleAlarm_disabled_noop() async {
        // disable() ne requiert pas AlarmKit si aucun pendingAlarmID n'est planté
        await SmartAlarmService.shared.disable()
        XCTAssertFalse(SmartAlarmService.shared.isEnabled,
            "isEnabled doit être false après disable()")

        let pendingBefore = UserDefaults.standard.string(forKey: "smartAlarm.pendingAlarmID")

        var threw = false
        do {
            try await SmartAlarmService.shared.scheduleAlarm(bedtimeDate: Date())
        } catch {
            threw = true
        }
        XCTAssertFalse(threw, "scheduleAlarm(bedtimeDate:) ne doit pas throw quand isEnabled=false")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "smartAlarm.pendingAlarmID"),
                       pendingBefore, "Aucun pendingAlarmID planté quand isEnabled=false")
        XCTAssertEqual(SmartAlarmService.shared.state, .disabled, "État reste .disabled")
    }
}
