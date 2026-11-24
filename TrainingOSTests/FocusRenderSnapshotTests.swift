import XCTest
import SwiftUI
import UIKit
@testable import TrainingOS

/// Captures de la carte Focus (lecture seule) pour validation visuelle : aucune assertion de pixels.
/// PNG écrits dans FOCUS_SNAPSHOT_DIR (si défini) et joints au résultat de test.
@MainActor
final class FocusRenderSnapshotTests: XCTestCase {

    func testRenderFocusEffortAcrossThemesAndRepRanges() async throws {
        let date = "focus-shot-\(UUID().uuidString)"
        let previous = AppTheme.shared.selectedTheme
        defer {
            AppTheme.shared.applyTheme(previous)
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let dir = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_DIR"]
        let tag = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_TAG"] ?? "shot"
        for theme in [AppThemeOption.sinCity, .pearl, .oledBlack, .blood] {
            AppTheme.shared.applyTheme(theme)
            for scheme in ["3x6-10", "3x10-12"] {
                let name = "T-Bar Row \(scheme)"
                do {
                    let editor = ExerciseViewModel(name: name, scheme: scheme, weightData: nil, sessionDate: date)
                    editor.initializeSets()
                    editor.sets[0].weight = "85"
                    XCTAssertEqual(editor.saveDraft(), .accepted)
                }
                var log: ExerciseLogResult? = nil
                let card = ExerciseCard(name: name, scheme: scheme, weightData: nil,
                                        logResult: Binding(get: { log }, set: { log = $0 }),
                                        isExpanded: true, sessionDate: date, presentation: .focus)
                let host = UIHostingController(rootView: ScrollView { card }.background(Color.appBg))
                host.overrideUserInterfaceStyle = theme == .pearl ? .light : .dark
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
                window.rootViewController = host; window.makeKeyAndVisible()
                for _ in 0..<3 { host.view.layoutIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000) }
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let file = "\(tag)-\(theme.rawValue)-\(scheme).png"
                let attachment = XCTAttachment(image: image); attachment.name = file
                attachment.lifetime = .keepAlways; add(attachment)
                if let dir, let png = image.pngData() {
                    try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
                }
                window.isHidden = true; window.rootViewController = nil
            }
        }
    }

