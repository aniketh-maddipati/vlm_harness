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
}
