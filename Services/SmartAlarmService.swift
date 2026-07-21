import Foundation
import Combine
import SwiftUI
import AlarmKit

// Defined at file level — avoids @MainActor isolation inherited from SmartAlarmService
struct SmartAlarmMetadata: AlarmMetadata {}

enum SmartAlarmError: LocalizedError {
    case authorizationDenied
    case alarmInPast
    case schedulingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:    return "Permission AlarmKit refusée — activer dans Réglages"
        case .alarmInPast:            return "Heure d'alarme déjà passée"
        case .schedulingFailed(let e): return "Scheduling échoué : \(e.localizedDescription)"
        }
    }
}

enum AlarmState: Equatable {
    case disabled
    case armed(at: Date)
    case notArmed
    case authorizationDenied
}

@MainActor
final class SmartAlarmService: ObservableObject {
    static let shared = SmartAlarmService()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var windowStartHour: Int
    @Published private(set) var windowStartMinute: Int
    @Published private(set) var windowEndHour: Int
    @Published private(set) var windowEndMinute: Int
    @Published private(set) var state: AlarmState = .disabled

    private enum Keys {
        static let enabled         = "smartAlarm.enabled"
        static let windowStartHH   = "smartAlarm.windowStartHH"
        static let windowStartMM   = "smartAlarm.windowStartMM"
        static let windowEndHH     = "smartAlarm.windowEndHH"
        static let windowEndMM     = "smartAlarm.windowEndMM"
        static let pendingAlarmID  = "smartAlarm.pendingAlarmID"  // UUID.uuidString
        static let lastBedtimeTS   = "smartAlarm.lastBedtimeTimestamp"
    }

    private init() {
        let d = UserDefaults.standard
        isEnabled         = d.bool(forKey: Keys.enabled)
        windowStartHour   = d.object(forKey: Keys.windowStartHH) != nil ? d.integer(forKey: Keys.windowStartHH) : 6
        windowStartMinute = d.object(forKey: Keys.windowStartMM) != nil ? d.integer(forKey: Keys.windowStartMM) : 30
        windowEndHour     = d.object(forKey: Keys.windowEndHH)   != nil ? d.integer(forKey: Keys.windowEndHH)   : 7
        windowEndMinute   = d.object(forKey: Keys.windowEndMM)   != nil ? d.integer(forKey: Keys.windowEndMM)   : 0
        state             = isEnabled ? .notArmed : .disabled
    }

    // MARK: - Public actions

