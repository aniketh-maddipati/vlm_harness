import CoreGraphics
import XCTest
@testable import Lumina

#if DEBUG
final class DevSplitPlacementTests: XCTestCase {
    func testFlag() {
        XCTAssertFalse(DevSplitPlacement.requested(arguments: ["Lumina"]))
        XCTAssertTrue(DevSplitPlacement.requested(arguments: ["Lumina", "--dev-split"]))
    }

    func testHalvesTileTheVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1084)
        let leading = DevSplitPlacement.leadingFrame(visible: visible)
        let trailing = DevSplitPlacement.trailingFrame(visible: visible)

        XCTAssertEqual(leading, CGRect(x: 0, y: 0, width: 864, height: 1084))
        XCTAssertEqual(trailing, CGRect(x: 864, y: 0, width: 864, height: 1084))
        XCTAssertEqual(leading.maxX, trailing.minX)
        XCTAssertEqual(leading.union(trailing), visible)
    }

    func testOddWidthSharesTheTrailingEdge() {
        let visible = CGRect(x: 10, y: 20, width: 1001, height: 400)
        let trailing = DevSplitPlacement.trailingFrame(visible: visible)
        XCTAssertEqual(trailing.width, 500)
        XCTAssertEqual(trailing.maxX, visible.maxX)
        XCTAssertEqual(trailing.minY, visible.minY)
        XCTAssertEqual(trailing.height, visible.height)
    }
}
#endif
