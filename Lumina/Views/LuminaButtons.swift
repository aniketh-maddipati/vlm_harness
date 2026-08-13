import SwiftUI

struct LuminaPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(LuminaTokens.Motion.control, value: configuration.isPressed)
    }
}

struct LuminaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LuminaTokens.Typeface.navigation(15))
            .foregroundStyle(LuminaTokens.Ink.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minHeight: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? LuminaTokens.Surface.hover : Color.clear)
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LuminaTokens.Ink.primary.opacity(configuration.isPressed ? 0.45 : 0.85),
                        lineWidth: 1
                    )
            }
            .animation(LuminaTokens.Motion.control, value: configuration.isPressed)
    }
}

struct LuminaGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LuminaTokens.Typeface.navigation(15))
            .foregroundStyle(LuminaTokens.Ink.secondary.opacity(configuration.isPressed ? 0.55 : 0.95))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .animation(LuminaTokens.Motion.control, value: configuration.isPressed)
    }
}

enum LuminaDecisionRole {
    case reject, hero, keep

    var title: String {
        switch self {
        case .reject: "Cut"
        case .hero: "Anchor"
        case .keep: "Keep"
        }
    }

    var shortcut: String {
        switch self {
        case .reject: "X"
        case .hero: "A"
        case .keep: "K"
        }
    }
}

struct LuminaDecisionButton: View {
    let role: LuminaDecisionRole
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(role.shortcut)
                    .font(LuminaTokens.Typeface.navigation(14, weight: .medium))
                    .foregroundStyle(foreground)
                Text(role.title)
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
            }
            .frame(minWidth: 56, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(LuminaPressStyle())
    }

    private var foreground: Color {
        role == .reject ? LuminaTokens.Status.reject : LuminaTokens.Ink.primary
    }
}

struct LuminaDecisionBar: View {
    let onReject: () -> Void
    let onHero: () -> Void
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            LuminaDecisionButton(role: .reject, action: onReject)
            LuminaDecisionButton(role: .hero, action: onHero)
            LuminaDecisionButton(role: .keep, action: onKeep)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

struct LuminaFooterBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 14) {
            content()
        }
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        .padding(.vertical, 10)
        .background(LuminaTokens.Surface.porcelain)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }
}

struct LuminaQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietBody(configuration: configuration)
    }

    /// Hover halo + press dip — quiet, but every press reads as a press.
    private struct QuietBody: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.7 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : (hovering ? 0.05 : 0)))
                        .padding(-2)
                )
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : LuminaTokens.Motion.control, value: configuration.isPressed)
                .animation(reduceMotion ? nil : LuminaTokens.Motion.control, value: hovering)
        }
    }
}

struct LuminaTextActionButton: View {
    let title: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LuminaTokens.Typeface.navigation(15))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(minHeight: LuminaTokens.HitTarget.minimum)
                .background(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LuminaTokens.Ink.primary.opacity(prominent ? 0.85 : 0.55),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .accessibilityLabel(title)
    }
}

struct LuminaGhostActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LuminaTokens.Typeface.navigation(15))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: LuminaTokens.HitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .accessibilityLabel(title)
    }
}
