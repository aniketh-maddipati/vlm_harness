import SwiftUI

struct DecisionDock: View {
    let current: AssetDecision
    var isCompact: Bool = false
    let onDecision: (AssetDecision) -> Void

    private let roles: [AssetDecision] = [.cut, .needsMe, .keep]

    var body: some View {
        HStack(spacing: isCompact ? 6 : 10) {
            ForEach(roles) { role in
                DecisionDockButton(
                    role: role,
                    isActive: current == role,
                    isCompact: isCompact
                ) {
                    onDecision(role)
                }
            }
        }
        .padding(.horizontal, isCompact ? 10 : 14)
        .padding(.vertical, isCompact ? 6 : 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Decision dock")
    }
}

private struct DecisionDockButton: View {
    let role: AssetDecision
    let isActive: Bool
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(role.shortcut)
                    .font(LuminaTokens.Typeface.navigation(isCompact ? 13 : 14, weight: .medium))
                    .foregroundStyle(labelInk)
                Text(role.title)
                    .font(LuminaTokens.Typeface.meta(isCompact ? 10 : 11))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(minWidth: isCompact ? 52 : 68)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .strokeBorder(borderInk, lineWidth: isActive ? 1 : 0)
            )
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? activeFill : Color.clear)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .help("\(role.title) (\(role.shortcut))")
        .accessibilityLabel("\(role.title), shortcut \(role.shortcut)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var labelInk: Color {
        if isActive, role == .cut { return LuminaTokens.Status.reject }
        return isActive ? LuminaTokens.Ink.primary : LuminaTokens.Ink.secondary
    }

    private var borderInk: Color {
        if isActive, role == .cut { return LuminaTokens.Status.reject.opacity(0.65) }
        return isActive ? LuminaTokens.Ink.primary.opacity(0.35) : .clear
    }

    private var activeFill: Color {
        switch role {
        case .cut: LuminaTokens.Status.reject.opacity(0.06)
        case .needsMe: LuminaTokens.Status.needsAttention.opacity(0.08)
        case .keep: LuminaTokens.Surface.mist
        case .undecided, .anchor: .clear
        }
    }
}

struct LuminaQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(LuminaTokens.Motion.control, value: configuration.isPressed)
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
