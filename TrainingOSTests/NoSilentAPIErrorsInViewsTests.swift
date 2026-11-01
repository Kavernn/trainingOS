import XCTest

/// Garde-fou de migration : interdit les erreurs d'appels API silencieuses
/// dans Views/. Vérifie uniquement les écrans migrés (hors allowlist). Un
/// écran est "migré" quand il adopte Loadable (ou équivalent) à la place
/// de `try? await APIService.*`, `try? await URLSession.authed.*`, ou
/// d'un `catch` qui ne fait que logger un appel API.
///
/// Workflow : quand on migre un écran, on retire son dossier de l'allowlist.
/// Si le test tombe, soit on complète la migration, soit on remet l'allowlist.
final class NoSilentAPIErrorsInViewsTests: XCTestCase {

    /// Dossiers Views/* exemptés du scan. État au 2026-11-01 : seul Stats
    /// est migré (Build B 14 commits + 3f.5), tout le reste est en dette.
    private let allowlist: Set<String> = [
        "BodyComp", "Budget", "Cardio", "Components", "Dashboard",
        "EnergyRecovery", "GymFinder", "HealthDashboard", "HIIT",
        "Historique", "Intelligence", "Inventaire", "MentalHealth", "More",
        "Notes", "Nutrition", "Oath", "Onboarding", "Profile", "Programme",
        "PSS", "Recovery", "Seance", "Seasons", "Settings", "Shared",
        "Timer", "XP",
    ]

    /// Fichiers Swift directement sous Views/ (hors sous-dossier) :
    /// également allowlistés initialement.
    private let allowlistTopLevelFiles: Set<String> = [
        "SplashView.swift", "VoiceDictationButton.swift",
    ]

    func test_noSilentAPIErrorsInMigratedViews() throws {
        let viewsRoot = Self.viewsRoot
        let violations = try scanViews(root: viewsRoot)
        if !violations.isEmpty {
            XCTFail(
                "Appels API silencieux dans un écran migré :\n"
                + violations.map { "  \($0)" }.joined(separator: "\n")
                + "\n\nMigre vers Loadable / do-catch avec surface utilisateur, ou remets le dossier dans allowlist."
            )
        }
    }

    // MARK: - Scanner

    private static var viewsRoot: URL {
        // #filePath = <repo>/TrainingOSTests/NoSilentAPIErrorsInViewsTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TrainingOSTests/
            .deletingLastPathComponent()  // <repo>/
            .appendingPathComponent("Views")
    }

    private func scanViews(root: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil) else { return [] }

        var out: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }

            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let firstComp = rel.components(separatedBy: "/").first ?? ""

            // Allowlist : composant racine OU fichier top-level
            if allowlist.contains(firstComp) { continue }
            if !rel.contains("/") && allowlistTopLevelFiles.contains(firstComp) { continue }

            let content = try String(contentsOf: url, encoding: .utf8)
            out.append(contentsOf: findViolations(in: content, path: "Views/" + rel))
        }
        return out.sorted()
    }

    /// Détecte 3 patterns suspects :
    /// 1. `try? await APIService...`
    /// 2. `try? await URLSession.authed...`
    /// 3. `catch { ... }` dont le corps ne contient que des appels logger
    ///    (Logger, logger., os_log, print, NSLog) et rien d'autre.
    private func findViolations(in content: String, path: String) -> [String] {
        var out: [String] = []
        let lines = content.components(separatedBy: "\n")

        let try1 = try? NSRegularExpression(pattern: #"try\s*\?\s*await\s+APIService"#)
        let try2 = try? NSRegularExpression(pattern: #"try\s*\?\s*await\s+URLSession\.authed"#)
        let catchRe = try? NSRegularExpression(pattern: #"\bcatch\b[^{]*\{"#)
        let loggerLine = try? NSRegularExpression(
            pattern: #"[Ll]ogger|os_log|print\s*\(|debugPrint|NSLog|statsHistoryLogger"#)

        for (i, line) in lines.enumerated() {
            let r = NSRange(line.startIndex..., in: line)
            if try1?.firstMatch(in: line, range: r) != nil {
                out.append("\(path):\(i+1): try? await APIService")
            }
            if try2?.firstMatch(in: line, range: r) != nil {
                out.append("\(path):\(i+1): try? await URLSession.authed")
            }
            if catchRe?.firstMatch(in: line, range: r) != nil {
                if let flagged = catchOnlyLogsStart(at: i, in: lines, loggerRe: loggerLine) {
                    out.append("\(path):\(i+1): catch { log-only }  → body L\(flagged)")
                }
            }
        }
        return out
    }

    /// À partir de l'index du `catch { ... }`, lit le corps en comptant
    /// les accolades. Retourne la ligne finale si TOUTES les lignes de
    /// code non-vides du corps matchent `loggerRe`. nil sinon.
    private func catchOnlyLogsStart(
        at startLine: Int,
        in lines: [String],
        loggerRe: NSRegularExpression?
    ) -> Int? {
        guard let loggerRe else { return nil }

        var depth = 1
        var j = startLine
        let catchLine = lines[startLine]
        depth += catchLine.filter { $0 == "{" }.count - 1  // on en a déjà compté 1 pour catch {
        depth -= catchLine.filter { $0 == "}" }.count

        var bodyLines: [(idx: Int, text: String)] = []
        j += 1
        while j < lines.count, depth > 0 {
            let l = lines[j]
            depth += l.filter { $0 == "{" }.count
            depth -= l.filter { $0 == "}" }.count
            if depth > 0 { bodyLines.append((j, l)) }
            j += 1
        }

        let codeLines = bodyLines.filter {
            let s = $0.text.trimmingCharacters(in: .whitespaces)
            return !s.isEmpty && !s.hasPrefix("//")
        }
        guard !codeLines.isEmpty else { return nil }

        let allLogger = codeLines.allSatisfy {
            loggerRe.firstMatch(in: $0.text,
                                range: NSRange($0.text.startIndex..., in: $0.text)) != nil
        }
        return allLogger ? (codeLines.last!.idx + 1) : nil
    }
}
