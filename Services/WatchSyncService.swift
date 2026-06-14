import Foundation
import Combine
import OSLog
#if os(iOS)
import HealthKit
#endif

private let watchLogger = Logger(subsystem: "TrainingOS", category: "watch_sync")

/// Orchestrates automatic Apple Watch → Supabase synchronisation.
///
/// Data flow:
///   Apple Watch → HealthKit (iPhone) → WatchSyncService → APIService → Supabase
///
/// Sync triggers:
///   - App foregrounded (via ScenePhase in TrainingOSApp or DashboardView)
///   - HealthKit background delivery (hourly observer for steps/HR/HRV)
///   - Manual pull-to-refresh in RecoveryView
///
/// Deduplication: syncs at most once every 30 minutes (UserDefaults timestamp).
@MainActor
class WatchSyncService: ObservableObject {
    static let shared = WatchSyncService()

    @Published var isSyncing          = false
    @Published var lastSyncDate: Date?
    @Published var lastSyncCompleted: Date?
    @Published var lastError: String?

    private let syncInterval:     TimeInterval = 30 * 60   // 30 min
    private let backfillInterval: TimeInterval = 60 * 60   // 1h — backfill is expensive (7 days × upsert)
    private let defaults       = UserDefaults.standard
    private let lastSyncKey    = "watchSync_lastDate"
    private let lastBackfillKey = "watchSync_lastBackfill"
    private let hk             = HealthKitService.shared

    private init() {
        lastSyncDate = defaults.object(forKey: lastSyncKey) as? Date
    }

    // MARK: - Public API

    var shouldSync: Bool {
        guard let last = lastSyncDate else { return true }
        return Date().timeIntervalSince(last) > syncInterval
    }

    private var shouldBackfill: Bool {
        guard let last = defaults.object(forKey: lastBackfillKey) as? Date else { return true }
        return Date().timeIntervalSince(last) > backfillInterval
    }

    /// Syncs only if the last sync was more than 30 min ago.
    /// Backfill throttle is enforced inside sync() — no need to duplicate here.
    func syncIfNeeded() async {
        guard shouldSync else { return }
        await sync()
    }

    /// Requests HealthKit authorization (shows system dialog) then syncs.
    /// Call this only from an explicit user action (e.g. a "Connect HealthKit" button).
    func requestAuthorizationAndSync() async {
        #if os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "HealthKit non disponible sur cet appareil"
            return
        }
        #endif
        let authorized = await hk.requestAuthorization()
        guard authorized else {
            lastError = "Accès refusé — activer dans Réglages > Confidentialité > Santé"
            return
        }
        await sync(manual: true)
    }

    /// Force-syncs regardless of the last sync timestamp.
    /// Does NOT prompt for HealthKit authorization — call requestAuthorizationAndSync() for that.
    /// Pass `manual: true` from UI buttons to surface errors when no HealthKit data is found.
    func sync(manual: Bool = false) async {
        guard !isSyncing else { return }
        guard hk.hasBeenAuthorized() else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
        // Watchdog: safety net if a future HK callback hangs (real fix is sequential fetches above)
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            self?.isSyncing = false
        }
        defer { watchdog.cancel() }

        // Sync today
        let snapshot = await hk.fetchTodayHealthSnapshot()
        let hasData  = snapshot.steps != nil || snapshot.sleepHours != nil
                    || snapshot.restingHr != nil || snapshot.hrv != nil
                    || snapshot.activeEnergy != nil || !snapshot.workouts.isEmpty
        if hasData {
            do {
                try await APIService.shared.syncWearableData(snapshot)
                if snapshot.hrv != nil { NotificationService.cancelHRVReminder() }
            } catch {
                lastError = error.localizedDescription
                return
            }
        }

        // Backfill recent days — throttled to 1h to avoid excessive egress
        if shouldBackfill {
            await backfillRecentDaysIfNeeded()
            defaults.set(Date(), forKey: lastBackfillKey)
        }

        if manual && !hasData && lastError == nil {
            lastError = "Aucune donnée HealthKit — porte ton Apple Watch et autorise l'accès dans Réglages > Santé"
        }

        lastSyncDate      = Date()
        lastSyncCompleted = Date()
        defaults.set(lastSyncDate, forKey: lastSyncKey)
    }

    /// Checks the last 7 days and syncs any day missing steps or sleep in its recovery log.
    /// Safe to call at any time — idempotent.
    func backfillRecentDaysIfNeeded() async {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"

        let existingLog = (try? await APIService.shared.fetchRecoveryData()) ?? []

        // Build list of dates that need backfill (any core metric still missing)
        let datesToBackfill: [Date] = (1...7).compactMap { daysAgo -> Date? in
            let date = Date(timeIntervalSince1970: Date().timeIntervalSince1970 - Double(daysAgo) * 86400)
            let dateStr = fmt.string(from: date)
            let entry = existingLog.first(where: { $0.date == dateStr })
            let missing = entry?.steps == nil || entry?.sleepHours == nil
                       || entry?.restingHr == nil || entry?.hrv == nil
            return missing ? date : nil
        }
        guard !datesToBackfill.isEmpty else { return }

        // sequential — withTaskGroup hangs on iOS 26 beta (same LIFO bug as async let)
        for date in datesToBackfill {
            let t          = await hk.fetchSnapshotForDate(date)
            let sleepHours = await hk.fetchSleep(for: date)
            let hrv        = await hk.fetchHRV(for: date)
            let snap = WearableSnapshot(date: t.date, steps: t.steps, sleepHours: sleepHours,
                                        restingHr: t.restingHr, hrv: hrv, activeEnergy: nil,
                                        bodyWeightLbs: nil, bodyFatPct: nil,
                                        hrMorning: nil, hrPostWorkout: nil, hrEvening: nil,
                                        workouts: [], spo2: nil, wristTemp: nil,
                                        bedtime: nil, wakeTime: nil)
            guard snap.steps != nil || snap.sleepHours != nil
               || snap.restingHr != nil || snap.hrv != nil else { continue }
            do {
                try await APIService.shared.syncWearableData(snap)
            } catch {
                watchLogger.warning("WatchSync backfill failed for \(snap.date): \(error)")
            }
        }
    }

    /// Registers hourly HealthKit background observers.
    /// Call once from the app entry point (e.g. TrainingOSApp.init or onAppear).
    func enableBackgroundDelivery() async {
        await hk.enableBackgroundDelivery { [weak self] in
            Task { @MainActor in
                await self?.sync()
            }
        }
    }
}
