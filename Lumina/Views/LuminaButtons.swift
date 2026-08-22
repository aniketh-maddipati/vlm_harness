import SwiftUI

/// Shared press language — every control dips, the whole frame is the target.
struct LuminaPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, pressedScale: pressedScale)
    }

    private struct PressBody: View {
        let configuration: Configuration
        var pressedScale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
                .opacity(configuration.isPressed ? 0.78 : 1)
                .animation(reduceMotion ? nil : LuminaTokens.Motion.control, value: configuration.isPressed)
        }
    }
}

struct LuminaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration)
    }

    private struct PrimaryBody: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(LuminaTokens.Typeface.navigation(15))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(minHeight: LuminaTokens.HitTarget.minimum)
                .contentShape(Capsule(style: .continuous))
                .background(
                    Capsule(style: .continuous)
                        .fill(configuration.isPressed ? LuminaTokens.Surface.hover : Color.clear)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LuminaTokens.Ink.primary.opacity(configuration.isPressed ? 0.40 : 0.85),
                            lineWidth: 1
                        )
                }
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(reduceMotion ? nil : LuminaTokens.Motion.control, value: configuration.isPressed)
        }
    }
}

struct LuminaGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostBody(configuration: configuration)
    }

    private struct GhostBody: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(LuminaTokens.Typeface.navigation(15))
                .foregroundStyle(LuminaTokens.Ink.secondary.opacity(configuration.isPressed ? 0.55 : 0.95))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(minHeight: LuminaTokens.HitTarget.minimum)
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(reduceMotion ? nil : LuminaTokens.Motion.control, value: configuration.isPressed)
        }
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
            .frame(minWidth: 56, minHeight: LuminaTokens.HitTarget.minimum)
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

    /// Press dip on the whole frame — no hover, nothing smaller than a thumb.
    private struct QuietBody: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .frame(minHeight: LuminaTokens.HitTarget.minimum)
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.72 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
                        .padding(-4)
                )
                .animation(reduceMotion ? nil : LuminaTokens.Motion.control, value: configuration.isPressed)
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
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(minHeight: LuminaTokens.HitTarget.minimum)
                .background(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LuminaTokens.Ink.primary.opacity(prominent ? 0.85 : 0.55),
                            lineWidth: 1
                        )
                )
                .contentShape(Capsule(style: .continuous))
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
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: LuminaTokens.HitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .accessibilityLabel(title)
    }
}
