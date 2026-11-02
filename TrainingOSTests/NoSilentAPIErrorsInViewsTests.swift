import XCTest

/// Garde-fou de migration : interdit les erreurs d'appels API silencieuses
/// dans Views/. Granularité SITE (fichier + fonction d'API appelée), plus
/// robuste que la ligne. Tout NOUVEAU site silencieux fait échouer le test,
/// même dans un fichier déjà listé (nouvelle fonction = nouvelle dette).
///
/// Détecte :
/// 1. `try? await APIService.shared.XYZ(...)` → site = fichier + "XYZ"
/// 2. `try? await URLSession.authed...`       → site = fichier + "URLSession.authed"
/// 3. `catch { ... }` silencieux :
///    - vide                      → site = fichier + "catch:empty"
///    - uniquement logger/print/NSLog → site = fichier + "catch:log-only"
///    - uniquement `_ = ...` ignoré   → site = fichier + "catch:ignored"
///
/// Workflow : à chaque migration, on retire les sites concernés de
/// `knownSites`. Si le test tombe sur un nouveau site, soit on migre, soit
/// on l'ajoute explicitement à `knownSites` (dette tracée, pas de drift
/// invisible).
final class NoSilentAPIErrorsInViewsTests: XCTestCase {

    /// Sites connus comme silencieux à la date de création du garde-fou
    /// (2026-11-01) : 92 try? détectés. Catches silencieux ajoutés après
    /// première exécution. Chaque migration retire ses lignes.
    private static let knownSites: Set<String> = [
        "Views/BodyComp/BodyCompView.swift:URLSession.authed",
        "Views/BodyComp/BodyCompView.swift:fetchProfilData",
        "Views/BodyComp/NavyCalculatorView.swift:fetchProfilData",
        "Views/Budget/BudgetView.swift:fetchBudgetStatus",
        "Views/Cardio/CardioSummaryView.swift:fetchCardioData",
        "Views/Cardio/CardioSummaryView.swift:fetchReadiness",
        "Views/Cardio/CardioSummaryView.swift:fetchRecoveryData",
        "Views/Cardio/CardioView.swift:fetchCardioData",
        "Views/Cardio/CardioView.swift:fetchCardioMetrics",
        "Views/Cardio/CardioView.swift:fetchHIITData",
        "Views/Dashboard/DashboardViewModel.swift:checkMoodDue",
        "Views/Dashboard/DashboardViewModel.swift:fetchBudgetStatus",
        "Views/Dashboard/DashboardViewModel.swift:fetchCardioData",
        "Views/Dashboard/DashboardViewModel.swift:fetchNutritionDetail",
        "Views/Dashboard/DashboardViewModel.swift:fetchRitualToday",
        "Views/Dashboard/DashboardViewModel.swift:fetchTimeCapsules",
        "Views/Dashboard/DashboardViewModel.swift:fetchWeeklyReport",
        "Views/Dashboard/DashboardViewModel.swift:fetchWeeklyTonnage",
        "Views/Dashboard/DashboardViewModel.swift:fetchWorkoutDNA",
        "Views/Dashboard/DashboardViewModel.swift:getActiveSeason",
        "Views/Dashboard/DashboardViewModel.swift:getWarRoomConfig",
        "Views/Dashboard/DashboardViewModel.swift:getWarRoomTodayStatus",
        "Views/Dashboard/MorningRevealView.swift:fetchRecoveryData",
        "Views/EnergyRecovery/EnergyRecoveryView.swift:fetchEnergyDaily",
        "Views/EnergyRecovery/EnergyRecoveryView.swift:fetchEnergyHistory",
        "Views/EnergyRecovery/EnergyRecoveryView.swift:fetchHRVAnalysis",
        "Views/EnergyRecovery/EnergyRecoveryView.swift:fetchReadiness",
        "Views/EnergyRecovery/EnergyRecoveryView.swift:fetchReadinessHistory",
        "Views/EnergyRecovery/EnergyRecoveryView.swift:fetchRecoveryData",
        "Views/EnergyRecovery/EnergyRecoveryView.swift:fetchSleepHistory",
        "Views/EnergyRecovery/EnergyRecoveryView.swift:fetchSleepStats",
        "Views/GymFinder/GymFinderViewModel.swift:URLSession.authed",
        "Views/HIIT/HIITHistoriqueView.swift:fetchHIITData",
        "Views/Historique/HistoriqueView.swift:URLSession.authed",
        "Views/Intelligence/RitualEveningView.swift:fetchRitualToday",
        "Views/Intelligence/RitualView.swift:fetchRitualToday",
        "Views/Intelligence/WarRoomGateView.swift:getCurrentOath",
        "Views/Intelligence/WarRoomSettingsView.swift:getWarRoomConfig",
        "Views/Inventaire/InventaireView.swift:URLSession.authed",
        "Views/MentalHealth/MentalHealthDashboardView.swift:fetchMentalHealthSummary",
        "Views/MentalHealth/MentalHealthView.swift:checkMoodDue",
        "Views/MentalHealth/MentalHealthView.swift:fetchMentalHealthSummary",
        "Views/MentalHealth/MentalHealthView.swift:fetchMoodEmotions",
        "Views/MentalHealth/MoodTrackerView.swift:fetchMoodEmotions",
        "Views/MentalHealth/MoodTrackerView.swift:fetchMoodHistory",
        "Views/Oath/OathView.swift:getCurrentOath",
        "Views/Oath/OathView.swift:getOathVersions",
        "Views/PSS/PSSView.swift:checkPSSDue",
        "Views/PSS/PSSView.swift:fetchLifeStressTrend",
        "Views/PSS/PSSView.swift:fetchPSSHistory",
        "Views/PSS/PSSView.swift:fetchPSSQuestions",
        "Views/Profile/ProfileView.swift:fetchPSSHistory",
        "Views/Profile/ProfileView.swift:fetchProfileStats",
        "Views/Profile/ProfileView.swift:fetchWorkoutDNA",
        "Views/Profile/ProfileView.swift:getCurrentOath",
        "Views/Profile/ProfileView.swift:getWarRoomConfig",
        "Views/Profile/ProfileView.swift:getWarRoomSummary",
        "Views/Programme/ProgrammeViewModel.swift:fetchProgressionSuggestions",
        "Views/Recovery/RecoveryView.swift:fetchHRVAnalysis",
        "Views/Recovery/RecoveryView.swift:fetchReadiness",
        "Views/Recovery/RecoveryView.swift:fetchRecoveryData",
        "Views/Seance/BonusSeanceView.swift:URLSession.authed",
        "Views/Seance/ExerciseViewModel.swift:fetchSeanceData",
        "Views/Seance/SeanceSoirView.swift:URLSession.authed",
        "Views/Seance/SessionSupportViews.swift:fetchSeanceData",
        "Views/Seance/WorkoutActiveView.swift:URLSession.authed",
        "Views/Seance/WorkoutActiveView.swift:fetchExerciseWeightData",
        "Views/Seance/WorkoutActiveView.swift:fetchStatsData",
        "Views/Seasons/SeasonView.swift:getActiveSeason",
        "Views/Seasons/SeasonView.swift:getAllSeasons",
        "Views/XP/XPView.swift:fetchHIITData",
        "Views/XP/XPView.swift:fetchRecoveryData",
        "Views/XP/XPView.swift:fetchWeights",

        // Catches silencieux détectés par le filet durci (2026-11-01). À
        // migrer ou documenter cas par cas selon l'intention.
        "Views/Cardio/CardioView.swift:catch:log-only",
        "Views/Dashboard/DashboardViewModel.swift:catch:log-only",
        "Views/Recovery/RecoveryView.swift:catch:log-only",
        "Views/Onboarding/OnboardingView.swift:catch:empty",
    ]

