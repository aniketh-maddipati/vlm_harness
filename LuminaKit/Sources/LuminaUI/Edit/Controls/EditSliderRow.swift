import SwiftUI
import AppKit
import LuminaCore

// WP-5. The sliders of the open section, and the slider row itself, to the README's spec:
// track 2.5 → 4pt on hover, fill from the default, default tick, thumb springs, drag (⇧ ¼, ⌥ 1/10,
// snap to the default, Esc cancels), double-click resets, click the number to type.

struct EditSliderList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let m: EditControlMetrics

    var body: some View {
        let section = model.edit.section, settings = model.visibleSettings
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2.scaled(s)), count: m.twoColumns ? 2 : 1)
        VStack(alignment: .leading, spacing: 4.scaled(s)) {
            if section == .colour {
                EditSegments(items: EditSetting.colourAxes.map { axis in
                    .init(id: nil, title: EditFormat.axisName(axis), selected: model.edit.colourAxis == axis) { model.setColourAxis(axis) }
                }, height: m.hit)
                .padding(.bottom, 2.scaled(s))
            }
            if model.editCur != nil {
                LazyVGrid(columns: cols, spacing: 0) {
                    ForEach(settings, id: \.key) { EditSliderRow(setting: $0, m: m) }
                }
                if model.changedCount(section) > 0 {
                    HStack {
                        Spacer(minLength: 0)
                        Button("Reset \(section.rawValue)") { model.resetSection() }
                            .buttonStyle(LuminaLinkButtonStyle())
                            .help("Put every \(section.rawValue) setting back to as shot · ⌘Z undoes it")
                    }
                }
            }
        }
        .padding(.top, 4.scaled(s)).padding(.bottom, 8.scaled(s))
    }
}

