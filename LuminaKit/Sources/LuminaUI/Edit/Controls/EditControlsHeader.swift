import SwiftUI
import LuminaCore

// WP-5. The top of the controls column: file name and tag, Undo, Redo, More; the tools row;
// the section tabs.

/// A small square-ish button on the 0.07 fill (Undo, Redo, More, the tools).
struct EditChipButtonStyle: ButtonStyle {
    var on = false, tint: Color? = nil, radius: CGFloat = LuminaRadius.pill
    func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration, style: self) }
    private struct Content: View {
        let configuration: Configuration; let style: EditChipButtonStyle
        @Environment(\.luminaScale) private var s
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: style.radius.scaled(s), style: .continuous)
            configuration.label
                .foregroundStyle(!enabled ? LuminaColor.textDisabled : style.on ? LuminaColor.textOnPrimary : style.tint ?? LuminaColor.textPrimary)
                .background(shape.fill(style.on ? LuminaColor.primaryFill : style.tint != nil ? LuminaColor.accentGoldTint : hover && enabled ? LuminaColor.fill16 : LuminaColor.fill07))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Rectangle()).onHover { hover = $0 }
        }
    }
}

struct EditControlsHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let m: EditControlMetrics

    var body: some View {
        let cropping = model.edit.overlay == .crop
        let edited = model.editCur.map { model.edits.isEdited($0, decisions: model.decisions) } ?? false
        // Kept burst frames share one edit: the header says how many this edit lands on.
        let shared = model.editCur.map { model.edits.sharedBy($0, decisions: model.decisions) } ?? 1
        HStack(spacing: 6.scaled(s)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.shoot.photo(model.editCur)?.file ?? "–").font(LuminaFont.body(s, .bold)).foregroundStyle(LuminaColor.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                Text(model.editTag + (shared > 1 ? " · burst ×\(shared)" : "")).font(LuminaFont.small(s)).foregroundStyle(edited ? LuminaColor.textPrimary : LuminaColor.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            icon("↶", size: LuminaFontSize.overlayTitle, label: "Undo", help: cropping ? "Undo crop step · ⌘Z" : "Undo · ⌘Z", id: AccessibilityID.Edit.undo) {
                if cropping { model.cropUndo() } else { model.editUndo() }
            }
            .disabled(!cropping && !model.edits.canUndo)
            icon("↷", size: LuminaFontSize.overlayTitle, label: "Redo", help: cropping ? "Redo crop step · ⇧⌘Z" : "Redo · ⇧⌘Z", id: AccessibilityID.Edit.redo) {
                if cropping { model.cropRedo() } else { model.editRedo() }
            }
            .disabled(!cropping && !model.edits.canRedo)

            Menu {
                Button("Copy settings    ⌘C") { model.copySettings() }.disabled(!edited)
                Button("Paste settings    ⌘V") { model.pasteSettings() }.disabled(model.editControls.clipboard == nil)
                Button("Same as last photo    =") { model.sameAsLast() }.disabled(model.editControls.lastLook == nil)
                Divider()
                Button("Reset all to as shot    ⇧0") { model.resetAll() }.disabled(!edited)
            } label: {
                Text("⋯").font(LuminaFont.ui(LuminaFontSize.title2, .bold, s)).frame(width: m.hit, height: m.hit)
            }
            .menuStyle(.button).buttonStyle(EditChipButtonStyle()).menuIndicator(.hidden).fixedSize()
            .disabled(model.editCur == nil)
            .help("Copy, paste and reset")
            .accessibilityLabel("More")

            if m.below {
                Button { model.edit.controlsCollapsed.toggle() } label: {
                    Text(model.edit.controlsCollapsed ? "Show ▴" : "Hide ▾").font(LuminaFont.small(s))
                        .padding(.horizontal, 8.scaled(s)).frame(height: m.hit)
                }
                .buttonStyle(EditChipButtonStyle(radius: LuminaRadius.chip))
                .accessibilityLabel(model.edit.controlsCollapsed ? "Show controls" : "Hide controls")
            }
        }
    }

    private func icon(_ glyph: String, size: CGFloat, label: String, help: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(LuminaFont.ui(size, .bold, s)).frame(width: m.hit, height: m.hit)
        }
        .buttonStyle(EditChipButtonStyle())
        .help(help).accessibilityLabel(label).accessibilityIdentifier(id)
    }
}