    func enable() async {
        guard await requestAlarmKitAuthorization() else { return }
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Keys.enabled)
        state = .notArmed
        await rescheduleIfBedtimeExists()
    }

    func disable() async {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Keys.enabled)
        cancelAlarm()
        state = .disabled
    }

    func updateWindow(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) async {
        let d = UserDefaults.standard
        windowStartHour = startHour;     d.set(startHour,   forKey: Keys.windowStartHH)
        windowStartMinute = startMinute; d.set(startMinute, forKey: Keys.windowStartMM)
        windowEndHour = endHour;         d.set(endHour,     forKey: Keys.windowEndHH)
        windowEndMinute = endMinute;     d.set(endMinute,   forKey: Keys.windowEndMM)
        await rescheduleIfBedtimeExists()
    }

    // Called from EveningSleepSheet "Armer réveil cyclique" tap — bedtime = Date.now
    func scheduleAlarm(bedtimeDate: Date) async throws {
        guard isEnabled else { return }
        UserDefaults.standard.set(bedtimeDate.timeIntervalSinceReferenceDate, forKey: Keys.lastBedtimeTS)
        Task { try? await APIService.shared.logBedtimeTap(bedtimeDate) }
        try await scheduleFromBedtimeDate(bedtimeDate)
    }

    // stop(id:) is synchronous in AlarmKit
    func cancelAlarm() {
        guard let idString = UserDefaults.standard.string(forKey: Keys.pendingAlarmID),
              let id = UUID(uuidString: idString) else { return }
        try? AlarmManager.shared.stop(id: id)
        UserDefaults.standard.removeObject(forKey: Keys.pendingAlarmID)
        state = isEnabled ? .notArmed : .disabled
    }

    // MARK: - Cycle logic (pure, tested separately)

    func calculateCyclePoints(bedtime: Date, sleepLatency: TimeInterval = 15 * 60) -> [Date] {
        let sleepStart = bedtime.addingTimeInterval(sleepLatency)
        let cycle: TimeInterval = 90 * 60
        return (1...6).map { sleepStart.addingTimeInterval(Double($0) * cycle) }
    }

    func selectOptimalPoint(from points: [Date], windowStart: Date, windowEnd: Date) -> Date {
        if let match = points.first(where: { $0 >= windowStart && $0 <= windowEnd }) {
            return match
        }
        return windowEnd  // no cycle in window → maximize sleep → borne FIN
    }

    // MARK: - Private

    private func requestAlarmKitAuthorization() async -> Bool {
        do {
            let authState = try await AlarmManager.shared.requestAuthorization()
            return authState == .authorized
        } catch {
            state = .authorizationDenied
            return false
        }
    }

    private func rescheduleIfBedtimeExists() async {
        guard isEnabled else { return }
        let ts = UserDefaults.standard.double(forKey: Keys.lastBedtimeTS)
        guard ts > 0 else { state = .notArmed; return }
        let bedtimeDate = Date(timeIntervalSinceReferenceDate: ts)
        try? await scheduleFromBedtimeDate(bedtimeDate)
    }

    private func scheduleFromBedtimeDate(_ bedtimeDate: Date) async throws {
        let (wStart, wEnd) = windowDates(relativeTo: bedtimeDate)
        let points = calculateCyclePoints(bedtime: bedtimeDate)
        let alarmTime = selectOptimalPoint(from: points, windowStart: wStart, windowEnd: wEnd)

        guard alarmTime > Date() else {
            state = .notArmed
            throw SmartAlarmError.alarmInPast
        }

        // Cancel existing via pendingAlarmID — single cancellation source
        if let existingIDString = UserDefaults.standard.string(forKey: Keys.pendingAlarmID),
           let existingID = UUID(uuidString: existingIDString) {
            try? AlarmManager.shared.stop(id: existingID)
            UserDefaults.standard.removeObject(forKey: Keys.pendingAlarmID)
        }

        let alarmID = UUID()

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource("VinceSeven — réveil cycle"),
            secondaryButton: AlarmButton(
                text: LocalizedStringResource("Snooze"),
                textColor: .white,
                systemImageName: "moon.zzz.fill"
            ),
            secondaryButtonBehavior: .countdown
        )

        let presentation = AlarmPresentation(alert: alert)

        let attributes = AlarmAttributes<SmartAlarmMetadata>(
            presentation: presentation,
            metadata: SmartAlarmMetadata(),
            tintColor: AppTheme.shared.accent
        )

        let configuration: AlarmManager.AlarmConfiguration<SmartAlarmMetadata> = .alarm(
            schedule: .fixed(alarmTime),
            attributes: attributes
        )

        do {
            try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
        } catch {
            throw SmartAlarmError.schedulingFailed(error)
        }

        UserDefaults.standard.set(alarmID.uuidString, forKey: Keys.pendingAlarmID)
        state = .armed(at: alarmTime)
    }

    // Evening bedtime (hour 12–23) → alarm next calendar day
    // Post-midnight bedtime (hour 0–11) → alarm same calendar day
    private func windowDates(relativeTo bedtimeDate: Date) -> (Date, Date) {
        // Calendar.current VOLONTAIRE — l'heure d'alarme suit le device, pas MTL.
        // L'utilisateur veut son 7h30 là où il est. Ne pas migrer vers Calendar.mtl.
        let calendar = Calendar.current
        let bedtimeHour = calendar.component(.hour, from: bedtimeDate)
        let dayOffset = bedtimeHour >= 12 ? 1 : 0
        let morningBase = calendar.date(byAdding: .day, value: dayOffset, to: bedtimeDate)!

        var startComps = calendar.dateComponents([.year, .month, .day], from: morningBase)
        startComps.hour = windowStartHour; startComps.minute = windowStartMinute; startComps.second = 0
        var endComps = startComps
        endComps.hour = windowEndHour; endComps.minute = windowEndMinute

        return (calendar.date(from: startComps)!, calendar.date(from: endComps)!)
    }
}
