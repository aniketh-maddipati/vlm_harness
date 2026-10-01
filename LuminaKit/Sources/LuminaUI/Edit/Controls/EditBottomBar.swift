import SwiftUI
import LuminaCore

// WP-5. The bottom bar (README §3): ‹ Previous and Next → (gold, ⏎); Save {n} and ✕ Out;
// then All shortcuts ?. On the last photo the gold moves from Next to Save.

struct EditBottomBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let m: EditControlMetrics

    var body: some View {
        let last = model.editIsLast, none = model.editCur == nil, n = model.keptIDs.count
        VStack(spacing: 6.scaled(s)) {
            HStack(spacing: 6.scaled(s)) {
                Button { model.editMove(-1) } label: {
                    Text("‹").font(LuminaFont.ui(LuminaFontSize.overlayTitle, .regular, s)).frame(width: m.button, height: m.button)
                }
                .buttonStyle(EditBarButtonStyle(kind: .plain))
                .disabled(model.editIsFirst)
                .help("Previous photo · ←").accessibilityLabel("Previous photo").accessibilityIdentifier(AccessibilityID.Edit.prev)

                Button { model.editNext() } label: {
                    HStack(spacing: 8.scaled(s)) {
                        Text("Next →").font(LuminaFont.body(s, .bold)).lineLimit(1)
                        Spacer(minLength: 0)
                        KeyHint("⏎", opacity: 0.7)
                    }
                    .padding(.horizontal, 12.scaled(s)).frame(maxWidth: .infinity).frame(height: m.button)
                }
                .buttonStyle(EditBarButtonStyle(kind: last ? .quiet : .gold))
                .disabled(none)
                .help(last ? "Last photo · ⏎ goes to Save" : "Next photo · → or ⏎").accessibilityLabel("Next").accessibilityIdentifier(AccessibilityID.Edit.next)
            }
            WeightedRow(weights: [1.4, 1], spacing: 6.scaled(s)) {
                Button { model.go(.save) } label: {
                    HStack(spacing: 8.scaled(s)) {
                        Text("Save \(n)").font(LuminaFont.caption(s, .bold)).lineLimit(1)
                        Spacer(minLength: 0)
                        if m.keyHints { KeyHint("⌘S", opacity: 0.6) }
                    }
                    .padding(.horizontal, 12.scaled(s)).frame(maxWidth: .infinity).frame(height: m.button)
                }
                .buttonStyle(EditBarButtonStyle(kind: last ? .gold : .strong))
                .help("Go to Save · ⌘S · edits are already kept").accessibilityLabel("Save \(n)").accessibilityIdentifier(AccessibilityID.Edit.save)

                Button { model.editOut() } label: {
                    HStack(spacing: 7.scaled(s)) {
                        Text("✕").font(LuminaFont.ui(LuminaFontSize.hint, .bold, s))
                        Text("Out").font(LuminaFont.caption(s, .semibold)).lineLimit(1)
                    }
                    .padding(.horizontal, 8.scaled(s)).frame(maxWidth: .infinity).frame(height: m.button)
                }
                .buttonStyle(EditBarButtonStyle(kind: .out))
                .disabled(none)
                .help("Out · X · drops it from your keepers · ⌘Z brings it back").accessibilityLabel("Out").accessibilityIdentifier(AccessibilityID.Edit.out)
            }
            HStack {
                Spacer(minLength: 0)
                Button { model.helpOpen() } label: {
                    HStack(spacing: 6.scaled(s)) { Text("All shortcuts"); KeyHint("?", opacity: 0.8) }
                }
                .buttonStyle(LuminaLinkButtonStyle())
                .help("Every key and gesture · ?").accessibilityLabel("All shortcuts")
            }
        }
        .padding(.top, 6.scaled(s))
        .overlay(alignment: .top) { LuminaColor.fill07.frame(height: 1) }
    }
}

struct EditBarButtonStyle: ButtonStyle {
    enum Kind { case plain, gold, strong, quiet, out }
    let kind: Kind
    func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration, kind: kind) }
    private struct Content: View {
        let configuration: Configuration; let kind: Kind
        @Environment(\.luminaScale) private var s
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduce
        @State private var hover = false
        var body: some View {
            let on = hover && enabled
            let fill: Color = switch kind {
            case .gold: LuminaColor.accentGold
            case .strong: on ? LuminaColor.fill20 : LuminaColor.fill13
            case .plain: on ? LuminaColor.fill16 : LuminaColor.fill08
            case .quiet: on ? LuminaColor.fill10 : LuminaColor.fill06
            case .out: on ? LuminaColor.errorBg : LuminaColor.fill06
            }
            let live: Color = switch kind {
            case .gold: LuminaColor.textOnPrimary
            case .strong, .plain: LuminaColor.textPrimary
            case .quiet: LuminaColor.textTertiary
            case .out: on ? LuminaColor.errorText : LuminaColor.textSecondary
            }
            let text = enabled ? live : LuminaColor.textDisabled
            configuration.label
                .foregroundStyle(text)
                .background(RoundedRectangle(cornerRadius: LuminaRadius.buttonPrimary.scaled(s), style: .continuous).fill(fill))
                .brightness(kind == .gold && on ? 0.04 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Rectangle()).onHover { hover = $0 }
                .animation(LuminaMotion.panelFade(reduce), value: hover)
        }
    }
}

/// Children side by side, widths in proportion to `weights` (CSS `1.4fr 1fr`).
struct WeightedRow: Layout {
    var weights: [CGFloat]; var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width } + spacing * CGFloat(max(0, subviews.count - 1))
        let widths = self.widths(w, subviews.count)
        let h = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (v, w) in zip(subviews, widths(bounds.width, subviews.count)) {
            v.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
    private func widths(_ total: CGFloat, _ n: Int) -> [CGFloat] {
        guard n > 0 else { return [] }
        let ws = (0..<n).map { weights.indices.contains($0) ? weights[$0] : 1 }, sum = ws.reduce(0, +)
        let free = max(0, total - spacing * CGFloat(n - 1))
        return ws.map { free * $0 / sum }
    }
}
