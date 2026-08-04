import SwiftUI

struct LuminaPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(LuminaTokens.Motion.control, value: configuration.isPressed)
    }
}

struct LuminaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LuminaTokens.Typeface.control(16, weight: .medium))
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .frame(minHeight: 48)
            .background(
                LuminaTokens.Ink.primary.opacity(configuration.isPressed ? 0.72 : 0.92),
                in: RoundedRectangle(cornerRadius: LuminaTokens.Radius.button, style: .continuous)
            )
            .foregroundStyle(LuminaTokens.Surface.porcelain)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(LuminaTokens.Motion.control, value: configuration.isPressed)
    }
}

struct LuminaGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LuminaTokens.Typeface.control(15))
            .foregroundStyle(LuminaTokens.Ink.secondary.opacity(configuration.isPressed ? 0.55 : 0.95))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
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
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                Text(role.title)
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
            }
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(LuminaPressStyle())
    }
}

struct LuminaDecisionBar: View {
    let onReject: () -> Void
    let onHero: () -> Void
    let onKeep: () -> Void

    var body: some View {
        HStack(spacing: 28) {
            LuminaDecisionButton(role: .reject, action: onReject)
            LuminaDecisionButton(role: .hero, action: onHero)
            LuminaDecisionButton(role: .keep, action: onKeep)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: LuminaTokens.Radius.dock, style: .continuous)
                .fill(LuminaTokens.Surface.elevated.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: LuminaTokens.Radius.dock, style: .continuous)
                        .strokeBorder(LuminaTokens.Line.hairline, lineWidth: LuminaTokens.Line.hairlineWidth)
                )
        )
    }
}

struct LuminaFooterBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 14) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(LuminaTokens.Surface.elevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }
}
