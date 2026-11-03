import XCTest
import SwiftUI
import UIKit
@testable import TrainingOS

@MainActor
final class UIHardeningPresentationTests: XCTestCase {
    func testSharedControlsAtSmallAndLargeWidthsAndTextSizes() async throws {
        let originalTheme = AppTheme.shared.selectedTheme
        defer { AppTheme.shared.applyTheme(originalTheme) }
        for theme in [AppThemeOption.electric, .electricLight] {
            AppTheme.shared.applyTheme(theme)
            for width in [320.0, 430.0] {
                for large in [false, true] {
                    let content = VStack(spacing: 16) {
                        ErrorBannerView(error: "Impossible de charger les données. Tes informations précédentes restent disponibles.", onRetry: {}, onDismiss: {})
                        PrimaryButton(title: "Enregistrer les modifications de la séance", action: {})
                        PrimaryButton(title: "Enregistrer les modifications", isLoading: true, action: {})
                        PrimaryButton(title: "Supprimer", style: .destructive, size: .small, isDisabled: true, action: {})
                        CardInfoButton(title: "Récupération et énergie du jour", entries: [])
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .ignoresSafeArea()
                    .background(Color.appBg)
                    .environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
                    .environment(\.colorScheme, theme == .electricLight ? .light : .dark)
                    let host = UIHostingController(rootView: content)
                    let fitted = host.sizeThatFits(in: CGSize(width: width, height: 10000))
                    XCTAssertLessThanOrEqual(fitted.width, width + 1, "Must fit horizontally")
                    XCTAssertGreaterThan(fitted.height, 200)
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: fitted.height))
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    host.view.frame = window.bounds
                    await Task.yield()
                    host.view.layoutIfNeeded()
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                        host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let name = "ui-hardening-\(theme.rawValue)-\(Int(width))-\(large)"
                    let attachment = XCTAttachment(image: image)
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
                    try XCTUnwrap(image.pngData()).write(to: file)
                    print("UI_HARDENING_VISUAL \(file.path)")
                    window.isHidden = true
                    window.rootViewController = nil
                }
            }
        }
    }
    func testLongPrimaryActionReportsItsFullAccessibleHeight() {
        let host = UIHostingController(rootView: PrimaryButton(
            title: "Enregistrer les modifications de la séance", action: {})
            .environment(\.dynamicTypeSize, .accessibility3))
        let fitted = host.sizeThatFits(in: CGSize(width: 288, height: 10000))
        XCTAssertGreaterThan(fitted.height, 100)
        XCTAssertLessThanOrEqual(fitted.width, 289)
    }

    func testNutritionFormLightDarkSmallLargeDynamicType() async throws {
        let originalTheme = AppTheme.shared.selectedTheme
        defer { AppTheme.shared.applyTheme(originalTheme) }
        for theme in [AppThemeOption.electric, .electricLight] {
            AppTheme.shared.applyTheme(theme)
            for width in [320.0, 430.0] {
                for large in [false, true] {
                    let host = UIHostingController(rootView:
                        SimpleAddNutritionSheet(onSave: { _, _, _, _ in })
                            .environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
                            .environment(\.colorScheme, theme == .electricLight ? .light : .dark))
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: width == 320 ? 568 : 932))
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    host.view.frame = window.bounds
                    await Task.yield()
                    host.view.layoutIfNeeded()
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                        host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let name = "nutrition-form-\(theme.rawValue)-\(Int(width))-\(large)"
                    let attachment = XCTAttachment(image: image)
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
                    try XCTUnwrap(image.pngData()).write(to: file)
                    print("UI_HARDENING_VISUAL \(file.path)")
                    window.isHidden = true
                    window.rootViewController = nil
                }
            }
        }
    }

}
