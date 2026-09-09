import XCTest

/// Launches the real app and checks the one screen that carries the brand —
/// the HUD is reachable and its press-to-talk control is on screen and
/// hittable. Runs on device / simulator only (not `swift test`).
final class HUDGlanceableStateUITests: XCTestCase {

    private func launchPastOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        let continueButton = app.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 2) {
            continueButton.tap()
        }
        return app
    }

    func testTalkButtonIsPresentAndHittable() {
        let app = launchPastOnboarding()
        let talk = app.buttons["talkButton"]
        XCTAssertTrue(talk.waitForExistence(timeout: 5))
        XCTAssertTrue(talk.isHittable)
    }

    func testAppLaunchesInPortrait() {
        let app = launchPastOnboarding()
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        // trackit is portrait-locked (Info.plist UISupportedInterfaceOrientations);
        // the key window must come up taller than it is wide and stay that way.
        XCTAssertGreaterThan(window.frame.height, window.frame.width)
    }
}
