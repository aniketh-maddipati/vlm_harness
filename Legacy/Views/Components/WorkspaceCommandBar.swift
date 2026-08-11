// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import SwiftUI

/// Large tactile command bar — three cull decisions + stack apply.
struct WorkspaceCommandBar: View {
    let leadDecision: AssetDecision
    var restCount: Int = 0
    let onKeep: () -> Void
    let onCut: () -> Void
    let onMaybe: () -> Void
    let onApplyToRest: () -> Void
    let onPreviewEdits: () -> Void

    var body: some View {
        HStack(spacing: LuminaTokens.Spacing.md) {
            LuminaCommandButton(
                title: "Keep",
                shortcut: "⌘K",
                isProminent: true,
                isActive: leadDecision == .keep,
                action: onKeep
            )
            LuminaCommandButton(
                title: "Cut",
                shortcut: "⌘X",
                isDestructive: true,
                isActive: leadDecision == .cut,
                action: onCut
            )
            LuminaCommandButton(
                title: "Maybe",
                shortcut: "⌘M",
                isActive: leadDecision == .needsMe,
                action: onMaybe
            )

            Spacer(minLength: LuminaTokens.Spacing.lg)

            if restCount > 0 {
                LuminaCommandButton(
                    title: "Cut \(restCount) behind",
                    shortcut: "⌘↩",
                    isProminent: true,
                    action: onApplyToRest
                )
            }

            Spacer(minLength: LuminaTokens.Spacing.md)

            LuminaCommandButton(
                title: "Preview edits",
                shortcut: "⌘E",
                action: onPreviewEdits
            )
        }
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        .padding(.vertical, LuminaTokens.Spacing.md)
        .background(LuminaTokens.Surface.highlight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LuminaTokens.Line.emphasis)
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace commands")
    }
}

struct LuminaCommandButton: View {
    let title: String
    let shortcut: String
    var isDestructive: Bool = false
    var isProminent: Bool = false
    var isActive: Bool = false
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            LuminaHaptics.decision()
            action()
        } label: {
            VStack(spacing: compact ? 2 : 6) {
                if !compact {
                    Text(title)
                        .font(LuminaTokens.Typeface.navigation(16))
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                } else {
                    Text(title)
                        .font(LuminaTokens.Typeface.navigation(20))
                        .foregroundStyle(labelColor)
                }
                Text(shortcut)
                    .font(LuminaTokens.Typeface.meta(compact ? 11 : 12))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
            .frame(minWidth: compact ? 52 : 96, minHeight: compact ? 52 : LuminaTokens.HitTarget.command)
            .padding(.horizontal, compact ? 8 : 16)
            .padding(.vertical, compact ? 8 : 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fillColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isActive || isProminent ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(LuminaCommandPressStyle())
        .accessibilityLabel("\(title), \(shortcut)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var labelColor: Color {
        if isDestructive, isActive { return LuminaTokens.Status.reject }
        return LuminaTokens.Ink.primary
    }

    private var fillColor: Color {
        if isActive, isDestructive { return LuminaTokens.Status.reject.opacity(0.08) }
        if isActive { return LuminaTokens.Surface.mist }
        if isProminent { return LuminaTokens.Surface.mist }
        return LuminaTokens.Surface.highlight
    }

    private var borderColor: Color {
        if isDestructive, isActive { return LuminaTokens.Status.reject.opacity(0.55) }
        if isProminent { return LuminaTokens.Ink.primary.opacity(0.45) }
        if isActive { return LuminaTokens.Line.emphasis }
        return LuminaTokens.Line.hairline
    }
}

struct LuminaCommandPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(LuminaTokens.Motion.control, value: configuration.isPressed)
    }
}
