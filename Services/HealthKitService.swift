import Foundation
import Combine

// MARK: - Shared types (cross-platform)
struct SleepWindow {
    let bedtime:  Date
    let wakeTime: Date
    let hours:    Double
}

#if os(iOS)
import HealthKit

@MainActor
class HealthKitService: ObservableObject {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    @Published var isAuthorized = false

    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        let ids: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .bodyMass,
            .bodyFatPercentage,
            .activeEnergyBurned,
        ]
        for id in ids {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep   = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let workout = HKObjectType.workoutType() as HKObjectType? { types.insert(workout) }
        return types
    }()

    private var backgroundObservers: [HKObserverQuery] = []  // ROB-6: retained to prevent leak

    private init() {}

    // MARK: - Authorization

    func hasBeenAuthorized() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return false }
        return store.authorizationStatus(for: type) != .notDetermined
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            return true
        } catch {
            return false
        }
    }

    // MARK: - Steps
    func fetchTodaySteps() async -> Int? {
        return await fetchSteps(for: Date())
    }

    func fetchSteps(for date: Date) async -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                let val = stats?.sumQuantity()?.doubleValue(for: .count())
                cont.resume(returning: val.map { Int($0) })
            }
            store.execute(q)
        }
    }

    /// Resting HR for a specific date.
    /// Uses a 48-hour window (day-1 00:00 → day+1 00:00) because Apple Health
    /// stores resting HR samples with timestamps from the overnight measurement
    /// period, which may fall on the previous calendar day.
    func fetchRestingHR(for date: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let cal   = Calendar.current
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: date)!)
        let end   = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date))!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let val = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit(from: "count/min"))
                cont.resume(returning: val)
            }
            store.execute(q)
        }
    }

    /// Snapshot for a past date (steps + resting HR scoped to that date — accurate backfill).
    func fetchSnapshotForDate(_ date: Date) async -> (date: String, steps: Int?, restingHr: Double?) {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        async let s  = fetchSteps(for: date)
        async let hr = fetchRestingHR(for: date)   // ROB-8: date-scoped HR, not "latest overall"
        let (steps, rhr) = await (s, hr)
        return (fmt.string(from: date), steps, rhr)
    }

    // MARK: - Sleep (last night)
    func fetchLastNightSleep() async -> Double? {
        return await fetchLastNightSleepWindow()?.hours
    }

    /// Sleep hours for the night that precedes `date` (18:00 day-1 → 12:00 day).
    func fetchSleep(for date: Date) async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal   = Calendar.current
        let start = cal.date(byAdding: .hour, value: -6, to: cal.startOfDay(for: date))!
        let end   = cal.date(byAdding: .hour, value: 12, to: cal.startOfDay(for: date))!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 100, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else { cont.resume(returning: nil); return }
                let asleep = samples.filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                }
                guard !asleep.isEmpty else { cont.resume(returning: nil); return }
                let total = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: total > 0 ? total / 3600.0 : nil)
            }
            store.execute(q)
        }
    }

    /// Returns the bedtime, wake time, and total sleep duration from HealthKit for the last 18h window.
    func fetchLastNightSleepWindow() async -> SleepWindow? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let now   = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -18, to: now)!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: now)
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 100, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else { cont.resume(returning: nil); return }
                let asleep = samples.filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                }
                guard !asleep.isEmpty else { cont.resume(returning: nil); return }
                let totalSec = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                guard totalSec > 0 else { cont.resume(returning: nil); return }
                let bedtime  = asleep.min(by: { $0.startDate < $1.startDate })!.startDate
                let wakeTime = asleep.max(by: { $0.endDate   < $1.endDate   })!.endDate
                cont.resume(returning: SleepWindow(bedtime: bedtime, wakeTime: wakeTime, hours: totalSec / 3600.0))
            }
            store.execute(q)
        }
    }

    // MARK: - Resting Heart Rate
    func fetchLatestRestingHR() async -> Double? {
        return await fetchLatestQuantity(.restingHeartRate, unit: HKUnit(from: "count/min"))
    }

    // MARK: - HRV
    func fetchLatestHRV() async -> Double? {
        return await fetchLatestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
    }

    /// HRV for a specific date — same 48-hour window as fetchRestingHR.
    func fetchHRV(for date: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let cal   = Calendar.current
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: date)!)
        let end   = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date))!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let val = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .secondUnit(with: .milli))
                cont.resume(returning: val)
            }
            store.execute(q)
        }
    }

    // MARK: - Body Weight
    func fetchLatestBodyWeight() async -> Double? {
        guard let kg = await fetchLatestQuantity(.bodyMass, unit: .gramUnit(with: .kilo)) else { return nil }
        return kg * 2.20462
    }

    // MARK: - Body Fat %
    func fetchLatestBodyFat() async -> Double? {
        guard let v = await fetchLatestQuantity(.bodyFatPercentage, unit: .percent()) else { return nil }
        return v * 100.0
    }

    // MARK: - Generic latest quantity helper
    private func fetchLatestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let val = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: val)
            }
            store.execute(q)
        }
    }

    // MARK: - Today Active Energy
    func fetchTodayActiveEnergy() async -> Double? {
        return await fetchActiveEnergy(for: Date())
    }

    func fetchActiveEnergy(for date: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()))
            }
            store.execute(q)
        }
    }

    // MARK: - All Workouts (last N days, all activity types)
    func fetchAllWorkouts(days: Int = 1) async -> [HKWorkout] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: 20, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
    }

    // MARK: - Today Health Snapshot
    func fetchTodayHealthSnapshot() async -> WearableSnapshot {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())

        async let steps         = fetchTodaySteps()
        async let sleep         = fetchLastNightSleep()
        async let rhr           = fetchLatestRestingHR()
        async let hrv           = fetchLatestHRV()
        async let activeEnergy  = fetchTodayActiveEnergy()
        async let rawWorkouts   = fetchAllWorkouts(days: 1)
        async let bodyWeightLbs = fetchLatestBodyWeight()
        async let bodyFatPct    = fetchLatestBodyFat()

        let (s, sl, hr, h, ae, wkts, bw, bf) = await (steps, sleep, rhr, hrv, activeEnergy, rawWorkouts, bodyWeightLbs, bodyFatPct)

        let workouts = wkts.map { w -> WearableWorkout in
            let type: String
            switch w.workoutActivityType {
            case .running:   type = "course"
            case .cycling:   type = "vélo"
            case .swimming:  type = "natation"
            case .walking:   type = "marche"
            default:         type = "autre"
            }
            let dist = w.totalDistance.map { $0.doubleValue(for: .meter()) / 1000.0 }
            let cal  = w.totalEnergyBurned?.doubleValue(for: .kilocalorie())
            return WearableWorkout(type: type, durationMin: w.duration / 60.0,
                                   distanceKm: dist, calories: cal, avgHr: nil, avgPace: nil)
        }

        return WearableSnapshot(date: today, steps: s, sleepHours: sl, restingHr: hr,
                                hrv: h, activeEnergy: ae, bodyWeightLbs: bw,
                                bodyFatPct: bf, workouts: workouts)
    }

    // MARK: - Background Delivery
    func enableBackgroundDelivery(onChange: @escaping () -> Void) async {
        guard backgroundObservers.isEmpty else { return }  // already registered
        let ids: [HKQuantityTypeIdentifier] = [
            .stepCount, .restingHeartRate, .heartRateVariabilitySDNN, .activeEnergyBurned
        ]
        for id in ids {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            try? await store.enableBackgroundDelivery(for: type, frequency: .hourly)
            let pred = HKQuery.predicateForSamples(withStart: Date(), end: nil)
            let q = HKObserverQuery(sampleType: type, predicate: pred) { _, completion, _ in
                onChange()
                completion()
            }
            store.execute(q)
            backgroundObservers.append(q)  // ROB-6: retain query to prevent deallocation
        }
    }

    // MARK: - Workout → CardioEntry
    func workoutToCardioEntry(_ w: HKWorkout) -> (type: String, durationMin: Double, distanceKm: Double?, calories: Double?, avgHr: Double?) {
        let type: String
        switch w.workoutActivityType {
        case .running:   type = "course"
        case .cycling:   type = "vélo"
        case .swimming:  type = "natation"
        case .walking:   type = "marche"
        default:         type = "autre"
        }
        let dur  = w.duration / 60.0
        let dist = w.totalDistance.map { $0.doubleValue(for: .meter()) / 1000.0 }
        let cal  = w.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        return (type, dur, dist, cal, nil)
    }
}