    /// Séance réelle : 1er exercice loggé, Deadhang (chronométré) courant, Focus demandé → repli liste.
    /// Captures en haut de liste, après auto-défilement, et tout en bas (accès au bouton principal).
    func testRenderDeadhangFallbackAndListBottom() async throws {
        let date = "focus-shot-\(UUID().uuidString)"
        let flagBefore = UserDefaults.standard.object(forKey: FocusModePreference.key)
        defer {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            if let flagBefore { UserDefaults.standard.set(flagBefore, forKey: FocusModePreference.key) }
            else { UserDefaults.standard.removeObject(forKey: FocusModePreference.key) }
        }
        UserDefaults.standard.set(true, forKey: FocusModePreference.key)
        let dir = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_DIR"]
        let tag = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_TAG"] ?? "shot"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:
            Fixtures.seanceDataJSON(today: "Pull B", todayDate: date, exerciseName: "T-Bar Row")) as? [String: Any])
        json["full_program"] = ["Pull B": ["T-Bar Row": "3x6-10", "Deadhang": "3x8-12"]]
        json["inventory_tracking"] = ["Deadhang": "time"]
        let data = try APIService.decoder.decode(SeanceData.self, from: JSONSerialization.data(withJSONObject: json))
        let owner = SeanceViewModel(draftSessionType: "morning", followsActivePlanning: true)
        owner.seanceData = data
        owner.startSession()
        owner.logResults["T-Bar Row"] = ExerciseLogResult(name: "T-Bar Row", weight: 85, reps: "10,10,10")
        owner.currentPlanningLoader = { _, _ in ("stale", data) }
        let root = TabView {
            NavigationStack { WorkoutSeanceView(data: data, vm: owner, isOverride: true) }
                .tabItem { Label("Séance", systemImage: "dumbbell.fill") }
            Text("Programme").tabItem { Label("Programme", systemImage: "list.bullet.clipboard") }
        }
        let host = UIHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func shot(_ label: String) async throws {
            for _ in 0..<4 { host.view.layoutIfNeeded(); try await Task.sleep(nanoseconds: 200_000_000) }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let file = "\(tag)-deadhang-\(label).png"
            let attachment = XCTAttachment(image: image); attachment.name = file
            attachment.lifetime = .keepAlways; add(attachment)
            if let dir, let png = image.pngData() {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
            }
        }
        func scrollViews(_ v: UIView) -> [UIScrollView] {
            (v as? UIScrollView).map { [$0] } ?? [] + v.subviews.flatMap(scrollViews)
        }
        // Attente sur condition (délai max 5 s), jamais une durée fixe : la carte courante
        // (Deadhang) s'ouvre au montage ; le contenu doit alors dépasser l'écran.
        func scrollable() -> UIScrollView? {
            scrollViews(window).filter { $0.contentSize.height > $0.bounds.height }
                .max { $0.contentSize.height < $1.contentSize.height }
        }
        let deadline = Date().addingTimeInterval(5)
        while scrollable() == nil, Date() < deadline {
            host.view.layoutIfNeeded(); try await Task.sleep(nanoseconds: 100_000_000)
        }
        try await shot("1-ouverture")
        let main = try XCTUnwrap(scrollable())
        main.setContentOffset(CGPoint(x: 0, y: -main.adjustedContentInset.top), animated: false)
        try await shot("2-haut")
        let bottom = main.contentSize.height - main.bounds.height + main.adjustedContentInset.bottom
        main.setContentOffset(CGPoint(x: 0, y: max(0, bottom)), animated: false)
        try await shot("3-bas")
    }

    /// 4.4d : superset en Focus, 2 thèmes — B après A S1 (chrome « ⇄ », undo croisé), puis A après B S1
    /// (repos de B affiché pendant que Focus revient sur A).
    func testRenderSupersetPairAcrossTwoThemes() async throws {
        let flagBefore = UserDefaults.standard.object(forKey: FocusModePreference.key)
        let restBefore = UserDefaults.standard.object(forKey: AutoRestPreference.key)
        let previous = AppTheme.shared.selectedTheme
        var dates: [String] = []
        defer {
            RestTimerManager.shared.dismiss()
            AppTheme.shared.applyTheme(previous)
            for key in UserDefaults.standard.dictionaryRepresentation().keys where dates.contains(where: key.contains) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            if let flagBefore { UserDefaults.standard.set(flagBefore, forKey: FocusModePreference.key) }
            else { UserDefaults.standard.removeObject(forKey: FocusModePreference.key) }
            if let restBefore { UserDefaults.standard.set(restBefore, forKey: AutoRestPreference.key) }
            else { UserDefaults.standard.removeObject(forKey: AutoRestPreference.key) }
        }
        UserDefaults.standard.set(true, forKey: FocusModePreference.key)
        UserDefaults.standard.set(true, forKey: AutoRestPreference.key)
        let dir = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_DIR"]
        let tag = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_TAG"] ?? "shot"
        for theme in [AppThemeOption.sinCity, .pearl] {
            AppTheme.shared.applyTheme(theme)
            RestTimerManager.shared.dismiss()
            let date = "focus-shot-\(UUID().uuidString)"; dates.append(date)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.seanceDataJSON(
                today: "Push", todayDate: date, exerciseName: "Bench Press",
                historyDate: "2026-11-15", historyWeight: 135, historyReps: "8,8,8")) as? [String: Any])
            json["full_program"] = ["Push": ["Bench Press": "3x8-10", "Dips": "4x8-10"]]
            json["exercise_order"] = ["Push": ["Bench Press", "Dips"]]
            json["exercise_supersets"] = ["Push": ["Bench Press": ["A": "Bench Press", "B": "Dips", "rest": 90]]]
            var weights = try XCTUnwrap(json["weights"] as? [String: Any])
            weights["Dips"] = ["current_weight": 25, "last_reps": "10,10,10,10", "last_logged": "2026-11-15",
                               "history": [["date": "2026-11-15", "weight": 25, "reps": "10,10,10,10"]]]
            json["weights"] = weights
            let data = try APIService.decoder.decode(SeanceData.self, from: JSONSerialization.data(withJSONObject: json))
            let owner = SeanceViewModel(draftSessionType: "morning", followsActivePlanning: true)
            owner.seanceData = data
            owner.startSession()
            owner.currentPlanningLoader = { _, _ in ("stale", data) }
            let root = TabView {
                NavigationStack { WorkoutSeanceView(data: data, vm: owner, isOverride: true) }
                    .tabItem { Label("Séance", systemImage: "dumbbell.fill") }
            }
            let host = UIHostingController(rootView: root)
            host.overrideUserInterfaceStyle = theme == .pearl ? .light : .dark
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            func settle() async throws { for _ in 0..<5 { host.view.layoutIfNeeded(); try await Task.sleep(nanoseconds: 200_000_000) } }
            func shot(_ label: String) {
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let file = "\(tag)-paire-\(label)-\(theme.rawValue).png"
                let attachment = XCTAttachment(image: image); attachment.name = file
                attachment.lifetime = .keepAlways; add(attachment)
                if let dir, let png = image.pngData() {
                    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
                }
            }
            try await settle()
            shot("1-A")
            NotificationCenter.default.post(name: FocusSwitch.debugFocusPrimaryAction, object: nil)   // A S1 → B
            try await Task.sleep(nanoseconds: 900_000_000); try await settle()
            shot("2-B-undo-croise")
            NotificationCenter.default.post(name: FocusSwitch.debugFocusPrimaryAction, object: nil)   // B S1 → A + repos
            try await Task.sleep(nanoseconds: 900_000_000); try await settle()
            shot("3-A-repos-de-B")
            window.isHidden = true; window.rootViewController = nil
        }
    }

    /// units.format (2 décimales, affiché = enregistré) : mises en page étroites de la liste en kg avec 61.25 —
    /// carte loggée repliée (puce d'en-tête), carte dépliée (dernière charge, historique).
    func testRenderListNarrowLayoutsWithTwoDecimalLoad() async throws {
        let date = "focus-shot-\(UUID().uuidString)"
        let flagBefore = UserDefaults.standard.object(forKey: FocusModePreference.key)
        let kgBefore = UnitSettings.shared.isKg
        let previous = AppTheme.shared.selectedTheme
        defer {
            UnitSettings.shared.isKg = kgBefore
            AppTheme.shared.applyTheme(previous)
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(date) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            if let flagBefore { UserDefaults.standard.set(flagBefore, forKey: FocusModePreference.key) }
            else { UserDefaults.standard.removeObject(forKey: FocusModePreference.key) }
        }
        UserDefaults.standard.set(false, forKey: FocusModePreference.key)
        UnitSettings.shared.isKg = true
        let lbs = 61.25 / 0.453592
        XCTAssertEqual(UnitSettings.shared.format(lbs), "61.25 kg")
        XCTAssertEqual(UnitSettings.shared.format(60 / 0.453592), "60 kg")
        XCTAssertEqual(UnitSettings.shared.format(62.5 / 0.453592), "62.5 kg")
        XCTAssertEqual(UnitSettings.shared.format(lbs, decimals: 0), "61 kg", "arrondi explicite inchangé")
        let dir = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_DIR"]
        let tag = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_TAG"] ?? "shot"
        for theme in [AppThemeOption.sinCity, .pearl] {
            AppTheme.shared.applyTheme(theme)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.seanceDataJSON(
                today: "Push", todayDate: date, exerciseName: "Incline Dumbbell Press",
                historyDate: "2026-11-15", historyWeight: lbs, historyReps: "10,9,8")) as? [String: Any])
            json["full_program"] = ["Push": ["Barbell Bench Press": "3x8-10", "Incline Dumbbell Press": "3x8-10"]]
            json["exercise_order"] = ["Push": ["Barbell Bench Press", "Incline Dumbbell Press"]]
            let data = try APIService.decoder.decode(SeanceData.self, from: JSONSerialization.data(withJSONObject: json))
            let owner = SeanceViewModel(draftSessionType: "morning", followsActivePlanning: true)
            owner.seanceData = data
            owner.startSession()
            owner.logResults["Barbell Bench Press"] = ExerciseLogResult(name: "Barbell Bench Press", weight: lbs, reps: "10,10,9")
            owner.currentPlanningLoader = { _, _ in ("stale", data) }
            let root = TabView {
                NavigationStack { WorkoutSeanceView(data: data, vm: owner, isOverride: true) }
                    .tabItem { Label("Séance", systemImage: "dumbbell.fill") }
            }
            let host = UIHostingController(rootView: root)
            host.overrideUserInterfaceStyle = theme == .pearl ? .light : .dark
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            for _ in 0..<6 { host.view.layoutIfNeeded(); try await Task.sleep(nanoseconds: 200_000_000) }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let file = "\(tag)-liste-61.25kg-\(theme.rawValue).png"
            let attachment = XCTAttachment(image: image); attachment.name = file
            attachment.lifetime = .keepAlways; add(attachment)
            if let dir, let png = image.pngData() {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
            }
            window.isHidden = true; window.rootViewController = nil
        }
    }

    /// 4.4a : écran Focus complet (chrome, chiffres proposés en pointillé, « Série terminée » en bas), 4 thèmes.
    func testRenderFocusScreenWithCompleteButton() async throws {
        let flagBefore = UserDefaults.standard.object(forKey: FocusModePreference.key)
        let previous = AppTheme.shared.selectedTheme
        var dates: [String] = []
        defer {
            AppTheme.shared.applyTheme(previous)
            for key in UserDefaults.standard.dictionaryRepresentation().keys where dates.contains(where: key.contains) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            if let flagBefore { UserDefaults.standard.set(flagBefore, forKey: FocusModePreference.key) }
            else { UserDefaults.standard.removeObject(forKey: FocusModePreference.key) }
        }
        UserDefaults.standard.set(true, forKey: FocusModePreference.key)
        let dir = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_DIR"]
        let tag = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_TAG"] ?? "shot"
        for theme in [AppThemeOption.sinCity, .pearl, .oledBlack, .blood] {
            AppTheme.shared.applyTheme(theme)
            let date = "focus-shot-\(UUID().uuidString)"; dates.append(date)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.seanceDataJSON(
                today: "Pull B", todayDate: date, exerciseName: "T-Bar Row",
                historyDate: "2026-11-15", historyWeight: 85, historyReps: "10,9,8")) as? [String: Any])
            json["full_program"] = ["Pull B": ["T-Bar Row": "3x10-12"]]
            let transition = ProcessInfo.processInfo.environment["FOCUS_SNAPSHOT_TRANSITION"] == "1"
            if transition { json["full_program"] = ["Pull B": ["T-Bar Row": "2x10-12", "Upright Row": "3x10"]] }
            let data = try APIService.decoder.decode(SeanceData.self, from: JSONSerialization.data(withJSONObject: json))
            if theme == .blood && !transition {                          // état « saisi » (après un +) sur un thème
                let editor = ExerciseViewModel(name: "T-Bar Row", scheme: "3x10-12", weightData: nil, sessionDate: date)
                editor.initializeSets()
                editor.sets[0].weight = "90"; editor.sets[0].reps = "11"
                XCTAssertEqual(editor.saveDraft(), .accepted)
            }
            let owner = SeanceViewModel(draftSessionType: "morning", followsActivePlanning: true)
            owner.seanceData = data
            owner.startSession()
            owner.currentPlanningLoader = { _, _ in ("stale", data) }
            let root = TabView {
                NavigationStack { WorkoutSeanceView(data: data, vm: owner, isOverride: true) }
                    .tabItem { Label("Séance", systemImage: "dumbbell.fill") }
            }
            let host = UIHostingController(rootView: root)
            host.overrideUserInterfaceStyle = theme == .pearl ? .light : .dark
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            window.rootViewController = host; window.makeKeyAndVisible()
            for _ in 0..<5 { host.view.layoutIfNeeded(); try await Task.sleep(nanoseconds: 200_000_000) }
            if transition {                                              // S1, S2 → doLog → Transition
                for _ in 0..<2 {
                    NotificationCenter.default.post(name: FocusSwitch.debugFocusPrimaryAction, object: nil)
                    try await Task.sleep(nanoseconds: 900_000_000)
                }
                for _ in 0..<5 { host.view.layoutIfNeeded(); try await Task.sleep(nanoseconds: 200_000_000) }
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let file = "\(tag)-\(transition ? "transition" : "ecran")-\(theme.rawValue).png"
            let attachment = XCTAttachment(image: image); attachment.name = file
            attachment.lifetime = .keepAlways; add(attachment)
            if let dir, let png = image.pngData() {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
            }
            window.isHidden = true; window.rootViewController = nil
        }
    }
}
