import CoreGraphics
import Foundation

/// D26 / D28 — quantized sizes around the focused frame.
///
/// Springs travel between these steps and dead-stop; nothing interpolates at rest.
/// Distant frames compress first and stay visible. The focused frame never moves
/// as a side effect of a neighbor entering the strip.
@MainActor
enum ElasticCanvasLayout {
    static var steps: [CGFloat] { HiFiTokens.Grid.elasticityStepsPx }
    static var stripTrackHeight: CGFloat { HiFiTokens.Grid.stripEvidenceHeight }

    /// Periphery long-edge at `|distance|` from focus.
    /// Distance 0 is the hero (strip track). Distance ≥ 1 walks the sealed
    /// `elasticityStepsPx`; the last step repeats so frames compress, never vanish.
    static func peripheryLongEdge(distanceFromFocus: Int) -> CGFloat {
        if distanceFromFocus <= 0 { return stripTrackHeight }
        let index = min(distanceFromFocus - 1, steps.count - 1)
        return steps[index]
    }

    static func distance(from index: Int, focus: Int) -> Int {
        abs(index - focus)
    }

    /// Inspect-strip thumb long-edge: same quantization, scaled so the nearest
    /// step fills the 90 px evidence track.
    static func stripThumbLongEdge(distanceFromFocus: Int) -> CGFloat {
        let raw = peripheryLongEdge(distanceFromFocus: distanceFromFocus)
        guard let maxStep = steps.first, maxStep > 0 else { return stripTrackHeight }
        return raw / maxStep * stripTrackHeight
    }

    /// D27 dim-in-place for inspect periphery (and rejects). Not an opacity fade to absent.
    static var peripheryDimOpacity: Double { HiFiTokens.Color.rejectDimOpacity }

    static func plateOpacity(distanceFromFocus: Int, rejected: Bool = false) -> Double {
        if distanceFromFocus <= 0 && !rejected { return 1 }
        return peripheryDimOpacity
    }

    /// Neighbor window used by the inspect strip (same table, compressed).
    static let inspectNeighborHalfWindow = 14

    static func inspectNeighborRange(focusIndex: Int?, count: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        guard let focusIndex, (0..<count).contains(focusIndex) else {
            return 0..<min(count, inspectNeighborHalfWindow + 2)
        }
        let lo = max(0, focusIndex - inspectNeighborHalfWindow)
        let hi = min(count, focusIndex + inspectNeighborHalfWindow + 1)
        return lo..<hi
    }
}
