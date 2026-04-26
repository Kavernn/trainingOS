import Foundation
import UserNotifications

// MARK: - BehaviorTracker
// Records timestamps of key user actions and derives preferred hours for adaptive notifications.
// Stores up to 14 recent timestamps per event type in UserDefaults.
// Requires ≥3 data points before deviating from defaults.

final class BehaviorTracker {
    static let shared = BehaviorTracker()
    private init() {}

    enum Event: String, CaseIterable {
        case appOpen       = "bt_app_open"
        case sessionEnd    = "bt_session_end"
        case nutritionLog  = "bt_nutrition_log"
        case selfCareCheck = "bt_selfcare_check"
    }

    private let maxStored = 14
    private let minRequired = 3

    // MARK: - Record

    func record(_ event: Event) {
        var timestamps = load(event)
        timestamps.append(Date().timeIntervalSince1970)
        if timestamps.count > maxStored {
            timestamps = Array(timestamps.suffix(maxStored))
        }
        save(timestamps, for: event)
        rescheduleNotifications()
    }

    // MARK: - Query preferred hour

    /// Returns the learned preferred hour (0–23) for an event, or nil if insufficient data.
    func preferredHour(for event: Event) -> Int? {
        let timestamps = load(event)
        guard timestamps.count >= minRequired else { return nil }

        let hours = timestamps.map { t -> Double in
            let date = Date(timeIntervalSince1970: t)
            let h = Double(Calendar.current.component(.hour, from: date))
            let m = Double(Calendar.current.component(.minute, from: date))
            return h + m / 60.0
        }.sorted()

        // Trimmed mean — discard outer 20% on each side
        let trimCount = max(0, Int(Double(hours.count) * 0.2))
        let trimmed = Array(hours.dropFirst(trimCount).dropLast(trimCount))
        guard !trimmed.isEmpty else { return nil }

        let mean = trimmed.reduce(0, +) / Double(trimmed.count)
        // Round to nearest 30-minute slot, return hour
        return Int(round(mean * 2) / 2) % 24
    }

    // MARK: - Private helpers

    private func load(_ event: Event) -> [Double] {
        guard let data = UserDefaults.standard.data(forKey: event.rawValue),
              let decoded = try? JSONDecoder().decode([Double].self, from: data)
        else { return [] }
        return decoded
    }

    private func save(_ timestamps: [Double], for event: Event) {
        if let data = try? JSONEncoder().encode(timestamps) {
            UserDefaults.standard.set(data, forKey: event.rawValue)
        }
    }

    private func rescheduleNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            NotificationService.scheduleAll()
        }
    }
}
