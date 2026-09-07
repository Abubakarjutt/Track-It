import XCTest

/// Exercises the tap-select fallback surface: with no exercise recognised,
/// pressing and releasing the talk button must not crash and must leave the
/// HUD interactive. A thin smoke check — the parse/engine logic is covered
/// in `swift test`.
final class TapSelectInteractionUITests: XCTestCase {

    func testPressReleaseLeavesHUDInteractive() {
        let app = XCUIApplication()
        app.launch()
        let continueButton = app.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 2) { continueButton.tap() }

        let talk = app.buttons["talkButton"]
        XCTAssertTrue(talk.waitForExistence(timeout: 5))
        talk.press(forDuration: 0.4)

        // After a press with nothing said, the button is still there to try again.
        XCTAssertTrue(talk.isHittable)
    }
}
