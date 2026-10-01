import SwiftUI
import LuminaCore

// WP-6. Help (?): five groups, every key in SF Mono, the list from KEYMAP.md (`HelpContent`).
// Help owns the keyboard (R-23): only Esc and ? reach it, through the model. A click outside
// the panel closes it.

struct HelpOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        GeometryReader { geo in
            let width = min(980.scaled(s), (geo.size.width * 0.92).rounded(.down))
            ZStack {
                OverlayPalette.dimHelp.contentShape(Rectangle()).onTapGesture { model.helpClose() }.accessibilityHidden(true)
                OverlayPanel {
                    // Hugs its content when that fits; scrolls inside 88 % of the height when it doesn't.
                    FittingScroll(maxHeight: (geo.size.height * 0.88).rounded(.down)) { content(width: width) }
                }
                .frame(width: width)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.Edit.help)
                .accessibilityLabel("All shortcuts")
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// CSS `repeat(auto-fit, minmax(260px, 1fr))`, gaps 18 / 30, padding 22 / 26.
    private func content(width: CGFloat) -> some View {
        let padX = (width < 400 ? 16 : 26).scaled(s), gapX = 30.scaled(s), inner = max(1, width - 2 * padX)
        let groups = HelpContent.groups
        let cols = max(1, min(groups.count, Int((inner + gapX) / (260.scaled(s) + gapX))))
        let colW = (inner - gapX * CGFloat(cols - 1)) / CGFloat(cols)
        let rows = stride(from: 0, to: groups.count, by: cols).map { Array(groups[$0..<min($0 + cols, groups.count)]) }
        return VStack(alignment: .leading, spacing: 18.scaled(s)) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(alignment: .top, spacing: gapX) {
                    ForEach(rows[r], id: \.title) { g in group(g).frame(width: colW, alignment: .topLeading) }
                }
            }
            HStack {
                Spacer(minLength: 0)
                Button { model.introShow() } label: { Text(HelpContent.introAgain) }
                    .buttonStyle(OverlayChipButtonStyle(kind: .outline))
                    .accessibilityIdentifier(OverlayID.helpIntroAgain)
            }
        }
        .padding(.horizontal, padX).padding(.vertical, 22.scaled(s))
        .frame(width: width, alignment: .leading)
    }

    private func group(_ g: HelpGroup) -> some View {
        VStack(alignment: .leading, spacing: 4.scaled(s)) {
            Text(g.title).font(LuminaFont.small(s, .bold)).foregroundStyle(LuminaColor.accentGold)
                .padding(.bottom, 3.scaled(s)).accessibilityAddTraits(.isHeader)
            ForEach(g.rows.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 10.scaled(s)) {
                    Text(g.rows[i].keys).font(LuminaFont.mono(LuminaFontSize.monoHint, s)).foregroundStyle(LuminaColor.textPrimary)
                        .frame(width: 96.scaled(s), alignment: .leading)
                    Text(g.rows[i].text).font(LuminaFont.small(s)).foregroundStyle(LuminaColor.textSecondary).lineSpacing(2.scaled(s))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
