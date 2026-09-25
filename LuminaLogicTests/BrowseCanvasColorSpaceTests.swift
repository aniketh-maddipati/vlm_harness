import AppKit
import CoreGraphics
import QuartzCore
import XCTest
@testable import Lumina

/// The browse canvas must tell Core Animation which space its drawable is
/// encoded in, and that space must stay the one `MetalPreviewPool` blits into.
///
/// What these tests do NOT claim: that the layer used to be untagged. Measured
/// on macOS 15 (Darwin 25.5), `CAMetalLayer.colorspace` is nil on a bare layer
/// but becomes sRGB as soon as `pixelFormat` is set to a non-`_srgb` format,
/// which `MetalBrowseNSView` has always done. The explicit tag replaces an
/// undocumented default that is derived from the pixel format with one derived
/// from the pixels. `testBrowseCanvasTagsItsLayer` therefore passes with or
/// without the explicit assignment — it pins the observable end state, not the
/// change. `testBrowseTagMatchesTheBlitThatProducesThePixels` is the test that
/// actually fails if either side moves.
///
/// Neither test can prove anything about displayed colour. There is no window,
/// no screen profile and no compositor here, so nothing measures what reaches
/// the panel. A browse-vs-tile-vs-develop appearance claim needs sampled pixels
/// on a real P3 display, not a logic test.
@MainActor
final class BrowseCanvasColorSpaceTests: XCTestCase {
    func testBrowseCanvasTagsItsLayer() throws {
        let view = MetalBrowseNSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))

        // No Metal device on this machine means the no-Metal path: a plain
        // CALayer, which has no colourspace to tag and must not have crashed.
        guard let metalLayer = view.layer as? CAMetalLayer else {
            XCTAssertNotNil(view.layer, "the no-Metal fallback must still install a layer")
            throw XCTSkip("no Metal device — browse canvas fell back to a plain CALayer")
        }

        let tagged = try XCTUnwrap(
            metalLayer.colorspace,
            "browse canvas left its CAMetalLayer untagged; Core Animation will not colour-match it"
        )
        // CoreGraphics vends named spaces as singletons, so identity is a valid
        // check that this is the blit's space and not a lookalike.
        XCTAssertTrue(
            tagged === ImagePixelFormat.workingColorSpace,
            "the tag must be the space the browse blit writes, not a second policy"
        )
        XCTAssertEqual(tagged.name as String?, CGColorSpace.sRGB as String)

        // The tag would be wrong if it followed the display instead of the
        // pixels: the drawable holds sRGB values, so claiming P3 would suppress
        // the conversion Core Animation should be doing.
        XCTAssertFalse(
            tagged === DevelopColorPolicy.displayColorSpace,
            "browse pixels are sRGB-encoded; tagging them with the develop display space over-saturates them"
        )
    }

    /// The tag is only correct while the blit still writes that space, and both
    /// sides must keep reading one constant. This is the assertion that breaks
    /// if someone changes either half.
    func testBrowseTagMatchesTheBlitThatProducesThePixels() throws {
        let pool = try source("Lumina/Services/MetalPreviewPool.swift")
        XCTAssertTrue(
            pool.contains("space: ImagePixelFormat.workingColorSpace"),
            "browse blit no longer writes ImagePixelFormat.workingColorSpace — the layer tag is now a lie"
        )

        let canvas = try source("Lumina/Views/MetalBrowseCanvas.swift")
        XCTAssertTrue(
            canvas.contains("metalLayer.colorspace = ImagePixelFormat.workingColorSpace"),
            "browse canvas must read the blit's own constant rather than restate a space"
        )
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repoRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
