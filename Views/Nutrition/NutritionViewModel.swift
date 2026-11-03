import SwiftUI
import Combine

@MainActor
final class NutritionViewModel: ObservableObject {

    @Published var settings: NutritionSettings? = nil
    @Published var entries: [NutritionEntry] = []
    @Published var totals: NutritionTotals? = nil
    @Published var history: [NutritionDayHistory] = []
    @Published var todayType: String? = nil
    @Published var todaySession: String? = nil
    @Published var isLoading = true
    @Published var networkError: String? = nil
    @Published var qualityScore: Int? = nil
    @Published var qualityIsTooEarly: Bool = false
    @Published var qualityNoData: Bool = false
    @Published var refreshID: UUID = UUID()

    @Published private(set) var hasLoaded = false
    @Published private(set) var energy: EnergyDaily?
    private var generation = 0
    private let fetch: (URLRequest) async throws -> (Data, URLResponse)
    private let remove: (String) async throws -> Void
    private let fetchEnergy: () async throws -> EnergyDaily

    init(fetch: @escaping (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.authed.data(for: $0)
    }, remove: @escaping (String) async throws -> Void = {
        try await APIService.shared.deleteNutritionEntry(id: $0)
    }, fetchEnergy: @escaping () async throws -> EnergyDaily = {
        try await APIService.shared.fetchEnergyDaily()
    }) {
        self.fetch = fetch
        self.remove = remove
        self.fetchEnergy = fetchEnergy
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await fetch(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    func loadData(days: Int = 7) async {
        generation += 1
        let token = generation
        isLoading = true
        defer { if token == generation { isLoading = false } }
        guard let url = URL(string: "\(APIConfig.base)/api/nutrition_data?days=\(days)") else { return }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        do {
            let data = try await responseData(for: req)
            guard token == generation, !Task.isCancelled else { return }
            let decoded = try APIService.decoder.decode(NutritionDataResponse.self, from: data)
            settings = decoded.settings
            totals = decoded.totals
            entries = decoded.entries
            history = decoded.history
            todayType = decoded.todayType
            todaySession = decoded.todaySession
            hasLoaded = true
            networkError = nil
            refreshID = UUID()
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                networkError = "Impossible de charger la nutrition"
            }
            return
        }
        // Supplemental failures retain the last useful value; every publication
        // belongs to this refresh, including responses from transports ignoring cancellation.
        if let qURL = URL(string: "\(APIConfig.base)/api/nutrition/quality"),
           let data = try? await responseData(for: URLRequest(url: qURL)),
           let quality = try? APIService.decoder.decode(NutritionQualityResponse.self, from: data) {
            guard token == generation, !Task.isCancelled else { return }
            qualityScore = quality.noData ? nil : quality.score
            qualityIsTooEarly = quality.isTooEarly
            qualityNoData = quality.noData
        }
        guard token == generation, !Task.isCancelled else { return }
        if let freshEnergy = try? await fetchEnergy() {
            guard token == generation, !Task.isCancelled else { return }
            energy = freshEnergy
        }
    }

    func deleteEntry(_ entry: NutritionEntry) async {
        guard let eid = entry.entryId else { return }
        do {
            try await remove(eid)
        } catch {
            // An in-flight read must not erase this failed mutation's feedback.
            generation += 1
            isLoading = false
            networkError = "Suppression échouée — réessaie"
            return
        }
        await loadData()
    }
}
