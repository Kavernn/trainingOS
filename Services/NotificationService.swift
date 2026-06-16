import AVFoundation
import Combine
import SwiftUI
import UserNotifications

enum NotificationService {

    // MARK: - Preference helpers

    /// Returns true if a notification is enabled (defaults to true when never explicitly set).
    static func isEnabled(_ key: String) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static var globalDisabled: Bool {
        UserDefaults.standard.bool(forKey: "notif_all_disabled")
    }

    /// Schedules (or reschedules) all recurring app notifications.
    /// Safe to call multiple times — removes previous copies first.
    /// Uses BehaviorTracker to adapt times to the user's learned patterns.
    static func scheduleAll() {
        guard !globalDisabled else { return }
        let tracker = BehaviorTracker.shared
        if isEnabled("notif_on_seance_friday")  { scheduleFridayReminder(tracker: tracker) }
        if isEnabled("notif_on_selfcare")       { scheduleSelfCareReminder(tracker: tracker) }
        if isEnabled("notif_on_pss")            { schedulePSSWeeklyReminder(tracker: tracker) }
        if isEnabled("notif_on_nutrition")      { scheduleNutritionReminder(tracker: tracker) }
        if isEnabled("notif_on_recap")          { scheduleWeeklyRecapNotification(tracker: tracker) }
        let morningHour  = UserDefaults.standard.integer(forKey: "ritual_morning_hour")
        let eveningHour  = UserDefaults.standard.integer(forKey: "ritual_evening_hour")
        let eveningMin   = UserDefaults.standard.integer(forKey: "ritual_evening_minute")
        if isEnabled("notif_on_ritual_morning") {
            scheduleRitualMorningReminder(hour: morningHour > 0 ? morningHour : 7)
        }
        if isEnabled("notif_on_ritual_evening") {
            scheduleRitualEveningReminder(hour: eveningHour > 0 ? eveningHour : 20,
                                          minute: eveningMin > 0 ? eveningMin : 30)
        }
        let hrvHour   = UserDefaults.standard.integer(forKey: "hrv_morning_hour")
        let hrvMinute = UserDefaults.standard.integer(forKey: "hrv_morning_minute")
        if isEnabled("notif_on_hrv_morning") {
            scheduleHRVMorningReminder(hour: hrvHour > 0 ? hrvHour : 7, minute: hrvMinute)
        } else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["hrv.morning.reminder"])
        }
    }

    /// Call after data loads, passing the sorted session dates.
    static func scheduleContextual(sessionDates: [String], currentStreak: Int) {
        guard !globalDisabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            if isEnabled("notif_on_inactivity")       { scheduleInactivityReminder(sessionDates: sessionDates) }
            if isEnabled("notif_on_streak_milestone") { scheduleStreakMilestone(streak: currentStreak) }
        }
    }

    // MARK: - Friday Training Reminder (adaptive — defaults to 09:00)

    private static func scheduleFridayReminder(tracker: BehaviorTracker) {
        let center = UNUserNotificationCenter.current()
        let id = "weekly.friday.fullbody"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Full Body aujourd'hui 💪"
        content.body  = "Pull B + Full Body — c'est vendredi, on envoie."
        content.sound = .default

        // Adapt to learned session-end time, clamped to a reasonable training window (6–14h)
        let rawHour = tracker.preferredHour(for: .sessionEnd) ?? 9
        let hour = min(max(rawHour, 6), 14)

        var dc = DateComponents()
        dc.weekday = 6
        dc.hour    = hour
        dc.minute  = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Self-Care Daily Reminder (adaptive — defaults to 21:00)

    private static func scheduleSelfCareReminder(tracker: BehaviorTracker) {
        let center = UNUserNotificationCenter.current()
        let id = "selfcare.daily.reminder"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Habitudes du soir 🌙"
        content.body  = "Tes habitudes de self-care t'attendent — coche tes actions du jour."
        content.sound = .default

        // Use learned self-care time if available, else fall back to app-open evening hour
        let rawHour = tracker.preferredHour(for: .selfCareCheck)
                   ?? tracker.preferredHour(for: .appOpen)
                   ?? 21
        // Clamp to evening window (19–23)
        let hour = min(max(rawHour, 19), 23)

        var dc = DateComponents()
        dc.hour   = hour
        dc.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - PSS Weekly Reminder (adaptive Monday — defaults to 10:00)

    private static func schedulePSSWeeklyReminder(tracker: BehaviorTracker) {
        let center = UNUserNotificationCenter.current()
        let id = "pss.weekly.test"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Test PSS hebdo 🧠"
        content.body  = "Comment ton stress évolue cette semaine ? 2 minutes pour le mesurer."
        content.sound = .default

        // Use morning app-open hour (when user checks their score), clamped to 7–12
        let rawHour = tracker.preferredHour(for: .appOpen) ?? 10
        let hour = min(max(rawHour, 7), 12)

        var dc = DateComponents()
        dc.weekday = 2   // Monday
        dc.hour    = hour
        dc.minute  = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Nutrition Daily Reminder (adaptive — new, defaults to 12:30)

    private static func scheduleNutritionReminder(tracker: BehaviorTracker) {
        let center = UNUserNotificationCenter.current()
        let id = "nutrition.daily.reminder"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        // Only schedule once we have enough nutrition-logging data
        guard let rawHour = tracker.preferredHour(for: .nutritionLog) else { return }
        let hour = min(max(rawHour, 7), 20)

        // Don't remind if a meal was already logged today
        let today = DateFormatter.isoDate.string(from: Date())
        guard UserDefaults.standard.string(forKey: "nutrition.last.log.date") != today else { return }

        let content = UNMutableNotificationContent()
        content.title = "Repas du jour 🥗"
        content.body  = "Tu n'as pas encore loggé tes repas — garde le cap sur tes objectifs."
        content.sound = .default

        var dc = DateComponents()
        dc.hour   = hour
        dc.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Post-action cancellation

    static func cancelNutritionReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["nutrition.daily.reminder"])
    }

    static func cancelMorningRitualReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["ritual.morning.reminder", "ritual.streak.risk"])
    }

    static func cancelEveningRitualReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["ritual.evening.reminder"])
    }

    static func cancelSessionReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["weekly.friday.fullbody", "inactivity.reminder"])
    }

    static func cancelPSSReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["pss.weekly.test"])
    }

    static func cancelHRVReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["hrv.morning.reminder"])
    }

    // MARK: - Inactivity Reminder (adaptive fire time — defaults to 19:00)

    private static func scheduleInactivityReminder(sessionDates: [String]) {
        let center = UNUserNotificationCenter.current()
        let id = "inactivity.reminder"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard let lastDateStr = sessionDates.sorted().last,
              let lastDate = DateFormatter.isoDate.date(from: lastDateStr) else { return }

        let daysSince = Int(round((Date().timeIntervalSince1970 - lastDate.timeIntervalSince1970) / 86400.0))
        guard daysSince >= 3 else { return }

        // Guard: schedule at most once per calendar day (prevents re-fire on repeated StatsView loads)
        let today = DateFormatter.isoDate.string(from: Date())
        let guardKey = "notif_inactivity_date"
        guard UserDefaults.standard.string(forKey: guardKey) != today else { return }
        UserDefaults.standard.set(today, forKey: guardKey)

        let content = UNMutableNotificationContent()
        content.title = "Retour en salle ? 💪"
        content.body  = "\(daysSince + 1) jours sans séance — ton corps est prêt."
        content.sound = .default

        // Fire at the user's usual session time (or 19h by default)
        let rawHour = BehaviorTracker.shared.preferredHour(for: .sessionEnd) ?? 19
        let hour = min(max(rawHour, 10), 21)
        let secondsUntil = nextOccurrence(hour: hour, minute: 0, fromNow: true)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(secondsUntil, 60), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Streak Milestones (7, 14, 30, 60, 100 days)

    private static func scheduleStreakMilestone(streak: Int) {
        let center = UNUserNotificationCenter.current()
        let id = "streak.milestone"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let milestones = [7: "🔥 Streak de 7 jours !", 14: "🔥🔥 14 jours consécutifs !",
                          30: "🏆 30 jours — champion !", 60: "⚡ 60 jours de feu !",
                          100: "💎 100 jours — légende !"]
        guard let message = milestones[streak] else { return }

        // Guard: don't re-fire for the same milestone (prevents re-fire on repeated StatsView loads)
        let guardKey = "notif_milestone_last"
        guard UserDefaults.standard.integer(forKey: guardKey) != streak else { return }
        UserDefaults.standard.set(streak, forKey: guardKey)

        let content = UNMutableNotificationContent()
        content.title = message
        content.body  = "Continue comme ça — TrainingOS est fier de toi."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Proactive Alert (D3/D10 — at most once per dimension per day)

    static func scheduleProactiveAlert(title: String, body: String, identifier: String) {
        guard !globalDisabled else { return }
        let today = DateFormatter.isoDate.string(from: Date())
        let guardKey = "proactive_alert_shown_\(identifier)_\(today)"
        guard !UserDefaults.standard.bool(forKey: guardKey) else { return }
        UserDefaults.standard.set(true, forKey: guardKey)

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            let content = UNMutableNotificationContent()
            content.title = title
            content.body  = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    // MARK: - D13: Streak danger (17:30 daily, only if streak >= 3 and no session today)

    static func scheduleStreakDanger(streak: Int, hasSessionToday: Bool) {
        guard !globalDisabled else { return }
        let center = UNUserNotificationCenter.current()
        let id = "streak.danger.daily"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard streak >= 3, !hasSessionToday else { return }

        let today = DateFormatter.isoDate.string(from: Date())
        let guardKey = "notif_streak_danger_date"
        guard UserDefaults.standard.string(forKey: guardKey) != today else { return }
        UserDefaults.standard.set(today, forKey: guardKey)

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Streak de \(streak) jours 🔥"
            content.body  = "Pas encore de séance aujourd'hui — protège ton streak."
            content.sound = .default
            var dc = DateComponents()
            dc.hour = 17; dc.minute = 30
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // MARK: - Weekly Recap (Sunday — adaptive hour, defaults to 10:00)

    private static func scheduleWeeklyRecapNotification(tracker: BehaviorTracker) {
        let center = UNUserNotificationCenter.current()
        let id = "weekly.recap.sunday"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let rawHour = tracker.preferredHour(for: .appOpen) ?? 10
            let hour = min(max(rawHour, 8), 12)

            let content = UNMutableNotificationContent()
            content.title = "Ton rapport de la semaine"
            content.body  = "Résultats, patterns, tendances — 30 secondes pour voir où tu en es."
            content.sound = .default

            var dc = DateComponents()
            dc.weekday = 1  // Sunday
            dc.hour    = hour
            dc.minute  = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // MARK: - War Room daily check-in (22:00 fixed — after self-care reminder)

    /// Call with isEnabled = true when War Room is active; false removes the notification.
    static func scheduleWarRoomDailyCheckin(isEnabled: Bool) {
        let center = UNUserNotificationCenter.current()
        let id = "war_room.daily.checkin"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard isEnabled else { return }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "War Room — journée terminée ?"
            content.body  = "Log ta victoire ou ta défaite. La guerre ne se gagne pas en silence."
            content.sound = .default

            var dc = DateComponents()
            dc.hour   = 22
            dc.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // MARK: - Evening Routine Bedtime Reminder (23h30 — one-shot daily)

    /// Schedule at 20h when the EveningRoutineCard appears.
    /// No-op if bedtime_ok already checked, if it's past 23h30, or already scheduled today.
    static func scheduleEveningRoutineBedtimeReminder(bedtimeOkAlreadyChecked: Bool) {
        guard !globalDisabled else { return }
        guard !bedtimeOkAlreadyChecked else { return }

        let now = Date()
        let cal = Calendar.current
        let hour   = cal.component(.hour,   from: now)
        let minute = cal.component(.minute, from: now)
        guard hour < 23 || (hour == 23 && minute < 30) else { return }

        let today    = DateFormatter.isoDate.string(from: now)
        let guardKey = "notif_evening_routine_bedtime_date"
        guard UserDefaults.standard.string(forKey: guardKey) != today else { return }
        UserDefaults.standard.set(today, forKey: guardKey)

        let center = UNUserNotificationCenter.current()
        let id = "routine.stricte.bedtime"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "23h30"
            content.body  = "Il est temps de poser l'écran."
            content.sound = .default
            var dc = DateComponents()
            dc.hour = 23; dc.minute = 30
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    static func cancelEveningRoutineBedtimeReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["routine.stricte.bedtime"])
    }

    // MARK: - Ritual Morning Reminder (B1 — adaptive, defaults to 07:00)

    static func scheduleRitualMorningReminder(hour: Int = 7, minute: Int = 0) {
        let center = UNUserNotificationCenter.current()
        let id = "ritual.morning.reminder"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Déclare ta guerre"
            content.body  = "Commence la journée avec une intention. L'ancienne version de toi ne t'attend pas."
            content.sound = .default

            var dc = DateComponents()
            dc.hour   = max(5, min(hour, 12))
            dc.minute = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // MARK: - Ritual Evening Reminder (B2 — adaptive, defaults to 20:30)

    static func scheduleRitualEveningReminder(hour: Int = 20, minute: Int = 30) {
        let center = UNUserNotificationCenter.current()
        let id = "ritual.evening.reminder"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Est-ce que tu l'as tué ?"
            content.body  = "🌙 Juge ta journée — engage-toi pour demain."
            content.sound = .default

            var dc = DateComponents()
            dc.hour   = max(18, min(hour, 23))
            dc.minute = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // MARK: - HRV Morning Reminder (configurable hour — defaults to 07:00)

    static func scheduleHRVMorningReminder(hour: Int = 7, minute: Int = 0) {
        let center = UNUserNotificationCenter.current()
        let id = "hrv.morning.reminder"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Mesure HRV du matin"
            content.body  = "Reste allongé et ouvre l'app — ta mesure du jour est prête."
            content.sound = .default

            var dc = DateComponents()
            dc.hour   = max(4, min(hour, 10))
            dc.minute = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // MARK: - Ritual Streak At Risk (B3 — fires at 13:00 if morning not done)

    /// Call this after loading ritualToday — if morning not done and hour >= 12, schedule an at-risk reminder.
    static func scheduleRitualStreakAtRisk(morningDone: Bool, phoenixStreak: Int) {
        guard !globalDisabled, isEnabled("notif_on_ritual_streak") else { return }
        let center = UNUserNotificationCenter.current()
        let id = "ritual.streak.risk"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard !morningDone, phoenixStreak > 0 else { return }

        // Guard: schedule at most once per calendar day
        let today = DateFormatter.isoDate.string(from: Date())
        let guardKey = "notif_streak_risk_date"
        guard UserDefaults.standard.string(forKey: guardKey) != today else { return }
        UserDefaults.standard.set(today, forKey: guardKey)

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let hour = Calendar.current.component(.hour, from: Date())
            guard hour < 14 else { return }

            let content = UNMutableNotificationContent()
            content.title = "Streak à risque — \(phoenixStreak) jour\(phoenixStreak > 1 ? "s" : "")"
            content.body  = "Tu n'as pas encore déclaré ta guerre aujourd'hui."
            content.sound = .default

            // Fire at 13:00 today
            var dc = DateComponents()
            dc.hour   = 13
            dc.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // MARK: - Demon Haunting Notification (B4 — fires if demon carry_count >= 3)

    /// Call after loading demons — schedules a one-time "it's still there" push if a demon >= 3 days.
    static func scheduleRitualDemonHaunting(demons: [RitualDemon]) {
        guard !globalDisabled, isEnabled("notif_on_ritual_demon") else { return }
        let center = UNUserNotificationCenter.current()
        let id = "ritual.demon.haunting"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let heavyDemons = demons.filter { $0.carryCount >= 3 }
        guard let oldest = heavyDemons.max(by: { $0.carryCount < $1.carryCount }) else { return }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Il est encore là — \(oldest.carryCount) nuits"
            content.body  = "«\(oldest.intention)» n'a pas été tué."
            content.sound = .default

            center.add(UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: reasonableHourTrigger()
            ))
        }
    }

    // MARK: - Event: Phoenix state change

    /// Fires once when the user's Phoenix state changes (e.g. Braises → Flamme).
    /// De-duplicated via UserDefaults — won't fire again for the same state.
    static func notifyPhoenixStateChange(newState: String, newLabel: String) {
        let key = "notif.phoenix.state"
        let last = UserDefaults.standard.string(forKey: key) ?? ""
        guard last != newState else { return }
        UserDefaults.standard.set(newState, forKey: key)
        guard !globalDisabled, isEnabled("notif_on_phoenix") else { return }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let center = UNUserNotificationCenter.current()
            let id = "event.phoenix.state"
            center.removePendingNotificationRequests(withIdentifiers: [id])

            let content = UNMutableNotificationContent()
            content.title = "Phoenix : \(newLabel)"
            let bodies: [String: String] = [
                "supernova":      "Tu as atteint le sommet — SUPERNOVA.",
                "envol":          "Ton Phoenix prend son envol. Garde l'altitude.",
                "flamme":         "La flamme est allumée. Tu construis sur du solide.",
                "braises_chaudes":"Le feu couve. Maintiens la pression.",
                "braises":        "Les braises rougeoient. Quelques jours de plus.",
                "cendres":        "Retour aux cendres. La reconstruction commence maintenant.",
                "foundation":     "Fondation posée. Tout commence ici.",
            ]
            content.body  = bodies[newState] ?? "Ton score Phoenix a changé."
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: reasonableHourTrigger()))
        }
    }

    // MARK: - Event: Season milestones (D30, D60, D75)

    /// Schedules calendar-exact notifications for season milestones if not yet passed.
    static func scheduleSeasonMilestones(seasonStartISO: String, seasonNumber: Int) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let start = f.date(from: String(seasonStartISO.prefix(10))) else { return }
        let center = UNUserNotificationCenter.current()

        // (day, id, title, body)
        let milestones: [(Int, String, String, String)] = [
            (30, "event.season.d30.\(seasonNumber)", "Saison \(seasonNumber) — Jour 30",
             "Le premier tiers est fait. Ton Oath t'attend — relis-le."),
            (45, "event.season.d45.\(seasonNumber)", "Saison \(seasonNumber) — Mi-parcours",
             "45 jours. La saison se gagne ou se perd dans les 45 prochains."),
            (60, "event.season.d60.\(seasonNumber)", "Saison \(seasonNumber) — Jour 60",
             "Deux tiers. Relis ton intention de départ — es-tu encore dans la même guerre ?"),
            (75, "event.season.d75.\(seasonNumber)", "Saison \(seasonNumber) — Dernière ligne droite",
             "15 jours. Ne relâche pas. Cette saison se joue maintenant."),
            (89, "event.season.d89.\(seasonNumber)", "Saison \(seasonNumber) — Demain c'est fini",
             "Dernière journée demain. Tu mérites un Oath relu avant la clôture."),
        ]

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            for (day, id, title, body) in milestones {
                let fireDate = Calendar.current.safeDateByAdding(.day, value: day - 1, to: start)
                guard fireDate > Date() else { continue }
                center.removePendingNotificationRequests(withIdentifiers: [id])
                let content = UNMutableNotificationContent()
                content.title = title
                content.body  = body
                content.sound = .default
                var dc = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
                dc.hour = 9; dc.minute = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    // MARK: - Event: DNA archetype change

    /// Fires once when the user's archetype changes — de-duplicated by archetype key.
    static func notifyDNAArchetypeChange(newKey: String, newLabel: String) {
        let storageKey = "notif.dna.archetype"
        let last = UserDefaults.standard.string(forKey: storageKey) ?? ""
        guard !last.isEmpty, last != newKey else {
            UserDefaults.standard.set(newKey, forKey: storageKey)
            return
        }
        UserDefaults.standard.set(newKey, forKey: storageKey)
        guard !globalDisabled, isEnabled("notif_on_dna") else { return }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let center = UNUserNotificationCenter.current()
            let id = "event.dna.archetype"
            center.removePendingNotificationRequests(withIdentifiers: [id])
            let content = UNMutableNotificationContent()
            content.title = "Ton ADN a évolué"
            content.body  = "Tu es maintenant un \(newLabel). Ton profil d'entraînement a changé."
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: reasonableHourTrigger()))
        }
    }

    // MARK: - Event: Time Capsule unlocking soon (≤7 days)

    /// Schedules a one-shot notification for each capsule unlocking within 7 days.
    static func scheduleTimeCapsuleSoon(capsules: [TimeCapsule]) {
        guard !globalDisabled, isEnabled("notif_on_capsule") else { return }
        let center = UNUserNotificationCenter.current()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let sevenDays = 7.0 * 86400

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            for capsule in capsules {
                let unlockISO = capsule.unlockAt
                guard let unlockDate = f.date(from: String(unlockISO.prefix(10))) else { continue }
                let interval = unlockDate.timeIntervalSince(now)
                guard interval > 0 && interval <= sevenDays else { continue }
                let id = "event.capsule.soon.\(capsule.id)"
                center.removePendingNotificationRequests(withIdentifiers: [id])
                let daysLeft = max(1, Int(interval / 86400))
                let content = UNMutableNotificationContent()
                content.title = "Ta capsule temporelle s'ouvre bientôt"
                content.body  = daysLeft == 1
                    ? "Ta capsule temporelle s'ouvre demain. Prépare-toi."
                    : "Ta capsule temporelle s'ouvre dans \(daysLeft) jours."
                content.sound = .default
                // Fire at 9:00 on the day that is 7 days before unlock
                var dc = Calendar.current.dateComponents([.year, .month, .day], from: now)
                dc.hour = 9; dc.minute = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    // MARK: - Weekly recap with real data

    /// Reschedule Sunday recap with actual session/PR counts from the latest report.
    static func scheduleWeeklyRecapWithData(report: WeeklyReport, tracker: BehaviorTracker) {
        guard !globalDisabled, isEnabled("notif_on_recap") else { return }
        let center = UNUserNotificationCenter.current()
        let id = "weekly.recap.sunday"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let rawHour = tracker.preferredHour(for: .appOpen) ?? 10
            let hour = min(max(rawHour, 8), 12)

            let content = UNMutableNotificationContent()
            content.title = "Ton rapport de la semaine"
            var bodyParts: [String] = []
            bodyParts.append("\(report.sessionCount) séance\(report.sessionCount == 1 ? "" : "s")")
            if report.prCount > 0 { bodyParts.append("\(report.prCount) PR") }
            if let avg = report.avgSleepHours { bodyParts.append(String(format: "%.1fh de sommeil en moyenne", avg)) }
            content.body = bodyParts.isEmpty
                ? "Résultats, patterns, tendances — 30 secondes."
                : bodyParts.joined(separator: " · ")
            content.sound = .default

            var dc = DateComponents()
            dc.weekday = 1
            dc.hour    = hour
            dc.minute  = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // MARK: - Helper: reasonable-hour trigger (9h–21h, else next 9am)

    /// Returns a trigger that fires now (1s) if current hour is 9–20, else fires at next 9:00.
    private static func reasonableHourTrigger() -> UNNotificationTrigger {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 9 && hour < 21 {
            return UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
        // Outside window — schedule for next 9:00
        var dc = DateComponents(); dc.hour = 9; dc.minute = 0
        return UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
    }

    // MARK: - Helper

    private static func nextOccurrence(hour: Int, minute: Int, fromNow: Bool) -> TimeInterval {
        var dc = DateComponents()
        dc.hour = hour; dc.minute = minute; dc.second = 0
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone.current
        guard let next = cal.nextDate(after: Date(), matching: dc, matchingPolicy: .nextTime) else {
            return 86400
        }
        return next.timeIntervalSince(Date())
    }
}

// MARK: - Rest Timer Manager

@MainActor
final class RestTimerManager: ObservableObject {
    static let shared   = RestTimerManager()
    static let presetKey = "restTimerPreset"
    private init() {}

    @Published var totalSeconds  = 120
    @Published var isRunning     = false
    @Published var isVisible     = false
    @Published var exerciseName: String? = nil

    /// Non-published — views compute remaining via TimelineView using startDate
    private(set) var remaining: Int = 120
    /// Published so adjust() triggers immediate UI update even when totalSeconds is unchanged.
    @Published private(set) var startDate: Date?

    private var timerTask: Task<Void, Never>?
    private var beepPlayer: AVAudioPlayer?

    /// Start (or restart) the timer. Always replaces any running timer, always auto-starts.
    func start(seconds: Int, exerciseName: String? = nil) {
        timerTask?.cancel(); timerTask = nil
        cancelNotification()
        let secs        = max(10, seconds)
        totalSeconds    = secs
        remaining       = secs
        startDate       = Date()
        isRunning       = true
        isVisible       = true
        if let name = exerciseName { self.exerciseName = name }
        UserDefaults.standard.set(secs, forKey: Self.presetKey)
        scheduleNotification(seconds: secs)
        timerTask = Task { [weak self] in await self?.runLoop() }
    }

    /// Resume a paused timer without changing duration.
    func resume() {
        guard !isRunning, remaining > 0 else { return }
        startDate = Date().addingTimeInterval(-Double(totalSeconds - remaining))
        isRunning = true
        scheduleNotification(seconds: remaining)
        timerTask = Task { [weak self] in await self?.runLoop() }
    }

    func stop() {
        isRunning = false
        startDate = nil
        timerTask?.cancel(); timerTask = nil
        cancelNotification()
    }

    func reset() { stop(); remaining = totalSeconds }

    func dismiss() { stop(); isVisible = false; exerciseName = nil }

    func adjust(by delta: Int) {
        remaining = max(1, remaining + delta)
        if isRunning {
            totalSeconds = max(totalSeconds, remaining)
            startDate = Date().addingTimeInterval(-Double(totalSeconds - remaining))
            cancelNotification()
            scheduleNotification(seconds: remaining)
        } else {
            totalSeconds = remaining
        }
    }

    private func scheduleNotification(seconds: Int) {
        cancelNotification()
        let content = UNMutableNotificationContent()
        content.title = "Repos terminé ✅"; content.body = "C'est reparti !"; content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "restTimer", content: content, trigger: trigger))
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["restTimer"])
    }

    private func runLoop() async {
        guard let sd = startDate else { return }
        var lastSoundedRem = totalSeconds + 1   // anti-double-bip
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 500_000_000)   // tick 0.5s
            guard !Task.isCancelled else { break }
            let rem = max(0, totalSeconds - Int(Date().timeIntervalSince(sd)))
            remaining = rem
            if rem <= 3 && rem > 0 && rem < lastSoundedRem {
                lastSoundedRem = rem
                playBeep(hz: 880); triggerImpact(style: .rigid)
            }
            if rem == 0 {
                isRunning = false
                cancelNotification()
                playBeep(hz: 1200); triggerNotificationFeedback(.success)
                break
            }
        }
        timerTask = nil
    }

    private func playBeep(hz: Double) {
        beepPlayer = makeBeep(hz: hz, duration: hz > 1000 ? 0.35 : 0.12)
        beepPlayer?.play()
    }
}
