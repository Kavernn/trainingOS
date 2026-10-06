import XCTest
import SwiftUI
import UIKit
@testable import TrainingOS

@MainActor
final class LandmineTests: XCTestCase {
    func testCalculationAndInverse() {
        XCTAssertEqual(ExerciseCalculator.totalWeight(for: 35, equipmentType: "barbell"), 115)
        XCTAssertEqual(ExerciseCalculator.totalWeight(for: 35, equipmentType: "landmine"), 80)
        for (bar, end, total) in [(45.0, 0.0, 45.0), (45,25,70), (45,70,115), (35,90,125), (35,45,80), (20,30,50)] {
            XCTAssertEqual(ExerciseCalculator.totalWeight(for: end, equipmentType: "landmine", barWeight: bar), total)
            XCTAssertEqual(ExerciseCalculator.inputHint(currentWeight: total, equipmentType: "landmine", barWeight: bar), end)
        }
        XCTAssertEqual(ExerciseCalculator.inputHint(currentWeight: 120, equipmentType: "landmine"), 75)
        XCTAssertEqual(ExerciseCalculator.inputHint(currentWeight: 10, equipmentType: "landmine"), 0)
        XCTAssertEqual(weightTypeToLegacy("landmine"), "landmine")
        XCTAssertEqual(weightTypeToLegacy("barbell"), "barbell")
    }

    func testDraftLogPayloadVolumeRecoveryAllSourcesAndUnits() throws {
        let units = UnitSettings.shared
        let previous = units.isKg
        defer { units.isKg = previous }
        for kg in [false, true] {
            units.isKg = kg
            for source in ["morning", "evening", "bonus"] {
                let date = "landmine-\(UUID().uuidString)"
                let store = ExerciseDraftPersistence(date: date, sessionType: source, exerciseName: "Meadows Row")
                defer { store.clear() }
                let bar = units.toStorage(kg ? 20 : 35)
                let weight = try APIService.decoder.decode(WeightData.self, from: JSONSerialization.data(withJSONObject: ["bar_weight": bar]))
                let vm = ExerciseViewModel(name: "Meadows Row", scheme: "1x8", weightData: weight,
                    equipmentType: "landmine", isSecondSession: source == "evening", isBonusSession: source == "bonus", sessionDate: date)
                vm.initializeSets()
                vm.sets[0].weight = kg ? "30" : "45"; vm.sets[0].reps = "8"
                XCTAssertEqual(vm.saveDraft(), .accepted)
                let restored = ExerciseViewModel(name: "Meadows Row", scheme: "1x8", weightData: nil,
                    isSecondSession: source == "evening", isBonusSession: source == "bonus", sessionDate: date)
                restored.initializeSets()
                XCTAssertEqual(restored.equipmentType, "landmine")
                XCTAssertEqual(restored.barWeight, bar)
                XCTAssertEqual(restored.sets[0].weight, vm.sets[0].weight)
                let log = try XCTUnwrap(restored.buildLogCandidate(alreadyLoggedViaBinding: false))
                let total = units.toStorage(kg ? 50 : 80)
                XCTAssertEqual(log.weight, total, accuracy: 0.00001)
                XCTAssertEqual(restored.totalWeight(for: units.toStorage(kg ? 30 : 45)), log.weight)
                XCTAssertEqual(restored.overloadCurrentVolumeLbs, total * 8, accuracy: 0.0001)
                XCTAssertEqual(log.sets[0]["weight"] as? Double, log.weight)
                let body = WorkoutPayloadBuilder.exercise(exercise: log.name, weight: log.weight, reps: log.reps,
                    rpe: log.rpe, sets: log.sets, force: true, isSecond: log.isSecond, isBonus: log.isBonus,
                    equipmentType: log.equipmentType, painZone: "", notes: "", date: date)
                XCTAssertEqual(body["weight"] as? Double, log.weight)
                XCTAssertEqual(body["equipment_type"] as? String, "landmine")
                let owner = SeanceViewModel(draftSessionType: source)
                let data = try APIService.decoder.decode(SeanceData.self, from: Fixtures.seanceDataJSON(todayDate: date))
                owner.seanceData = data
                owner.logResults = [log.name: log]
                let restoredOwner = SeanceViewModel(draftSessionType: source)
                restoredOwner.seanceData = data
                restoredOwner.restoreLogResults(from: data, serverSessionType: source, serverCompleted: false)
                XCTAssertEqual(restoredOwner.logResults[log.name]?.barWeight, bar)
                XCTAssertEqual(restoredOwner.logResults[log.name]?.weight, log.weight)
                SessionDraftStore.clear(date: date, sessionType: source)
                let recovery = try XCTUnwrap(ExerciseRecoveryHydration.make(log, equipment: "landmine", tracking: "reps", unilateral: false, displayWeight: units.display))
                XCTAssertEqual(Double(recovery.sets[0].weight)!, kg ? 30 : 45, accuracy: 0.00001)
                XCTAssertTrue(restored.setSkipped(true)); XCTAssertTrue(restored.setSkipped(false))
                XCTAssertEqual(restored.sets[0].weight, vm.sets[0].weight)
                restored.sets[0].weight = "0"
                XCTAssertEqual(try XCTUnwrap(restored.buildLogCandidate(alreadyLoggedViaBinding: false)).weight, bar)
                XCTAssertEqual(restored.overloadCurrentVolumeLbs, bar * 8, accuracy: 0.00001)
            }
        }
    }

