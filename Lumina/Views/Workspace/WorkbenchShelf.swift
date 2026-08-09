import SwiftUI

/// Shared workbench shelf — one per table, not one per photograph.
struct WorkbenchShelf: View {
    let selectionCount: Int
    let label: String
    let staged: StagedAction?
    var reduceTransparency: Bool = false
    var increaseContrast: Bool = false
    let onSetAside: () -> Void
    let onHold: () -> Void
    let onAdvance: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                .lineLimit(1)
                .accessibilityHidden(true)

            Spacer(minLength: 12)

            shelfTarget(
                keyHint: "⌫",
                title: staged == .setAside ? "staged — press ↩ again to confirm" : "Set aside",
                minWidth: 140,
                prominence: .secondary,
                isStaged: staged == .setAside,
                action: onSetAside
            )
            shelfTarget(
                keyHint: "⇧↩",
                title: staged == .hold ? "staged — press ↩ again to confirm" : "Hold",
                minWidth: 140,
                prominence: .quiet,
                isStaged: staged == .hold,
                action: onHold
            )
            shelfTarget(
                keyHint: "↩",
                title: advanceTitle,
                minWidth: 180,
                prominence: .primary,
                isStaged: staged == .advance,
                action: onAdvance
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .background(shelfBackground)
        .overlay {
            Rectangle()
                .strokeBorder(
                    increaseContrast ? LuminaTokens.Line.emphasis : Color.white.opacity(0.12),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Decision shelf")
    }

    private var advanceTitle: String {
        if staged == .advance {
            return "staged — press ↩ again to confirm"
        }
        let n = max(selectionCount, 1)
        return "Advance \(n)"
    }

    @ViewBuilder
    private var shelfBackground: some View {
        if reduceTransparency {
            LuminaTokens.Surface.shelfOpaque
        } else {
            LuminaTokens.Surface.shelf
        }
    }

    private enum Prominence { case primary, secondary, quiet }

    private func shelfTarget(
        keyHint: String,
        title: String,
        minWidth: CGFloat,
        prominence: Prominence,
        isStaged: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            LuminaHaptics.decision()
            action()
        } label: {
            HStack(spacing: 8) {
                Text(keyHint)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ink(for: prominence).opacity(0.7))
                Text(title)
                    .font(LuminaTokens.Typeface.navigation(13, weight: prominence == .primary ? .semibold : .regular))
                    .foregroundStyle(ink(for: prominence))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 14)
            .frame(minWidth: minWidth, minHeight: 68)
            .background(fill(for: prominence, isStaged: isStaged))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isStaged ? Color.white.opacity(0.28) : border(for: prominence),
                        lineWidth: isStaged ? 3 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(WorkbenchShelfButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(keyHint)
        .accessibilityAddTraits(isStaged ? .isSelected : [])
    }

    private func ink(for prominence: Prominence) -> Color {
        switch prominence {
        case .primary: return LuminaTokens.Ink.onAdvance
        case .secondary, .quiet: return LuminaTokens.Ink.onTable
        }
    }

    private func fill(for prominence: Prominence, isStaged: Bool) -> Color {
        switch prominence {
        case .primary:
            return LuminaTokens.Surface.advanceFill
        case .secondary:
            return Color.white.opacity(isStaged ? 0.10 : 0.06)
        case .quiet:
            return Color.white.opacity(isStaged ? 0.08 : 0.03)
        }
    }

    private func border(for prominence: Prominence) -> Color {
        switch prominence {
        case .primary: return Color.clear
        case .secondary: return Color.white.opacity(0.14)
        case .quiet: return Color.white.opacity(0.08)
        }
    }
}

private struct WorkbenchShelfButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(LuminaTokens.Motion.control, value: configuration.isPressed)
    }
}

/// Centred staged treatment banner — Adapt / Develop copy from the contract.
struct StagedTreatmentBanner: View {
    let snapshot: StagingCopySnapshot

    var body: some View {
        VStack(spacing: 6) {
            Text(snapshot.isDevelop
                 ? CopyContract.developBanner(count: snapshot.scopeCount)
                 : CopyContract.adaptBanner(snapshot))
                .font(LuminaTokens.Typeface.navigation(15, weight: .medium))
                .foregroundStyle(LuminaTokens.Ink.onTable)
                .multilineTextAlignment(.center)
            if !snapshot.isDevelop {
                Text(CopyContract.adaptedIndependently)
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LuminaTokens.Surface.shelfOpaque.opacity(0.94))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Centred staged-advance banner — clear of the shelf.
struct StagedAdvanceBanner: View {
    let count: Int

    var body: some View {
        VStack(spacing: 6) {
            Text("Advance \(count) → the story")
                .font(LuminaTokens.Typeface.navigation(15, weight: .medium))
                .foregroundStyle(LuminaTokens.Ink.onTable)
            Text("↩ confirms · Esc cancels · ⌘Z undoes the whole round afterwards")
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LuminaTokens.Surface.shelfOpaque.opacity(0.94))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
