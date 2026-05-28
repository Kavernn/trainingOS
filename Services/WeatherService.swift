import SwiftUI
import Combine
import CoreLocation

struct DayForecast: Identifiable {
    let id = UUID()
    let date: Date
    let maxTemp: Double
    let minTemp: Double
    let symbol: String
}

@MainActor
final class WeatherViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var temperature: Double? = nil
    @Published var conditionSymbol: String = "cloud.fill"
    @Published var cityName: String = ""
    @Published var locationDenied: Bool = false
    @Published var forecast: [DayForecast] = []

    var todayMax: Double? { forecast.first?.maxTemp }
    var todayMin: Double? { forecast.first?.minTemp }

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        restoreFromCache()
    }

    func requestUpdate() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationDenied = false
            locationManager.requestLocation()
        case .denied, .restricted:
            locationDenied = true
        @unknown default:
            break
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.fetchWeather(for: loc)
            await self.reverseGeocode(loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                locationDenied = false
                manager.requestLocation()
            } else if status == .denied || status == .restricted {
                locationDenied = true
            }
        }
    }

    private func fetchWeather(for location: CLLocation) async {
        if CacheService.shared.load(for: "weather_data") != nil { return }
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min,weather_code&temperature_unit=celsius&forecast_days=7&timezone=auto"
        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        parseWeatherJSON(json)
        CacheService.shared.save(data, for: "weather_data")
    }

    private func restoreFromCache() {
        guard let data = CacheService.shared.load(for: "weather_data"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        parseWeatherJSON(json)
    }

    private func parseWeatherJSON(_ json: [String: Any]) {
        if let current = json["current"] as? [String: Any],
           let temp = current["temperature_2m"] as? Double {
            temperature = temp
            if let code = current["weather_code"] as? Int {
                conditionSymbol = Self.symbol(for: code)
            }
        }

        if let daily = json["daily"] as? [String: Any],
           let times  = daily["time"]               as? [String],
           let maxArr = daily["temperature_2m_max"] as? [Double],
           let minArr = daily["temperature_2m_min"] as? [Double],
           let codes  = daily["weather_code"]       as? [Int] {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withFullDate]
            forecast = zip(times.indices, times).compactMap { i, dateStr -> DayForecast? in
                guard i < maxArr.count, i < minArr.count, i < codes.count,
                      let date = fmt.date(from: dateStr) else { return nil }
                return DayForecast(date: date, maxTemp: maxArr[i], minTemp: minArr[i],
                                   symbol: Self.symbol(for: codes[i]))
            }
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        let geocoder = CLGeocoder()
        if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
            cityName = placemark.locality ?? placemark.administrativeArea ?? ""
        }
    }

    private static func symbol(for code: Int) -> String {
        switch code {
        case 0:           return "sun.max.fill"
        case 1:           return "sun.haze.fill"
        case 2:           return "cloud.sun.fill"
        case 3:           return "cloud.fill"
        case 45, 48:      return "cloud.fog.fill"
        case 51, 53, 55:  return "cloud.drizzle.fill"
        case 61, 63, 65:  return "cloud.rain.fill"
        case 71, 73, 75:  return "cloud.snow.fill"
        case 80, 81, 82:  return "cloud.heavyrain.fill"
        case 95, 96, 99:  return "cloud.bolt.rain.fill"
        default:          return "cloud.fill"
        }
    }
}

struct WeatherChipView: View {
    @ObservedObject var vm: WeatherViewModel

    var body: some View {
        if let temp = vm.temperature {
            VStack(spacing: 0) {
                // — Ligne actuelle —
                HStack(spacing: 10) {
                    Image(systemName: vm.conditionSymbol)
                        .font(.system(size: 22, weight: .medium))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: "%.0f°", temp))
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(.white)
                        if !vm.cityName.isEmpty {
                            Text(vm.cityName)
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                    }

                    Spacer()

                    if let hi = vm.todayMax, let lo = vm.todayMin {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange.opacity(0.8))
                                Text(String(format: "%.0f°", hi))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.cyan.opacity(0.8))
                                Text(String(format: "%.0f°", lo))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, vm.forecast.isEmpty ? 12 : 10)

                // — Strip hebdomadaire —
                if !vm.forecast.isEmpty {
                    Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 10)
                    HStack(spacing: 0) {
                        ForEach(Array(vm.forecast.enumerated()), id: \.1.id) { idx, day in
                            DayColumn(day: day, isToday: idx == 0)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                }
            }
            .background(Color.appCard)
            .cornerRadius(14)

        } else if vm.locationDenied {
            HStack(spacing: 8) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                Text("Météo · Activer la localisation dans Réglages")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.appCard)
            .cornerRadius(14)
        }
    }
}

private struct DayColumn: View {
    let day: DayForecast
    let isToday: Bool

    private var dayLabel: String {
        if isToday { return "Auj" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_CA")
        fmt.dateFormat = "EEE"
        return fmt.string(from: day.date).capitalized.prefix(3).description
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayLabel)
                .font(.system(size: 10, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .orange : .gray.opacity(0.6))

            Image(systemName: day.symbol)
                .font(.system(size: 14))
                .symbolRenderingMode(.multicolor)
                .frame(height: 16)

            Text(String(format: "%.0f°", day.maxTemp))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isToday ? .white : .white.opacity(0.75))

            Text(String(format: "%.0f°", day.minTemp))
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
        }
    }
}
