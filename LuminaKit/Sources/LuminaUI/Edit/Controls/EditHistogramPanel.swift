import SwiftUI
import LuminaCore

// WP-5. The histogram above the tools row (prototype `data-lumina="histogram"`): the luma shape
// on #1E1D1B, 5pt padding, radius 8, a 38pt plot; 8pt clipping markers at the top corners, blue
// for shadows on the left and red for highlights on the right, whose words go in the hint line.
// The data is the model's (`editHistogram`): measured by the image provider when it can.

struct EditHistogramPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        let h = model.editHistogram
        let lo = h?.shadowsClipping ?? false, hi = h?.highlightsClipping ?? false
        ZStack(alignment: .top) {
            HistogramShape(heights: h?.heights ?? []).fill(LuminaColor.fill55)
            HStack(spacing: 0) {
                if lo { ClipMarker(colour: LuminaColor.swatch["blue"] ?? .blue, hint: AppModel.shadowsClippingHint, id: AccessibilityID.Edit.shadowsClipping) }
                Spacer(minLength: 0)
                if hi { ClipMarker(colour: LuminaColor.errorDot, hint: AppModel.highlightsClippingHint, id: AccessibilityID.Edit.highlightsClipping) }
            }
        }
        .frame(height: 38.scaled(s))
        .padding(5.scaled(s))
        .background(RoundedRectangle(cornerRadius: LuminaRadius.buttonSecondary.scaled(s), style: .continuous).fill(LuminaColor.bgApp))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Edit.histogram)
        .accessibilityLabel("Histogram")
        .accessibilityValue([lo ? "shadows clipping" : nil, hi ? "highlights clipping" : nil].compactMap { $0 }.joined(separator: ", "))
        // Measured again for another photo or another look at rest; the last one stays while a drag goes on.
        .task(id: model.histogramRequest) { await model.measureEditHistogram() }
        .onDisappear { model.setHintNote(nil) }
    }
}

/// An 8pt square at a top corner. Hovering it explains it in the hint line.
private struct ClipMarker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let colour: Color, hint: String, id: String
    var body: some View {
        RoundedRectangle(cornerRadius: 2.scaled(s), style: .continuous).fill(colour)
            .frame(width: 8.scaled(s), height: 8.scaled(s))
            // A little more than the square answers the pointer: 8pt is hard to find.
            .contentShape(Rectangle().inset(by: -5.scaled(s)))
            .onHover { inside in
                if inside { model.setHintNote(hint) } else if model.editControls.hintNote == hint { model.setHintNote(nil) }
            }
            .onDisappear { if model.editControls.hintNote == hint { model.setHintNote(nil) } }
            .help(hint)
            .luminaStatus(id, hint)
    }
}

/// The prototype's path on its 176 × 52 box, stretched to the frame: the heights along the
/// width, the tallest reaching 48 of the 52.
struct HistogramShape: Shape {
    var heights: [Double]
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard heights.count >= 2 else { return p }
        let n = CGFloat(heights.count - 1), top = r.height * 48 / 52
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        for (i, v) in heights.enumerated() {
            let y = CGFloat(min(1, max(0, v.isFinite ? v : 0)))
            p.addLine(to: CGPoint(x: r.minX + r.width * CGFloat(i) / n, y: r.maxY - y * top))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
