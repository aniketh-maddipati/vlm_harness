import AppKit
import SwiftUI
import XCTest
@testable import Lumina

@MainActor
final class ElasticWrapLayoutTests: XCTestCase {
    private func burst(width: CGFloat) -> some View {
        ElasticWrapLayout(horizontalSpacing: 20, verticalSpacing: 8) {
            ElasticWrapLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<7, id: \.self) { _ in
                    Color.clear.frame(width: 128, height: 80)
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }

    func testNestedOpenBurstWrapsAtAvailableWidthAndRemeasuresOnResize() {
        let host = NSHostingView(rootView: burst(width: 420))
        XCTAssertEqual(host.fittingSize.height, 256, accuracy: 0.5, "seven frames fit three rows at three per row")
        host.rootView = burst(width: 560)
        XCTAssertEqual(host.fittingSize.height, 168, accuracy: 0.5, "widening fits four frames then three")
        host.rootView = burst(width: 280)
        XCTAssertEqual(host.fittingSize.height, 344, accuracy: 0.5, "narrowing wraps to four rows")
    }

    func testCompactChipGroupsKeepTheirNaturalWidthAndRowGap() {
        let host = NSHostingView(rootView:
            ElasticWrapLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                Color.clear.frame(width: 70, height: 28)
                Color.clear.frame(width: 90, height: 28)
                Color.clear.frame(width: 60, height: 28)
            }.frame(width: 180, alignment: .leading)
        )
        XCTAssertEqual(host.fittingSize.height, 62, accuracy: 0.5)
    }
}
