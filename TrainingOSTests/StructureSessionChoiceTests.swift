import XCTest
import SwiftUI
import UIKit
@testable import TrainingOS

@MainActor
final class StructureSessionChoiceTests: XCTestCase {
    func testHistoricalNamesWithSameTitleKeepDistinctBusinessIdentity() {
        let am = StructureSessionOption(id: "Lundi AM — Haut du corps")
        let pm = StructureSessionOption(id: "Mardi PM — Haut du corps")
        XCTAssertEqual(am.title, pm.title)
        XCTAssertEqual(am.context, "Lundi AM")
        XCTAssertEqual(pm.context, "Mardi PM")
        XCTAssertNotEqual(am.id, pm.id)
        XCTAssertEqual(am.id, "Lundi AM — Haut du corps")
    }

    func testIdentitySurvivesReorderingAndLongListReconstruction() {
        let names = (1...40).map { "Séance \($0) — renforcement musculaire" }
        let first = names.map { StructureSessionOption(id: $0) }
        let reordered = names.reversed().map { StructureSessionOption(id: $0) }
        XCTAssertEqual(Set(first.map(\.id)), Set(reordered.map(\.id)))
        XCTAssertEqual(first.first, reordered.last)
    }

    func testOnlyCompleteHistoricalPrefixIsRemovedForDisplay() {
        XCTAssertEqual(StructureSessionOption(id: "Dimanche PM — Mobilité").title, "Mobilité")
        for name in ["Lundi AM — ", "Upper A", "Lundi AM", "Mon AM — Upper"] {
            XCTAssertEqual(StructureSessionOption(id: name).title, name)
            XCTAssertNil(StructureSessionOption(id: name).context)
        }
    }
    func testLongChoiceListRendersWithoutMutatingParentSelection() async throws {
        let names = (1...30).map { "Lundi AM — Séance \($0) : haut du corps et renforcement musculaire" }
        var callbacks = 0
        for size in [CGSize(width: 375, height: 667), CGSize(width: 393, height: 852), CGSize(width: 440, height: 956)] {
            for large in [false, true] {
                let host = UIHostingController(rootView: StructureSessionChoiceSheet(
                    moment: "Matin", sessions: names, selectedSession: names[1],
                    onPick: { _ in callbacks += 1 })
                    .environment(\.dynamicTypeSize, large ? .accessibility3 : .large))
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = window.bounds
                await Task.yield()
                host.view.layoutIfNeeded()
                XCTAssertEqual(callbacks, 0, "Opening the chooser must not assign a session")
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "structure-choices-\(Int(size.width))-\(large)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
                window.rootViewController = nil
            }
        }
    }
}
