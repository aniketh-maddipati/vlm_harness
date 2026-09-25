import SwiftUI

/// Elastic v4 surface grammar — type stacks, the cursor ring, the in-set outline,
/// and the one button costume (`design_handoff_elastic_v4` visual spec §1).
///
/// Three families only: serif for the wordmark and overlay titles, sans for buttons
/// with words, mono for everything else. No hover, no press scale, fade-only births.
///
/// Pointer law, one way:
/// - A plate is the whole target, and it is a settled button. Unfocused press travels.
///   Focused press is P. There is no ✓/P overlay — the plate is the keep door.
/// - Facts (lead / trail, phone glyph, in-set outline, reject ✕) never ask.
/// - Word buttons are for operations larger than one frame: Auto, Export, the burst
///   `set` / `phone` / `out`, the group's `take`. Fold / ×N lean the stack; they do
///   not decide. `out` is the pointer reject door — a travel click cannot reject.
/// - Keyboard X still rejects (same-mark-clears). Pointer reject is the settled
///   burst `out`, never a chip on the photograph.
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
    func elasticMarked(
        radius: CGFloat,
        ringed: Bool,
        inSet: Bool,
        sequence: ElasticSequenceMark? = nil
    ) -> some View {
        self
            .overlay {
                if inSet {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .inset(by: ElasticLayout.setOutlineInset)
                        .stroke(LuminaTokens.Elastic.warmAccent, lineWidth: ElasticLayout.setOutlineWidth)
                }
                if sequence != nil {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .inset(by: ElasticLayout.sequenceOutlineInset)
                        .stroke(
                            LuminaTokens.Elastic.ink.opacity(ElasticLayout.sequenceOutlineOpacity),
                            lineWidth: ElasticLayout.sequenceOutlineWidth
                        )
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

/// The Elastic button costume: the label is the whole target. No hover, no scale.
/// A slow opacity settle is the only press cue (§5 still bans hover).
struct LuminaElasticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ElasticPressBody(configuration: configuration)
    }

    private struct ElasticPressBody: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.72 : 1)
                .animation(
                    LuminaTokens.Motion.press(configuration.isPressed, reduceMotion: reduceMotion),
                    value: configuration.isPressed
                )
        }
    }
}

/// A photograph plate that is itself a settled button. Double-tap is exclusive so
/// a second press does not also fire the single-press action.
struct ElasticPlateButton<Label: View>: View {
    let action: () -> Void
    var onDoubleTap: (() -> Void)?
    @ViewBuilder var label: () -> Label

    init(
        action: @escaping () -> Void = {},
        onDoubleTap: (() -> Void)? = nil,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.action = action
        self.onDoubleTap = onDoubleTap
        self.label = label
    }

    var body: some View {
        if let onDoubleTap {
            Button(action: action, label: label)
                .buttonStyle(LuminaElasticButtonStyle())
                .highPriorityGesture(TapGesture(count: 2).onEnded(onDoubleTap))
        } else {
            Button(action: action, label: label)
                .buttonStyle(LuminaElasticButtonStyle())
        }
    }
}
