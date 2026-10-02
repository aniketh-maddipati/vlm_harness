import SwiftUI
import LuminaCore

// WP-4. Edit's layout (README §3, LAYOUT_SIZING §5): the photo column (canvas, filmstrip, facts)
// and the controls column (WP-5) beside it, or under it when the window is under 860 wide, and
// the overlays (WP-6) above both. How the space is divided is `EditLayout.frames`, the same
// maths the headless tests check.

public struct EditScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let f = EditLayout.frames(area: geo.size, window: model.windowSize, scale: s, focus: model.edit.focus,
                                      controlsHidden: model.edit.controlsHidden, controlsCollapsed: model.edit.controlsCollapsed)
            switch f.controls {
            case .hidden:
                EditPhotoColumn(frames: f)
            case .side(let width):
                HStack(spacing: 0) {
                    EditPhotoColumn(frames: f).frame(width: f.columnWidth)
                    EditControls().frame(width: width)
                }
            case .below(let maxHeight):
                let collapsed = model.edit.controlsCollapsed
                VStack(spacing: 0) {
                    EditPhotoColumn(frames: f).frame(maxHeight: .infinity)
                    // The column takes its natural height under the photo, capped (WP5.md #6);
                    // collapsed it is only its header and bottom bar.
                    EditControls()
                        .frame(maxHeight: collapsed ? nil : maxHeight + f.toggleRow)
                        .fixedSize(horizontal: false, vertical: collapsed)
                }
            }
        }
        .overlay { EditOverlays() }
    }
}

/// The photo column: canvas, then the filmstrip (with the facts line beside it on wide columns),
/// then the facts line on its own row.
struct EditPhotoColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let frames: EditLayout.Frames

    var body: some View {
        VStack(spacing: 0) {
            EditCanvas().frame(maxWidth: .infinity, maxHeight: .infinity)
            if frames.stripRow > 0 {
                HStack(alignment: .center, spacing: 14.scaled(s)) {
                    EditFilmstrip(thumbHeight: frames.stripHeight)
                    if frames.factsInline { EditFactsLine(compact: true).frame(maxWidth: 420.scaled(s)) }
                }
                .padding(.vertical, LayoutScale.px(4, s)).padding(.horizontal, 8.scaled(s))
                .frame(height: frames.stripRow)
            }
            if !frames.factsInline && frames.factsRow > 0 {
                EditFactsLine(compact: false).padding(.horizontal, 10.scaled(s)).frame(height: frames.factsRow)
            }
        }
        .background(LuminaColor.bgApp)
    }
}
