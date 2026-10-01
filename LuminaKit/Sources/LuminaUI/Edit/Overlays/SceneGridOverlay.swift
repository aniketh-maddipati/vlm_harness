import SwiftUI
import LuminaCore

// WP-6. The scene grid (`Overlay.sceneGrid`): the kept photos of the current photo's scene, each
// with its edit; click one to open it. Esc closes it (`editEscape`).

struct SceneGridOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let grid: (title: String, subtitle: String, ids: [String])

    var body: some View {
        VStack(alignment: .leading, spacing: 8.scaled(s)) {
            HStack(spacing: 10.scaled(s)) {
                Text(grid.title).font(LuminaFont.small(s, .bold)).foregroundStyle(LuminaColor.accentGold).lineLimit(1).layoutPriority(1)
                Text(grid.subtitle).font(LuminaFont.small(s)).foregroundStyle(LuminaColor.textSecondary).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Button { model.sceneGridClose() } label: { Text("Cancel esc") }
                    .buttonStyle(OverlayChipButtonStyle()).accessibilityIdentifier(OverlayID.sceneGridCancel).accessibilityLabel("Cancel")
            }
            GeometryReader { geo in cells(geo.size) }
        }
        .padding(10.scaled(s))
        .background(LuminaColor.bgCanvas)
        .contentShape(Rectangle()).onTapGesture {}
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(OverlayID.sceneGrid)
        .accessibilityLabel(grid.title)
    }

    private func cells(_ size: CGSize) -> some View {
        let n = grid.ids.count, gap = LuminaSpacing.tileGap.scaled(s)
        // The prototype's shape: about 3:2 cells whatever the canvas.
        let cols = max(1, min(n, Int((Double(n) * 1.6 * Double(size.width / max(size.height, 1)) / 1.5).squareRoot().rounded(.up))))
        let rows = max(1, (n + cols - 1) / cols)
        let w = max(1, (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)), h = max(1, (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
        return VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<cols, id: \.self) { c in
                        let i = r * cols + c
                        if i < n, let p = model.shoot.photo(grid.ids[i]) { cell(p, width: w, height: h) }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func cell(_ p: Photo, width: CGFloat, height: CGFloat) -> some View {
        let key = model.edits.key(for: p.id, decisions: model.decisions)
        let current = p.id == model.editCur, done = model.edits.done.contains(key)
        let name = p.file.hasPrefix("DSC") && p.file.count > 3 ? String(p.file.dropFirst(3)) : p.file
        return ZStack {
            LuminaColor.bgPanel
            LookThumb(photo: p, look: model.edits.look(p.id, decisions: model.decisions), maxPoint: max(width, height))
            if done {
                Text("✓").font(LuminaFont.ui(LuminaFontSize.hint, .bold, s)).foregroundStyle(LuminaColor.textOnPrimary)
                    .frame(width: 16.scaled(s), height: 16.scaled(s)).background(Circle().fill(LuminaColor.accentGold))
                    .padding(5.scaled(s)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            CellLabel(text: name, selected: current).padding(5.scaled(s))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.photo.scaled(s)))
        .modifier(SelectedRing(on: current))
        .contentShape(Rectangle())
        .onTapGesture { model.sceneGridPick(p.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(OverlayID.sceneCell(p.id))
        .accessibilityLabel(p.file + (done ? ", done" : ""))
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.sceneGridPick(p.id) }
    }
}
