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

// File d'attente unifiée des prompts de lancement. Priorité stricte : séance > nutrition > DNA.
// Identifiable via caseKey stable → un seul case-type peut coexister (idempotence naturelle).
enum LaunchPrompt: Identifiable {
    case morningReveal(MorningBriefData)
    case nutritionCatchup(NutritionCatchupPrompt)
    case dnaEvolution(DNAEvolutionEvent)

    var caseKey: String {
        switch self {
        case .morningReveal:    return "morningReveal"
        case .nutritionCatchup: return "nutritionCatchup"
        case .dnaEvolution:     return "dnaEvolution"
        }
    }

    var priority: Int {
        switch self {
        case .morningReveal:    return 0
        case .nutritionCatchup: return 1
        case .dnaEvolution:     return 2
        }
    }

    var id: String { caseKey }
}

@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    let api    = APIService.shared
    let alerts = AlertService.shared
    let units  = UnitSettings.shared

    @Published var userProfile: UserProfile? = nil
    @Published var pendingDeepLink: String? = nil
    @Published var macroSessionHint: MacroNutritionHint? = nil

    // File d'attente des prompts de lancement (nutrition catchup, DNA evolution, morning reveal).
    // Le head (launchQueue.first) EST le prompt affiché ; le reste est en attente derrière lui.
    // Règle molle "jamais réordonner l'affiché" : les enqueue tardifs s'insèrent triés par
    // priorité dans le RESTE (index >= 1), le head reste stable jusqu'à son dismiss.
    @Published private(set) var launchQueue: [LaunchPrompt] = []

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
            enqueueLaunchPrompt(.dnaEvolution(DNAEvolutionEvent(oldArchetypeKey: lastKey, dna: dna)))
        }
        UserDefaults.standard.set(newKey, forKey: "dna_last_archetype_key")
        UserDefaults.standard.set(today, forKey: "dna_last_check_date")
    }

    func acknowledgeDNAEvolution() {
        launchQueue.removeAll { $0.caseKey == "dnaEvolution" }
    }

    // MARK: - Nutrition catchup (estimation rétroactive veille)

    /// Vérifie une fois/jour si la nutrition de la veille est anormalement basse.
    /// Guard UserDefaults posé UNIQUEMENT si aucun prompt à tirer (jour ack).
    /// Si prompt à tirer : enqueue .nutritionCatchup, guard NON posé
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
            enqueueLaunchPrompt(.nutritionCatchup(NutritionCatchupPrompt(
                yesterday: yesterday,
                currentCalories:  day.calories,
                currentProteines: day.proteines,
                entriesCount:     day.entriesCount,
                targetCalories:   calT,
                targetProteines:  protT
            )))
            // PAS de UserDefaults ici — on attend la décision user.
        } else {
            UserDefaults.standard.set(today, forKey: key)
        }
    }

    /// User a répondu "hier était complet" (ackForToday=true) ou l'estimation
    /// a été écrite avec succès. Clear le pending et pose le guard si ackForToday.
    /// Swipe-close du sheet → binding reset via ContentView, ackForToday=false → guard
    /// non posé, re-prompt au prochain launch.
    func dismissNutritionCatchup(ackForToday: Bool) {
        if ackForToday {
            UserDefaults.standard.set(todayStr, forKey: "nutrition_catchup_check_date")
        }
        launchQueue.removeAll { $0.caseKey == "nutritionCatchup" }
    }

    /// Écriture de l'estimation. Sur throw : NI pending clear NI guard posé —
    /// le sheet reste ouvert avec message d'erreur pour retry manuel.
    func commitYesterdayEstimate(pctCal: Double, pctProt: Double) async throws {
        try await APIService.shared.postYesterdayEstimate(
            pctCalories: pctCal, pctProteines: pctProt
        )
        dismissNutritionCatchup(ackForToday: true)
    }

    // MARK: - Launch prompt queue

    /// Enqueue un prompt de lancement. Idempotent : skip silencieusement si le même case-type
    /// est déjà en file. Le head reste stable ("jamais réordonner l'affiché") : queue vide →
    /// append (devient head/affiché) ; sinon insertion triée par priorité DANS LE RESTE (index >= 1).
    func enqueueLaunchPrompt(_ prompt: LaunchPrompt) {
        guard !launchQueue.contains(where: { $0.caseKey == prompt.caseKey }) else { return }
        if launchQueue.isEmpty {
            launchQueue.append(prompt)
            return
        }
        var insertAt = launchQueue.count
        for i in 1..<launchQueue.count {
            if launchQueue[i].priority > prompt.priority {
                insertAt = i
                break
            }
        }
        launchQueue.insert(prompt, at: insertAt)
    }

    /// Dismiss unifié : pose le side-effect UserDefaults propre au case puis retire de la file.
    /// Le head suivant est présenté automatiquement via les computeds.
    func dismissLaunchPrompt(_ prompt: LaunchPrompt) {
        switch prompt {
        case .morningReveal:
            UserDefaults.standard.set(todayStr, forKey: "morningRevealDate")
        case .nutritionCatchup:
            // UserDefaults "nutrition_catchup_check_date" posé uniquement via
            // dismissNutritionCatchup(ackForToday: true) — le contrat once/jour dépend de l'ack.
            break
        case .dnaEvolution:
            // UserDefaults "dna_last_check_date" posé dès checkDNAEvolution (indépendant du dismiss).
            break
        }
        launchQueue.removeAll { $0.caseKey == prompt.caseKey }
    }

    /// Alimente le .sheet racine — retourne le head uniquement si c'est un case-sheet.
    var currentSheetPrompt: LaunchPrompt? {
        guard let head = launchQueue.first, case .nutritionCatchup = head else { return nil }
        return head
    }

    /// Alimente le .fullScreenCover racine — retourne le head uniquement si c'est un case-cover.
    var currentCoverPrompt: LaunchPrompt? {
        guard let head = launchQueue.first else { return nil }
        switch head {
        case .morningReveal, .dnaEvolution: return head
        case .nutritionCatchup:             return nil
        }
    }
}
