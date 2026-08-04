import SwiftUI

struct DecisionDock: View {
    let current: AssetDecision
    var isCompact: Bool = false
    let onDecision: (AssetDecision) -> Void

    private let roles: [AssetDecision] = [.cut, .needsMe, .keep, .anchor]

    var body: some View {
        HStack(spacing: isCompact ? 8 : 12) {
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
        .padding(.horizontal, isCompact ? 14 : 20)
        .padding(.vertical, isCompact ? 10 : 12)
        .frame(height: LuminaTokens.HitTarget.dockHeight)
        .background(
            RoundedRectangle(cornerRadius: LuminaTokens.Radius.dock, style: .continuous)
                .fill(LuminaTokens.Surface.elevated)
                .shadow(
                    color: LuminaTokens.Depth.softShadow,
                    radius: LuminaTokens.Depth.softShadowRadius,
                    y: LuminaTokens.Depth.softShadowY
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: LuminaTokens.Radius.dock, style: .continuous)
                .strokeBorder(LuminaTokens.Line.hairline, lineWidth: LuminaTokens.Line.hairlineWidth)
        }
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
            VStack(spacing: 3) {
                Text(role.shortcut)
                    .font(LuminaTokens.Typeface.control(isCompact ? 13 : 15, weight: .medium))
                    .foregroundStyle(ink)
                    .frame(width: 18, height: 18)
                Text(role.title)
                    .font(LuminaTokens.Typeface.meta(isCompact ? 10 : 11, weight: .medium))
                    .foregroundStyle(ink.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(minWidth: isCompact ? 64 : 84)
            .frame(maxWidth: .infinity)
            .frame(minHeight: LuminaTokens.HitTarget.decision)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: LuminaTokens.Radius.button, style: .continuous)
                    .fill(isActive ? activeFill : Color.clear)
            )
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .help("\(role.title) (\(role.shortcut))")
        .accessibilityLabel("\(role.title), shortcut \(role.shortcut)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var ink: Color {
        isActive ? activeInk : LuminaTokens.Ink.primary
    }

    private var activeFill: Color {
        switch role {
        case .cut: LuminaTokens.Status.reject.opacity(0.12)
        case .needsMe: LuminaTokens.Status.needsAttention.opacity(0.14)
        case .keep: LuminaTokens.Status.keep.opacity(0.16)
        case .anchor: LuminaTokens.Ink.primary.opacity(0.08)
        case .undecided: .clear
        }
    }

    private var activeInk: Color {
        switch role {
        case .cut: LuminaTokens.Status.reject
        case .needsMe: LuminaTokens.Status.needsAttention
        case .keep: LuminaTokens.Ink.primary
        case .anchor: LuminaTokens.Ink.primary
        case .undecided: LuminaTokens.Ink.primary
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
                .font(LuminaTokens.Typeface.control(15, weight: .medium))
                .foregroundStyle(prominent ? LuminaTokens.Surface.porcelain : LuminaTokens.Ink.primary)
                .padding(.horizontal, prominent ? 22 : 16)
                .padding(.vertical, 12)
                .frame(minHeight: LuminaTokens.HitTarget.minimum)
                .background(
                    RoundedRectangle(cornerRadius: LuminaTokens.Radius.button, style: .continuous)
                        .fill(prominent ? LuminaTokens.Ink.primary : LuminaTokens.Surface.secondary)
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
                .font(LuminaTokens.Typeface.control(14))
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
