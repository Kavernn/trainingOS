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
        "Views/GymFinder/GymFinderViewModel.swift:URLSession.authed",
        "Views/HIIT/HIITHistoriqueView.swift:fetchHIITData",
        "Views/Historique/HistoriqueView.swift:URLSession.authed",
        "Views/Intelligence/RitualEveningView.swift:fetchRitualToday",
        "Views/Intelligence/RitualView.swift:fetchRitualToday",
        "Views/Intelligence/WarRoomGateView.swift:getCurrentOath",
        "Views/Intelligence/WarRoomSettingsView.swift:getWarRoomConfig",
        "Views/Inventaire/InventaireView.swift:URLSession.authed",
        // à migrer avec l'écran Nutrition, après le commit du WIP de Vince
        "Views/Nutrition/NutritionView.swift:fetchEnergyDaily",
        // à migrer avec l'écran Nutrition, après le commit du WIP de Vince
        "Views/Nutrition/NutritionViewModel.swift:URLSession.authed",
        "Views/Oath/OathView.swift:getCurrentOath",
        "Views/Oath/OathView.swift:getOathVersions",
        "Views/Profile/ProfileView.swift:fetchPSSHistory",
        "Views/Profile/ProfileView.swift:fetchProfileStats",
        "Views/Profile/ProfileView.swift:fetchWorkoutDNA",
        "Views/Profile/ProfileView.swift:getCurrentOath",
        "Views/Profile/ProfileView.swift:getWarRoomConfig",
        "Views/Profile/ProfileView.swift:getWarRoomSummary",
        "Views/Programme/ProgrammeViewModel.swift:fetchProgressionSuggestions",
        "Views/Seance/BonusSeanceView.swift:URLSession.authed",
        "Views/Seance/SeanceSoirView.swift:URLSession.authed",
        "Views/Seance/SessionSupportViews.swift:fetchSeanceData",
        "Views/Seasons/SeasonView.swift:getActiveSeason",
        "Views/Seasons/SeasonView.swift:getAllSeasons",
        "Views/XP/XPView.swift:fetchHIITData",
        "Views/XP/XPView.swift:fetchRecoveryData",
        "Views/XP/XPView.swift:fetchWeights",

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
        "Views/Seance/WorkoutActiveView.swift:loadReadiness",
            // Raison : alimente uniquement le ReadinessChip optionnel du
            // contextPanel. Affichage dégradé (pas de chip) acceptable sur
            // échec — l'utilisateur continue sa séance LIVE sans ce signal.
        "Views/Seance/ExerciseViewModel.swift:verifyFinishCompletion",
            // Raison : verif conservative post-save. Échec = "non vérifié" →
            // le caller (saveSession) set `submitError` "Séance non confirmée
            // en base — réessaie", surfaced au user. Pas de nouvelle UI.
        "Views/Seance/ExerciseViewModel.swift:finish",
            // Raison : verif morning completion dans finish(). Échec = fresh
            // nil → `verified` false → même submitError visible. Idem.
        "Views/Seance/WorkoutActiveView.swift:retryWeightFetch",
            // Raison : catch du bouton "Réessayer" dans weightFetchFailedRow /
            // estimatedWeightRow. Déclenché par le user après avoir déjà vu
            // l'erreur initiale — un nouvel échec laisse la row visible, user
            // peut re-cliquer. Pas de nouvelle surface UI à ajouter.
        "Views/Stats/StatsView.swift:syncDeloadFlag",
            // Raison : UserDefaults "deload_active" + cancelDeloadNotifications
            // (notif) uniquement. L'affichage du deload passe par
            // fetchDeloadStatus (Loadable DeloadStatus). Un échec = flag non
            // resynchronisé et notifs non-cancelled sur transition, retry au
            // prochain app open.
    ]

    /// Prouve que le scanner est invariant aux symlinks dans le chemin racine.
    /// Avant la normalisation : scanner `/tmp/root` (symlink de `/private/tmp/root`)
    /// produisait des `rel` du type `Views/private/tmp/root/File.swift` au lieu
    /// de `Views/File.swift` — le match contre `knownSites` échouait silencieusement.
    func test_scan_isSymlinkInvariant() throws {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NoSilentAPIErrors-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let real = tmp.appendingPathComponent("real", isDirectory: true)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        let swiftFile = real.appendingPathComponent("Fake.swift")
        try #"_ = try? await APIService.shared.fetchFakeFoo()"#
            .write(to: swiftFile, atomically: true, encoding: .utf8)

        let link = tmp.appendingPathComponent("link", isDirectory: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let viaReal = try scanViews(root: real)
        let viaLink = try scanViews(root: link)

        XCTAssertEqual(viaReal.count, 1)
        XCTAssertEqual(viaLink.count, 1)
        XCTAssertEqual(viaReal.map { "\($0.file):\($0.function)" },
                       viaLink.map { "\($0.file):\($0.function)" })
    }

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
        // Normalise les deux côtés avant de calculer le chemin relatif : sans
        // ça, un repo sous /tmp (symlink de /private/tmp) produit `url.path`
        // résolu et `root.path` non résolu — le `replacingOccurrences` échoue
        // silencieusement et `rel` devient `Views/private/tmp/.../File.swift`,
        // ce qui fait rater le match dans `knownSites`.
        let normRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: normRoot, includingPropertiesForKeys: nil) else { return [] }

        var out: [Violation] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let normURL = url.resolvingSymlinksInPath().standardizedFileURL
            let rel = "Views/" + normURL.path.replacingOccurrences(of: normRoot.path + "/", with: "")
            let content = try String(contentsOf: normURL, encoding: .utf8)
            out.append(contentsOf: findViolations(in: content, path: rel))
        }
        return out
    }

    private func findViolations(in content: String, path: String) -> [Violation] {
        var out: [Violation] = []
        let lines = content.components(separatedBy: "\n")

        // Pré-passe : construit la map `taskName -> fnName` pour attraper les
        // `try? await <taskName>` dont la tâche source (async let / Task) appelle
        // APIService.shared ou URLSession.authed. Sans ça, le pattern
        // `async let weekTask = APIService.shared.fetchWeeklyHealthSummary(...)`
        // + `try? await weekTask` passe entre les mailles (HealthDashboardView).
        let bindings = taskBindings(in: content)

        let apiRe       = try? NSRegularExpression(pattern: #"try\s*\?\s*await\s+APIService\.shared\.(\w+)"#)
        let urlRe       = try? NSRegularExpression(pattern: #"try\s*\?\s*await\s+URLSession\.authed"#)
        let taskAwaitRe = try? NSRegularExpression(pattern: #"try\s*\?\s*await\s+(\w+)"#)
        let catchRe     = try? NSRegularExpression(pattern: #"\bcatch\b[^{]*\{"#)

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
            // `try? await <identifier>` où identifier est une tâche connue :
            // on émet avec le nom de la fn de l'initialiseur. On exclut les
            // identifiers déjà couverts par apiRe (APIService) / urlRe (URLSession)
            // pour éviter le double count sur `try? await APIService.shared.fn()`.
            if let m = taskAwaitRe?.firstMatch(in: line, options: [], range: r),
               m.numberOfRanges > 1 {
                let name = ns.substring(with: m.range(at: 1))
                if name != "APIService", name != "URLSession",
                   let fn = bindings[name] {
                    out.append(.init(file: path, line: i + 1, function: fn))
                }
            }
            if catchRe?.firstMatch(in: line, options: [], range: r) != nil,
               let kind = silentCatchKind(startLine: i, in: lines, path: path) {
                out.append(.init(file: path, line: i + 1, function: "catch:\(kind)"))
            }
        }
        return out
    }

    /// Map `taskName -> fnName` pour les tâches dont l'initialiseur appelle
    /// APIService.shared.<fn> ou URLSession.authed. Couvre deux patterns :
    ///   1. `async let xxx = APIService.shared.fn(...)`
    ///   2. `let xxx = Task { ... APIService.shared.fn(...) ... }`
    /// Approche fichier-plat (pas de résolution par scope). Risque de
    /// collision si deux fonctions du même fichier redéfinissent le même
    /// nom avec une tâche différente — jamais vu en pratique, les noms de
    /// tâche sont très spécifiques (`weekTask`, `pssDueTask`).
    private func taskBindings(in content: String) -> [String: String] {
        var map: [String: String] = [:]

        let lines = content.components(separatedBy: "\n")
        let asyncApi = try? NSRegularExpression(pattern: #"async\s+let\s+(\w+)\s*=.*APIService\.shared\.(\w+)"#)
        let asyncUrl = try? NSRegularExpression(pattern: #"async\s+let\s+(\w+)\s*=.*URLSession\.authed"#)
        for line in lines {
            let ns = line as NSString
            let r = NSRange(location: 0, length: ns.length)
            if let m = asyncApi?.firstMatch(in: line, options: [], range: r), m.numberOfRanges > 2 {
                map[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
            } else if let m = asyncUrl?.firstMatch(in: line, options: [], range: r), m.numberOfRanges > 1 {
                map[ns.substring(with: m.range(at: 1))] = "URLSession.authed"
            }
        }

        // `let x = Task { ... }` : brace-match pour isoler le corps, puis
        // chercher APIService.shared.<fn> ou URLSession.authed dedans.
        let ns = content as NSString
        let taskOpen = try? NSRegularExpression(pattern: #"let\s+(\w+)\s*=\s*Task\s*\{"#)
        let fnInBody = try? NSRegularExpression(pattern: #"APIService\.shared\.(\w+)"#)
        taskOpen?.enumerateMatches(in: content, options: [],
                                   range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m, m.numberOfRanges > 1 else { return }
            let name = ns.substring(with: m.range(at: 1))
            var depth = 1
            var i = m.range.location + m.range.length
            while i < ns.length && depth > 0 {
                let ch = ns.character(at: i)
                if ch == 0x7B { depth += 1 }       // {
                else if ch == 0x7D { depth -= 1 }  // }
                i += 1
            }
            let bodyRange = NSRange(location: m.range.location + m.range.length,
                                    length: i - (m.range.location + m.range.length))
            let body = ns.substring(with: bodyRange)
            let bNS = body as NSString
            let bR = NSRange(location: 0, length: bNS.length)
            if let mm = fnInBody?.firstMatch(in: body, options: [], range: bR), mm.numberOfRanges > 1 {
                map[name] = bNS.substring(with: mm.range(at: 1))
            } else if body.contains("URLSession.authed") {
                map[name] = "URLSession.authed"
            }
        }

        return map
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
