import Foundation
import Combine

// MARK: - Shared types (cross-platform)
struct SleepWindow {
    let bedtime:  Date
    let wakeTime: Date
    let hours:    Double
}

struct SleepStages {
    let deepHours: Double
    let remHours:  Double
    let coreHours: Double
    var totalHours: Double { deepHours + remHours + coreHours }
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
            .heartRate,
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
            let shareTypes: Set<HKSampleType> = [HKWorkoutType.workoutType()]
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
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
        let cal   = ({ var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c }())
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

    /// Resting HR for a specific date — daily average via statistics query.
    /// 48-hour window (day-1 00:00 → day+1 00:00) covers overnight samples
    /// whose timestamps may fall on the previous calendar day.
    func fetchRestingHR(for date: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let cal   = ({ var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c }())
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: date)!)
        let end   = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date))!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .discreteAverage) { _, stats, _ in
                let val = stats?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
                cont.resume(returning: val)
            }
            store.execute(q)
        }
    }

    /// Snapshot for a past date (steps + resting HR scoped to that date — accurate backfill).
    func fetchSnapshotForDate(_ date: Date) async -> (date: String, steps: Int?, restingHr: Double?) {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        // sequential — async let LIFO crash on iOS 26 beta
        let steps = await fetchSteps(for: date)
        let rhr   = await fetchRestingHR(for: date)   // ROB-8: date-scoped HR, not "latest overall"
        return (fmt.string(from: date), steps, rhr)
    }

    // MARK: - Sleep (last night)
    func fetchLastNightSleep() async -> Double? {
        return await fetchLastNightSleepWindow()?.hours
    }

    /// Sleep hours for the night that precedes `date` (18:00 day-1 → 12:00 day).
    func fetchSleep(for date: Date) async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal   = ({ var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c }())
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
        let start = ({ var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c }()).date(byAdding: .hour, value: -18, to: now)!
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

    /// HRV for a specific date — morning window 04:00–10:00 (HRV4Training standard).
    /// Falls back to 20:00 previous day – 10:00 target day if no morning samples.
    /// Apple Watch heartRateVariabilitySDNN reports RMSSD despite the identifier name.
    func fetchHRV(for date: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current

        // Primary: morning window 04:00–10:00 (pre-activity, most stable RMSSD)
        guard let morningStart = cal.date(bySettingHour: 4,  minute: 0, second: 0, of: date),
              let morningEnd   = cal.date(bySettingHour: 10, minute: 0, second: 0, of: date) else { return nil }

        let morningPred = HKQuery.predicateForSamples(withStart: morningStart, end: morningEnd)
        let morningVal: Double? = await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: morningPred, options: .discreteAverage) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli)))
            }
            store.execute(q)
        }
        if let v = morningVal { return v }

        // Fallback: overnight window (20:00 previous day – 10:00 target day)
        // Covers watches worn during sleep without pre-wake measurements
        let prevDay     = cal.date(byAdding: .day, value: -1, to: date)!
        guard let nightStart = cal.date(bySettingHour: 20, minute: 0, second: 0, of: prevDay) else { return nil }
        let nightPred   = HKQuery.predicateForSamples(withStart: nightStart, end: morningEnd)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: nightPred, options: .discreteAverage) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli)))
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

    // MARK: - Heart Rate (keyed moments)

    private func fetchAvgHR(start: Date, end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .discreteAverage) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min")))
            }
            store.execute(q)
        }
    }

    /// Average HR 06:00–09:00 (repos matinal).
    func fetchMorningHR(for date: Date) async -> Double? {
        let cal   = ({ var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c }())
        let start = cal.date(bySettingHour: 6, minute: 0, second: 0, of: date)!
        let end   = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
        return await fetchAvgHR(start: start, end: end)
    }

    /// Average HR in the 30 min following the last workout of the day.
    func fetchPostWorkoutHR(for date: Date) async -> Double? {
        let cal      = ({ var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c }())
        let dayStart = cal.startOfDay(for: date)
        let dayEnd   = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        guard let last = workouts.first else { return nil }
        let start = last.endDate
        let end   = last.endDate.addingTimeInterval(30 * 60)
        return await fetchAvgHR(start: start, end: end)
    }

    /// Average HR 21:00–23:00 (repos vespéral).
    func fetchEveningHR(for date: Date) async -> Double? {
        let cal   = ({ var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c }())
        let start = cal.date(bySettingHour: 21, minute: 0, second: 0, of: date)!
        let end   = cal.date(bySettingHour: 23, minute: 0, second: 0, of: date)!
        return await fetchAvgHR(start: start, end: end)
    }

    // MARK: - Session HR & Calories (for post-session summary)

    func fetchWorkoutHR(start: Date, end: Date) async -> Double? {
        return await fetchAvgHR(start: start, end: end)
    }

    func fetchWorkoutCalories(start: Date, end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()))
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
        let cal   = ({ var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c }())
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
        let start = ({ var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c }()).date(byAdding: .day, value: -days, to: Date())!
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
        let today = DateFormatter.isoDate.string(from: Date())
        let now   = Date()

        enum Field {
            case steps(Int?), sleep(Double?), rhr(Double?), hrv(Double?)
            case energy(Double?), workouts([HKWorkout])
            case weight(Double?), fat(Double?)
            case hrM(Double?), hrP(Double?), hrE(Double?)
        }
        var s: Int? = nil; var sl: Double? = nil; var hr: Double? = nil
        var h: Double? = nil; var ae: Double? = nil; var wkts: [HKWorkout] = []
        var bw: Double? = nil; var bf: Double? = nil
        var hrM: Double? = nil; var hrP: Double? = nil; var hrE: Double? = nil

        await withTaskGroup(of: Field.self) { group in
            group.addTask { .steps(await self.fetchTodaySteps()) }
            group.addTask { .sleep(await self.fetchLastNightSleep()) }
            group.addTask { .rhr(await self.fetchLatestRestingHR()) }
            group.addTask { .hrv(await self.fetchLatestHRV()) }
            group.addTask { .energy(await self.fetchTodayActiveEnergy()) }
            group.addTask { .workouts(await self.fetchAllWorkouts(days: 1)) }
            group.addTask { .weight(await self.fetchLatestBodyWeight()) }
            group.addTask { .fat(await self.fetchLatestBodyFat()) }
            group.addTask { .hrM(await self.fetchMorningHR(for: now)) }
            group.addTask { .hrP(await self.fetchPostWorkoutHR(for: now)) }
            group.addTask { .hrE(await self.fetchEveningHR(for: now)) }
            for await field in group {
                switch field {
                case .steps(let v):    s    = v
                case .sleep(let v):    sl   = v
                case .rhr(let v):      hr   = v
                case .hrv(let v):      h    = v
                case .energy(let v):   ae   = v
                case .workouts(let v): wkts = v
                case .weight(let v):   bw   = v
                case .fat(let v):      bf   = v
                case .hrM(let v):      hrM  = v
                case .hrP(let v):      hrP  = v
                case .hrE(let v):      hrE  = v
                }
            }
        }

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
                                bodyFatPct: bf, hrMorning: hrM, hrPostWorkout: hrP,
                                hrEvening: hrE, workouts: workouts)
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

    // MARK: - Sleep Stages
    func fetchLastNightSleepStages() async -> SleepStages? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let now   = Date()
        let start = ({ var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c }()).date(byAdding: .hour, value: -18, to: now)!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: now)
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 200, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else { cont.resume(returning: nil); return }
                var deep = 0.0, rem = 0.0, core = 0.0
                for s in samples {
                    let dur = s.endDate.timeIntervalSince(s.startDate) / 3600.0
                    switch s.value {
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: deep += dur
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:  rem  += dur
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue: core += dur
                    default: break
                    }
                }
                guard deep + rem + core > 0 else { cont.resume(returning: nil); return }
                cont.resume(returning: SleepStages(deepHours: deep, remHours: rem, coreHours: core))
            }
            store.execute(q)
        }
    }

    // MARK: - Write Cardio Workout to HealthKit
    func saveCardioWorkout(type: String, startDate: Date, endDate: Date, distanceKm: Double?) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let activityType: HKWorkoutActivityType
        switch type {
        case "course":   activityType = .running
        case "vélo":     activityType = .cycling
        case "marche":   activityType = .walking
        default:         activityType = .other
        }
        var totalDistance: HKQuantity? = nil
        if let km = distanceKm, km > 0 {
            totalDistance = HKQuantity(unit: .meter(), doubleValue: km * 1000)
        }
        let workout = HKWorkout(
            activityType: activityType,
            start: startDate,
            end: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalEnergyBurned: nil,
            totalDistance: totalDistance,
            metadata: nil
        )
        try? await store.save(workout)
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
    func fetchLastNightSleepStages() async -> SleepStages? { nil }
    func fetchLatestRestingHR() async -> Double? { nil }
    func fetchLatestHRV() async -> Double? { nil }
    func fetchRestingHR(for date: Date) async -> Double? { nil }
    func fetchHRV(for date: Date) async -> Double? { nil }
    func fetchSleep(for date: Date) async -> Double? { nil }
    func fetchActiveEnergy(for date: Date) async -> Double? { nil }
    func fetchMorningHR(for date: Date) async -> Double? { nil }
    func fetchPostWorkoutHR(for date: Date) async -> Double? { nil }
    func fetchEveningHR(for date: Date) async -> Double? { nil }
    func fetchLatestBodyWeight() async -> Double? { nil }
    func fetchLatestBodyFat() async -> Double? { nil }
    func fetchTodayActiveEnergy() async -> Double? { nil }
    func fetchAllWorkouts(days: Int = 1) async -> [Any] { [] }
    func fetchTodayHealthSnapshot() async -> WearableSnapshot {
        WearableSnapshot(date: "", steps: nil, sleepHours: nil, restingHr: nil,
                         hrv: nil, activeEnergy: nil, bodyWeightLbs: nil,
                         bodyFatPct: nil, hrMorning: nil, hrPostWorkout: nil,
                         hrEvening: nil, workouts: [])
    }
    func enableBackgroundDelivery(onChange: @escaping () -> Void) async {}
    func saveCardioWorkout(type: String, startDate: Date, endDate: Date, distanceKm: Double?) async {}
}

#endif
