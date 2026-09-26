import CoreGraphics
import Foundation

/// Which frames a drag rectangle crosses, in the order the caller supplies.
/// Geometry only — the table no longer draws a marquee (D29).
nonisolated enum ElasticMarqueeSelection {
    static func ids(in rect: CGRect, frames: [UUID: CGRect], order: [UUID]) -> [UUID] {
        guard rect.width > 0 || rect.height > 0 else { return [] }
        return order.filter { frames[$0]?.intersects(rect) == true }
    }
}
