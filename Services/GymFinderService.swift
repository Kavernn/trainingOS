import Foundation
import CoreLocation

// MARK: - Overpass API Models (private)

private struct OverpassResponse: Codable {
    let elements: [OverpassElement]
}

private struct OverpassElement: Codable {
    let type: String
    let id: Int64
    let lat: Double?
    let lon: Double?
    let center: OverpassCenter?
    let tags: [String: String]?

    var latitude: Double?  { lat ?? center?.lat }
    var longitude: Double? { lon ?? center?.lon }
}

private struct OverpassCenter: Codable {
    let lat: Double
    let lon: Double
}

// MARK: - Gym Finder Service

final class GymFinderService {
    static let shared = GymFinderService()
    private init() {}

    private let overpassURL = URL(string: "https://overpass-api.de/api/interpreter")!

    func searchGyms(near location: CLLocation, radiusMeters: Int) async throws -> [Gym] {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let query = """
        [out:json][timeout:25];
        (
          node["leisure"="fitness_centre"](around:\(radiusMeters),\(lat),\(lon));
          way["leisure"="fitness_centre"](around:\(radiusMeters),\(lat),\(lon));
          node["amenity"="gym"](around:\(radiusMeters),\(lat),\(lon));
          way["amenity"="gym"](around:\(radiusMeters),\(lat),\(lon));
          node["sport"="fitness"]["name"](around:\(radiusMeters),\(lat),\(lon));
        );
        out body center qt;
        """

        var request = URLRequest(url: overpassURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        request.httpBody = "data=\(encoded)".data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OverpassResponse.self, from: data)

        var seen = Set<String>()
        var gyms: [Gym] = []

        for element in response.elements {
            guard let eLat = element.latitude,
                  let eLon = element.longitude,
                  let tags = element.tags,
                  let name = tags["name"], !name.isEmpty else { continue }

            let dedupeKey = "\(name.lowercased())_\(Int(eLat * 100))_\(Int(eLon * 100))"
            guard !seen.contains(dedupeKey) else { continue }
            seen.insert(dedupeKey)

            let gymLocation = CLLocation(latitude: eLat, longitude: eLon)
            let distance = location.distance(from: gymLocation)

            let gym = Gym(
                id: "\(element.type)/\(element.id)",
                name: name,
                latitude: eLat,
                longitude: eLon,
                address: buildAddress(from: tags),
                phone: tags["phone"] ?? tags["contact:phone"],
                website: tags["website"] ?? tags["contact:website"],
                openingHours: tags["opening_hours"],
                gymType: inferGymType(from: tags, name: name),
                distanceMeters: distance
            )
            gyms.append(gym)
        }

        return gyms.sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
    }

    private func buildAddress(from tags: [String: String]) -> String {
        var parts: [String] = []
        if let num = tags["addr:housenumber"], let street = tags["addr:street"] {
            parts.append("\(num) \(street)")
        } else if let street = tags["addr:street"] {
            parts.append(street)
        }
        if let city = tags["addr:city"] { parts.append(city) }
        let result = parts.joined(separator: ", ")
        return result.isEmpty ? "Adresse non disponible" : result
    }

    private func inferGymType(from tags: [String: String], name: String) -> GymType {
        let lower = name.lowercased()
        let sport = tags["sport"]?.lowercased() ?? ""

        if sport.contains("crossfit") || lower.contains("crossfit") { return .crossfit }

        let commercialBrands = ["goodlife", "la fitness", "anytime fitness", "planet fitness",
                                "24 hour fitness", "equifit", "énergie cardio", "snap fitness",
                                "gold's gym", "lifetime fitness", "crunch fitness"]
        if commercialBrands.contains(where: { lower.contains($0) }) { return .commercial }

        let hotelKeywords = ["marriott", "hilton", "hyatt", "sheraton", "westin",
                             "intercontinental", "holiday inn", "hampton inn", "best western"]
        if hotelKeywords.contains(where: { lower.contains($0) }) { return .hotel }
        if tags["tourism"] == "hotel" { return .hotel }

        if tags["amenity"] == "community_centre" || lower.contains("ymca") ||
           lower.contains("communautaire") || lower.contains("community centre") { return .community }

        if tags["leisure"] == "outdoor_gym" { return .outdoor }

        return .independent
    }
}
