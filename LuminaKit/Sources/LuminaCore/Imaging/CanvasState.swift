import Foundation
import CoreGraphics
import Observation

// WP-4. What only the Edit canvas needs to remember (reached with `model.canvas`): what the
// view measured, the pointer, and the crop's own undo history.

/// A provider that knows a photo's real pixel size (after orientation), so "1:1" is one photo
/// pixel per screen pixel. Optional: without it Edit assumes a 24 MP frame.
public protocol PixelSizing {
    func pixelSize(for photo: Photo) -> CGSize?
}

@MainActor @Observable
public final class CanvasState {
    public struct CropStep: Equatable, Sendable {
        public var draft: Look, ratio: String, swapped: Bool
    }
    /// The canvas as the view laid it out; nil until a view has (headless: computed from the window).
    public var size: CGSize?
    /// Screen pixels per point. 2 until a view says otherwise.
    public var backingScale: CGFloat = 2
    /// The pointer over the canvas, from its centre (Z zooms there). Not observed: it changes on every move.
    @ObservationIgnored public var pointer: CGPoint?
    /// The ratio is turned the other way (portrait on a landscape frame, or the reverse).
    public var cropSwapped = false
    public internal(set) var cropUndo: [CropStep] = []
    public internal(set) var cropRedo: [CropStep] = []
    @ObservationIgnored var lastCropKind = ""
    @ObservationIgnored var lastCropAt = Date.distantPast
    /// The filmstrip's own scroll, in points, on top of "current centred". Reset when the photo changes.
    public var stripScroll: CGFloat = 0
    public init() {}
}
