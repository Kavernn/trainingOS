import Foundation
import UserNotifications

// MARK: - Alert Service

@MainActor
final class AlertService: ObservableObject {

    static let shared = AlertService()

    @Published var alerts: [ProactiveAlert] = []

    private let baseURL = "https://training-os-rho.vercel.app"
    private let dismissedKey = "proactive_dismissed_alerts"

    // Dismissed keys: "<alert_id>_<yyyy-MM-dd>" — reset automatically each day
    private var dismissed: Set<String> {
        get {
            guard let data = UserDefaults.standard.data(forKey: dismissedKey),
                  let set = try? JSONDecoder().decode(Set<String>.self, from: data)
            else { return [] }
            return set
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: dismissedKey)
            }
        }
    }

    // The highest-priority alert not yet dismissed today
    var visibleAlert: ProactiveAlert? {
        let today = DateFormatter.isoDate.string(from: Date())
        return alerts.first { !dismissed.contains("\($0.id)_\(today)") }
    }

    // MARK: - Fetch

    func fetch() async {
        guard let url = URL(string: "\(baseURL)/api/proactive_alerts") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ProactiveAlertsResponse.self, from: data)
            alerts = response.alerts
            scheduleNotificationIfNeeded()
        } catch {
            // Silent fail — non-critical path
        }
    }

    // MARK: - Dismiss

    func dismiss(_ alert: ProactiveAlert) {
        let today = DateFormatter.isoDate.string(from: Date())
        var current = dismissed
        current.insert("\(alert.id)_\(today)")

        // Prune keys older than 3 days to avoid unbounded growth
        let cutoff = DateFormatter.isoDate.string(
            from: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        )
        current = current.filter { key in
            guard let datePart = key.split(separator: "_").last.map(String.init) else { return true }
            return datePart >= cutoff
        }
        dismissed = current
    }

    // MARK: - Local notification (19:30 today, one-shot)

    private func scheduleNotificationIfNeeded() {
        guard let top = visibleAlert else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            // Only schedule if 19:30 today hasn't passed
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = 19
            components.minute = 30
            guard let target = Calendar.current.date(from: components), target > Date() else { return }

            let content = UNMutableNotificationContent()
            content.title = top.title
            content.body  = top.message
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "proactive.daily",
                content: content,
                trigger: trigger
            )
            // Replace any existing proactive notification
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["proactive.daily"]
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}
