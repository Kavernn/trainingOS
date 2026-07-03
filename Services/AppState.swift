import SwiftUI
import Combine

// Seuil sous lequel on propose une estimation rétroactive pour la veille.
// Appliqué à calories ET protéines vs cibles courantes (TDEE).
private let LOW_NUTRITION_THRESHOLD: Double = 0.6

// Prompt affiché à l'ouverture app quand la nutrition de la veille est basse.
struct NutritionCatchupPrompt: Identifiable, Equatable {
    let id = UUID()
    let yesterday: String        // "YYYY-MM-DD"
    let currentCalories: Double
    let currentProteines: Double
    let entriesCount: Int
    let targetCalories: Double
    let targetProteines: Double
}

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
    @Published var openRecoveryView: Bool = false
    @Published var macroSessionHint: MacroNutritionHint? = nil
    @Published var pendingDNAEvolution: DNAEvolutionEvent? = nil
    @Published var pendingNutritionCatchup: NutritionCatchupPrompt? = nil

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

    // MARK: - Nutrition catchup (estimation rétroactive veille)

    /// Vérifie une fois/jour si la nutrition de la veille est anormalement basse.
    /// Guard UserDefaults posé UNIQUEMENT si aucun prompt à tirer (jour ack).
    /// Si prompt à tirer : set pendingNutritionCatchup, guard NON posé
    /// (la décision user posera le guard via dismiss/commit).
    /// Si fetch échoue : ni guard ni pending → retry au prochain check.
    func checkYesterdayNutrition() async {
        let today = todayStr
        let key = "nutrition_catchup_check_date"
        guard UserDefaults.standard.string(forKey: key) != today else { return }

        let cal = Calendar(identifier: .gregorian)
        guard let ydayDate = cal.date(byAdding: .day, value: -1, to: Date()) else { return }
        let yesterday = DateFormatter.isoDate.string(from: ydayDate)

        // sequential — iOS 26 beta async let LIFO crash
        // Fetch settings + day summary. Si l'un échoue → NE PAS poser la clé.
        let resp: NutritionDataResponse? = await {
            guard let url = try? APIService.shared.buildURL(path: "/api/nutrition_data"),
                  let (data, _) = try? await URLSession.authed.data(from: url) else { return nil }
            return try? APIService.decoder.decode(NutritionDataResponse.self, from: data)
        }()
        let day: NutritionDaySummary? = try? await APIService.shared.fetchNutritionDay(date: yesterday)

        guard let resp,
              let day,
              let calT     = resp.settings?.calories,  calT  > 0,
              let protT    = resp.settings?.proteines, protT > 0 else {
            return
        }

        let calRatio  = day.calories  / calT
        let protRatio = day.proteines / protT

        if calRatio < LOW_NUTRITION_THRESHOLD || protRatio < LOW_NUTRITION_THRESHOLD {
            pendingNutritionCatchup = NutritionCatchupPrompt(
                yesterday: yesterday,
                currentCalories:  day.calories,
                currentProteines: day.proteines,
                entriesCount:     day.entriesCount,
                targetCalories:   calT,
                targetProteines:  protT
            )
            // PAS de UserDefaults ici — on attend la décision user.
        } else {
            UserDefaults.standard.set(today, forKey: key)
        }
    }

    /// User a répondu "hier était complet" (ackForToday=true) ou l'estimation
    /// a été écrite avec succès. Clear le pending et pose le guard si ackForToday.
    /// Swipe-close du sheet → binding se reset à nil sans passer par ici, guard
    /// non posé, re-prompt au prochain launch.
    func dismissNutritionCatchup(ackForToday: Bool) {
        pendingNutritionCatchup = nil
        if ackForToday {
            UserDefaults.standard.set(todayStr, forKey: "nutrition_catchup_check_date")
        }
    }

    /// Écriture de l'estimation. Sur throw : NI pending clear NI guard posé —
    /// le sheet reste ouvert avec message d'erreur pour retry manuel.
    func commitYesterdayEstimate(pctCal: Double, pctProt: Double) async throws {
        try await APIService.shared.postYesterdayEstimate(
            pctCalories: pctCal, pctProteines: pctProt
        )
        dismissNutritionCatchup(ackForToday: true)
    }
}
