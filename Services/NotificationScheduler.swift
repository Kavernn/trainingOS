import Foundation
import UserNotifications

final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private init() {}

    func scheduleMorningNotification(for data: DashboardData) {
        // CODE-7: schedule at most once per calendar day
        let today = DateFormatter.isoDate.string(from: Date())
        let lastKey = "notif_morning_scheduled_date"
        guard UserDefaults.standard.string(forKey: lastKey) != today else { return }
        UserDefaults.standard.set(today, forKey: lastKey)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["morning-coaching"])

        let content = UNMutableNotificationContent()
        content.title = "Bonne séance 💪"
        content.body  = "Au programme aujourd'hui : \(data.today)"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour   = 7
        dateComponents.minute = 30
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "morning-coaching", content: content, trigger: trigger)
        center.add(request)
    }
}
