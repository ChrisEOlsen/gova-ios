import XCTest

/// App-agnostic smoke test: launches the app, taps every tab, and confirms that
/// tapping a list row pushes a detail screen. It uses only native XCUITest
/// queries, so it works on any generated GOVA app without app-specific
/// identifiers. It degrades gracefully on a single-screen or auth-gated app.
final class SmokeTest: XCTestCase {

    func testLaunchesWalksTabsAndPushesADetail() {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 15) else {
            // No tab bar: a single-screen app, or a login gate. A blank launch is
            // still a failure, so assert *something* interactive rendered.
            let rendered = app.buttons.firstMatch.waitForExistence(timeout: 5)
                || app.staticTexts.firstMatch.waitForExistence(timeout: 5)
                || app.textFields.firstMatch.waitForExistence(timeout: 5)
            XCTAssertTrue(rendered, "app launched to an empty screen")
            return
        }

        // Every tab must be tappable and respond.
        let tabs = tabBar.buttons
        XCTAssertGreaterThan(tabs.count, 0, "tab bar has no tabs")
        for i in 0..<tabs.count {
            let tab = tabs.element(boundBy: i)
            tab.tap()
            XCTAssertTrue(tab.exists, "tab \(i) disappeared after tapping")
        }

        // From the first tab that has rows, push a detail and confirm it bound.
        // A row that fails to push a real detail (the Logger bug) fails here.
        for i in 0..<tabs.count {
            tabs.element(boundBy: i).tap()
            let firstCell = app.cells.firstMatch
            if firstCell.waitForExistence(timeout: 3) {
                firstCell.tap()
                let backButton = app.navigationBars.buttons.firstMatch
                XCTAssertTrue(
                    backButton.waitForExistence(timeout: 5),
                    "tapping a row did not push a detail screen (no nav back button appeared)"
                )
                if backButton.exists { backButton.tap() }
                return
            }
        }
        // No tab had rows (empty data set) — the tab walk above still validated
        // navigation; nothing more to push.
    }
}
