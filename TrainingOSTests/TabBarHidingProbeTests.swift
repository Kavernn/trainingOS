import XCTest
import SwiftUI
import UIKit
import Combine
@testable import TrainingOS

/// Étape 4.3 — vérification EN PREMIER : `.toolbar(.hidden, for: .tabBar)` posé dans le
/// NavigationStack d'un onglet masque-t-il réellement la tab bar sous iOS 26 ?
/// Même structure que l'app : TabView → NavigationStack (onglet Séance) → contenu.
@MainActor
private final class TabBarProbeState: ObservableObject {
    @Published var hidden = false
}

@MainActor
private struct TabBarProbeRoot: View {
    @ObservedObject var state: TabBarProbeState
    var body: some View {
        TabView {
            NavigationStack {
                Text("Séance active")
                    .toolbar(state.hidden ? .hidden : .visible, for: .tabBar)
            }
            .tabItem { Label("Séance", systemImage: "dumbbell.fill") }
            Text("Programme")
                .tabItem { Label("Programme", systemImage: "list.bullet.clipboard") }
        }
    }
}

@MainActor
final class TabBarHidingProbeTests: XCTestCase {

    private func tabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for sub in view.subviews { if let bar = tabBar(in: sub) { return bar } }
        return nil
    }

    /// Visible = présent dans la fenêtre, non masqué, opaque, et au moins en partie à l'écran.
    private func observation(_ window: UIWindow) -> (visible: Bool, detail: String) {
        guard let bar = tabBar(in: window) else { return (false, "aucune UITabBar dans la hiérarchie") }
        let frame = bar.convert(bar.bounds, to: window)
        let onScreen = frame.intersects(window.bounds) && frame.height > 0
        let visible = bar.window != nil && !bar.isHidden && bar.alpha > 0.01 && onScreen
        let detail = "iOS \(UIDevice.current.systemVersion) · isHidden=\(bar.isHidden) alpha=\(bar.alpha) "
            + "frame=\(frame) window=\(window.bounds) → visible=\(visible)"
        return (visible, detail)
    }

    private func record(_ label: String, _ detail: String) {
        let attachment = XCTAttachment(string: "\(label) : \(detail)")
        attachment.name = label
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testToolbarHiddenForTabBarActuallyHidesAndRestores() async throws {
        let state = TabBarProbeState()
        let host = UIHostingController(rootView: TabBarProbeRoot(state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        func settle() async throws {
            for _ in 0..<5 {
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        try await settle()
        let initial = observation(window)
        record("1-initial", initial.detail)
        XCTAssertTrue(initial.visible, "Tab bar attendue visible au départ — \(initial.detail)")

        state.hidden = true
        try await settle()
        let hidden = observation(window)
        record("2-hidden", hidden.detail)
        XCTAssertFalse(hidden.visible, "Tab bar attendue masquée — \(hidden.detail)")

        state.hidden = false
        try await settle()
        let restored = observation(window)
        record("3-restored", restored.detail)
        XCTAssertTrue(restored.visible, "Tab bar attendue de retour — \(restored.detail)")
    }
}
