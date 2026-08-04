import SwiftUI

struct LuminaPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(LuminaAtmosphere.Motion.dissolve, value: configuration.isPressed)
    }
}

struct LuminaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LuminaAtmosphere.Typeface.body(16).weight(.medium))
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .frame(minHeight: 48)
            .background(
                LuminaAtmosphere.affirm.opacity(configuration.isPressed ? 0.72 : 0.92),
                in: Capsule()
            )
            .foregroundStyle(Color.black.opacity(0.85))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(LuminaAtmosphere.Motion.dissolve, value: configuration.isPressed)
    }
}

struct LuminaGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LuminaAtmosphere.Typeface.body(15))
            .foregroundStyle(LuminaAtmosphere.whisper.opacity(configuration.isPressed ? 0.55 : 0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .animation(LuminaAtmosphere.Motion.dissolve, value: configuration.isPressed)
    }
}

enum LuminaDecisionRole {
    case reject, hero, keep

    var title: String {
        switch self {
        case .reject: "Cut"
        case .hero: "Hero"
        case .keep: "Keep"
        }
    }

    var shortcut: String {
        switch self {
        case .reject: "X"
        case .hero: "H"
        case .keep: "P"
        }
    }
}

/// Whisper decisions — keys + soft labels, no traffic-light cards.
struct LuminaDecisionButton: View {
    let role: LuminaDecisionRole
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(role.shortcut)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.78))
                Text(role.title)
                    .font(LuminaAtmosphere.Typeface.caption(11))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(LuminaPressStyle())
        .keyboardShortcut(KeyEquivalent(Character(role.shortcut.lowercased())), modifiers: [])
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
            Capsule()
                .fill(Color.black.opacity(0.28))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
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
        .background(Color.black.opacity(0.35))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }
}
