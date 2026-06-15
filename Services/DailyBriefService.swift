import Foundation
import Combine

struct DailyBrief: Codable {
    let date: String
    let useQuote: Bool
    let mot: String?
    let lecture: String
    let recommandation: [String]
    let generatedAt: String

    enum CodingKeys: String, CodingKey {
        case date, mot, lecture, recommandation
        case useQuote    = "use_quote"
        case generatedAt = "generated_at"
    }
}

@MainActor
class DailyBriefService: ObservableObject {
    static let shared = DailyBriefService()

    @Published var brief: DailyBrief?
    @Published var isLoading = false
    @Published var isStale = false

    private let cacheDataKey = "daily_brief_v1_data"
    private let cacheDateKey = "daily_brief_v1_date"

    func loadIfNeeded() async {
        let todayStr = DateFormatter.isoDate.string(from: Date())

        // Serve from UserDefaults cache if already fresh today
        if UserDefaults.standard.string(forKey: cacheDateKey) == todayStr,
           let cached = loadCached() {
            brief = cached
            isStale = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await APIService.shared.fetchDailyBrief()
            brief = fetched
            isStale = false
            saveCached(fetched, date: todayStr)
        } catch {
            // Fallback: yesterday's cached brief (never show empty)
            if let staleCache = loadCached() {
                brief = staleCache
                isStale = true
            }
        }
    }

    private func loadCached() -> DailyBrief? {
        guard let data = UserDefaults.standard.data(forKey: cacheDataKey) else { return nil }
        return try? JSONDecoder().decode(DailyBrief.self, from: data)
    }

    private func saveCached(_ brief: DailyBrief, date: String) {
        if let data = try? JSONEncoder().encode(brief) {
            UserDefaults.standard.set(data, forKey: cacheDataKey)
            UserDefaults.standard.set(date, forKey: cacheDateKey)
        }
    }
}