/// Auto (A) · Crop (C) · Before (a switch) · Variations (V).
struct EditToolsRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduce
    let m: EditControlMetrics

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4.scaled(s)), count: m.wideTools ? 4 : 2)
        let before = model.edit.before, variations = model.edit.overlay == .variations
        LazyVGrid(columns: cols, spacing: 4.scaled(s)) {
            tool(model.autoCanUndo ? "Undo Auto" : "Auto", key: "A", id: "auto", help: "Auto exposure and white balance · A · press again to undo") { model.auto() }
            tool("Crop", key: "C", on: model.edit.overlay == .crop, id: "crop", help: "Crop and straighten · C") {
                if model.edit.overlay == .crop { model.cropKeep() } else { model.cropOpen() }
            }
            Button { model.edit.before.toggle() } label: {
                HStack(spacing: 6.scaled(s)) {
                    Text("Before").font(LuminaFont.small(s, .semibold)).lineLimit(1)
                    Capsule().fill(before ? LuminaColor.accentGold : LuminaColor.fill22)
                        .frame(width: 20.scaled(s), height: 11.scaled(s))
                        .overlay(alignment: .leading) {
                            Circle().fill(before ? LuminaColor.textOnPrimary : LuminaColor.textPrimary)
                                .frame(width: 7.scaled(s), height: 7.scaled(s))
                                .offset(x: (before ? 11 : 2).scaled(s))
                                .animation(LuminaMotion.sliderFill(reduce), value: before)
                        }
                }
                .frame(maxWidth: .infinity).frame(height: m.tool)
            }
            .buttonStyle(EditChipButtonStyle(tint: before ? LuminaColor.accentGold : nil))
            .help("Switch the original on or off · hold \\ to just peek")
            .accessibilityIdentifier(AccessibilityID.Edit.tool("before"))
            .accessibilityLabel("Before").accessibilityValue(before ? "on" : "off")
            .accessibilityAddTraits(before ? .isSelected : [])
            tool("Variations", key: "V", on: variations, id: "variations", help: "Quick check of the setting under the pointer, or this section’s main one · hold V, let go to apply") {
                if variations { model.variationsClose() } else { model.variationsHold(true); if model.edit.overlay == .variations { model.edit.variationSticky = true } }
            }
        }
        .disabled(model.editCur == nil)
    }

    private func tool(_ title: String, key: String, on: Bool = false, id: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // No key hint on the tools (prototype `tbar`: `kOn:false` at every size); the key is
            // in the tooltip and in Help.
            Text(title).font(LuminaFont.small(s, .semibold)).lineLimit(1)
                .padding(.horizontal, 4.scaled(s)).frame(maxWidth: .infinity).frame(height: m.tool)
        }
        .buttonStyle(EditChipButtonStyle(on: on))
        .help(help)
        .accessibilityIdentifier(AccessibilityID.Edit.tool(id)).accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Light · Curve · Colour · Effects. A dot marks a section with changes.
struct EditSectionTabs: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let m: EditControlMetrics

    var body: some View {
        EditSegments(items: EditSection.allCases.map { sec in
            let n = model.changedCount(sec), title = sec.rawValue.prefix(1).uppercased() + sec.rawValue.dropFirst()
            return .init(id: AccessibilityID.Edit.section(sec.rawValue), title: title, selected: model.edit.section == sec, dot: n > 0,
                         help: n > 0 ? "\(title) · \(n) changed" : title) { model.setSection(sec) }
        }, height: m.hit)
    }
}

/// A segmented row in the design's style (the section tabs, Colour's Hue / Saturation / Luminance).
struct EditSegments: View {
    struct Item { let id: String?; let title: String; let selected: Bool; var dot = false; var help: String? = nil; let action: () -> Void }
    @Environment(\.luminaScale) private var s
    let items: [Item]; let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in Segment(item: item, height: height) }
        }
        .padding(2.scaled(s))
        .background(RoundedRectangle(cornerRadius: LuminaRadius.buttonSecondary.scaled(s), style: .continuous).fill(LuminaColor.fill06))
    }

    private struct Segment: View {
        @Environment(\.luminaScale) private var s
        @State private var hover = false
        let item: Item; let height: CGFloat
        var body: some View {
            Button(action: item.action) {
                Text(item.title).font(LuminaFont.small(s, item.selected ? .bold : .regular)).lineLimit(1)
                    .foregroundStyle(item.selected || hover ? LuminaColor.textPrimary : LuminaColor.textSecondary)
                    .frame(maxWidth: .infinity).frame(height: height)
                    .background(RoundedRectangle(cornerRadius: LuminaRadius.chip.scaled(s), style: .continuous).fill(item.selected ? LuminaColor.bgSelected : .clear))
                    .overlay(alignment: .topTrailing) {
                        if item.dot { Circle().fill(LuminaColor.textPrimary).frame(width: 5.scaled(s), height: 5.scaled(s)).padding(5.scaled(s)) }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).onHover { hover = $0 }
            .help(item.help ?? item.title)
            .accessibilityLabel(item.title)
            .accessibilityAddTraits(item.selected ? .isSelected : [])
            .modifier(OptionalID(id: item.id))
        }
    }
}

struct OptionalID: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}
