import XCTest

/// Flow 8 — layout stays coherent across window sizes: controls reachable, counts visible,
/// cells have nonzero frames, nothing overlaps out of reach.
final class LayoutTests: LuminaUITestCase {

    func testLayoutAt1280x800() { assertCoherentLayout(size: CGSize(width: 1280, height: 800)) }

    func testLayoutAtLargeDesktop() { assertCoherentLayout(size: CGSize(width: 1680, height: 1050)) }

    private func assertCoherentLayout(size: CGSize, file: StaticString = #file, line: UInt = #line) {
        launch(LaunchConfig(fixture: .mixed60, windowSize: size))
        let sheet = lumina.openShoot.open(.mixed60)

        XCTContext.runActivity(named: "Toolbar and controls reachable at \(Int(size.width))x\(Int(size.height))") { _ in
            XCTAssertTrue(sheet.homeButton.isHittable, "grid/home control reachable", file: file, line: line)
            XCTAssertTrue(sheet.element(P0AXID.densityValue).exists, "density readout visible", file: file, line: line)

            // Kept/selection counts become visible after a decision; assert they render.
            sheet.focus(index: 0).pressKeep()
            _ = lumina.waitForProbe { $0.keptCount > 0 }
            XCTAssertTrue(sheet.element(P0AXID.exportCount).waitForExistence(timeout: 5),
                          "kept/export count visible", file: file, line: line)

            // Contact cells retain nonzero frames.
            let cell = sheet.cell(sheet.assetID(at: 0))
            XCTAssertTrue(cell.exists, file: file, line: line)
            XCTAssertGreaterThan(cell.frame.width, 1, "cell has nonzero width", file: file, line: line)
            XCTAssertGreaterThan(cell.frame.height, 1, "cell has nonzero height", file: file, line: line)
        }

        // Grid return remains reachable from single-photo.
        let single = sheet.focus(index: 1).openFocused()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: P0AXID.gridReturn).firstMatch.isHittable,
                      "grid return reachable at \(Int(size.width))x\(Int(size.height))", file: file, line: line)
        single.returnToGrid()
        Invariants.assert(lumina.requireProbe(), app: app, file: file, line: line)
    }
}
