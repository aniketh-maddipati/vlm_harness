import SwiftUI
import AppKit
import LuminaCore

// WP-4. Crop and straighten on the canvas (README §3 "Crop"; R-24): the whole turned and
// straightened frame shows (`canvasLook`), shrunk under the toolbar (`EditLayout.cropFrameRect`),
// the box over it with a rule-of-thirds grid, the outside dimmed. Corners resize (held to the
// ratio unless Free), the inside moves, a drag outside the box (the arcs at its corners show
// where) turns the picture, and in Straighten mode a line drawn along the horizon levels it. A
// crosshair through the frame's centre turns with the picture and reads the angle. The toolbar
// has the ratio menu (with the portrait / landscape swap), Straighten with the angle, Turn,
// Cancel and Apply. Every change is a model function, so it lands in Crop's own undo (⌘Z / Q
// inside Crop).

struct CropStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// The turned frame on the canvas, in the stage's coordinates.
    let frame: CGRect
    @State private var dragStart: CropBox?
    @State private var lineStart: CGPoint?
    @State private var lineEnd: CGPoint?
    /// A turn being dragged: the angle it started from, the box's centre, the pointer's bearing.
    @State private var turnStart: (angle: Double, centre: CGPoint, bearing: Double)?
    @State private var hoverArc: Corner?

    private static let space = "lumina.cropStage"
    enum Corner: CaseIterable { case tl, tr, bl, br }

    var body: some View {
        let b = CropBox(model.edit.cropDraft)
        let box = CGRect(x: frame.minX + b.x * frame.width, y: frame.minY + b.y * frame.height,
                         width: b.w * frame.width, height: b.h * frame.height)
        let arc = Self.arcSize(box)
        ZStack(alignment: .topLeading) {
            // Outside the box, a drag turns the picture about the box's centre (prototype `cropDown`).
            Color.clear.contentShape(Rectangle())
                .gesture(turnGesture(box))

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

            crosshair(b)

            ForEach(Corner.allCases, id: \.self) { c in
                CropTurnArc(corner: c, size: arc, lit: hoverArc == c || turnStart != nil)
                    .frame(width: arc, height: arc)
                    .position(corner(c, of: box))
                    .allowsHitTesting(false)
            }

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
        // The stage's own coordinates are the named space's (it is set on this view).
        .onContinuousHover(coordinateSpace: .local) { phase in
            var lit: Corner?
            if case .active(let p) = phase, !box.contains(p) {
                lit = Corner.allCases.first { c in
                    let q = corner(c, of: box)
                    return hypot(p.x - q.x, p.y - q.y) <= arc / 2 + 6
                }
            }
            if hoverArc != lit { hoverArc = lit }
        }
        .animation(dragStart == nil && turnStart == nil ? LuminaMotion.cropBox(reduce) : nil, value: b)
    }

    /// The arcs' size (prototype `arcS`): 17 % of the box's short side, 28…72.
    static func arcSize(_ box: CGRect) -> CGFloat {
        max(28, min(72, min(box.width, box.height) * 0.17)).rounded()
    }

    private func corner(_ c: Corner, of r: CGRect) -> CGPoint {
        switch c {
        case .tl: CGPoint(x: r.minX, y: r.minY)
        case .tr: CGPoint(x: r.maxX, y: r.minY)
        case .bl: CGPoint(x: r.minX, y: r.maxY)
        case .br: CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    /// "0.0°" (prototype `sg(ang, 1)`), and how much of the photo a steep angle leaves.
    static func angleText(_ b: CropBox, frame: CGRect) -> String {
        let a = (b.angle * 10).rounded() / 10
        var t = a == 0 ? "0.0°" : String(format: "%+.1f°", a).replacingOccurrences(of: "-", with: "−")
        guard frame.height > 0, b.h > 0 else { return t }
        let sc = CropBox.coverScale(angle: b.angle, aspect: Double(frame.width / frame.height) * b.w / b.h)
        if sc > 1.3 { t += " · keeps \(Int((100 / (sc * sc)).rounded()))% of the photo" }
        return t
    }

    /// Through the frame's centre: a faint level and plumb line, the same two dashed in gold
    /// turned by the angle, and the angle beside them (prototype `axOn`).
    private func crosshair(_ b: CropBox) -> some View {
        let c = CGPoint(x: frame.midX, y: frame.midY), r: CGFloat = 4000
        let cross = Path { p in
            p.move(to: CGPoint(x: c.x - r, y: c.y)); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
            p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        }
        let turn = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(b.angle * .pi / 180)).translatedBy(x: -c.x, y: -c.y)
        return ZStack(alignment: .topLeading) {
            cross.stroke(LuminaColor.textPrimary.opacity(0.2), lineWidth: 1)
            cross.applying(turn).stroke(LuminaColor.accentGold, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            Color.clear.frame(width: 1, height: 1)
                .overlay(alignment: .topLeading) {
                    Text(Self.angleText(b, frame: frame))
                        .font(LuminaFont.mono(11, s)).foregroundStyle(LuminaColor.accentGold)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(LuminaColor.overlayChip))
                        .offset(x: 10, y: -24)
                }
                .position(c)
        }
        .allowsHitTesting(false)
    }

    /// A drag outside the box turns the picture: the angle follows the pointer's bearing around
    /// the box's centre (⇧ a quarter as fast), −45…45° (prototype `cropDown`, `c.ang`).
    private func turnGesture(_ box: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { v in
                guard !model.edit.straightening else { return }
                if turnStart == nil {
                    let c = CGPoint(x: box.midX, y: box.midY)
                    turnStart = (CropBox(model.edit.cropDraft).angle, c, Double(atan2(v.startLocation.y - c.y, v.startLocation.x - c.x)))
                }
                guard let t = turnStart else { return }
                var da = (Double(atan2(v.location.y - t.centre.y, v.location.x - t.centre.x)) - t.bearing) * 180 / .pi
                if da > 180 { da -= 360 }
                if da < -180 { da += 360 }
                let fine = NSEvent.modifierFlags.contains(.shift)
                model.setCropAngle(t.angle + da * (fine ? 0.25 : 1))
            }
            .onEnded { _ in turnStart = nil }
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

/// A quarter-circle-and-a-half outside a corner of the box (prototype `data-rot`: a ring with
/// two borders lit, 0.55 white, full white under the pointer): where a drag turns the picture.
private struct CropTurnArc: View {
    let corner: CropStage.Corner
    let size: CGFloat
    let lit: Bool
    private var turn: Double {
        switch corner {
        case .tl: 0
        case .tr: 90
        case .br: 180
        case .bl: 270
        }
    }

    var body: some View {
        // The ring's half that faces away from the box: centred on the corner's outward diagonal
        // (screen angles, clockwise from 3 o'clock: top-left 225°, top-right 315°, …).
        let line: CGFloat = size > 48 ? 3 : 2
        Circle().trim(from: 0.375, to: 0.875)
            .stroke(LuminaColor.textPrimary.opacity(lit ? 1 : 0.55), lineWidth: line)
            .padding(line / 2)
            .rotationEffect(.degrees(turn))
            .animation(.easeOut(duration: 0.12), value: lit)
    }
}

/// Ratio {name} ▾ · Straighten {angle} S · Turn ↻ · Cancel esc · Apply ⏎ (prototype crop toolbar).
struct CropToolbar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        let b = CropBox(model.edit.cropDraft), straightening = model.edit.straightening
        let angle = (b.angle * 10).rounded() / 10
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
                Text("Ratio \(model.edit.cropRatio) ▾").font(LuminaFont.small(s, .semibold))
                    .foregroundStyle(LuminaColor.textPrimary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .padding(.horizontal, 9.scaled(s)).frame(height: LuminaHeight.chip.scaled(s))
            .background(RoundedRectangle(cornerRadius: LuminaRadius.pill.scaled(s), style: .continuous).fill(LuminaColor.fill07))
            .accessibilityIdentifier(AccessibilityID.Edit.cropRatio)
            .accessibilityLabel("Ratio \(model.edit.cropRatio)")

            toolButton(fill: straightening ? LuminaColor.accentGold : LuminaColor.fill10, dark: straightening, action: { model.straighten() }) {
                HStack(spacing: 6.scaled(s)) {
                    Text("Straighten")
                    Text(angle == 0 ? "0.0°" : String(format: "%+.1f°", angle).replacingOccurrences(of: "-", with: "−"))
                        .font(LuminaFont.mono(LuminaFontSize.small, s)).opacity(0.8)
                    KeyCap(text: "S", onGold: straightening)
                }
            }
            .help("Straighten · S · draw along the horizon; or drag outside the frame to turn")
            toolButton(fill: .clear, action: { model.cropRotate(1) }) {
                HStack(spacing: 5.scaled(s)) { Text("Turn"); Text("↻").font(LuminaFont.ui(15, .bold, s)) }
            }
            .help("Turn a quarter right · R")
            .accessibilityLabel("Turn right")
            toolButton(fill: .clear, weight: .regular, action: { model.cropCancel() }) {
                HStack(spacing: 6.scaled(s)) { Text("Cancel"); KeyCap(text: "esc") }
            }
            .accessibilityLabel("Cancel")
            toolButton(fill: LuminaColor.accentGold, dark: true, weight: .bold, action: { model.cropKeep() }) {
                HStack(spacing: 6.scaled(s)) { Text("Apply"); KeyCap(text: "⏎", onGold: true) }
            }
            .accessibilityLabel("Apply")
        }
        .padding(4.scaled(s))
        .background(RoundedRectangle(cornerRadius: LuminaRadius.segmented.scaled(s), style: .continuous).fill(LuminaColor.overlayScrim))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Edit.crop)
    }

    private func toolButton<L: View>(fill: Color, dark: Bool = false, weight: Font.Weight = .semibold, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label().font(LuminaFont.small(s, weight))
                .foregroundStyle(dark ? LuminaColor.textOnPrimary : LuminaColor.textPrimary)
                .padding(.horizontal, 8.scaled(s)).frame(height: LuminaHeight.chip.scaled(s))
                .background(RoundedRectangle(cornerRadius: LuminaRadius.pill.scaled(s), style: .continuous).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
