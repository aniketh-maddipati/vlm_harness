import SwiftUI
import LuminaCore

// WP-0 contract: the controls every screen shares, so there is one primary button and one
// secondary button in the app. Sizes are tokens × luminaScale.

/// A key hint ("⏎", "⌘O", "R") in SF Mono.
public struct KeyHint: View {
    @Environment(\.luminaScale) private var s
    let text: String; var opacity: Double
    public init(_ text: String, opacity: Double = 0.6) { self.text = text; self.opacity = opacity }
    public var body: some View { Text(text).font(LuminaFont.mono(LuminaFontSize.monoHint, s)).opacity(opacity).accessibilityHidden(true) }
}

/// Primary: #EFECE6 fill, dark text, white on hover. Height 36 (or `height`).
public struct LuminaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.luminaScale) private var s
    @Environment(\.isEnabled) private var enabled
    var height: CGFloat, radius: CGFloat, fontSize: CGFloat, padding: CGFloat
    public init(height: CGFloat = LuminaHeight.buttonPrimary, radius: CGFloat = LuminaRadius.buttonPrimary, fontSize: CGFloat = LuminaFontSize.body, padding: CGFloat = 18) {
        self.height = height; self.radius = radius; self.fontSize = fontSize; self.padding = padding
    }
    public func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration, style: self) }
    private struct Content: View {
        let configuration: Configuration; let style: LuminaPrimaryButtonStyle
        @Environment(\.luminaScale) private var s
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(LuminaFont.ui(style.fontSize, .semibold, s))
                .foregroundStyle(enabled ? LuminaColor.textOnPrimary : LuminaColor.textDisabled)
                .padding(.horizontal, style.padding.scaled(s)).frame(minHeight: style.height.scaled(s))
                .background(RoundedRectangle(cornerRadius: style.radius.scaled(s), style: .continuous)
                    .fill(!enabled ? LuminaColor.fill08 : hover ? LuminaColor.primaryHover : LuminaColor.primaryFill))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Rectangle()).onHover { hover = $0 }
        }
    }
}

/// Secondary: fill 0.08, 0.16 on hover. Height 32 (or `height`).
public struct LuminaSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat, radius: CGFloat, padding: CGFloat
    public init(height: CGFloat = LuminaHeight.buttonSecondary, radius: CGFloat = LuminaRadius.buttonSecondary, padding: CGFloat = 14) {
        self.height = height; self.radius = radius; self.padding = padding
    }
    public func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration, style: self) }
    private struct Content: View {
        let configuration: Configuration; let style: LuminaSecondaryButtonStyle
        @Environment(\.luminaScale) private var s
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false
        var body: some View {
            configuration.label
                .font(LuminaFont.body(s))
                .foregroundStyle(enabled ? LuminaColor.textPrimary : LuminaColor.textDisabled)
                .padding(.horizontal, style.padding.scaled(s)).frame(minHeight: style.height.scaled(s))
                .background(RoundedRectangle(cornerRadius: style.radius.scaled(s), style: .continuous).fill(hover && enabled ? LuminaColor.fill16 : LuminaColor.fill08))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Rectangle()).onHover { hover = $0 }
        }
    }
}

/// A plain text button (links, "Start over"): tertiary text, primary on hover; the hit area is
/// still at least 28pt high (R-54).
public struct LuminaLinkButtonStyle: ButtonStyle {
    var size: CGFloat
    public init(size: CGFloat = LuminaFontSize.small) { self.size = size }
    public func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration, size: size) }
    private struct Content: View {
        let configuration: Configuration; let size: CGFloat
        @Environment(\.luminaScale) private var s
        @State private var hover = false
        var body: some View {
            configuration.label.font(LuminaFont.ui(size, .regular, s))
                .foregroundStyle(hover ? LuminaColor.textPrimary : LuminaColor.textTertiary)
                .frame(minHeight: LuminaHeight.minHit.scaled(s)).contentShape(Rectangle()).onHover { hover = $0 }
        }
    }
}

public extension ButtonStyle where Self == LuminaPrimaryButtonStyle { static var luminaPrimary: LuminaPrimaryButtonStyle { .init() } }
public extension ButtonStyle where Self == LuminaSecondaryButtonStyle { static var luminaSecondary: LuminaSecondaryButtonStyle { .init() } }
public extension ButtonStyle where Self == LuminaLinkButtonStyle { static var luminaLink: LuminaLinkButtonStyle { .init() } }

/// A demo / file photo, decoded off the main thread at the size it is shown. Fades in over 120 ms.
/// Screens with their own loading rules (the Edit canvas) use `ImageProvider` directly.
public struct PhotoThumb: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduce
    let photo: Photo; let maxPoint: CGFloat; var cover: Bool
    @State private var image: CGImage?
    public init(_ photo: Photo, maxPoint: CGFloat, cover: Bool = true) { self.photo = photo; self.maxPoint = maxPoint; self.cover = cover }
    public var body: some View {
        ZStack {
            LuminaColor.bgCanvas
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: cover ? .fill : .fit).transition(.opacity)
            }
        }
        .clipped()
        .task(id: "\(photo.id)|\(Int(maxPoint / 80))") {
            let px = Int((maxPoint * displayScale / 80).rounded(.up)) * 80
            if let img = try? await model.services.images.image(for: photo, maxPixel: max(80, px), look: nil) {
                withAnimation(LuminaMotion.tileFade(reduce)) { image = img }
            }
        }
    }
}
