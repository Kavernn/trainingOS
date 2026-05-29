import SwiftUI
import Combine

@MainActor
final class NutritionViewModel: ObservableObject {

    @Published var settings: NutritionSettings? = nil
    @Published var entries: [NutritionEntry] = []
    @Published var totals: NutritionTotals? = nil
    @Published var history: [NutritionDayHistory] = []
    @Published var effectiveCalories: Double? = nil
    @Published var effectiveGlucides: Double? = nil
    @Published var todayType: String? = nil
    @Published var todaySession: String? = nil
    @Published var isLoading = true
    @Published var networkError: String? = nil
    @Published var qualityScore: Int? = nil
    @Published var qualityIsTooEarly: Bool = false
    @Published var qualityNoData: Bool = false

    func loadData(days: Int = 7, silent: Bool = false) async {
        if !silent { isLoading = true }
        let url = URL(string: "\(APIConfig.base)/api/nutrition_data?days=\(days)")!
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.authed.data(for: req)
            let decoded   = try JSONDecoder().decode(NutritionDataResponse.self, from: data)
            settings          = decoded.settings
            totals            = decoded.totals
            entries           = decoded.entries
            history           = decoded.history
            effectiveCalories = decoded.effectiveCalories
            effectiveGlucides = decoded.effectiveGlucides
            todayType         = decoded.todayType
            todaySession      = decoded.todaySession
            networkError = nil
        } catch {
            // N-B2: always set networkError on failure, even when entries exist
            networkError = "Impossible de charger la nutrition"
        }
        isLoading = false
        if let qUrl = URL(string: "\(APIConfig.base)/api/nutrition/quality"),
           let (qData, _) = try? await URLSession.authed.data(for: URLRequest(url: qUrl)),
           let q = try? JSONDecoder().decode(NutritionQualityResponse.self, from: qData) {
            qualityScore      = q.noData ? nil : q.score
            qualityIsTooEarly = q.isTooEarly
            qualityNoData     = q.noData
        }
    }

    func deleteEntry(_ entry: NutritionEntry) async {
        guard let eid = entry.entryId else { return }
        let url = URL(string: "\(APIConfig.base)/api/nutrition/delete")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": eid])
        _ = try? await URLSession.authed.data(for: req)
        await loadData(silent: true)
    }
}
