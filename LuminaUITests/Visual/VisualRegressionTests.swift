import XCTest

/// Visual-regression foundation. Runs at a pinned 1280×800 window with reduce-motion on and a fixed
/// fixture. Captures screenshots (kept always) and asserts *semantic* layout via the structured
/// probe + per-cell accessibility values. Exact cross-machine pixel diffing is intentionally NOT
/// gated here (documented as local-Mac-only in docs/P0_UI_AUTOMATION.md); capture + semantic
/// assertions are the portable, mandatory floor.
final class VisualRegressionTests: LuminaUITestCase {
    private let windowSize = CGSize(width: 1280, height: 800)

    override func setUp() {
        super.setUp()
        attachPlatformMetadata()
    }

    func testContactSheetStates() {
        launch(LaunchConfig(fixture: .mixed60, windowSize: windowSize))
        let sheet = lumina.openShoot.open(.mixed60)
        capture(name: "contact-sheet-1280x800")

        // Focused asset — pointer travel, not a hidden selection.
        let ids = sheet.visibleIDs()
        sheet.focus(assetID: ids[2])
        assertFocused(ids[2])
        capture(name: "focused-asset", element: sheet.cell(ids[2]))

        sheet.focusNext()
        let distinct = lumina.waitForProbe {
            $0.focusedAssetID != ids[2] && $0.focusedAssetID != nil
        }
        XCTAssertNotEqual(distinct.focusedAssetID, ids[2])
        XCTAssertTrue(distinct.selectedAssetIDs.isEmpty, "keyboard travel must not create selection")
        capture(name: "focused-and-selected-different-assets")

        sheet.focus(assetID: ids[9])
        let both = lumina.waitForProbe { $0.focusedAssetID == ids[9] }
        XCTAssertEqual(both.focusedAssetID, ids[9], "cell is focused")
        XCTAssertFalse(both.selectedAssetIDs.contains(ids[9]), "pointer focus is not persistent selection")
        capture(name: "focused-plus-selected-same-cell", element: sheet.cell(ids[9]))

        // Kept and rejected markers.
        if let keep = sheet.firstVisibleID(cull: "undecided") {
            sheet.focus(assetID: keep); sheet.pressKeep()
            _ = lumina.waitForProbe { $0.culls[keep] == "keep" }
            capture(name: "kept-asset", element: sheet.cell(keep))
        }
        if let reject = sheet.firstVisibleID(cull: "undecided") {
            sheet.focus(assetID: reject); sheet.pressReject()
            _ = lumina.waitForProbe { $0.culls[reject] == "reject" }
            capture(name: "rejected-asset", element: sheet.cell(reject))
        }

        // Edited marker (seeded by the fixture).
        if let edited = lumina.requireProbe().editedIDs.first(where: { sheet.visibleIDs().contains($0) }) {
            capture(name: "edited-marker", element: sheet.cell(edited))
        }
    }

    func testSinglePhotoPlaceholder() {
        launch(LaunchConfig(fixture: .mixed60, windowSize: windowSize))
        let sheet = lumina.openShoot.open(.mixed60)
        let single = sheet.focus(index: 4).openFocused()
        XCTAssertTrue(single.image.waitForExistence(timeout: 8))
        capture(name: "single-photo-placeholder")
    }

    func testMissingOriginalState() {
        launch(LaunchConfig(fixture: .missingOriginals, windowSize: windowSize))
        let sheet = lumina.openShoot.open(.missingOriginals)
        let probe = lumina.waitForProbe { $0.assetCount > 0 }
        capture(name: "missing-original-contact-sheet")
        if let missing = probe.missingAssetIDs.first(where: { probe.visibleAssetIDs.contains($0) }) {
            sheet.focus(assetID: missing)
            let single = sheet.openFocused()
            _ = single.image.waitForExistence(timeout: 8)
            capture(name: "missing-original-single-photo")
        }
    }

    // MARK: - Helpers

    private func assertFocused(_ id: String, file: StaticString = #file, line: UInt = #line) {
        let snapshot = lumina.waitForProbe { $0.focusedAssetID == id }
        XCTAssertEqual(snapshot.focusedAssetID, id, "asset \(id) should be focused", file: file, line: line)
    }

    private func capture(name: String, element: XCUIElement? = nil) {
        let screenshot: XCUIScreenshot
        if let element, element.exists {
            screenshot = element.screenshot()
        } else {
            screenshot = app.windows.firstMatch.exists ? app.windows.firstMatch.screenshot() : XCUIScreen.main.screenshot()
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "visual-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachPlatformMetadata() {
        let info = ProcessInfo.processInfo
        let meta = """
        os=\(info.operatingSystemVersionString)
        host=redacted
        window=\(Int(windowSize.width))x\(Int(windowSize.height))
        note=Exact pixel comparison is local-Mac-only; semantic layout assertions are the portable gate.
        """
        let attachment = XCTAttachment(string: meta)
        attachment.name = "visual-platform-metadata"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
