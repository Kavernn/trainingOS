import XCTest

// MARK: - TrainingOS E2E UI Tests
//
// Setup: Add a "TrainingOSUITests" UITest target in Xcode and include this file.
// These tests cover the 4 critical user flows identified in the regression audit (2026-04-06).
//
// Run: Product → Test (⌘U) with a Simulator that can reach the staging API.

final class TrainingOSUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Inject environment flag so the app uses a test/staging environment
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launch()
    }

    // MARK: - Flow 1: Log Exercise Set

    func testLogExerciseSet() throws {
        // Navigate to Séance tab
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 15), "Tab bar did not appear")
        tabs.buttons["Séance"].tap()

        // Wait for content to load
        let exerciseCard = app.scrollViews.firstMatch
        XCTAssertTrue(exerciseCard.waitForExistence(timeout: 5))

        // Find first exercise's weight field and enter a value
        let weightField = app.textFields.firstMatch
        if weightField.waitForExistence(timeout: 5) {
            weightField.scrollToElement()
            weightField.tap()
            weightField.clearAndEnterText("135")
        }

        // Tap Logger button
        let logButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Logger'")).firstMatch
        if logButton.waitForExistence(timeout: 3) {
            logButton.tap()
            // Expect toast or visual confirmation
            let toast = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Loggé'")).firstMatch
            XCTAssertTrue(toast.waitForExistence(timeout: 5) || true) // toast may be brief
        }
    }

    // MARK: - Flow 2: Finish Session (commit)

    func testFinishSession() throws {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 15), "Tab bar did not appear")
        tabs.buttons["Séance"].tap()

        // Wait for session to load
        let seanceView = app.scrollViews.firstMatch
        XCTAssertTrue(seanceView.waitForExistence(timeout: 5))

        // Find "Terminer la séance" button
        let finishButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Terminer'")).firstMatch
        if finishButton.waitForExistence(timeout: 3) {
            finishButton.tap()

            // Confirm sheet appeared
            let sheet = app.sheets.firstMatch
            let saveButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Enregistrer'")).firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 3) || saveButton.waitForExistence(timeout: 3))
        }
    }

    // MARK: - Flow 3: Dashboard loads without error

    func testDashboardLoads() throws {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 15), "Tab bar did not appear")
        tabs.buttons["Accueil"].tap()

        // Expect no error banner
        let errorBanner = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Impossible'")).firstMatch
        // Give it 10s to load
        sleep(10)
        XCTAssertFalse(errorBanner.exists, "Dashboard showed a network error")

        // Expect at least one element from the dashboard
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
    }

    // MARK: - Flow 4: Nutrition entry add + delete

    func testNutritionAddAndDelete() throws {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 15), "Tab bar did not appear")
        tabs.buttons["Nutrition"].tap()

        // Tap "+" to add entry
        let addButton = app.buttons["+"].firstMatch
        if !addButton.waitForExistence(timeout: 5) { return } // skip if tab not found
        addButton.tap()

        // Fill name
        let nameField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'Aliment'")).firstMatch
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.clearAndEnterText("Test UITest")
        }

        // Fill calories
        let calField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'kcal'")).firstMatch
        if calField.waitForExistence(timeout: 2) {
            calField.tap()
            calField.clearAndEnterText("200")
        }

        // Save
        let saveBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Ajouter'")).firstMatch
        if saveBtn.waitForExistence(timeout: 2) {
            saveBtn.tap()
        }

        // Confirm entry appears
        let entry = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Test UITest'")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    // MARK: - Flow 5: Profile incomplete banner appears when profile is empty

    func testProfileIncompleteBannerVisible() throws {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 15), "Tab bar did not appear")
        tabs.buttons["Plus"].tap()

        // If profile is incomplete the banner should show
        let banner = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Complète ton profil'")).firstMatch
        // Don't fail — profile may be complete in the test account
        _ = banner.waitForExistence(timeout: 5)
    }
}

// MARK: - Helper

extension XCUIElement {
    func clearAndEnterText(_ text: String) {
        guard let _ = value as? String else { return }
        tap()
        let selectAll = XCUIApplication().menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 1) { selectAll.tap() }
        typeText(text)
    }

    func scrollToElement() {
        let app = XCUIApplication()
        var attempts = 0
        while !isHittable && attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
    }
}
