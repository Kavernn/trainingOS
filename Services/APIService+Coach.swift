import Foundation

extension APIService {
    func fetchDailyInsight() async throws -> DailyInsight {
        let url = try buildURL(path: "/api/coach/daily_insight")
        let data = try await fetchWithCache(url: url, key: "daily_insight")
        return try APIService.decoder.decode(DailyInsight.self, from: data)
    }

    func fetchPostSession(date: String? = nil) async throws -> PostSessionData {
        let today = DateFormatter.isoDate.string(from: Date())
        let key = "post_session_\(date ?? today)"
        let path = date != nil ? "/api/coach/post_session?date=\(date!)" : "/api/coach/post_session"
        let url = try buildURL(path: path)
        let data = try await fetchWithCache(url: url, key: key)
        return try APIService.decoder.decode(PostSessionData.self, from: data)
    }
}
