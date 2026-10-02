import SwiftUI
import LuminaCore

// WP-4. Edit's layout (README §3, LAYOUT_SIZING §5): the photo column (canvas, filmstrip, facts)
// and the controls column (WP-5) beside it, or under it when the window is under 860 wide, and
// the overlays (WP-6) above both, and the footer across the whole window under them (prototype
// `data-lumina="footer"`). How the space is divided is `EditLayout.frames`, the same maths the
// headless tests check.

public struct EditScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let f = EditLayout.frames(area: geo.size, window: model.windowSize, scale: s, focus: model.edit.focus,
                                      controlsHidden: model.edit.controlsHidden, controlsCollapsed: model.edit.controlsCollapsed)
            VStack(spacing: 0) {
                switch f.controls {
                case .hidden:
                    EditPhotoColumn(frames: f).frame(maxHeight: .infinity)
                case .side(let width):
                    HStack(spacing: 0) {
                        EditPhotoColumn(frames: f).frame(width: f.columnWidth)
                        EditControls().frame(width: width)
                    }
                    .frame(maxHeight: .infinity)
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
                    .frame(maxHeight: .infinity)
                }
                if f.footer > 0 { EditFooter().frame(height: f.footer) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay { EditOverlays() }
    }
}

/// The photo column (prototype: `padding:{{ pad }}`, `gap:{{ colGap }}`): the canvas, then the
/// filmstrip with its scene labels, then the facts line on windows 860 tall and up.
struct EditPhotoColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let frames: EditLayout.Frames

    var body: some View {
        VStack(spacing: frames.gap) {
            EditCanvas().frame(maxWidth: .infinity, maxHeight: .infinity)
            if frames.stripRow > 0 {
                EditFilmstrip(thumbHeight: frames.stripHeight, labels: frames.stripLabels,
                              labelRow: frames.stripLabelRow, labelGap: frames.stripLabelGap)
                    .padding(.bottom, LayoutScale.px(6, s))
                    .frame(height: frames.stripRow)
            }
            if frames.factsRow > 0 {
                EditFactsLine(showsLine: model.windowSize.width >= 1100).frame(height: frames.factsRow)
            }
        }
        .padding(.top, frames.padTop).padding(.horizontal, frames.padSide).padding(.bottom, frames.padBottom)
        .background(LuminaColor.bgApp)
    }
}

/// The footer across the whole window (prototype `data-lumina="footer"`): the hint for what is
/// under the pointer, else what Crop expects, else where the edits stand; "All shortcuts ?" right.
struct EditFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduce

    static let cropHint = "Drag a corner to crop. Turn outside the frame, or press S and draw along the horizon, to straighten. ⏎ applies."

    var body: some View {
        let hint = model.editHintText, status = model.editSaveStatus
        let cropping = model.edit.overlay == .crop
        let warn = model.edit.warning == AppModel.storageWarning
        HStack(spacing: 16.scaled(s)) {
            ZStack(alignment: .leading) {
                // The save status is the top bar's on Edit (prototype `saveT`); here only a storage problem shows.
                Text(cropping ? Self.cropHint : (warn ? status : ""))
                    .foregroundStyle(warn && !cropping ? LuminaColor.errorText : LuminaColor.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
                    .opacity(hint.isEmpty ? 1 : 0)
                    .luminaStatus(AccessibilityID.Edit.saveStatus, status)
                Text(hint).foregroundStyle(LuminaColor.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
                    .luminaStatus(AccessibilityID.Edit.hint, hint)
            }
            .font(LuminaFont.small(s))
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(LuminaMotion.panelFade(reduce), value: hint.isEmpty)
            Button { model.helpOpen() } label: {
                HStack(spacing: 6.scaled(s)) { Text("All shortcuts"); KeyCap(text: "?") }
                    .font(LuminaFont.small(s)).contentShape(Rectangle())
            }
            .buttonStyle(LuminaLinkButtonStyle())
            .fixedSize()
            .help("Every key and gesture · ?").accessibilityLabel("All shortcuts")
            .accessibilityIdentifier(AccessibilityID.Edit.shortcuts)
        }
        .padding(.horizontal, 20.scaled(s))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaColor.bgPanel)
        .overlay(alignment: .top) { LuminaColor.fill06.frame(height: 1).allowsHitTesting(false) }
    }
}
