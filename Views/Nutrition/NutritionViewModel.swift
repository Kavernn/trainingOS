import SwiftUI
import Combine

@MainActor
final class NutritionViewModel: ObservableObject {

    @Published var settings: NutritionSettings? = nil
    @Published var entries: [NutritionEntry] = []
    @Published var totals: NutritionTotals? = nil
    @Published var history: [NutritionDayHistory] = []
    @Published var effectiveCalories: Double? = nil
    @Published var todayType: String? = nil
    @Published var isLoading = true
    @Published var networkError: String? = nil

    func loadData(days: Int = 7, silent: Bool = false) async {
        if !silent { isLoading = true }
        let url = URL(string: "https://training-os-rho.vercel.app/api/nutrition_data?days=\(days)")!
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
            todayType         = decoded.todayType
            networkError = nil
        } catch {
            if entries.isEmpty { networkError = "Impossible de charger la nutrition" }
        }
        isLoading = false
    }

    func deleteEntry(_ entry: NutritionEntry) async {
        guard let eid = entry.entryId else { return }
        let url = URL(string: "https://training-os-rho.vercel.app/api/nutrition/delete")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": eid])
        _ = try? await URLSession.authed.data(for: req)
        await loadData(silent: true)
    }
}
