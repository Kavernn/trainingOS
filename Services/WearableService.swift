import Foundation

// MARK: - Protocol

/// Interface unifiée pour toute source de données wearable.
/// Chaque implémentation représente une source : Apple Watch (HealthKit),
/// Garmin, Strava, Fitbit.
protocol WearableDataSource {
    var name: String { get }
    var isConnected: Bool { get }

    func fetchHeartRate(for date: String) async -> Double?
    func fetchRestingHeartRate(for date: String) async -> Double?
    func fetchHRV(for date: String) async -> Double?
    func fetchSteps(for date: String) async -> Int?
    func fetchSleepHours(for date: String) async -> Double?
    func fetchActiveMinutes(for date: String) async -> Double?
    func fetchDistanceKm(for date: String) async -> Double?
    func fetchCalories(for date: String) async -> Double?
}

// MARK: - Apple Watch / HealthKit

/// Implémentation réelle — wrap de HealthKitService existant.
/// Couvre : steps, sommeil, FC repos, HRV, poids, workouts.
@MainActor
final class HealthKitWearable: WearableDataSource {
    var name: String { "Apple Health" }
    var isConnected: Bool { HealthKitService.shared.isAuthorized }

    private let hk = HealthKitService.shared

    func fetchHeartRate(for date: String) async -> Double? { nil } // via workout avg_hr
    func fetchRestingHeartRate(for date: String) async -> Double? {
        guard let d = isoDate(date) else { return await hk.fetchLatestRestingHR() }
        return await hk.fetchRestingHR(for: d)
    }
    func fetchHRV(for date: String) async -> Double? {
        guard let d = isoDate(date) else { return await hk.fetchLatestHRV() }
        return await hk.fetchHRV(for: d)
    }
    func fetchSteps(for date: String) async -> Int? {
        guard let d = isoDate(date) else { return await hk.fetchTodaySteps() }
        return await hk.fetchSteps(for: d)
    }
    func fetchSleepHours(for date: String) async -> Double? { await hk.fetchLastNightSleep() }

    private func isoDate(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: s)
    }
    func fetchActiveMinutes(for date: String) async -> Double? { nil }
    func fetchDistanceKm(for date: String) async -> Double? { nil }
    func fetchCalories(for date: String) async -> Double? { nil }
}

// MARK: - Garmin Connect (placeholder)

/// Endpoint requis : GET https://connectapi.garmin.com/wellness-api/wellness/dailies/{userId}/{date}
/// Auth : OAuth 2.0 — https://connectapi.garmin.com/oauth-service/oauth/request_token
/// Scope : WELLNESS
/// Retourne : steps, distanceInMeters, activeKilocalories, restingHeartRateInBeatsPerMinute,
///            averageStressLevel, floorsClimbed, minutesAsleep
///
/// Pour activer :
///   1. Créer une app sur https://developer.garmin.com/
///   2. Stocker consumer key/secret dans Keychain
///   3. Implémenter OAuth 1.0a flow
///   4. Mapper la réponse vers WearableDataSource
final class GarminWearable: WearableDataSource {
    var name: String { "Garmin Connect" }
    var isConnected: Bool { false } // TODO: check stored OAuth token

    func fetchHeartRate(for date: String) async -> Double? { nil }
    func fetchRestingHeartRate(for date: String) async -> Double? { nil }
    func fetchHRV(for date: String) async -> Double? { nil }
    func fetchSteps(for date: String) async -> Int? { nil }
    func fetchSleepHours(for date: String) async -> Double? { nil }
    func fetchActiveMinutes(for date: String) async -> Double? { nil }
    func fetchDistanceKm(for date: String) async -> Double? { nil }
    func fetchCalories(for date: String) async -> Double? { nil }
}

// MARK: - Strava (placeholder)

