import Foundation
import UserNotifications

final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private init() {}

    func scheduleMorningNotification(for data: DashboardData) {
        // Retired — superseded by ritual.morning.reminder in NotificationService.scheduleAll()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["morning-coaching"])
    }
}
