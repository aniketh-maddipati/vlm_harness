import SwiftUI
import AppKit
import LuminaCore

// WP-5. The Curve section's graph (prototype `data-lumina="curve"`): on #1E1D1B, 5pt padding,
// radius 8; the faint histogram behind, a quarter grid, the dashed diagonal, the gold curve
// through the three tone points, each point's band, its dot on the diagonal and the dashed move,
// "In · Out" while a point is dragged; under it Darks / Mids / Lights with their values; then the
// preset chips. Dragging a point up or down is the drag of its slider (one undo step, ⇧ ¼, ⌥ 1/10,
// snaps to 0, Esc cancels); double-click resets it.

struct EditCurveGraph: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let m: EditControlMetrics
    /// The label under the graph the pointer is over (its band lights).
    @State private var hot: String?

    var body: some View {
        let anchors = model.curveAnchors
        let dragKey = model.editControls.drag.map(\.key).flatMap { ToneCurve.keys.contains($0) ? $0 : nil }
        VStack(spacing: 5.scaled(s)) {
            plot(anchors, dragKey: dragKey)
                .aspectRatio(CGFloat(1 / (model.windowSize.height < 700 ? 0.6 : 0.82)), contentMode: .fit)
            labels(anchors, dragKey: dragKey)
        }
        .padding(5.scaled(s))
        .background(RoundedRectangle(cornerRadius: LuminaRadius.buttonSecondary.scaled(s), style: .continuous).fill(LuminaColor.bgApp))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Edit.curve)
        .accessibilityLabel("Curve")
        .task(id: model.histogramRequest) { await model.measureEditHistogram() }
    }

    // MARK: the plot

    private func plot(_ anchors: [CurveAnchor], dragKey: String?) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                HistogramShape(heights: model.editHistogram?.heights ?? []).fill(LuminaColor.fill16)
                ForEach(anchors, id: \.key) { a in
                    Rectangle().fill(hot == a.key || dragKey == a.key ? LuminaColor.accentGold.opacity(0.10) : .clear)
                        .frame(width: w * 0.2, height: h)
                        .position(x: w * a.x, y: h / 2)
                }
                CurveGrid().stroke(LuminaColor.fill08, lineWidth: 1)
                Path { p in p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: 0)) }
                    .stroke(LuminaColor.fill22, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                CurveLine(samples: model.curveSamples).stroke(LuminaColor.accentGold, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                ForEach(anchors, id: \.key) { a in
                    if a.changed {
                        Path { p in p.move(to: CGPoint(x: w * a.x, y: h * (1 - a.x))); p.addLine(to: CGPoint(x: w * a.x, y: h * (1 - a.y))) }
                            .stroke(LuminaColor.accentGold.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                    Circle().fill(LuminaColor.fill35).frame(width: 5.scaled(s), height: 5.scaled(s))
                        .position(x: w * a.x, y: h * (1 - a.x))
                }
                ForEach(anchors, id: \.key) { a in
                    CurvePoint(anchor: a, dragging: dragKey == a.key, plotHeight: h, m: m)
                        .position(x: w * a.x, y: h * (1 - a.y))
                }
                if let r = model.curveReadout {
                    Text(r).font(LuminaFont.mono(LuminaFontSize.hint, s)).foregroundStyle(LuminaColor.accentGold)
                        .padding(.horizontal, 6.scaled(s)).padding(.vertical, 1.scaled(s))
                        .background(RoundedRectangle(cornerRadius: 5.scaled(s), style: .continuous).fill(LuminaColor.bgCanvas.opacity(0.85)))
                        .padding(6.scaled(s))
                        .allowsHitTesting(false)
                        .luminaStatus(AccessibilityID.Edit.curveReadout, r)
                }
            }
        }
    }

    // MARK: the labels under it

    private func labels(_ anchors: [CurveAnchor], dragKey: String?) -> some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                ForEach(anchors, id: \.key) { a in
                    let lit = hot == a.key || dragKey == a.key
                    VStack(spacing: 1) {
                        Text(a.label).font(LuminaFont.ui(LuminaFontSize.hint, lit ? .bold : .regular, s))
                            .foregroundStyle(lit ? LuminaColor.textPrimary : LuminaColor.textSecondary)
                        Text(a.text).font(LuminaFont.mono(LuminaFontSize.hint, s))
                            .foregroundStyle(a.changed ? LuminaColor.accentGold : LuminaColor.textTertiary)
                    }
                    .lineLimit(1)
                    .frame(width: g.size.width * 0.3)
                    .contentShape(Rectangle())
                    .onHover { inside in if inside { hot = a.key } else if hot == a.key { hot = nil } }
                    .position(x: g.size.width * a.x, y: g.size.height / 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(height: 30.scaled(s))
    }
}

/// One of the three points: 12pt, a 2pt ring of the canvas colour, gold while dragged, ×1.3 on
/// hover. The hit target is 28pt (R-54).
private struct CurvePoint: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduce
    let anchor: CurveAnchor, dragging: Bool, plotHeight: CGFloat, m: EditControlMetrics
    @State private var hover = false
    /// The pointer's y at the last drag tick; nil when no drag has started on this point.
    @State private var lastY: CGFloat?

    var body: some View {
        let d = 12.scaled(s), key = anchor.key
        Circle().fill(dragging ? LuminaColor.accentGold : LuminaColor.textPrimary)
            .frame(width: d, height: d)
            .background(Circle().fill(LuminaColor.bgCanvas).padding(-2))
            .scaleEffect(hover || dragging ? 1.3 : 1)
            .animation(LuminaMotion.panelFade(reduce), value: hover || dragging)
            .frame(width: m.hit, height: m.hit)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { g in
                    guard let last = lastY else { lastY = g.location.y; model.curveDragBegan(key); return }
                    lastY = g.location.y
                    let flags = NSEvent.modifierFlags
                    model.curveDragMoved(by: Double((last - g.location.y) / max(plotHeight, 40)),
                                         fine: flags.contains(.shift), finer: flags.contains(.option))
                }
                .onEnded { _ in if lastY != nil { lastY = nil; model.curveDragEnded() } })
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.resetSetting(key) })
            .help("\(EditFormat.label(key)) — drag up or down · ⇧ fine · double-click resets")
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(AccessibilityID.Edit.curvePoint(key))
            .accessibilityLabel(EditFormat.label(key)).accessibilityValue(anchor.text)
            .accessibilityAdjustableAction { dir in model.nudgeSetting(key, dir == .increment ? 1 : -1, coarse: false) }
    }
}

