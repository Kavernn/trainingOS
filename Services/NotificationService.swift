import AVFoundation
import Combine
import SwiftUI
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

// MARK: - Rest Timer Manager

@MainActor
final class RestTimerManager: ObservableObject {
    static let shared   = RestTimerManager()
    static let presetKey = "restTimerPreset"
    private init() {}

    @Published var totalSeconds  = 120
    @Published var remaining     = 120
    @Published var isRunning     = false
    @Published var isVisible     = false
    @Published var exerciseName: String? = nil

    private var timerTask: Task<Void, Never>?
    private var beepPlayer: AVAudioPlayer?

    var progress: Double {
        totalSeconds > 0 ? min(1.0, Double(remaining) / Double(totalSeconds)) : 0
    }
    var timerColor: Color {
        if progress > 0.5  { return .green }
        if progress > 0.25 { return .yellow }
        return .red
    }

    /// Start (or restart) the timer. Always replaces any running timer, always auto-starts.
    func start(seconds: Int, exerciseName: String? = nil) {
        timerTask?.cancel(); timerTask = nil
        cancelNotification()
        let secs        = max(10, seconds)
        totalSeconds    = secs
        remaining       = secs
        isRunning       = true
        isVisible       = true
        if let name = exerciseName { self.exerciseName = name }
        UserDefaults.standard.set(secs, forKey: Self.presetKey)
        scheduleNotification(seconds: secs)
        timerTask = Task { await runLoop() }
    }

    /// Resume a paused timer without changing duration.
    func resume() {
        guard !isRunning, remaining > 0 else { return }
        isRunning = true
        scheduleNotification(seconds: remaining)
        timerTask = Task { await runLoop() }
    }

    func stop() {
        isRunning = false
        timerTask?.cancel(); timerTask = nil
        cancelNotification()
    }

    func reset() { stop(); remaining = totalSeconds }

    func dismiss() { stop(); isVisible = false; exerciseName = nil }

    /// Change preset without restarting.
    func setPreset(_ seconds: Int) {
        stop()
        totalSeconds = seconds
        remaining    = seconds
        UserDefaults.standard.set(seconds, forKey: Self.presetKey)
    }

    func adjust(by delta: Int) {
        remaining = max(10, remaining + delta)
        if isRunning {
            totalSeconds = max(totalSeconds, remaining)
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
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { break }
            guard remaining > 0 else { break }
            remaining -= 1
            if remaining <= 3 && remaining > 0 {
                playBeep(hz: 880); triggerImpact(style: .rigid)
            } else if remaining == 0 {
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
