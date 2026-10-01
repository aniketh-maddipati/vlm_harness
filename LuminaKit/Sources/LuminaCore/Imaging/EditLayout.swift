import Foundation
import CoreGraphics

// WP-4. Where the Edit photo sits in its canvas (R-41, R-55).

public enum EditLayout {
    /// The photo at its true aspect ratio, whole, centred, touching the canvas (minus `padding`)
    /// on one axis. Never thinner than 1pt.
    public static func photoRect(aspect: CGFloat, canvas: CGSize, padding: CGFloat) -> CGRect {
        let w = max(1, canvas.width - 2 * padding), h = max(1, canvas.height - 2 * padding)
        var size = aspect >= w / h ? CGSize(width: w, height: w / aspect) : CGSize(width: h * aspect, height: h)
        size.width = max(1, size.width); size.height = max(1, size.height)
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height)
    }
    /// Zoom is clamped to ¼× of Fit … 2× of 1:1 (R-46). `oneToOne` is the factor that shows 1:1.
    public static func clampZoom(_ z: Double, oneToOne: Double) -> Double { clamp(0.25, z, max(1, 2 * oneToOne)) }
}
