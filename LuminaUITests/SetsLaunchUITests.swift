import XCTest

/// The built app opens the Claude Design page in its window. The page's own behaviour is covered
/// by the probe (Scripts/probe.sh); this only proves the shipped app launches into it.
final class SetsLaunchUITests: LuminaTestCase {
    func testTheDesignPageLoads() {
        continueAfterFailure = false        // each wait is a precondition of the next: no window, no web view
        let app = XCUIApplication()
        app.launchEnvironment["LUMINA_SAMPLE"] = "1"
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "no window")
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30), "no web view")
        // The step pills are the design's top bar: open → cull → edit → export. WebKit exposes
        // page text as the element's value.
        let pill = web.staticTexts.matching(NSPredicate(format: "value == 'export'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 30), "the design's page didn't render")
    }
}
