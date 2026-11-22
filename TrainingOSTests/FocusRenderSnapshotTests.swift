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
        try await shot("1-ouverture")
        let main = try XCTUnwrap(scrollViews(window).filter { $0.contentSize.height > $0.bounds.height }
            .max { $0.contentSize.height < $1.contentSize.height })
        main.setContentOffset(CGPoint(x: 0, y: -main.adjustedContentInset.top), animated: false)
        try await shot("2-haut")
        let bottom = main.contentSize.height - main.bounds.height + main.adjustedContentInset.bottom
        main.setContentOffset(CGPoint(x: 0, y: max(0, bottom)), animated: false)
        try await shot("3-bas")
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
            let data = try APIService.decoder.decode(SeanceData.self, from: JSONSerialization.data(withJSONObject: json))
            if theme == .blood {                                         // état « saisi » (après un +) sur un thème
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
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let file = "\(tag)-ecran-\(theme.rawValue).png"
            let attachment = XCTAttachment(image: image); attachment.name = file
            attachment.lifetime = .keepAlways; add(attachment)
            if let dir, let png = image.pngData() {
                try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
            }
            window.isHidden = true; window.rootViewController = nil
        }
    }
}