    /// Catches background-side-effect-only : l'appel n'alimente aucune UI
    /// (pas d'@Published lu, pas de Loadable observé). Seul un side-effect
    /// (notif, UserDefaults) suit le succès. Un échec silencieux est
    /// acceptable — PAS de carte d'erreur, PAS de Loadable, logger uniquement.
    ///
    /// Convention : le catch doit commencer par `logger.error("fnName: …")`
    /// — le scanner extrait fnName de la chaîne et vérifie l'appartenance
    /// à ce set. Format : `Views/.../File.swift:fnName`.
    ///
    /// Chaque entrée documente SA raison (notifications uniquement, UserDefaults
    /// seul, etc.). Si tu ajoutes un site ici, écris pourquoi la UI n'a pas
    /// besoin de le remonter.
    private static let knownBackgroundSideEffects: Set<String> = [
        "Views/Dashboard/DashboardViewModel.swift:fetchWeeklyReport",
            // Raison : schedule du notif recap hebdo uniquement. Aucune @Published,
            // aucune carte dashboard ne lit la réponse. Un échec = pas de rappel
            // cette semaine, l'utilisateur reverra son résumé au prochain cycle.
        "Views/Dashboard/DashboardViewModel.swift:getActiveSeason",
            // Raison : scheduleSeasonMilestones (notif) uniquement. L'état saison
            // affiché vient d'ailleurs (SeasonView fetch dédié). Un échec = pas
            // de rappels de milestone cette session, retry au prochain app open.
        "Views/Dashboard/DashboardViewModel.swift:fetchWorkoutDNA",
            // Raison : notifyDNAArchetypeChange (notif) uniquement. L'enqueue
            // DNA evolution vit dans AppState.checkDNAEvolution (appel distinct).
            // Un échec = pas de notif changement d'archétype, non critique.
        "Views/Dashboard/DashboardViewModel.swift:fetchTimeCapsules",
            // Raison : scheduleTimeCapsuleSoon (notif) uniquement. Les capsules
            // sont consommées côté push notif seulement. Un échec = pas de
            // rappel capsule aujourd'hui, l'app ne dépend pas de l'état client.
    ]