#else

// MARK: - macOS stub (HealthKit non disponible)
@MainActor
class HealthKitService: ObservableObject {
    static let shared = HealthKitService()
    @Published var isAuthorized = false
    private init() {}

    func hasBeenAuthorized() -> Bool { false }
    func requestAuthorization() async -> Bool { false }
    func fetchTodaySteps() async -> Int? { nil }
    func fetchSteps(for date: Date) async -> Int? { nil }
    func fetchSnapshotForDate(_ date: Date) async -> (date: String, steps: Int?, restingHr: Double?) {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return (fmt.string(from: date), nil, nil)
    }
    func fetchLastNightSleep() async -> Double? { nil }
    func fetchLastNightSleepWindow() async -> SleepWindow? { nil }
    func fetchLatestRestingHR() async -> Double? { nil }
    func fetchLatestHRV() async -> Double? { nil }
    func fetchRestingHR(for date: Date) async -> Double? { nil }
    func fetchHRV(for date: Date) async -> Double? { nil }
    func fetchSleep(for date: Date) async -> Double? { nil }
    func fetchActiveEnergy(for date: Date) async -> Double? { nil }
    func fetchLatestBodyWeight() async -> Double? { nil }
    func fetchLatestBodyFat() async -> Double? { nil }
    func fetchTodayActiveEnergy() async -> Double? { nil }
    func fetchAllWorkouts(days: Int = 1) async -> [Any] { [] }
    func fetchTodayHealthSnapshot() async -> WearableSnapshot {
        WearableSnapshot(date: "", steps: nil, sleepHours: nil, restingHr: nil,
                         hrv: nil, activeEnergy: nil, bodyWeightLbs: nil,
                         bodyFatPct: nil, workouts: [])
    }
    func enableBackgroundDelivery(onChange: @escaping () -> Void) async {}
}

#endif
