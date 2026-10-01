import SwiftUI
import LuminaCore

// WP-6. Variations (hold V): the current photo with each of the grid's values, over the canvas.
// Three cells, the 3 × 3 temperature × tint grid, or two for vignette (`Variations.spec`).
// Keys arrive through the model (KEYMAP "In Variations"); here: point, click, Apply, Cancel.

struct VariationsGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let spec: VariationSpec
    let photo: Photo
    /// Where the pointer was when the grid came up. Pointing only counts once it has moved, so
    /// a grid that opens under a resting pointer doesn't choose a cell by itself.
    @State private var pointerStart: CGPoint?
    @State private var pointerMoved = false

    private var hint: String {
        spec.kind == .grid ? OverlayCopy.whiteBalanceHint : model.overlays.held ? OverlayCopy.variationsHeldHint : OverlayCopy.variationsStickyHint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8.scaled(s)) {
            header
            GeometryReader { geo in cells(geo.size) }
        }
        .padding(10.scaled(s))
        .background(LuminaColor.bgCanvas)
        .contentShape(Rectangle()).onTapGesture {}
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Edit.variations)
        .accessibilityLabel(spec.title)
    }

    // MARK: header

    private var title: some View {
        Text(spec.title).font(LuminaFont.small(s, .bold)).foregroundStyle(LuminaColor.accentGold).lineLimit(1)
    }
    private var subtitle: some View {
        Text(hint).font(LuminaFont.small(s)).foregroundStyle(LuminaColor.textSecondary).lineLimit(1)
    }
    @ViewBuilder private var step: some View {
        if !spec.step.isEmpty { Text(spec.step).font(LuminaFont.mono(LuminaFontSize.small, s)).foregroundStyle(LuminaColor.textSecondary).lineLimit(1) }
    }
    private var buttons: some View {
        HStack(spacing: 8.scaled(s)) {
            Button { model.variationsApply() } label: { HStack(spacing: 6.scaled(s)) { Text("Apply"); KeyCap(text: "⏎", onGold: true) } }
                .buttonStyle(OverlayChipButtonStyle(kind: .gold))
                .accessibilityIdentifier(OverlayID.variationsApply).accessibilityLabel("Apply")
            Button { model.variationsClose() } label: { Text("Cancel esc") }
                .buttonStyle(OverlayChipButtonStyle())
                .accessibilityIdentifier(OverlayID.variationsCancel).accessibilityLabel("Cancel")
        }
    }
    /// One line when it fits; otherwise the words go under the title and the buttons keep their place.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10.scaled(s)) { title.fixedSize(); subtitle.fixedSize(); Spacer(minLength: 0); step.fixedSize(); buttons }
            VStack(alignment: .leading, spacing: 2.scaled(s)) {
                HStack(spacing: 10.scaled(s)) { title.fixedSize(); Spacer(minLength: 0); buttons }
                HStack(spacing: 10.scaled(s)) { subtitle.fixedSize(); Spacer(minLength: 0); step.fixedSize() }
            }
            VStack(alignment: .leading, spacing: 2.scaled(s)) {
                HStack(spacing: 10.scaled(s)) { title; Spacer(minLength: 0); step }
                subtitle
                HStack(spacing: 10.scaled(s)) { Spacer(minLength: 0); buttons }
            }
        }
    }

    // MARK: cells

    private func cells(_ size: CGSize) -> some View {
        // Side by side; in a canvas taller than wide (controls below the photo) two or three cells stack instead.
        let stacked = spec.kind != .grid && size.width < size.height * 0.9, gap = LuminaSpacing.tileGap.scaled(s)
        let cols = stacked ? 1 : max(1, spec.columns), rows = stacked ? max(1, spec.cells.count) : max(1, spec.rows)
        let w = max(1, (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)), h = max(1, (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
        let look = model.currentLook, selected = model.edit.variationIndex
        return VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<cols, id: \.self) { c in
                        let i = r * cols + c
                        if spec.cells.indices.contains(i) { cell(i, spec.cells[i], look: look, selected: i == selected, width: w, height: h) }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onContinuousHover { phase in
            guard case .active(let p) = phase else { return }
            guard let start = pointerStart else { pointerStart = p; return }
            if !pointerMoved, hypot(p.x - start.x, p.y - start.y) > 4 { pointerMoved = true }
            guard pointerMoved else { return }
            let c = Int(p.x / (w + gap)), r = Int(p.y / (h + gap)), i = r * cols + c
            if c >= 0, c < cols, r >= 0, spec.cells.indices.contains(i), i != model.edit.variationIndex { model.variationsSelect(i) }
        }
    }

    private func cell(_ i: Int, _ cell: VariationCell, look: Look, selected: Bool, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            LuminaColor.bgPanel
            LookThumb(photo: photo, look: look.merging(cell.values) { _, new in new }, maxPoint: max(width, height))
            CellLabel(text: cell.label, selected: selected).padding(6.scaled(s))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.photo.scaled(s)))
        .modifier(SelectedRing(on: selected))
        .contentShape(Rectangle())
        .onTapGesture { model.variationsPick(i) }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.Edit.variation(i))
        .accessibilityLabel(cell.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.variationsPick(i) }
    }
}
