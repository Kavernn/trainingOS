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
    @Published var openRecoveryView: Bool = false
    @Published var macroSessionHint: MacroNutritionHint? = nil
    @Published var pendingDNAEvolution: DNAEvolutionEvent? = nil

    var todayStr: String { DateFormatter.isoDate.string(from: Date()) }

    private init() {}

    func loadProfile() async {
        if let (profile, _, _) = try? await APIService.shared.fetchProfilData() {
            userProfile = profile
        }
    }

    func checkDNAEvolution() async {
        let today = todayStr
        guard UserDefaults.standard.string(forKey: "dna_last_check_date") != today else { return }
        guard let dna = try? await APIService.shared.fetchWorkoutDNA() else { return }
        let newKey = dna.archetype.key
        let lastKey = UserDefaults.standard.string(forKey: "dna_last_archetype_key")
        if let lastKey, lastKey != newKey {
            pendingDNAEvolution = DNAEvolutionEvent(oldArchetypeKey: lastKey, dna: dna)
        }
        UserDefaults.standard.set(newKey, forKey: "dna_last_archetype_key")
        UserDefaults.standard.set(today, forKey: "dna_last_check_date")
    }

    func acknowledgeDNAEvolution() {
        pendingDNAEvolution = nil
    }
}
