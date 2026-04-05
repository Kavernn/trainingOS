import UserNotifications

enum NotificationService {

    /// Schedules (or reschedules) all app notifications.
    /// Safe to call multiple times — removes previous copies first.
    static func scheduleAll() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            scheduleFridayFullBody()
            scheduleSelfCareReminder()
            schedulePSSWeeklyReminder()
        }
    }

    /// Call after data loads, passing the sorted session dates.
    static func scheduleContextual(sessionDates: [String], currentStreak: Int) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            scheduleInactivityReminder(sessionDates: sessionDates)
            scheduleStreakMilestone(streak: currentStreak)
        }
    }

    // MARK: - Friday Full Body

    private static func scheduleFridayFullBody() {
        let center = UNUserNotificationCenter.current()
        let id = "weekly.friday.fullbody"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Full Body aujourd'hui 💪"
        content.body  = "Pull B + Full Body — c'est vendredi, on envoie."
        content.sound = .default

        var dc = DateComponents()
        dc.weekday = 6
        dc.hour    = 9
        dc.minute  = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Self-Care Daily Reminder (every day at 9pm)

    private static func scheduleSelfCareReminder() {
        let center = UNUserNotificationCenter.current()
        let id = "selfcare.daily.reminder"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Habitudes du soir 🌙"
        content.body  = "Tes habitudes de self-care t'attendent — coche tes actions du jour."
        content.sound = .default

        var dc = DateComponents()
        dc.hour   = 21
        dc.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - PSS Weekly Reminder (every Monday at 10am)

    private static func schedulePSSWeeklyReminder() {
        let center = UNUserNotificationCenter.current()
        let id = "pss.weekly.test"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Test PSS hebdo 🧠"
        content.body  = "Comment ton stress évolue cette semaine ? 2 minutes pour le mesurer."
        content.sound = .default

        var dc = DateComponents()
        dc.weekday = 2   // Monday
        dc.hour    = 10
        dc.minute  = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Inactivity Reminder (fires at 7pm if > 3 days without session)

    private static func scheduleInactivityReminder(sessionDates: [String]) {
        let center = UNUserNotificationCenter.current()
        let id = "inactivity.reminder"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard let lastDateStr = sessionDates.sorted().last,
              let lastDate = DateFormatter.isoDate.date(from: lastDateStr) else { return }

        let daysSince = Int(round((Date().timeIntervalSince1970 - lastDate.timeIntervalSince1970) / 86400.0))
        guard daysSince >= 3 else { return }   // Already past threshold — fire tomorrow at 7pm

        let content = UNMutableNotificationContent()
        content.title = "Retour en salle ? 💪"
        content.body  = "\(daysSince + 1) jours sans séance — ton corps est prêt."
        content.sound = .default

        // Fire tomorrow at 7pm
        var dc = DateComponents()
        dc.hour   = 19
        dc.minute = 0
        // Use a time interval trigger for "tomorrow 7pm" equivalent
        let secondsUntil = nextOccurrence(hour: 19, minute: 0, fromNow: true)
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

        let content = UNMutableNotificationContent()
        content.title = message
        content.body  = "Continue comme ça — TrainingOS est fier de toi."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Helper

    private static func nextOccurrence(hour: Int, minute: Int, fromNow: Bool) -> TimeInterval {
        var dc = DateComponents()
        dc.hour = hour; dc.minute = minute; dc.second = 0
        guard let next = Calendar.current.nextDate(after: Date(), matching: dc, matchingPolicy: .nextTime) else {
            return 86400
        }
        return next.timeIntervalSince(Date())
    }
}
