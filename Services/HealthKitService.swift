import Foundation
import Combine
import HealthKit

@MainActor
class HealthKitService: ObservableObject {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    @Published var isAuthorized = false

    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        let ids: [HKQuantityTypeIdentifier] = [
            .stepCount, .restingHeartRate, .heartRateVariabilitySDNN,
            .bodyMass, .bodyFatPercentage, .distanceWalkingRunning,
            .activeEnergyBurned, .heartRate
        ]
        for id in ids {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let workout = HKObjectType.workoutType() as HKObjectType? { types.insert(workout) }
        return types
    }()

    private init() {}

    // MARK: - Authorization
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
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                let val = stats?.sumQuantity()?.doubleValue(for: .count())
                cont.resume(returning: val.map { Int($0) })
            }
            store.execute(q)
        }
    }

    // MARK: - Sleep (last night)
    func fetchLastNightSleep() async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let now   = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -18, to: now)!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: now)
        let sort  = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 50, sortDescriptors: [sort]) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else { cont.resume(returning: nil); return }
                let asleep = samples.filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                }
                let totalSec = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: totalSec > 0 ? totalSec / 3600.0 : nil)
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

    // MARK: - Body Weight
    func fetchLatestBodyWeight() async -> Double? {
        // Returns in lbs
        guard let kg = await fetchLatestQuantity(.bodyMass, unit: .gramUnit(with: .kilo)) else { return nil }
        return kg * 2.20462
    }

    // MARK: - Body Fat %
    func fetchLatestBodyFat() async -> Double? {
        guard let v = await fetchLatestQuantity(.bodyFatPercentage, unit: .percent()) else { return nil }
        return v * 100.0
    }

    // MARK: - Recent Running Workouts
    func fetchRecentRunningWorkouts(days: Int = 30) async -> [HKWorkout] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let pred  = HKQuery.predicateForSamples(withStart: start, end: Date())
        let workoutPred = HKQuery.predicateForWorkouts(with: .running)
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [pred, workoutPred])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: combined, limit: 20, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
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
        let dur = w.duration / 60.0
        let dist = w.totalDistance.map { $0.doubleValue(for: .meter()) / 1000.0 }
        let cal  = w.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        return (type, dur, dist, cal, nil)
    }
}
