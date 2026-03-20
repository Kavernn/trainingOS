import Foundation
import Combine

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
    func syncIfNeeded() async {
        guard shouldSync else { return }
        await sync()
    }

    /// Force-syncs regardless of the last sync timestamp.
    func sync() async {
        guard !isSyncing else { return }
        isSyncing  = true
        lastError  = nil
        defer { isSyncing = false }

        let authorized = await hk.requestAuthorization()
        guard authorized else {
            lastError = "HealthKit non autorisé"
            return
        }

        let snapshot = await hk.fetchTodayHealthSnapshot()

        // Skip if there's nothing to push
        guard snapshot.steps != nil
           || snapshot.sleepHours != nil
           || snapshot.restingHr != nil
           || snapshot.hrv != nil
           || snapshot.activeEnergy != nil
           || !snapshot.workouts.isEmpty
        else { return }

        do {
            try await APIService.shared.syncWearableData(snapshot)
            lastSyncDate = Date()
            defaults.set(lastSyncDate, forKey: lastSyncKey)
        } catch {
            lastError = error.localizedDescription
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