    func testDayComposerUsesLandmineTotalsAndRecovery() throws {
        let fixture = try DayComposerStabilizationFixture(equipment: ["A": "landmine"])
        defer { fixture.cleanup() }
        try fixture.mount(.morning)
        let vm = try XCTUnwrap(fixture.vms.first)
        XCTAssertEqual(vm.equipmentType, "landmine")
        vm.sets[0].weight = "70"; vm.sets[0].reps = "8"
        let previous = UnitSettings.shared.isKg
        UnitSettings.shared.isKg = false
        defer { UnitSettings.shared.isKg = previous }
        let log = try XCTUnwrap(vm.buildLogCandidate(alreadyLoggedViaBinding: false))
        XCTAssertEqual(log.weight, 115)
        XCTAssertEqual(log.barWeight, 45)
        XCTAssertEqual(vm.saveDraft(), .accepted)
        XCTAssertEqual(vm.overloadCurrentVolumeLbs, 920)
    }

    func testRealCardVisuals() async throws {
        let previous = AppTheme.shared.selectedTheme
        let kg = UnitSettings.shared.isKg
        defer { AppTheme.shared.applyTheme(previous); UnitSettings.shared.isKg = kg }
        UnitSettings.shared.isKg = false
        for theme in [AppThemeOption.electricLight, .electric] {
            AppTheme.shared.applyTheme(theme)
            for state in ["expanded", "logged", "skipped"] {
                for large in [false, true] {
                    let content = ExerciseCard.landminePresentationFixture(state: state)
                        .frame(width: 390).fixedSize(horizontal: false, vertical: true)
                        .padding(12).background(Color.appBg).ignoresSafeArea()
                        .environment(\.colorScheme, theme == .electricLight ? .light : .dark)
                        .environment(\.dynamicTypeSize, large ? .xxxLarge : .large)
                    let host = UIHostingController(rootView: content)
                    let size = host.sizeThatFits(in: CGSize(width: 414, height: 1600))
                    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                    window.rootViewController = host; window.makeKeyAndVisible()
                    defer { window.isHidden = true; window.rootViewController = nil }
                    host.view.layoutIfNeeded()
                    try await Task.sleep(nanoseconds: 100_000_000)
                    let image = UIGraphicsImageRenderer(size: size).image { _ in
                        host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
                    }
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("landmine-\(theme.rawValue)-\(state)-\(large).png")
                    try XCTUnwrap(image.pngData()).write(to: url)
                    print("LANDMINE_SNAPSHOT \(url.path)")
                }
            }
        }
    }
}
