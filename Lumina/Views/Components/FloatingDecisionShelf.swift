import SwiftUI

/// Compact floating decision shelf — attaches to the selected photograph’s lower matte.
struct FloatingDecisionShelf: View {
    var current: AssetDecision = .undecided
    let onSetAside: () -> Void
    let onHold: () -> Void
    let onAddToSet: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            shelfButton(
                title: AssetDecision.cut.routingTitle,
                shortcut: "X",
                prominence: .secondary,
                isActive: current == .cut,
                action: onSetAside
            )
            shelfButton(
                title: AssetDecision.needsMe.routingTitle,
                shortcut: "M",
                prominence: .secondary,
                isActive: current == .needsMe,
                action: onHold
            )
            shelfButton(
                title: AssetDecision.keep.routingTitle,
                shortcut: "S",
                prominence: .primary,
                isActive: current == .keep,
                action: onAddToSet
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LuminaTokens.Surface.porcelain.opacity(0.97))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LuminaTokens.Line.emphasis, lineWidth: 1)
        }
        .shadow(color: LuminaTokens.Ink.primary.opacity(0.06), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Decision shelf")
    }

    private enum Prominence { case primary, secondary }

    private func shelfButton(
        title: String,
        shortcut: String,
        prominence: Prominence,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            LuminaHaptics.decision()
            action()
        } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(LuminaTokens.Typeface.navigation(prominence == .primary ? 13 : 12, weight: prominence == .primary ? .medium : .regular))
                    .foregroundStyle(LuminaTokens.Ink.primary.opacity(prominence == .primary ? 1 : 0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(shortcut)
                    .font(LuminaTokens.Typeface.meta(10))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
            .frame(minWidth: prominence == .primary ? 88 : 72, minHeight: 44)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill(for: prominence, isActive: isActive))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(border(for: prominence, isActive: isActive), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(FloatingShelfButtonStyle())
        .help("\(title) (\(shortcut))")
        .accessibilityLabel("\(title), shortcut \(shortcut)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func fill(for prominence: Prominence, isActive: Bool) -> Color {
        if isActive { return LuminaTokens.Surface.mist }
        if prominence == .primary { return LuminaTokens.Surface.mist.opacity(0.85) }
        return Color.clear
    }

    private func border(for prominence: Prominence, isActive: Bool) -> Color {
        if prominence == .primary || isActive {
            return LuminaTokens.Ink.primary.opacity(0.40)
        }
        return LuminaTokens.Line.hairline
    }
}

private struct FloatingShelfButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(LuminaTokens.Motion.control, value: configuration.isPressed)
    }
}

/// Non-modal decision receipt — overlays without resizing the workspace.
struct DecisionReceiptBanner: View {
    let message: String
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Text(message)
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.primary)
            if let onUndo {
                Text("·")
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                Button("Undo") { onUndo() }
                    .font(LuminaTokens.Typeface.navigation(13, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .buttonStyle(LuminaQuietButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LuminaTokens.Surface.porcelain.opacity(0.96))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LuminaTokens.Line.emphasis, lineWidth: 1)
        }
        .shadow(color: LuminaTokens.Ink.primary.opacity(0.05), radius: 6, y: 2)
        .allowsHitTesting(onUndo != nil)
    }
}
