import XCTest
import SwiftUI
import UIKit
@testable import TrainingOS

@MainActor
final class MobilityChecklistVisualTests: XCTestCase {
    func testMixedAndChecklistOnlyFinishAndRecapElectricAndLight() async throws {
        let old = AppTheme.shared.selectedTheme
        defer { AppTheme.shared.applyTheme(old) }
        for theme in [AppThemeOption.electric, .electricLight] {
            AppTheme.shared.applyTheme(theme)
            for onlyMobility in [false, true] {
                let names = onlyMobility ? ["M1", "M2"] : ["Strength A", "Strength B", "M1", "M2"]
                let tracked = WorkoutCompletion.trackedNames(names, tracking: ["M1": "mobility", "M2": "mobility"])
                let logs = Dictionary(uniqueKeysWithValues: tracked.map { ($0, DayComposerFinishRig.log($0, source: .morning)) })
                let snapshot = SessionRecapSnapshot(sessionName: onlyMobility ? "Mobilité" : "Séance mixte",
                    coachingContext: .init(date: "2098-10-08", sessionType: "morning", sessionName: "Fixture"),
                    durationMin: 12, logResults: logs, exercises: tracked, rpe: onlyMobility ? 0 : 7,
                    comment: "", energyPre: 3, previousVolume: nil)
                let screens: [(String, AnyView)] = [
                    ("checklist", AnyView(VStack(spacing: 16) {
                        ExerciseCard(name: "M1", scheme: "Mobilité douce", weightData: nil,
                            trackingType: "mobility", logResult: .constant(nil),
                            isChecked: true, onCheckToggle: {}, sessionDate: "mobility-visual-fixture")
                        ExerciseCard(name: "M2", scheme: "Mobilité douce", weightData: nil,
                            trackingType: "mobility", logResult: .constant(nil),
                            isChecked: false, onCheckToggle: {}, sessionDate: "mobility-visual-fixture")
                    }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.appBg))),
                    ("finish", AnyView(FinishSessionSheet(exercises: tracked, logResults: logs, elapsedMin: 12,
                        rpe: .constant(7), comment: .constant(""), onSubmit: { _ in }))),
                    ("recap", AnyView(SessionRecapSheet(snapshot: snapshot, prs: [], trends: [:],
                        inventoryTracking: ["M1": "mobility", "M2": "mobility"], inventoryUnilateral: [:], exerciseMuscleMetadata: [:])))
                ]
                for (name, screen) in screens {
                    let host = UIHostingController(rootView: screen.environment(\.colorScheme, theme == .electricLight ? .light : .dark))
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1100))
                    window.rootViewController = host; window.makeKeyAndVisible()
                    defer { window.isHidden = true; window.rootViewController = nil }
                    host.view.layoutIfNeeded()
                    try await Task.sleep(nanoseconds: 700_000_000)
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                        host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent("mobility-\(theme.rawValue)-\(onlyMobility)-\(name).png")
                    try XCTUnwrap(image.pngData()).write(to: file)
                    print("MOBILITY_VISUAL \(file.path)")
                }
            }
        }
    }
}
