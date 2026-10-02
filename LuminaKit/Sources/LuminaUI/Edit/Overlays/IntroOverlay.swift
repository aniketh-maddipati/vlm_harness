import SwiftUI
import LuminaCore

// WP-6. The first-run intro: three numbered cards (`IntroContent`). Esc or ⏎ closes it (through
// the model, which remembers it was seen); so do its two buttons.

struct IntroOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        GeometryReader { geo in
            let width = min(560.scaled(s), (geo.size.width * 0.92).rounded(.down))
            ZStack {
                // The intro is closed on purpose, not by a stray click on the dimmed photo.
                OverlayPalette.dimIntro.contentShape(Rectangle()).onTapGesture {}.accessibilityHidden(true)
                OverlayPanel {
                    // Hugs its content when that fits; scrolls inside 90 % of the height when it doesn't.
                    // The buttons stay in reach on a short window; only the cards scroll.
                    VStack(spacing: 0) {
                        FittingScroll(maxHeight: max(80, (geo.size.height * 0.9).rounded(.down) - footerHeight)) { content(width: width) }
                        footer(width: width)
                    }
                }
                .frame(width: width)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.Edit.intro)
                .accessibilityLabel(IntroContent.title)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func content(width: CGFloat) -> some View {
        let padX = (width < 400 ? 18 : 28).scaled(s)
        return VStack(alignment: .leading, spacing: 20.scaled(s)) {
            VStack(alignment: .leading, spacing: 4.scaled(s)) {
                Text(IntroContent.title).font(LuminaFont.display(LuminaFontSize.title1, s)).foregroundStyle(LuminaColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(IntroContent.subtitle).font(LuminaFont.body(s)).foregroundStyle(LuminaColor.textSecondary)
            }
            VStack(alignment: .leading, spacing: 14.scaled(s)) {
                ForEach(IntroContent.cards, id: \.number) { card in
                    HStack(alignment: .top, spacing: 12.scaled(s)) {
                        Text(card.number).font(LuminaFont.mono(LuminaFontSize.small, s)).foregroundStyle(LuminaColor.textTertiary)
                            .frame(width: 18.scaled(s), alignment: .leading).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2.scaled(s)) {
                            Text(card.title).font(LuminaFont.body(s, .bold)).foregroundStyle(LuminaColor.textPrimary)
                            Text(card.text).font(LuminaFont.small(s)).foregroundStyle(LuminaColor.textSecondary).lineSpacing(3.scaled(s))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        KeyCap(text: card.key, large: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, padX).padding(.top, 26.scaled(s)).padding(.bottom, 20.scaled(s))
        .frame(width: width, alignment: .leading)
    }

    private var footerHeight: CGFloat { LuminaHeight.buttonSecondary.scaled(s) + 22.scaled(s) }

    private func footer(width: CGFloat) -> some View {
        HStack(spacing: 8.scaled(s)) {
            Spacer(minLength: 0)
            Button { model.introToHelp() } label: { Text(IntroContent.allShortcuts) }
                .buttonStyle(IntroButtonStyle(primary: false)).accessibilityIdentifier(OverlayID.introShortcuts)
            Button { model.introClose() } label: { Text(IntroContent.start) }
                .buttonStyle(IntroButtonStyle(primary: true)).accessibilityIdentifier(OverlayID.introStart)
        }
        .padding(.horizontal, (width < 400 ? 18 : 28).scaled(s)).padding(.bottom, 22.scaled(s))
        .frame(width: width, height: footerHeight, alignment: .top)
    }
}

/// "All shortcuts" (outlined) and "Start editing" (gold): height 32, radius 9, 13pt.
private struct IntroButtonStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration, primary: primary) }
    private struct Content: View {
        let configuration: Configuration; let primary: Bool
        @Environment(\.luminaScale) private var s
        @State private var hover = false
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: LuminaRadius.buttonPrimary.scaled(s), style: .continuous)
            configuration.label
                .font(LuminaFont.body(s, primary ? .bold : .regular))
                .foregroundStyle(primary ? LuminaColor.textOnPrimary : LuminaColor.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, (primary ? 16 : 14).scaled(s)).frame(minHeight: LuminaHeight.buttonSecondary.scaled(s))
                .background {
                    if primary { shape.fill(LuminaColor.accentGold).brightness(hover ? 0.06 : 0) }
                    else { shape.fill(hover ? LuminaColor.fill06 : .clear).overlay(shape.strokeBorder(LuminaColor.fill20, lineWidth: 1)) }
                }
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Rectangle()).onHover { hover = $0 }
        }
    }
}
