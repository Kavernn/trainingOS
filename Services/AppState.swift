import SwiftUI
import Combine

// Hint affiché dans la card coaching de séance — calculé par DashboardViewModel après chargement.
struct MacroNutritionHint: Equatable {
    let isAbove: Bool
    let macro: String    // "protéines" / "glucides" / "calories"
    let value: Double
    let threshold: Double
    let unit: String     // "g" ou "kcal"
}

@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    let api    = APIService.shared
    let alerts = AlertService.shared
    let units  = UnitSettings.shared

    @Published var userProfile: UserProfile? = nil
    @Published var pendingDeepLink: String? = nil
    @Published var ritualTodayNotDone: Bool = false
    @Published var macroSessionHint: MacroNutritionHint? = nil

    var todayStr: String { DateFormatter.isoDate.string(from: Date()) }

    private init() {}

    func loadProfile() async {
        if let (profile, _, _) = try? await APIService.shared.fetchProfilData() {
            userProfile = profile
        }
    }
}
