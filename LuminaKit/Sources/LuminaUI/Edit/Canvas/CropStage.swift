import SwiftUI
import LuminaCore

// WP-4. Crop and straighten on the canvas (README §3 "Crop"; R-24): the whole turned and
// straightened frame shows (`canvasLook`), the box over it with a rule-of-thirds grid, the
// outside dimmed. Corners resize (held to the ratio unless Free), the inside moves, and in
// Straighten mode a line drawn along the horizon levels the picture. The toolbar has the ratio
// menu (with the portrait / landscape swap), the angle, Turn, Cancel and Done. Every change is a
// model function, so it lands in Crop's own undo (⌘Z / Q inside Crop).

struct CropStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// The turned frame on the canvas, in the stage's coordinates.
    let frame: CGRect
    @State private var dragStart: CropBox?
    @State private var lineStart: CGPoint?
    @State private var lineEnd: CGPoint?

    private static let space = "lumina.cropStage"
    enum Corner: CaseIterable { case tl, tr, bl, br }

    var body: some View {
        let b = CropBox(model.edit.cropDraft)
        let box = CGRect(x: frame.minX + b.x * frame.width, y: frame.minY + b.y * frame.height,
                         width: b.w * frame.width, height: b.h * frame.height)
        ZStack(alignment: .topLeading) {
            // Outside the box: the canvas colour at 64 %. The canvas clips what reaches past it.
            Path { p in
                p.addRect(CGRect(x: -4000, y: -4000, width: 8000, height: 8000))
                p.addRect(box)
            }
            .fill(LuminaColor.bgCanvas.opacity(0.64), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            CropBoxView(dragging: dragStart != nil)
                .frame(width: max(1, box.width), height: max(1, box.height))
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .position(x: box.midX, y: box.midY)

            ForEach(Corner.allCases, id: \.self) { c in
                CropHandle(corner: c)
                    .frame(width: 24.scaled(s), height: 24.scaled(s))
                    .contentShape(Rectangle())
                    .gesture(cornerGesture(c))
                    .position(point(c, of: box))
            }

            if model.edit.straightening { straightenLayer }

            CropToolbar()
                .padding(.top, 10.scaled(s))
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .coordinateSpace(.named(Self.space))
        .animation(dragStart == nil ? LuminaMotion.cropBox(reduce) : nil, value: b)
    }

    private func point(_ c: Corner, of r: CGRect) -> CGPoint {
        switch c {
        case .tl: CGPoint(x: r.minX + 4, y: r.minY + 4)
        case .tr: CGPoint(x: r.maxX - 4, y: r.minY + 4)
        case .bl: CGPoint(x: r.minX + 4, y: r.maxY - 4)
        case .br: CGPoint(x: r.maxX - 4, y: r.maxY - 4)
        }
    }

    // MARK: dragging the box

    /// Resize from a corner; the opposite corner stays put. A ratio other than Free holds the
    /// box's real proportions; nothing leaves the frame.
    private func cornerGesture(_ c: Corner) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .onChanged { v in
                let first = dragStart == nil
                let b0 = dragStart ?? CropBox(model.edit.cropDraft)
                if first { dragStart = b0 }
                guard frame.width > 0, frame.height > 0 else { return }
                let fx = Double(v.translation.width / frame.width), fy = Double(v.translation.height / frame.height)
                var x0 = b0.x, y0 = b0.y, x1 = b0.x + b0.w, y1 = b0.y + b0.h
                switch c {
                case .tl: x0 += fx; y0 += fy
                case .tr: x1 += fx; y0 += fy
                case .bl: x0 += fx; y1 += fy
                case .br: x1 += fx; y1 += fy
                }
                let left = c == .tl || c == .bl, top = c == .tl || c == .tr
                // The fixed corner, and the room the moving one has from it.
                let ax = left ? b0.x + b0.w : b0.x, ay = top ? b0.y + b0.h : b0.y
                let roomW = left ? ax : 1 - ax, roomH = top ? ay : 1 - ay
                var w = min(roomW, max(0.05, left ? ax - x0 : x1 - ax))
                var h = min(roomH, max(0.05, top ? ay - y0 : y1 - ay))
                if let r = model.cropLockedRatio, r > 0 {
                    let fa = Double(frame.width / frame.height)
                    h = w * fa / r
                    if h > roomH { h = roomH; w = h * r / fa }
                }
                model.setCropRect(x: left ? ax - w : ax, y: top ? ay - h : ay, w: w, h: h, first: first)
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Move the whole box.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .onChanged { v in
                guard !model.edit.straightening else { return }
                let first = dragStart == nil
                let b0 = dragStart ?? CropBox(model.edit.cropDraft)
                if first { dragStart = b0 }
                guard frame.width > 0, frame.height > 0 else { return }
                let x = clamp(0, b0.x + Double(v.translation.width / frame.width), 1 - b0.w)
                let y = clamp(0, b0.y + Double(v.translation.height / frame.height), 1 - b0.h)
                model.setCropRect(x: x, y: y, w: b0.w, h: b0.h, first: first)
            }
            .onEnded { _ in dragStart = nil }
    }

    // MARK: straighten

    /// S: draw along a line that should be level or upright.
    private var straightenLayer: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { v in lineStart = v.startLocation; lineEnd = v.location }
                    .onEnded { v in
                        lineStart = nil; lineEnd = nil
                        model.straightenAlong(dx: Double(v.location.x - v.startLocation.x), dy: Double(v.location.y - v.startLocation.y))
                    })
            if let a = lineStart, let b = lineEnd {
                Path { p in p.move(to: a); p.addLine(to: b) }
                    .stroke(LuminaColor.bgCanvas, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .allowsHitTesting(false)
                Path { p in p.move(to: a); p.addLine(to: b) }
                    .stroke(LuminaColor.accentGold, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 5]))
                    .allowsHitTesting(false)
                Circle().fill(LuminaColor.accentGold).frame(width: 8, height: 8).position(a).allowsHitTesting(false)
                Circle().fill(LuminaColor.accentGold).frame(width: 8, height: 8).position(b).allowsHitTesting(false)
            }
        }
    }
}

