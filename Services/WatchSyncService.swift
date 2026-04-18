import Foundation
import Combine
#if os(iOS)
import HealthKit
#endif

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

    @Published var isSyncing   = false
    @Published var lastSyncDate: Date?
    @Published var lastError: String?

    private let syncInterval: TimeInterval = 30 * 60  // 30 min
    private let defaults     = UserDefaults.standard
    private let lastSyncKey  = "watchSync_lastDate"
    private let hk           = HealthKitService.shared

    private init() {
        lastSyncDate = defaults.object(forKey: lastSyncKey) as? Date
    }

    // MARK: - Public API

    var shouldSync: Bool {
        guard let last = lastSyncDate else { return true }
        return Date().timeIntervalSince(last) > syncInterval
    }

    /// Syncs only if the last sync was more than 30 min ago.
    /// Backfill always runs regardless of the throttle — it is idempotent and cheap.
    func syncIfNeeded() async {
        if hk.hasBeenAuthorized() {
            await backfillRecentDaysIfNeeded()
        }
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
        await sync()
    }

    /// Force-syncs regardless of the last sync timestamp.
    /// Does NOT prompt for HealthKit authorization — call requestAuthorizationAndSync() for that.
    func sync() async {
        guard !isSyncing else { return }
        guard hk.hasBeenAuthorized() else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        // Sync today
        let snapshot = await hk.fetchTodayHealthSnapshot()
        let hasData  = snapshot.steps != nil || snapshot.sleepHours != nil
                    || snapshot.restingHr != nil || snapshot.hrv != nil
                    || snapshot.activeEnergy != nil || !snapshot.workouts.isEmpty
        if hasData {
            do { try await APIService.shared.syncWearableData(snapshot) }
            catch { lastError = error.localizedDescription }
        }

        // Backfill recent days if their recovery logs have no steps
        await backfillRecentDaysIfNeeded()

        lastSyncDate = Date()
        defaults.set(lastSyncDate, forKey: lastSyncKey)
    }

    /// Checks the last 7 days and syncs any day that has HealthKit steps but no
    /// recovery log entry. Safe to call at any time — idempotent.
    func backfillRecentDaysIfNeeded() async {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"

        let existingLog = (try? await APIService.shared.fetchRecoveryData()) ?? []

        // Build list of dates that need backfill
        let datesToBackfill: [Date] = (1...7).compactMap { daysAgo -> Date? in
            guard let date = cal.date(byAdding: .day, value: -daysAgo, to: Date()) else { return nil }
            let dateStr = fmt.string(from: date)
            return existingLog.first(where: { $0.date == dateStr })?.steps != nil ? nil : date
        }
        guard !datesToBackfill.isEmpty else { return }

        // PERF-4: fetch all HK snapshots in parallel, then sync sequentially
        let hkService = hk
        var snapshots: [WearableSnapshot] = []
        await withTaskGroup(of: WearableSnapshot?.self) { group in
            for date in datesToBackfill {
                group.addTask { await hkService.fetchSnapshotForDate(date) }
            }
            for await snap in group {
                if let snap { snapshots.append(snap) }
            }
        }

        for snap in snapshots {
            guard let steps = snap.steps else { continue }
            let backfill = WearableSnapshot(
                date: snap.date, steps: steps, sleepHours: nil,
                restingHr: snap.restingHr, hrv: nil, activeEnergy: nil,
                bodyWeightLbs: nil, bodyFatPct: nil, workouts: []
            )
            try? await APIService.shared.syncWearableData(backfill)
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
