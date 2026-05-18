import SwiftUI
import CoreLocation
import MapKit
import Combine

@MainActor
final class GymFinderViewModel: NSObject, ObservableObject {
    @Published var gyms: [Gym] = []
    @Published var filteredGyms: [Gym] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var locationDenied = false
    @Published var userLocation: CLLocation?
    @Published var filters = GymFilters()
    @Published var selectedGym: Gym?
    @Published var favorites: [GymFavorite] = []
    @Published var history: [GymVisit] = []
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var workoutEquipmentSuggestion: [EquipmentKey] = []
    @Published var selectedEquipmentProfile: EquipmentProfile?

    private let locationManager = CLLocationManager()
    private let service = GymFinderService.shared

    private let favoritesKey  = "gym_favorites_v1"
    private let historyKey    = "gym_history_v1"
    private let cacheKey      = "gym_search_cache_v1"
    private let cacheTimeKey  = "gym_search_cache_time_v1"

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        loadFavorites()
        loadHistory()
        restoreCache()
    }

    // MARK: - Effective equipment (profile > crowdsource)

    func effectiveAvailable(for gym: Gym) -> Set<EquipmentKey> {
        if let profile = selectedEquipmentProfile {
            return profile.availableSet
        }
        guard let eqStrings = gym.crowdsource?.equipment else { return [] }
        return Set(eqStrings.compactMap { EquipmentKey(rawValue: $0) })
    }

    // MARK: - Location

    func requestLocation() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationDenied = false
            locationManager.requestLocation()
        case .denied, .restricted:
            locationDenied = true
        @unknown default: break
        }
    }

    // MARK: - Search

    func searchGyms() async {
        guard let location = userLocation else { requestLocation(); return }
        isLoading = true
        error = nil

        inferWorkoutEquipment()

        do {
            var results = try await service.searchGyms(near: location, radiusMeters: filters.radiusKm * 1000)
            await fetchCrowdsource(for: &results)
            gyms = results
            saveCache(results)
            applyFilters()
            withAnimation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: Double(filters.radiusKm) * 1400,
                    longitudinalMeters: Double(filters.radiusKm) * 1400
                ))
            }
        } catch {
            if gyms.isEmpty {
                self.error = "Recherche échouée. Vérifie ta connexion et réessaie."
            }
        }

        isLoading = false
    }

    func applyFilters() {
        var result = gyms

        if !filters.selectedTypes.isEmpty {
            result = result.filter { filters.selectedTypes.contains($0.gymType) }
        }
        if filters.openNow {
            result = result.filter { $0.isOpenNow == true }
        }
        if filters.dropInOnly {
            result = result.filter { $0.crowdsource?.dropInPrice != nil }
        }
        if !filters.requiredEquipment.isEmpty {
            result = result.filter { gym in
                guard let eq = gym.crowdsource?.equipment else { return false }
                return filters.requiredEquipment.allSatisfy { eq.contains($0.rawValue) }
            }
        }

        filteredGyms = result
    }

    func changeRadius(_ km: Int) {
        filters.radiusKm = km
        Task { await searchGyms() }
    }

    // MARK: - Workout-aware

    private func inferWorkoutEquipment() {
        guard let today = APIService.shared.dashboard?.today else { return }
        let lower = today.lowercased()

        if lower.contains("squat") || lower.contains("legs") || lower.contains("jambes") {
            workoutEquipmentSuggestion = [.squatRack, .barbell]
        } else if lower.contains("deadlift") || lower.contains("soulevé") || lower.contains("hinge") || lower.contains("rdl") {
            workoutEquipmentSuggestion = [.barbell, .dumbbells]
        } else if lower.contains("push") || lower.contains("chest") || lower.contains("poitrine") || lower.contains("press") {
            workoutEquipmentSuggestion = [.bench, .dumbbells, .cables]
        } else if lower.contains("pull") || lower.contains("back") || lower.contains("dos") || lower.contains("row") {
            workoutEquipmentSuggestion = [.cables, .dumbbells, .pullUpBar]
        } else if lower.contains("full") || lower.contains("complet") {
            workoutEquipmentSuggestion = [.dumbbells, .barbell]
        } else if lower.contains("cardio") || lower.contains("hiit") {
            workoutEquipmentSuggestion = [.cardio]
        }
    }

    func applyWorkoutFilter() {
        filters.requiredEquipment = Set(workoutEquipmentSuggestion)
        applyFilters()
    }

    // MARK: - Crowdsource

    private func fetchCrowdsource(for gyms: inout [Gym]) async {
        guard let url = URL(string: "\(APIConfig.base)/api/gyms/crowdsource_bulk") else { return }
        let ids = gyms.map { $0.id }
        guard let body = try? JSONSerialization.data(withJSONObject: ["gym_ids": ids]) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 10

        guard let (data, _) = try? await URLSession.authed.data(for: req),
              let decoded = try? JSONDecoder().decode([String: GymCrowdsource].self, from: data) else { return }

        for i in gyms.indices {
            gyms[i].crowdsource = decoded[gyms[i].id]
        }
    }

    func submitContribution(_ payload: GymContributionPayload) async {
        guard let body = try? JSONEncoder().encode(payload) else { return }
        var req = URLRequest(url: URL(string: "\(APIConfig.base)/api/gyms/contribute")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 10
        _ = try? await URLSession.authed.data(for: req)
    }

    // MARK: - Favorites

    func isFavorite(_ gym: Gym) -> Bool { favorites.contains { $0.id == gym.id } }

    func toggleFavorite(_ gym: Gym) {
        if let idx = favorites.firstIndex(where: { $0.id == gym.id }) {
            favorites.remove(at: idx)
        } else {
            favorites.append(GymFavorite(
                id: gym.id, name: gym.name, address: gym.address,
                latitude: gym.latitude, longitude: gym.longitude,
                gymType: gym.gymType, savedAt: Date()
            ))
        }
        saveFavorites()
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey),
              let decoded = try? JSONDecoder().decode([GymFavorite].self, from: data) else { return }
        favorites = decoded
    }

    private func saveFavorites() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: favoritesKey)
    }

    // MARK: - History

    func logVisit(to gym: Gym) {
        let visit = GymVisit(
            id: UUID().uuidString, gymId: gym.id,
            gymName: gym.name, gymAddress: gym.address, visitedAt: Date()
        )
        history.insert(visit, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        saveHistory()

        Task {
            _ = try? await APIService.shared.offlinePost(
                endpoint: "/api/gyms/history",
                payload: [
                    "gym_id": gym.id, "gym_name": gym.name,
                    "latitude": gym.latitude, "longitude": gym.longitude,
                    "visited_at": ISO8601DateFormatter().string(from: Date())
                ]
            )
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([GymVisit].self, from: data) else { return }
        history = decoded
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    // MARK: - Offline Cache (TTL 2h)

    private func saveCache(_ gyms: [Gym]) {
        guard let data = try? JSONEncoder().encode(gyms) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimeKey)
    }

    private func restoreCache() {
        let ts = UserDefaults.standard.double(forKey: cacheTimeKey)
        guard ts > 0,
              Date().timeIntervalSince1970 - ts < 7200,
              let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([Gym].self, from: data),
              !cached.isEmpty else { return }
        gyms = cached
        filteredGyms = cached
    }
}

// MARK: - CLLocationManagerDelegate

extension GymFinderViewModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.userLocation = loc
            await self.searchGyms()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationDenied = false
                manager.requestLocation()
            case .denied, .restricted:
                self.locationDenied = true
            default: break
            }
        }
    }
}