/// The box: a 1pt outline and the rule-of-thirds grid.
private struct CropBoxView: View {
    let dragging: Bool
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                Path { p in
                    for k in [1.0 / 3, 2.0 / 3] {
                        p.move(to: CGPoint(x: w * k, y: 0)); p.addLine(to: CGPoint(x: w * k, y: h))
                        p.move(to: CGPoint(x: 0, y: h * k)); p.addLine(to: CGPoint(x: w, y: h * k))
                    }
                }
                .stroke(LuminaColor.textPrimary.opacity(dragging ? 0.45 : 0.3), lineWidth: 1)
                Rectangle().strokeBorder(LuminaColor.textPrimary.opacity(0.9), lineWidth: 1)
            }
        }
    }
}

/// A corner: two 3pt strokes, 18pt long.
private struct CropHandle: View {
    @Environment(\.luminaScale) private var s
    let corner: CropStage.Corner
    var body: some View {
        let len = 18.scaled(s)
        Path { p in
            let right = corner == .tr || corner == .br, bottom = corner == .bl || corner == .br
            let x0: CGFloat = right ? len : 0, y0: CGFloat = bottom ? len : 0
            p.move(to: CGPoint(x: right ? 0 : len, y: y0)); p.addLine(to: CGPoint(x: x0, y: y0))
            p.addLine(to: CGPoint(x: x0, y: bottom ? 0 : len))
        }
        .stroke(LuminaColor.textPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .square, lineJoin: .miter))
        .frame(width: len, height: len)
    }
}

/// Ratio ▾ · Straighten {angle} · Turn ↻ · Cancel esc · Done ⏎.
struct CropToolbar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        let angle = CropBox(model.edit.cropDraft).angle
        HStack(spacing: 4.scaled(s)) {
            Menu {
                ForEach(CropBox.ratios, id: \.self) { name in
                    Button { model.setCropRatio(name) } label: {
                        if model.edit.cropRatio == name { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
                Divider()
                Button("Portrait ↔ landscape") { model.cropSwapRatio() }
            } label: {
                Text(model.edit.cropRatio).font(LuminaFont.small(s, .semibold))
            }
            .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
            .padding(.horizontal, 9.scaled(s)).frame(height: LuminaHeight.chip.scaled(s))
            .background(RoundedRectangle(cornerRadius: LuminaRadius.pill.scaled(s), style: .continuous).fill(LuminaColor.fill10))
            .accessibilityIdentifier(AccessibilityID.Edit.cropRatio)
            .accessibilityLabel("Ratio \(model.edit.cropRatio)")

            toolButton(on: model.edit.straightening, action: { model.straighten() }) {
                HStack(spacing: 6.scaled(s)) {
                    Text("Straighten")
                    Text(String(format: "%+.1f°", angle)).font(LuminaFont.mono(LuminaFontSize.hint, s)).opacity(0.8)
                    KeyHint("S")
                }
            }
            Slider(value: Binding(get: { CropBox(model.edit.cropDraft).angle }, set: { model.setCropAngle($0) }), in: -45...45)
                .controlSize(.mini).frame(width: 90.scaled(s))
                .accessibilityLabel("Straighten angle")
            toolButton(on: false, action: { model.cropRotate(1) }) {
                HStack(spacing: 5.scaled(s)) { Text("Turn"); Text("↻").font(LuminaFont.ui(LuminaFontSize.title3, .bold, s)) }
            }
            .accessibilityLabel("Turn right")
            toolButton(on: false, action: { model.cropCancel() }) { HStack(spacing: 6.scaled(s)) { Text("Cancel"); KeyHint("esc") } }
            Button { model.cropKeep() } label: { HStack(spacing: 6.scaled(s)) { Text("Done"); KeyHint("⏎") } }
                .buttonStyle(LuminaPrimaryButtonStyle(height: LuminaHeight.chip, radius: LuminaRadius.pill, fontSize: LuminaFontSize.small, padding: 9))
        }
        .padding(4.scaled(s))
        .background(RoundedRectangle(cornerRadius: LuminaRadius.segmented.scaled(s), style: .continuous).fill(LuminaColor.overlayScrim))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Edit.crop)
    }

    private func toolButton<L: View>(on: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label().font(LuminaFont.small(s, .semibold))
                .foregroundStyle(on ? LuminaColor.textOnPrimary : LuminaColor.textPrimary)
                .padding(.horizontal, 8.scaled(s)).frame(height: LuminaHeight.chip.scaled(s))
                .background(RoundedRectangle(cornerRadius: LuminaRadius.pill.scaled(s), style: .continuous)
                    .fill(on ? LuminaColor.accentGold : LuminaColor.fill04))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
