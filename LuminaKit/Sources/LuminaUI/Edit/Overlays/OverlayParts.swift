import SwiftUI
import LuminaCore

// WP-6. Pieces the overlays share: the photo with a look, key caps, the small buttons, the
// panel behind Help and the intro, and the identifiers the contract doesn't list yet.

/// Values the prototype uses for the overlays that `parity/tokens.json` doesn't carry yet
/// (CONTRACT-REQUESTS/WP6.md asks for them); everything else comes from `LuminaColor`.
enum OverlayPalette {
    /// Behind Help: rgba(0,0,0,0.6). Behind the intro: rgba(0,0,0,0.62).
    static let dimHelp = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.6)
    static let dimIntro = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.62)
    /// The Help and intro panel: #2A2927.
    static let panel = Color(.sRGB, red: 42 / 255, green: 41 / 255, blue: 39 / 255, opacity: 1)
    /// 0 20 60 rgba(0,0,0,0.5).
    static let panelShadow = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.5)
    /// The key cap's edge on a gold button: rgba(30,29,27,0.35).
    static let capOnGold = Color(.sRGB, red: 30 / 255, green: 29 / 255, blue: 27 / 255, opacity: 0.35)
}

/// Identifiers for overlay parts ACCESSIBILITY_CONTRACT.md has no name for yet.
enum OverlayID {
    static let sceneGrid = "edit.sceneGrid", sceneGridCancel = "edit.sceneGrid.cancel"
    static func sceneCell(_ id: String) -> String { "edit.sceneGrid.\(id)" }
    static let picker = "edit.picker"
    static let variationsApply = "edit.variations.apply", variationsCancel = "edit.variations.cancel"
    static let helpIntroAgain = "edit.help.intro", introShortcuts = "edit.intro.shortcuts", introStart = "edit.intro.start"
}

/// The current photo with a look applied, filling its frame (cover), decoded off the main
/// thread at the size it is shown. Fades in over 120 ms.
struct LookThumb: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduce
    let photo: Photo
    let look: Look
    let maxPoint: CGFloat
    @State private var image: CGImage?

    private var pixels: Int { min(1600, max(80, Int((maxPoint * displayScale / 80).rounded(.up)) * 80)) }
    private var key: String { "\(photo.id)|\(pixels)|" + look.keys.sorted().map { "\($0)=\(look[$0] ?? 0)" }.joined(separator: ",") }

    var body: some View {
        Color.clear
            .overlay {
                if let image { Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill).transition(.opacity) }
            }
            .clipped()
            .task(id: key) {
                if let img = try? await model.services.images.image(for: photo, maxPixel: pixels, look: look.isEmpty ? nil : look) {
                    withAnimation(LuminaMotion.tileFade(reduce)) { image = img }
                }
            }
    }
}

/// A key in a small outlined box ("⏎", "V", "⌘Z").
struct KeyCap: View {
    @Environment(\.luminaScale) private var s
    let text: String
    var onGold = false
    /// The intro cards' larger cap (18pt, 11pt text); every other cap is 16pt with 10.5pt text
    /// and 4pt sides (prototype).
    var large = false
    var body: some View {
        Text(text).font(LuminaFont.mono(large ? LuminaFontSize.hint : 10.5, s))
            .foregroundStyle(onGold ? LuminaColor.textOnPrimary : LuminaColor.textSecondary)
            .padding(.horizontal, (large ? 5 : 4).scaled(s))
            .frame(minWidth: (large ? 18 : 16).scaled(s), minHeight: (large ? 18 : 16).scaled(s))
            .overlay(RoundedRectangle(cornerRadius: 4.scaled(s)).strokeBorder(onGold ? OverlayPalette.capOnGold : LuminaColor.fill22, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// The small buttons on a grid's header ("Cancel esc", "Apply ⏎") and in Help: drawn as a
/// 24pt chip, hit area 28pt (R-54).
struct OverlayChipButtonStyle: ButtonStyle {
    enum Kind { case plain, gold, outline }
    var kind: Kind = .plain
    func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration, kind: kind) }
    private struct Content: View {
        let configuration: Configuration; let kind: Kind
        @Environment(\.luminaScale) private var s
        @State private var hover = false
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: LuminaRadius.chip.scaled(s), style: .continuous)
            configuration.label
                .font(LuminaFont.small(s, kind == .gold ? .bold : .regular))
                .foregroundStyle(kind == .gold ? LuminaColor.textOnPrimary : kind == .outline && !hover ? LuminaColor.textSecondary : LuminaColor.textPrimary)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 9.scaled(s)).frame(height: LuminaHeight.chip.scaled(s))
                .background {
                    switch kind {
                    case .plain: shape.fill(hover ? LuminaColor.fill16 : LuminaColor.fill08)
                    case .gold: shape.fill(LuminaColor.accentGold).brightness(hover ? 0.06 : 0)
                    case .outline: shape.strokeBorder(hover ? LuminaColor.fill35 : LuminaColor.fill20, lineWidth: 1)
                    }
                }
                .frame(minHeight: LuminaHeight.minHit.scaled(s))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Rectangle()).onHover { hover = $0 }
        }
    }
}

/// The panel Help and the intro sit on: #2A2927, radius 14, a soft shadow.
struct OverlayPanel<Content: View>: View {
    @Environment(\.luminaScale) private var s
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: LuminaRadius.dropOverlay.scaled(s), style: .continuous).fill(OverlayPalette.panel)
                .shadow(color: OverlayPalette.panelShadow, radius: 30.scaled(s), x: 0, y: 20.scaled(s)))
            .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.dropOverlay.scaled(s), style: .continuous))
            // A click on the panel is not a click on the dimmed photo behind it.
            .contentShape(Rectangle()).onTapGesture {}
    }
}

/// The selected cell: `0 0 0 2px #161514, 0 0 0 4px #FFD27A` (tokens: shadow.selectedCell).
struct SelectedRing: ViewModifier {
    @Environment(\.luminaScale) private var s
    let on: Bool
    func body(content: Content) -> some View {
        let w = 2.scaled(s), r = LuminaRadius.photo.scaled(s)
        content.overlay {
            if on {
                ZStack {
                    RoundedRectangle(cornerRadius: r + w).strokeBorder(LuminaColor.bgCanvas, lineWidth: w).padding(-w)
                    RoundedRectangle(cornerRadius: r + 2 * w).strokeBorder(LuminaColor.accentGold, lineWidth: w).padding(-2 * w)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

/// The mono label in the corner of a grid cell.
struct CellLabel: View {
    @Environment(\.luminaScale) private var s
    let text: String; let selected: Bool
    var body: some View {
        Text(text).font(LuminaFont.mono(LuminaFontSize.small, s)).lineLimit(1)
            .foregroundStyle(selected ? LuminaColor.accentGold : LuminaColor.textPrimary)
            .padding(.horizontal, 7.scaled(s)).frame(height: 20.scaled(s))
            .background(Capsule().fill(LuminaColor.overlayChip))
    }
}

/// A vertical scroll view that is only as tall as its content, up to `maxHeight`.
struct FittingScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0
    var body: some View {
        ScrollView(.vertical) {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: height > 0 ? min(height, max(1, maxHeight)) : max(1, maxHeight))
    }
}
