import XCTest

@MainActor
final class NotchFlowAppUITests: XCTestCase {
    func testSettingsWindowExposesGeneralControls() {
        let app = XCUIApplication(bundleIdentifier: "com.notchflow.NotchFlow")
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        statusItem.click()
        statusItem.menuItems["Settings…"].click()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Display"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Island"].exists)
        XCTAssertTrue(app.staticTexts["Startup"].exists)
        XCTAssertTrue(app.staticTexts["Launch at login"].exists)
    }
}
