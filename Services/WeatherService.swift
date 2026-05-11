import SwiftUI
import CoreLocation

@MainActor
final class WeatherViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var temperature: Double? = nil
    @Published var conditionSymbol: String = "cloud.fill"
    @Published var cityName: String = ""
    @Published var lastUpdated: Date? = nil
    @Published var locationDenied: Bool = false

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
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
        // 10min cache — skip re-fetch if data is recent
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < 600 { return }
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&temperature_unit=celsius&forecast_days=1"
        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double else { return }
        temperature = temp
        if let code = current["weather_code"] as? Int {
            conditionSymbol = Self.symbol(for: code)
        }
        lastUpdated = Date()
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
            HStack(spacing: 12) {
                Image(systemName: vm.conditionSymbol)
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "%.0f°C", temp))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    if !vm.cityName.isEmpty {
                        Text(vm.cityName)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                if let updated = vm.lastUpdated {
                    Text(updated, style: .relative)
                        .font(.system(size: 9))
                        .foregroundColor(.gray.opacity(0.45))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(hex: "11111c"))
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
            .background(Color(hex: "11111c"))
            .cornerRadius(14)
        }
    }
}