/// Lines at a quarter, a half and three quarters, both ways.
private struct CurveGrid: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for f in [0.25, 0.5, 0.75] {
            let x = r.minX + r.width * f, y = r.minY + r.height * f
            p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY))
            p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y))
        }
        return p
    }
}

/// The curve: outputs at even inputs, 0 at the bottom.
private struct CurveLine: Shape {
    var samples: [Double]
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard samples.count >= 2 else { return p }
        let n = CGFloat(samples.count - 1)
        for (i, v) in samples.enumerated() {
            let pt = CGPoint(x: r.minX + r.width * CGFloat(i) / n, y: r.maxY - r.height * CGFloat(v))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// The preset chips under the graph (prototype `sec.presets`): 24pt, radius 6, the matching one lit.
struct EditCurvePresets: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        ChipWrapRow(spacing: 4.scaled(s)) {
            ForEach(model.curvePresetNames, id: \.self) { name in
                let on = model.curvePresetIsOn(name)
                Button { model.applyCurvePreset(name) } label: {
                    Text(name).font(LuminaFont.small(s)).lineLimit(1)
                        .foregroundStyle(on ? LuminaColor.textOnPrimary : LuminaColor.textPrimary)
                        .padding(.horizontal, 9.scaled(s)).frame(height: 24.scaled(s))
                        .background(RoundedRectangle(cornerRadius: LuminaRadius.chip.scaled(s), style: .continuous).fill(on ? LuminaColor.primaryFill : LuminaColor.fill07))
                        // The chip is 24pt; its hit target reaches 28 (R-54).
                        .padding(.vertical, 2.scaled(s)).contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .help("\(name) curve · ⌘Z undoes it")
                .accessibilityIdentifier(AccessibilityID.Edit.curvePreset(name))
                .accessibilityLabel("\(name) curve")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.brightness(configuration.isPressed ? 0.06 : 0).scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Children left to right, wrapping onto the next line when the width runs out (CSS flex-wrap,
/// left-aligned; Open's `WrapRow` centres its lines).
private struct ChipWrapRow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let rows = arrange(limit ?? .infinity, subviews)
        let w = rows.map(\.width).max() ?? 0, h = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: limit ?? w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let sz = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
                x += sz.width + spacing
            }
            y += row.height + spacing
        }
    }
    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }
    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [], cur = Row()
        for i in subviews.indices {
            let sz = subviews[i].sizeThatFits(.unspecified)
            let next = cur.items.isEmpty ? sz.width : cur.width + spacing + sz.width
            if !cur.items.isEmpty, next > maxWidth { rows.append(cur); cur = Row() }
            cur.width = cur.items.isEmpty ? sz.width : cur.width + spacing + sz.width
            cur.height = max(cur.height, sz.height)
            cur.items.append(i)
        }
        if !cur.items.isEmpty { rows.append(cur) }
        return rows
    }
}
