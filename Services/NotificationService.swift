import UserNotifications

enum NotificationService {

    /// Schedules (or reschedules) all app notifications.
    /// Safe to call multiple times — removes previous copies first.
    static func scheduleAll() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            scheduleFridayFullBody()
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
        dc.weekday = 6   // 1 = dimanche … 6 = vendredi
        dc.hour    = 9
        dc.minute  = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        center.add(request)
    }
}