/// Endpoint requis : GET https://www.strava.com/api/v3/activities?after={epoch}&before={epoch}
/// Auth : OAuth 2.0 — https://www.strava.com/oauth/authorize
/// Scope : read,activity:read
/// Retourne : distance, elapsed_time, average_heartrate, average_cadence,
///            calories, average_watts (pour vélo)
///
/// Pour activer :
///   1. Créer une app sur https://www.strava.com/settings/api
///   2. Implémenter OAuth 2.0 avec refresh token
///   3. Filtrer les activités par date
///   4. Convertir distance (mètres → km), temps (s → min)
final class StravaWearable: WearableDataSource {
    var name: String { "Strava" }
    var isConnected: Bool { false } // TODO: check stored refresh token

    func fetchHeartRate(for date: String) async -> Double? { nil }
    func fetchRestingHeartRate(for date: String) async -> Double? { nil }
    func fetchHRV(for date: String) async -> Double? { nil }
    func fetchSteps(for date: String) async -> Int? { nil }
    func fetchSleepHours(for date: String) async -> Double? { nil }
    func fetchActiveMinutes(for date: String) async -> Double? { nil }
    func fetchDistanceKm(for date: String) async -> Double? { nil }
    func fetchCalories(for date: String) async -> Double? { nil }
}

// MARK: - Fitbit (placeholder)

/// Endpoint requis : GET https://api.fitbit.com/1/user/-/activities/date/{YYYY-MM-DD}.json
///                   GET https://api.fitbit.com/1.2/user/-/sleep/date/{YYYY-MM-DD}.json
///                   GET https://api.fitbit.com/1/user/-/hrv/date/{YYYY-MM-DD}.json
/// Auth : OAuth 2.0 — https://www.fitbit.com/oauth2/authorize
/// Scope : activity heartrate sleep
///
/// Pour activer :
///   1. Créer une app sur https://dev.fitbit.com/
///   2. Implémenter OAuth 2.0 avec PKCE
///   3. Mapper activities/summary, sleep/summary, hrv/hrv
final class FitbitWearable: WearableDataSource {
    var name: String { "Fitbit" }
    var isConnected: Bool { false } // TODO: check stored access token

    func fetchHeartRate(for date: String) async -> Double? { nil }
    func fetchRestingHeartRate(for date: String) async -> Double? { nil }
    func fetchHRV(for date: String) async -> Double? { nil }
    func fetchSteps(for date: String) async -> Int? { nil }
    func fetchSleepHours(for date: String) async -> Double? { nil }
    func fetchActiveMinutes(for date: String) async -> Double? { nil }
    func fetchDistanceKm(for date: String) async -> Double? { nil }
    func fetchCalories(for date: String) async -> Double? { nil }
}

// MARK: - Aggregator

/// Tente chaque source dans l'ordre et retourne la première valeur non-nil.
/// Priorité : Apple Health > Garmin > Strava > Fitbit
@MainActor
final class WearableAggregator {
    static let shared = WearableAggregator()

    private(set) var sources: [WearableDataSource] = []

    private init() {
        Task { @MainActor in
            sources = [HealthKitWearable(), GarminWearable(), StravaWearable(), FitbitWearable()]
        }
    }

    var connectedSources: [WearableDataSource] { sources.filter(\.isConnected) }

    func fetchRestingHeartRate(for date: String) async -> Double? {
        for source in connectedSources {
            if let v = await source.fetchRestingHeartRate(for: date) { return v }
        }
        return nil
    }

    func fetchHRV(for date: String) async -> Double? {
        for source in connectedSources {
            if let v = await source.fetchHRV(for: date) { return v }
        }
        return nil
    }

    func fetchSteps(for date: String) async -> Int? {
        for source in connectedSources {
            if let v = await source.fetchSteps(for: date) { return v }
        }
        return nil
    }

    func fetchSleepHours(for date: String) async -> Double? {
        for source in connectedSources {
            if let v = await source.fetchSleepHours(for: date) { return v }
        }
        return nil
    }
}
