import SwiftUI

struct LuminaPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

struct LuminaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(minHeight: 48)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

enum LuminaDecisionRole {
    case reject, hero, keep

    var title: String {
        switch self {
        case .reject: "Reject"
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

    var icon: String {
        switch self {
        case .reject: "xmark"
        case .hero: "star.fill"
        case .keep: "checkmark"
        }
    }

    var tint: Color {
        switch self {
        case .reject: .red
        case .hero: .yellow
        case .keep: .green
        }
    }
}

struct LuminaDecisionButton: View {
    let role: LuminaDecisionRole
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: role.icon)
                    .font(.title2.weight(.semibold))
                Text(role.title)
                    .font(.subheadline.weight(.semibold))
                Text(role.shortcut)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 96, minHeight: 72)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(role.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(role.tint.opacity(0.35), lineWidth: 1)
            }
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
        HStack(spacing: 16) {
            LuminaDecisionButton(role: .reject, action: onReject)
            LuminaDecisionButton(role: .hero, action: onHero)
            LuminaDecisionButton(role: .keep, action: onKeep)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

struct LuminaFooterBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 14) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
