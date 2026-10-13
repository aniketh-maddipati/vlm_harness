import AppKit
import XCTest
@testable import Lumina

/// The page fills the window. A larger offer is taken whole; the web view is pinned to the host
/// that SwiftUI sizes, and the Edit canvas (a sibling) keeps its own frame.
@MainActor
final class SetsWindowSizeTests: XCTestCase {
    func testALargerWindowIsTakenWhole() {
        XCTAssertEqual(SetsWindowSize.filled(width: 1800, height: 1200), CGSize(width: 1800, height: 1200))
        XCTAssertEqual(SetsWindowSize.filled(width: nil, height: 1300), CGSize(width: SetsWindowSize.initial.width, height: 1300))
    }

    func testNoOfferOpensAtTheReferenceSize() {
        XCTAssertEqual(SetsWindowSize.filled(width: nil, height: nil), SetsWindowSize.initial)
        XCTAssertEqual(SetsWindowSize.filled(width: .infinity, height: .infinity), SetsWindowSize.initial)
        XCTAssertEqual(SetsWindowSize.filled(width: .nan, height: .nan), SetsWindowSize.initial)
    }

    func testASmallOfferStaysAtTheMinimum() {
        XCTAssertEqual(SetsWindowSize.filled(width: 100, height: 100), SetsWindowSize.minimum)
        XCTAssertEqual(SetsWindowSize.filled(width: -20, height: 800), CGSize(width: SetsWindowSize.minimum.width, height: 800))
    }

    func testGrowingTheHostFillsThePageAndLeavesTheCanvas() {
        let host = SetsHostView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let page = NSView(frame: .zero)
        let canvas = NSView(frame: NSRect(x: 40, y: 80, width: 200, height: 100))
        host.webView = page
        host.addSubview(page)
        host.addSubview(canvas)
        host.setFrameSize(NSSize(width: 1400, height: 1100))
        XCTAssertEqual(page.frame, host.bounds)
        XCTAssertEqual(canvas.frame, NSRect(x: 40, y: 80, width: 200, height: 100))
        host.setFrameSize(NSSize(width: 1100, height: 800))
        XCTAssertEqual(page.frame, host.bounds)
        XCTAssertEqual(canvas.frame.size, NSSize(width: 200, height: 100))
    }

    func testLayoutFillsAPageLeftAtTheOldSize() {
        let host = SetsHostView(frame: NSRect(x: 0, y: 0, width: 1400, height: 1100))
        let page = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        host.webView = page
        host.addSubview(page)
        host.layout()
        XCTAssertEqual(page.frame, host.bounds)
    }
}
