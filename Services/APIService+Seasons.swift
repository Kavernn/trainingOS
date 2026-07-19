import Foundation
import OSLog

private let seasonsLogger = Logger(subsystem: "TrainingOS", category: "api+seasons")

extension APIService {

    func getActiveSeasonRaw() async throws -> Data {
        let url = try buildURL(path: "/api/seasons/active")
        return try await fetchWithCache(url: url, key: "season_active")
    }

    func getActiveSeason() async throws -> Season? {
        let data = try await getActiveSeasonRaw()
        if data.isEmpty || data == Data("{}".utf8) { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["id"] == nil { return nil }
        do {
            return try APIService.decoder.decode(Season.self, from: data)
        } catch {
            seasonsLogger.error("❌ getActiveSeason decode failed: \(error, privacy: .public)")
            throw APIError.decodingFailed(endpoint: "/api/seasons/active", error: error)
        }
    }

    func getAllSeasons() async throws -> [Season] {
        let url  = try buildURL(path: "/api/seasons")
        let data = try await fetchWithCache(url: url, key: "seasons_list")
        do {
            return try APIService.decoder.decode([Season].self, from: data)
        } catch {
            seasonsLogger.error("❌ getAllSeasons decode failed: \(error, privacy: .public)")
            throw APIError.decodingFailed(endpoint: "/api/seasons", error: error)
        }
    }

    func startSeason() async throws -> Season? {
        guard let data = try await offlinePost(endpoint: "/api/seasons/start", payload: [:]) else { return nil }
        CacheInvalidation.seasonMutated.invalidate()
        do {
            return try APIService.decoder.decode(Season.self, from: data)
        } catch {
            seasonsLogger.error("❌ startSeason decode failed: \(error, privacy: .public)")
            throw APIError.decodingFailed(endpoint: "/api/seasons/start", error: error)
        }
    }

    func closeSeason(id: String) async throws -> SeasonReport? {
        // POST direct + throw (pas offlinePost) : la fermeture d'une saison
        // est un événement de STRUCTURE (unique par définition), pas un log
        // de terrain. Le replay silencieux à la reconnexion écrasait le
        // rapport avant l'idempotence serveur (season_engine head guard).
        // Pattern miroir de updateSeason L59-73 ci-bas.
        var req = URLRequest(url: try buildURL(path: "/api/seasons/\(id)/close"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody  = try? JSONSerialization.data(withJSONObject: [:])
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.authed.data(for: req)
        CacheInvalidation.seasonMutated.invalidate()
        do {
            return try APIService.decoder.decode(SeasonReport.self, from: data)
        } catch {
            seasonsLogger.error("❌ closeSeason decode failed: \(error, privacy: .public)")
            throw APIError.decodingFailed(endpoint: "/api/seasons/\(id)/close", error: error)
        }
    }

    func updateSeason(id: String, fields: [String: Any]) async throws -> Season? {
        var req = URLRequest(url: try buildURL(path: "/api/seasons/\(id)"))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: fields)
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.authed.data(for: req)
        CacheInvalidation.seasonUpdated.invalidate()
        do {
            return try APIService.decoder.decode(Season.self, from: data)
        } catch {
            seasonsLogger.error("❌ updateSeason decode failed: \(error, privacy: .public)")
            throw APIError.decodingFailed(endpoint: "/api/seasons/\(id)", error: error)
        }
    }
}
