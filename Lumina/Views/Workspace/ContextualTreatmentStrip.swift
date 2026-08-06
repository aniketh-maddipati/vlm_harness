import SwiftUI

/// Lightweight preview-mode chips under the expanded active row.
/// Live develop sliders live only in TreatmentStageView — not repeated here.
struct ContextualTreatmentStrip: View {
    @Binding var previewMode: TreatmentPreviewMode
    @Binding var offsets: DevelopAdjustments
    @Binding var showDetailed: Bool
    var rowPreviewActive: Bool
    let onPreviewRow: () -> Void
    let onReset: () -> Void
    var onOpenTreatment: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
            HStack(spacing: LuminaTokens.Spacing.sm) {
                previewChip("Original", mode: .original)
                previewChip("Auto", mode: .auto)
                previewChip("Current", mode: .current)
                Spacer(minLength: 0)
                Button("Treat…") {
                    if let onOpenTreatment {
                        onOpenTreatment()
                    } else {
                        showDetailed = true
                    }
                }
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityHint("Opens the persistent live RAW editor. Sliders are not embedded in rows.")
            }

            HStack(spacing: LuminaTokens.Spacing.md) {
                Button(rowPreviewActive ? "Hide row preview" : "Preview across row") {
                    onPreviewRow()
                }
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .buttonStyle(LuminaQuietButtonStyle())

                Spacer(minLength: 0)

                Button("Reset") { onReset() }
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .buttonStyle(LuminaQuietButtonStyle())
            }

            Text("Live develop controls open in Treatment (T) — one editor for the focused photograph.")
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, LuminaTokens.Spacing.md)
        .padding(.vertical, LuminaTokens.Spacing.sm)
        .background(LuminaTokens.Surface.mist.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func previewChip(_ title: String, mode: TreatmentPreviewMode) -> some View {
        Button {
            previewMode = mode
        } label: {
            Text(title)
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(previewMode == mode ? LuminaTokens.Surface.well : Color.clear)
                )
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .accessibilityAddTraits(previewMode == mode ? .isSelected : [])
    }
}
