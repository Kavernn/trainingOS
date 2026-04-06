import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    let api    = APIService.shared
    let alerts = AlertService.shared
    let units  = UnitSettings.shared

    @Published var userProfile: UserProfile? = nil

    var todayStr: String { DateFormatter.isoDate.string(from: Date()) }

    private init() {}

    func loadProfile() async {
        if let (profile, _, _) = try? await APIService.shared.fetchProfilData() {
            userProfile = profile
        }
    }
}
