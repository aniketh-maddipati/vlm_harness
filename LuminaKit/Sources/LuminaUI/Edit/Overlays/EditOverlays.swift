import SwiftUI
import LuminaCore

// WP-6. What sits above Edit (`EditScreen` places this over the canvas and the controls):
// Variations and the scene grid over the canvas, the picker's chip, the toast, and Help and the
// first-run intro over everything. Every one fades in 120 ms (R-60); none animates in a loop.
// The rules are in `AppModel+Overlays`; views only draw and forward clicks.

public struct EditOverlays: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduce
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let canvas = canvasRect(geo)
            let overlay = model.edit.overlay
            ZStack(alignment: .topLeading) {
                if overlay == .sceneGrid, let grid = model.sceneGrid {
                    SceneGridOverlay(grid: grid).frame(width: canvas.width, height: canvas.height).offset(x: canvas.minX, y: canvas.minY)
                        .transition(.opacity)
                }
                if overlay == .variations, let spec = model.overlays.spec, let photo = model.shoot.photo(model.editCur) {
                    VariationsGrid(spec: spec, photo: photo).frame(width: canvas.width, height: canvas.height).offset(x: canvas.minX, y: canvas.minY)
                        .transition(.opacity)
                }
                if model.edit.pickingWhite || overlay == .picker {
                    PickerChip().frame(maxWidth: max(1, canvas.width - 24.scaled(s)), alignment: .leading)
                        .offset(x: canvas.minX + 12.scaled(s), y: canvas.minY + 12.scaled(s))
                        .transition(.opacity)
                }
                if let toast = model.toast {
                    ToastView(text: toast.text)
                        .frame(width: canvas.width, height: canvas.height, alignment: .bottom).offset(x: canvas.minX, y: canvas.minY)
                        .transition(.opacity)
                }
                if overlay == .help { HelpOverlay().transition(.opacity) }
                if overlay == .intro { IntroOverlay().transition(.opacity) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(LuminaMotion.panelFade(reduce), value: overlay)
            .animation(LuminaMotion.panelFade(reduce), value: model.toast)
            .animation(LuminaMotion.panelFade(reduce), value: model.edit.pickingWhite)
        }
        .onAppear { model.overlaysSync(); model.introOpenIfFirstRun(); model.toastScheduleExpiry() }
        .onChange(of: model.editCur) { model.overlaysSync(); model.introOpenIfFirstRun() }
        .onChange(of: model.toast) { model.toastScheduleExpiry() }
    }

    /// The canvas inside this view: what the canvas reported (`Metrics`), else what the layout
    /// rules say (LAYOUT_SIZING §5: everything but the controls column when it is at the side).
    private func canvasRect(_ geo: GeometryProxy) -> CGRect {
        let full = CGRect(origin: .zero, size: geo.size)
        if let c = Metrics.shared.canvas {
            let o = geo.frame(in: .global).origin
            let r = c.offsetBy(dx: -o.x, dy: -o.y).intersection(full)
            if !r.isNull, r.width >= 120, r.height >= 120 { return r }
        }
        let bp = model.breakpoints
        if model.edit.focus || model.edit.controlsHidden || bp.editControlsBelow { return full }
        return CGRect(x: 0, y: 0, width: max(1, geo.size.width - bp.editControlsWidth(s)), height: geo.size.height)
    }
}

/// `edit.toast`: the latest message (R's explanation, what a variation did), over the bottom of
/// the canvas. It stays 3.5 s (`toastScheduleExpiry`), then fades. Never takes a click.
private struct ToastView: View {
    @Environment(\.luminaScale) private var s
    let text: String
    var body: some View {
        Text(text).font(LuminaFont.small(s, id: AccessibilityID.Edit.toast)).foregroundStyle(LuminaColor.textPrimary)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12.scaled(s)).padding(.vertical, 6.scaled(s))
            .background(RoundedRectangle(cornerRadius: 14.scaled(s), style: .continuous).fill(LuminaColor.overlayChip))
            // The chip is the canvas's own colour: a hairline keeps it readable off the photo.
            .overlay(RoundedRectangle(cornerRadius: 14.scaled(s), style: .continuous).strokeBorder(LuminaColor.fill12, lineWidth: 1))
            .padding(.horizontal, 16.scaled(s)).padding(.bottom, 24.scaled(s))
            .luminaStatus(AccessibilityID.Edit.toast, text)
            .allowsHitTesting(false)
    }
}

/// The white picker is on: "Pick white · click something neutral…" at the canvas's top left.
/// A click on it (or Esc) switches the picker off.
private struct PickerChip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    var body: some View {
        Button { model.pickerCancel() } label: {
            HStack(spacing: 8.scaled(s)) {
                Text(OverlayCopy.pickerTitle).font(LuminaFont.small(s, .bold)).foregroundStyle(LuminaColor.textPrimary).fixedSize()
                Text(OverlayCopy.pickerHint).font(LuminaFont.small(s)).foregroundStyle(LuminaColor.textSecondary).lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, 10.scaled(s)).frame(height: LuminaHeight.chip.scaled(s))
            .background(Capsule().fill(LuminaColor.overlayScrim))
            .frame(minHeight: LuminaHeight.minHit.scaled(s)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(OverlayID.picker)
        .accessibilityLabel("\(OverlayCopy.pickerTitle), \(OverlayCopy.pickerHint)")
    }
}
