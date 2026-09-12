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

        // Every tab must be tappable and actually respond. `exists` is true
        // whether or not the tap did anything, so selection is the assertion
        // that has teeth.
        //
        // With more than five resources SwiftUI shows four tabs plus "More",
        // and the rest live in a list behind it — this test reaches only the
        // visible five. The per-resource assertions /build adds are what cover
        // the others (see CLAUDE.md § Verification).
        let tabs = tabBar.buttons
        XCTAssertGreaterThan(tabs.count, 0, "tab bar has no tabs")
        for i in 0..<tabs.count {
            let tab = tabs.element(boundBy: i)
            let label = tab.label
            tab.tap()
            XCTAssertTrue(tab.isSelected, "tab \(label) did not select when tapped")
        }

        // From the first tab that has rows, tap a row and confirm we navigated to
        // a detail. A successful push covers the list (portrait, full-screen), so
        // the tapped row becomes non-hittable. This deliberately does NOT look for
        // a nav-bar button — a list's own "+" toolbar button would satisfy that
        // even when nothing pushed. The Logger-style bug (push a placeholder, then
        // unwind back to the list) leaves the row hittable, so it is not mistaken
        // for a successful push.
        for i in 0..<tabs.count {
            tabs.element(boundBy: i).tap()
            let firstCell = app.cells.firstMatch
            guard firstCell.waitForExistence(timeout: 3), firstCell.isHittable else { continue }
            firstCell.tap()
            let leftTheList = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "isHittable == false"),
                object: firstCell
            )
            if XCTWaiter().wait(for: [leftTheList], timeout: 5) == .completed {
                // Navigated into a detail screen — pop back out and finish.
                let back = app.navigationBars.buttons.firstMatch
                if back.waitForExistence(timeout: 3) { back.tap() }
                return
            }
            // Row still hittable: this resource has no detail screen (a read-only
            // list) — acceptable, try the next tab. A detail-capable resource whose
            // detail is broken is caught by the per-resource assertions /build adds
            // on top of this generic test (see CLAUDE.md).
        }
        // No tab produced a detail push (all read-only lists, or empty data). The
        // tab walk above still validated that every screen loads.
    }
}