    func test_noSilentAPIErrors_siteBased() throws {
        let all = try scanViews(root: Self.viewsRoot)
        let unknown = all.filter { !Self.knownSites.contains("\($0.file):\($0.function)") }
        if !unknown.isEmpty {
            let sorted = unknown.sorted { ($0.file, $0.line) < ($1.file, $1.line) }
            XCTFail(
                "NOUVEAU try? ou catch silencieux détecté dans Views/ :\n"
                + sorted.map { "  \($0.file):\($0.line): \($0.function)" }.joined(separator: "\n")
                + "\n\nSoit tu migres (Loadable pour lecture / do-catch MUTATION pour écriture), soit tu l'ajoutes à knownSites (dette tracée)."
            )
        }
    }

    // MARK: - Model

    private struct Violation { let file: String; let line: Int; let function: String }

    private static var viewsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TrainingOSTests/
            .deletingLastPathComponent()  // <repo>/
            .appendingPathComponent("Views")
    }

    // MARK: - Scanner

    private func scanViews(root: URL) throws -> [Violation] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil) else { return [] }

        var out: [Violation] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let rel = "Views/" + url.path.replacingOccurrences(of: root.path + "/", with: "")
            let content = try String(contentsOf: url, encoding: .utf8)
            out.append(contentsOf: findViolations(in: content, path: rel))
        }
        return out
    }

    private func findViolations(in content: String, path: String) -> [Violation] {
        var out: [Violation] = []
        let lines = content.components(separatedBy: "\n")

        let apiRe   = try? NSRegularExpression(pattern: #"try\s*\?\s*await\s+APIService\.shared\.(\w+)"#)
        let urlRe   = try? NSRegularExpression(pattern: #"try\s*\?\s*await\s+URLSession\.authed"#)
        let catchRe = try? NSRegularExpression(pattern: #"\bcatch\b[^{]*\{"#)

        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            let r  = NSRange(location: 0, length: ns.length)

            if let m = apiRe?.firstMatch(in: line, options: [], range: r),
               m.numberOfRanges > 1 {
                let fn = ns.substring(with: m.range(at: 1))
                out.append(.init(file: path, line: i + 1, function: fn))
            }
            if urlRe?.firstMatch(in: line, options: [], range: r) != nil {
                out.append(.init(file: path, line: i + 1, function: "URLSession.authed"))
            }
            if catchRe?.firstMatch(in: line, options: [], range: r) != nil,
               let kind = silentCatchKind(startLine: i, in: lines, path: path) {
                out.append(.init(file: path, line: i + 1, function: "catch:\(kind)"))
            }
        }
        return out
    }

    /// Classifie un catch : "empty", "log-only", "ignored" ou nil si non silencieux.
    /// Exclut les catches dont le pattern catch est intentionnellement silencieux
    /// par contrat (queuedOffline = mutation enfilée, CancellationError, URLError
    /// code .cancelled). Ces catches n'ont rien à signaler à l'utilisateur.
    ///
    /// Exclut aussi les catches "background side-effect" documentés dans
    /// `knownBackgroundSideEffects` : le catch log-only est acceptable car
    /// l'appel ne nourrit aucune UI (notifications uniquement).
    private func silentCatchKind(startLine: Int, in lines: [String], path: String) -> String? {
        let catchLine = lines[startLine]
        if catchLine.contains("queuedOffline") { return nil }
        if catchLine.contains("CancellationError") { return nil }
        if catchLine.contains(".cancelled") { return nil }

        let body = catchBody(startLine: startLine, in: lines)
        if body.isEmpty { return "empty" }
        if body.allSatisfy(isLoggerOnly) {
            if isDocumentedBackgroundSideEffect(body: body, path: path) { return nil }
            return "log-only"
        }
        if body.allSatisfy(isIgnoredAssign) { return "ignored" }
        return nil
    }

    /// Vrai si le catch log-only commence par `logger.error("fnName: …")` avec
    /// un `fnName` déclaré dans `knownBackgroundSideEffects` pour ce `path`.
    /// Le préfixe `fnName:` DOIT être présent dans le message de log pour que
    /// l'opt-out fonctionne — convention explicite, pas d'auto-magie.
    private func isDocumentedBackgroundSideEffect(body: [String], path: String) -> Bool {
        guard let first = body.first else { return false }
        let re = try? NSRegularExpression(pattern: #"[Ll]ogger\.error\(\s*"(\w+):"#)
        let ns = first as NSString
        guard let m = re?.firstMatch(in: first, options: [],
                                     range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return false }
        let fn = ns.substring(with: m.range(at: 1))
        return Self.knownBackgroundSideEffects.contains("\(path):\(fn)")
    }

    /// Récupère les lignes NON vides et NON commentaires du corps du catch
    /// en joignant depuis `startLine` et en matchant brace par brace depuis
    /// le `{` du catch (évite les faux positifs quand `} catch {` partagent
    /// la ligne avec le `}` fermant du `do {}`).
    private func catchBody(startLine: Int, in lines: [String]) -> [String] {
        let joined = lines.dropFirst(startLine).joined(separator: "\n")
        guard let openRange = joined.range(
            of: #"\bcatch\b[^{]*\{"#, options: .regularExpression) else { return [] }
        let afterOpen = joined[openRange.upperBound...]
        var depth = 1
        var body = ""
        for ch in afterOpen {
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            body.append(ch)
        }
        return body.split(separator: "\n", omittingEmptySubsequences: false).compactMap {
            let s = $0.trimmingCharacters(in: .whitespaces)
            return (s.isEmpty || s.hasPrefix("//")) ? nil : s
        }
    }

    private func isLoggerOnly(_ s: String) -> Bool {
        s.range(of: #"^[\w\.]*([Ll]ogger|os_log|print\s*\(|debugPrint|NSLog)"#,
                options: .regularExpression) != nil
    }

    private func isIgnoredAssign(_ s: String) -> Bool {
        s.hasPrefix("_ =") || s.hasPrefix("_=")
    }
}