struct EditSliderRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduce
    let setting: EditSetting
    let m: EditControlMetrics

    @State private var hover = false
    @State private var valueHover = false
    /// The pointer's x at the last drag tick; nil when no drag has started on this row.
    @State private var lastX: CGFloat?
    @State private var trackWidth: CGFloat = 200
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let key = setting.key, v = model.value(key)
        let drag = model.editControls.drag.flatMap { $0.key == key ? $0 : nil }
        let dragging = drag != nil, snapped = drag?.snapped ?? false
        let changed = v != setting.def
        let chosen = model.editControls.keyboardChoosing && model.edit.hoverKey == nil && model.activeSettingKey == key
        let label = EditFormat.label(key), shown = EditFormat.value(key, v)
        let tone = chosen ? LuminaColor.accentGold : changed ? LuminaColor.textPrimary : LuminaColor.textTertiary

        VStack(spacing: 0) {
            HStack(spacing: 6.scaled(s)) {
                if let c = EditFormat.colour(of: key).flatMap({ LuminaColor.swatch[$0] }) {
                    Circle().fill(c).frame(width: 8.scaled(s), height: 8.scaled(s))
                }
                Text(setting.label).font(LuminaFont.small(s)).foregroundStyle(tone).lineLimit(1)
                    .accessibilityHidden(true)
                Spacer(minLength: 4.scaled(s))
                if key == "wb" { whitePicker }
                if model.edit.typingKey == key { field(label) } else { number(shown, label: label, colour: dragging ? LuminaColor.primaryHover : tone) }
            }
            .frame(height: m.hit)
            track(v: v, dragging: dragging, snapped: snapped, changed: changed, chosen: chosen)
                .frame(height: 12.scaled(s))
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(AccessibilityID.Edit.slider(key))
                .accessibilityLabel(label).accessibilityValue(shown)
                .accessibilityAdjustableAction { d in model.nudgeSetting(key, d == .increment ? 1 : -1, coarse: false) }
        }
        .frame(height: m.row)
        .padding(.horizontal, m.rowInset)
        .background(RoundedRectangle(cornerRadius: LuminaRadius.pill.scaled(s), style: .continuous)
            .fill(dragging ? LuminaColor.fill07 : hover ? LuminaColor.fill04 : .clear))
        .contentShape(Rectangle())
        .onHover { inside in
            hover = inside
            if inside { model.edit.hoverKey = key } else if model.edit.hoverKey == key { model.edit.hoverKey = nil }
        }
        .onDisappear { if model.edit.hoverKey == key { model.edit.hoverKey = nil } }
        .gesture(DragGesture(minimumDistance: 3)
            .onChanged { g in
                guard let last = lastX else {
                    // The first 3pt only start the drag, so a click never moves the value.
                    lastX = g.location.x; model.sliderDragBegan(key); return
                }
                lastX = g.location.x
                let flags = NSEvent.modifierFlags
                model.sliderDragMoved(by: Double((g.location.x - last) / max(trackWidth, 160.scaled(s))),
                                      fine: flags.contains(.shift), finer: flags.contains(.option))
            }
            .onEnded { _ in if lastX != nil { lastX = nil; model.sliderDragEnded() } })
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.resetSetting(key) })
        .animation(LuminaMotion.panelFade(reduce), value: hover)
        .accessibilityElement(children: .contain)
    }

    // MARK: the number

    private func number(_ shown: String, label: String, colour: Color) -> some View {
        Button { model.beginTyping(setting.key) } label: {
            Text(shown).font(LuminaFont.mono(LuminaFontSize.small, s)).foregroundStyle(colour).lineLimit(1)
                .padding(.horizontal, 5.scaled(s)).padding(.vertical, 2.scaled(s))
                .background(RoundedRectangle(cornerRadius: 4.scaled(s), style: .continuous).fill(valueHover ? LuminaColor.bgApp : .clear))
                .overlay(RoundedRectangle(cornerRadius: 4.scaled(s), style: .continuous).strokeBorder(valueHover ? LuminaColor.fill24 : .clear, lineWidth: 1))
                .frame(minWidth: m.hit, minHeight: m.hit, alignment: .trailing)
                .padding(.trailing, -5.scaled(s))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { valueHover = $0 }
        .help("Click to type a value")
        .accessibilityIdentifier(AccessibilityID.Edit.value(setting.key))
        .accessibilityLabel("Type \(label)").accessibilityValue(shown)
    }

    private func field(_ label: String) -> some View {
        TextField("", text: $text)
            .textFieldStyle(.plain).font(LuminaFont.mono(LuminaFontSize.small, s)).multilineTextAlignment(.trailing)
            .foregroundStyle(LuminaColor.textPrimary)
            .padding(.horizontal, 6.scaled(s))
            .frame(width: 64.scaled(s), height: 20.scaled(s))
            .background(RoundedRectangle(cornerRadius: 5.scaled(s), style: .continuous).fill(LuminaColor.bgApp))
            .overlay(RoundedRectangle(cornerRadius: 5.scaled(s), style: .continuous).strokeBorder(LuminaColor.accentGold, lineWidth: 1))
            .focused($fieldFocused)
            .onAppear { text = EditFormat.editable(setting.key, model.value(setting.key)); fieldFocused = true }
            .onSubmit { model.commitTyping(text) }
            .onExitCommand { model.cancelTyping() }
            // Clicking elsewhere keeps what was typed, as leaving a field does.
            .onChange(of: fieldFocused) { _, focused in if !focused, model.edit.typingKey == setting.key { model.commitTyping(text) } }
            .accessibilityIdentifier(AccessibilityID.Edit.valueField)
            .accessibilityLabel(label)
    }

    /// Temperature's "pick white" button (W).
    private var whitePicker: some View {
        let on = model.edit.pickingWhite
        return Button { model.pickWhite() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5.scaled(s), style: .continuous).fill(on ? LuminaColor.accentGold : LuminaColor.fill08)
                    .frame(width: 18.scaled(s), height: 18.scaled(s))
                Circle().strokeBorder(on ? LuminaColor.textOnPrimary : LuminaColor.textSecondary, lineWidth: 1.3)
                    .frame(width: 7.scaled(s), height: 7.scaled(s))
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(on ? LuminaColor.textOnPrimary : LuminaColor.textSecondary)
                        .frame(width: 1.3, height: 2.scaled(s)).offset(y: -5.scaled(s)).rotationEffect(.degrees(Double(i) * 90))
                }
            }
            .frame(width: m.hit, height: m.hit).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Pick white · W · click something that should be neutral grey")
        .accessibilityLabel("Pick white").accessibilityValue(on ? "on" : "off")
    }

    // MARK: the track

    private func track(v: Double, dragging: Bool, snapped: Bool, changed: Bool, chosen: Bool) -> some View {
        let q = SliderScale.position(setting, v), z = SliderScale.position(setting, setting.def)
        let lit = hover || dragging
        let th = (lit ? LuminaSlider.trackHover : LuminaSlider.track) * s
        let tick = (dragging && snapped ? LuminaSlider.zeroTickSnapped : LuminaSlider.zeroTick) * s
        let scale = dragging ? (snapped ? LuminaMotion.thumbScaleSnapped : LuminaMotion.thumbScaleDrag) : hover ? LuminaMotion.thumbScaleHover : 1
        let move = dragging ? nil : LuminaMotion.sliderFill(reduce)
        let thumb = 12.scaled(s)
        return GeometryReader { geo in
            let w = geo.size.width, mid = geo.size.height / 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: LuminaRadius.thumbInner).fill(lit ? LuminaColor.fill22 : LuminaColor.fill13)
                    .frame(width: w, height: th).offset(y: mid - th / 2)
                RoundedRectangle(cornerRadius: LuminaRadius.thumbInner).fill(chosen ? LuminaColor.accentGold : changed ? LuminaColor.textPrimary : LuminaColor.textDisabled)
                    .frame(width: max(1, abs(q - z) * w), height: th).offset(x: min(q, z) * w, y: mid - th / 2)
                    .animation(move, value: q)
                Rectangle().fill(dragging && snapped ? LuminaColor.textPrimary : LuminaColor.fill35)
                    .frame(width: 1, height: tick).offset(x: z * w - 0.5, y: mid - tick / 2)
                Circle().fill(LuminaColor.textPrimary)
                    .frame(width: thumb, height: thumb)
                    .background(Circle().fill(dragging ? LuminaColor.accentGoldGlow : .clear).padding(-3 * s))
                    .shadow(color: LuminaColor.shadowTabThumb, radius: 1, y: 1)
                    .scaleEffect(scale).animation(LuminaMotion.thumbScale(reduce), value: scale)
                    .offset(x: q * w - thumb / 2, y: mid - thumb / 2)
                    .animation(move, value: q)
            }
            .onAppear { trackWidth = w }
            .onChange(of: w) { _, new in trackWidth = new }
        }
    }
}
