import SwiftUI
import LuminaCore

// WP-4. Edit's layout: the photo column (canvas, filmstrip, facts), the controls column (WP-5)
// and the overlays above them (WP-6). WP-0 stub: side by side, no breakpoints.

public struct EditScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    public init() {}
    public var body: some View {
        HStack(spacing: 0) {
            EditCanvas()
            if !model.edit.focus { EditControls().frame(width: model.breakpoints.editControlsWidth(s)) }
        }
        .overlay { EditOverlays() }
    }
}

/// The canvas: the photo at its true aspect ratio, or the empty / failed states.
public struct EditCanvas: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    public init() {}
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                LuminaColor.bgCanvas
                if let p = model.shoot.photo(model.editCur) {
                    let r = EditLayout.photoRect(aspect: p.aspect, canvas: geo.size, padding: LuminaSpacing.photoPaddingMax)
                    PhotoThumb(p, maxPoint: max(r.width, r.height), cover: false).frame(width: r.width, height: r.height)
                        .luminaStatus(AccessibilityID.Edit.photo, "loaded")
                } else {
                    Text("Nothing to edit yet").font(LuminaFont.ui(LuminaFontSize.title2, .semibold, s)).accessibilityIdentifier(AccessibilityID.Edit.empty)
                }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier(AccessibilityID.Edit.canvas)
        }
    }
}
