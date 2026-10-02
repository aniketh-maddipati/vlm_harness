import SwiftUI
import AppKit
import LuminaCore

// WP-5. The controls column (README §3): header, the histogram, tools, sections, sliders, the hint
// line and the bottom bar with the save status. Its width and where it sits are the canvas's
// (WP-4); it fills what it is given and scrolls its sliders inside. Every action is a model
// function; nothing here reads the keyboard.

public struct EditControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @State private var swipes = SliderSwipeMonitor()
    /// The width the canvas gave the column (it decides; the rows and tools adapt).
    @State private var width: CGFloat?
    public init() {}

    public var body: some View {
        let m = EditControlMetrics(model.windowSize, s, width: width ?? model.breakpoints.editControlsWidth(s))
        let collapsed = m.below && model.edit.controlsCollapsed
        VStack(alignment: .leading, spacing: m.gap) {
            EditControlsHeader(m: m)
            if let w = model.edit.warning, !w.isEmpty { EditWarningLine(text: w) }
            if !collapsed {
                if model.histogramShown { EditHistogramPanel() }
                EditToolsRow(m: m)
                EditSectionTabs(m: m)
                ScrollView(.vertical) { EditSliderList(m: m).padding(.horizontal, m.rowInset) }
                    .padding(.horizontal, -m.rowInset)
                    .frame(maxHeight: .infinity, alignment: .top)
                EditHintLine()
            }
            EditBottomBar(m: m)
        }
        .padding(.top, m.padTop).padding(.horizontal, m.padSide).padding(.bottom, m.padBottom)
        .frame(maxWidth: .infinity, maxHeight: m.below ? nil : .infinity, alignment: .top)
        .background(LuminaColor.bgPanel)
        .background(GeometryReader { g in
            Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w }
        })
        // The inset hairline: on the left edge beside the photo, on top when the column sits below it.
        .overlay(alignment: m.below ? .top : .leading) {
            LuminaColor.hairline.frame(width: m.below ? nil : 1, height: m.below ? 1 : nil).allowsHitTesting(false)
        }
        .onAppear { swipes.install(model) }
        .onDisappear { swipes.remove(); if model.edit.hoverKey != nil { model.edit.hoverKey = nil } }
        // Esc while a slider is being dragged cancels the drag (the key reaches the model first).
        .onChange(of: model.heldKeys.contains("escape")) { _, down in if down { model.cancelSliderDrag() } }
    }
}

/// The column's sizes: the design's numbers × S, tighter on small windows as in the prototype.
struct EditControlMetrics {
    let s: CGFloat, small: Bool, below: Bool, twoColumns: Bool, wideTools: Bool, keyHints: Bool
    init(_ window: CGSize, _ s: CGFloat, width: CGFloat) {
        self.s = s
        small = window.width < 1100 || window.height < 760
        below = window.width < 860
        // Under the photo the column is as wide as the window: sliders in two columns, tools in one row.
        twoColumns = below && width >= 536 * s
        wideTools = width >= 440 * s
        keyHints = !below && !small && window.width * 0.23 >= 300
    }
    var gap: CGFloat { (small ? 6 : 8).scaled(s) }
    var padTop: CGFloat { (small ? 10 : 14).scaled(s) }
    var padSide: CGFloat { (small ? 12 : 16).scaled(s) }
    var padBottom: CGFloat { (small ? 8 : 12).scaled(s) }
    /// Slider rows reach 8pt into the column's padding, so their hover fill has room around the text.
    var rowInset: CGFloat { 8.scaled(s) }
    /// Hit targets are never under 28pt × S (R-54).
    var hit: CGFloat { LuminaHeight.minHit.scaled(s) }
    var tool: CGFloat { (small ? 28 : 30).scaled(s) }
    var button: CGFloat { (small ? 28 : 32).scaled(s) }
    /// A slider row: the label line (a 28pt hit target for the number) and the 12pt thumb line.
    var row: CGFloat { (small ? 40 : 44).scaled(s) }
}

/// `edit.warning`: storage full, another window, offline.
struct EditWarningLine: View {
    @Environment(\.luminaScale) private var s
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8.scaled(s)) {
            Circle().fill(LuminaColor.errorDot).frame(width: 6.scaled(s), height: 6.scaled(s)).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(text).font(LuminaFont.small(s, id: AccessibilityID.Edit.warning)).foregroundStyle(LuminaColor.errorText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10.scaled(s)).padding(.vertical, 6.scaled(s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: LuminaRadius.buttonSecondary.scaled(s), style: .continuous).fill(LuminaColor.errorBg))
        .luminaStatus(AccessibilityID.Edit.warning, text)
        .transition(.opacity)
    }
}

/// `edit.hint`: what the slider under the pointer does. The space is always there, sized for the
/// longest hint, so nothing moves when the pointer crosses the sliders.
struct EditHintLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        // A slider's hint, or a clipping marker's words.
        let text = model.editHintText
        Text(EditFormat.hint("lum_magenta")).font(LuminaFont.small(s)).fixedSize(horizontal: false, vertical: true).hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                Text(text).font(LuminaFont.small(s, id: AccessibilityID.Edit.hint)).foregroundStyle(LuminaColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(LuminaMotion.panelFade(reduce), value: text.isEmpty)
            }
            .luminaStatus(AccessibilityID.Edit.hint, text)
    }
}

/// A horizontal two-finger swipe over a slider adjusts it (KEYMAP "Mouse and trackpad"). The row
/// under the pointer is `edit.hoverKey`; vertical scrolling still scrolls the column.
@MainActor
final class SliderSwipeMonitor {
    private var monitor: Any?
    func install(_ model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak model] e in
            guard let model, model.step == .edit, model.edit.overlay == nil, let key = model.edit.hoverKey else { return e }
            let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
            guard !e.modifierFlags.contains(.control), abs(dx) > abs(dy) else { return e }
            // The glide after the fingers lift isn't the user moving the slider.
            guard e.momentumPhase.isEmpty else { return nil }
            // The thumb follows the fingers, whichever way the system scrolls content.
            let towardsRight = (e.isDirectionInvertedFromDevice ? dx : -dx) * (e.hasPreciseScrollingDeltas ? 1 : 8)
            model.sliderSwipe(key, by: Double(towardsRight))
            return nil
        }
    }
    func remove() { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }
}
