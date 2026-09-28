import XCTest
import SwiftUI
@testable import TrainingOS

@MainActor
final class DayComposerPresentationTests: XCTestCase {
    func testPendingReviewFailureNeverClaimCompletionOrBlindRetry() {
        for state in [DayComposerFinishCoordinator.ProductState.pending, .review, .failed] {
            let copy = DayComposerFinishPresentation(state: state)
            XCTAssertFalse(copy.title.contains("terminée"))
            XCTAssertTrue(copy.checkTitle.hasPrefix("Vérifier"))
            XCTAssertNotNil(copy.detail)
        }
        XCTAssertNotEqual(DayComposerFinishPresentation(state: .pending).symbol,
                          DayComposerFinishPresentation(state: .completed).symbol)
    }

    func testRPEPresentationDoesNotSelectAnEffortOnAppearance() async {
        var selected: Int?
        await capture("RPE-Soir-sans-selection", content: Form {
            DayComposerRPEChoices(source: .evening, selection: Binding(get: { selected }, set: { selected = $0 }))
            Button("Confirmer et terminer Soir") {}.disabled(selected == nil)
                .buttonStyle(.borderedProminent).listRowBackground(Color.appCard)
        }.scrollContentBackground(.hidden).background(Color.appBg).tint(Color.forge))
        XCTAssertNil(selected)
    }

    func testCompletedDayPresentationSnapshot() async {
        await capture("Journee-terminee", content: DayComposerCompletedSummary(leave: {})
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.appBg))
    }

    func testStatusPresentationSnapshots() async {
        for state in [DayComposerFinishCoordinator.ProductState.processing, .pending, .review, .failed, .completed] {
            await capture("Etat-\(state)", content: VStack(alignment: .leading, spacing: 20) {
                DayComposerFinishStatus(source: .morning, state: state)
                DayComposerFinishStatus(source: .evening, state: .ready)
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.appBg))
        }
    }

    func testActiveSourcePresentationSnapshots() async throws {
        let r = try DayComposerFinishRig(names: ["Développé haltères", "Tirage horizontal"])
        defer { r.cleanup() }
        for source in [DayComposerSource.morning, .evening] {
            let item = try XCTUnwrap(r.fixture.coordinator.orderedUnits.flatMap(\.items).first { $0.id.source == source })
            r.fixture.coordinator.consult(item.id)
            await capture("Active-\(source.title)", content: NavigationStack {
                DayComposerActiveView(coordinator: r.fixture.coordinator,
                    stabilizationBarrier: r.fixture.barrier, finishCoordinator: r.engine, onDismiss: {})
            })
        }
    }

    private func capture<Content: View>(_ name: String, content: Content) async {
        let controller = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        await Task.yield()
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }
}
