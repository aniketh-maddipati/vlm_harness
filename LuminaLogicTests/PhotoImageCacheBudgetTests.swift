import XCTest
@testable import Lumina

final class PhotoImageCacheBudgetTests: XCTestCase {

    func testTierCeilingsOrdered() {
        XCTAssertLessThan(PhotoImageCacheBudget.gridTierCeilingBytes, PhotoImageCacheBudget.previewTierCeilingBytes)
        XCTAssertLessThan(PhotoImageCacheBudget.previewTierCeilingBytes, PhotoImageCacheBudget.totalCeilingBytes)
    }

    func testTierCeilingForPixelSize() {
        XCTAssertEqual(
            PhotoImageCacheBudget.tierCeiling(maxPixelSize: PhotoImageTier.gridMaxPixelSize),
            PhotoImageCacheBudget.gridTierCeilingBytes
        )
        XCTAssertEqual(PhotoImageCacheBudget.tierCeiling(maxPixelSize: 1600), PhotoImageCacheBudget.previewTierCeilingBytes)
        XCTAssertEqual(PhotoImageCacheBudget.tierCeiling(maxPixelSize: nil), PhotoImageCacheBudget.proxyTierCeilingBytes)
    }

    func testMemoryCostPositive() {
        let image = NSImage(size: NSSize(width: 100, height: 100))
        image.addRepresentation(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 100,
            pixelsHigh: 100,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 400,
            bitsPerPixel: 32
        )!)
        XCTAssertEqual(PhotoImageCacheBudget.memoryCost(of: image), 40_000)
    }

    func testPrefetchWidthNamed() {
        XCTAssertEqual(PhotoImageCacheBudget.prefetchConcurrencyWidth, 8)
    }
}
