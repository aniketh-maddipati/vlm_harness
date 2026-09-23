import SwiftUI

/// Elastic v4 surface grammar — type stacks, the cursor ring, the in-set outline,
/// and the one button costume (`design_handoff_elastic_v4` visual spec §1).
///
/// Three families only: serif for the wordmark and overlay titles, sans for buttons
/// with words, mono for everything else. No hover, no press scale, fade-only births.
@MainActor
enum ElasticType {
    /// `ui-monospace, Menlo, monospace` — metadata, captions, badges, bars.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// `-apple-system` — Auto, Export, the ask input.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// `'Iowan Old Style', Georgia, serif` — wordmark and keys-overlay titles only.
    static func serif(_ size: CGFloat) -> Font {
        LuminaTokens.Typeface.editorial(size)
    }

    /// CSS `line-height` as a multiple of the font size, converted to the extra
    /// leading SwiftUI adds between lines (system fonts set ~1.2 by default).
    static func lineSpacing(size: CGFloat, lineHeight: CGFloat) -> CGFloat {
        max(0, size * (lineHeight - ElasticLayout.systemLineHeight))
    }
}

extension View {
    /// Ring and outline, per the state matrix (§4): the ring is a box-shadow outside
    /// the tile, the in-set outline sits across the edge. Both may show at once.
    func elasticMarked(radius: CGFloat, ringed: Bool, inSet: Bool) -> some View {
        self
            .overlay {
                if inSet {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .inset(by: ElasticLayout.setOutlineInset)
                        .stroke(LuminaTokens.Elastic.warmAccent, lineWidth: ElasticLayout.setOutlineWidth)
                }
            }
            .background {
                if ringed {
                    // `0 0 0 3px ink, 0 0 0 4.5px #EFECE6` — spread grows the radius with it.
                    ZStack {
                        RoundedRectangle(
                            cornerRadius: radius + ElasticLayout.ringOuter,
                            style: .continuous
                        )
                        .fill(LuminaTokens.Elastic.shellAlt)
                        .padding(-ElasticLayout.ringOuter)
                        RoundedRectangle(
                            cornerRadius: radius + ElasticLayout.focusRingWidth,
                            style: .continuous
                        )
                        .fill(LuminaTokens.Elastic.ink)
                        .padding(-ElasticLayout.focusRingWidth)
                    }
                }
            }
    }

    /// `@keyframes born { opacity 0 → 1 }`, ease-out — the only entrance there is.
    func elasticBorn(_ milliseconds: Int) -> some View {
        transition(
            .opacity.animation(.easeOut(duration: Double(milliseconds) / ElasticLayout.msPerSecond))
        )
    }
}

/// The Elastic button costume: the label is the whole target and nothing changes on
/// press or hover (§5 "No hover styles. Nothing changes on hover anywhere.").
struct LuminaElasticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}
