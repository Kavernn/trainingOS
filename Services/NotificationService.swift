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

/// Singleton managing rest timer state across all views.
/// Using a shared instance ensures a single source of truth regardless of
/// how many ExerciseCards or sheets observe it.
@MainActor
final class RestTimerManager: ObservableObject {
    static let shared = RestTimerManager()
    private init() {}

    private static let endDateKey = "restTimerEndDate"
    private static let totalKey   = "restTimerTotal"
    static  let presetKey         = "restTimerPreset"

    @Published var totalSeconds = 120
    @Published var remaining    = 120
    @Published var isRunning    = false
    @Published var currentExerciseName: String? = nil
    @Published var pendingStart: (seconds: Int, name: String)? = nil

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

    func start() {
        guard remaining > 0 else { return }
        timerTask?.cancel()
            timerTask = nil
        isRunning = true
        let endDate = Date().addingTimeInterval(TimeInterval(remaining))
        UserDefaults.standard.set(endDate,      forKey: Self.endDateKey)
        UserDefaults.standard.set(totalSeconds, forKey: Self.totalKey)
        scheduleNotification(seconds: remaining)
        timerTask = Task { await runLoop() }
    }

    func stop() {
        isRunning = false
        timerTask?.cancel()
        timerTask = nil
        UserDefaults.standard.removeObject(forKey: Self.endDateKey)
        UserDefaults.standard.removeObject(forKey: Self.totalKey)
        cancelNotification()
    }

    func reset() { stop(); remaining = totalSeconds }

    /// +/- adjustment. When running, extends totalSeconds if needed to keep progress ≤ 1.
    func adjustTime(by delta: Int) {
        remaining = max(10, remaining + delta)
        if isRunning {
            totalSeconds = max(totalSeconds, remaining)
            rescheduleNotification(seconds: remaining)
        } else {
            totalSeconds = remaining
        }
    }

    /// Apply a preset chip. Restarts if already running.
    func applyPreset(_ seconds: Int) {
        let wasRunning = isRunning
        if isRunning { stop() }
        totalSeconds = seconds
        remaining    = seconds
        UserDefaults.standard.set(seconds, forKey: Self.presetKey)
        if wasRunning { start() }
    }

    /// Called when an exercise is logged. Sets the preset but never starts automatically.
    /// If a timer is already running for a different exercise, ask before replacing.
    func requestAutoStart(_ seconds: Int, exerciseName: String) {
        if isRunning, let current = currentExerciseName, current != exerciseName {
            pendingStart = (seconds, exerciseName)
        } else if !isRunning {
            currentExerciseName = exerciseName
            totalSeconds = seconds
            remaining    = seconds
            UserDefaults.standard.set(seconds, forKey: Self.presetKey)
            // No auto-start — user presses play manually
        }
        // Same exercise running: don't interrupt
    }

    func confirmReplace() {
        guard let p = pendingStart else { return }
        stop()
        currentExerciseName = p.name
        totalSeconds = p.seconds
        remaining    = p.seconds
        UserDefaults.standard.set(p.seconds, forKey: Self.presetKey)
        start()  // User explicitly confirmed the replacement → start
        pendingStart = nil
    }

    func cancelReplace() {
        pendingStart = nil
    }

    /// Restore state on sheet appear. If already running (singleton), just sync time.
    func restoreIfNeeded(autoStartSeconds: Int? = nil) {
        if isRunning { syncFromEndDate(); return }
        if let end = UserDefaults.standard.object(forKey: Self.endDateKey) as? Date {
            let left = Int(end.timeIntervalSinceNow.rounded())
            guard left > 0 else {
                UserDefaults.standard.removeObject(forKey: Self.endDateKey)
                applyInitial(autoStartSeconds: autoStartSeconds)
                return
            }
            totalSeconds = UserDefaults.standard.integer(forKey: Self.totalKey)
            if totalSeconds == 0 { totalSeconds = left }
            remaining = left
            timerTask?.cancel()
            timerTask = Task { await runLoop() }
            isRunning = true
        } else {
            applyInitial(autoStartSeconds: autoStartSeconds)
        }
    }

    func syncFromEndDate() {
        guard let end = UserDefaults.standard.object(forKey: Self.endDateKey) as? Date else { return }
        let left = Int(end.timeIntervalSinceNow.rounded())
        if left <= 0 {
            remaining = 0; isRunning = false
            timerTask?.cancel(); timerTask = nil
            UserDefaults.standard.removeObject(forKey: Self.endDateKey)
            playBeep(hz: 1200); triggerNotificationFeedback(.success)
        } else {
            remaining = left
        }
    }

    private func applyInitial(autoStartSeconds: Int?) {
        if let auto = autoStartSeconds, auto > 0 {
            totalSeconds = auto; remaining = auto
            UserDefaults.standard.set(auto, forKey: Self.presetKey)
        } else {
            let saved = UserDefaults.standard.integer(forKey: Self.presetKey)
            if saved > 0 { totalSeconds = saved; remaining = saved }
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

    private func rescheduleNotification(seconds: Int) {
        UserDefaults.standard.set(Date().addingTimeInterval(TimeInterval(seconds)), forKey: Self.endDateKey)
        scheduleNotification(seconds: seconds)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["restTimer"])
    }

    private func runLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { break }
            if remaining > 0 {
                remaining -= 1
                if remaining <= 3 && remaining > 0 {
                    playBeep(hz: 880); triggerImpact(style: .rigid)
                } else if remaining == 0 {
                    isRunning = false
                    UserDefaults.standard.removeObject(forKey: Self.endDateKey)
                    playBeep(hz: 1200); triggerNotificationFeedback(.success)
                }
            }
        }
    }

    private func playBeep(hz: Double) {
        beepPlayer = makeBeep(hz: hz, duration: hz > 1000 ? 0.35 : 0.12)
        beepPlayer?.play()
    }
}
