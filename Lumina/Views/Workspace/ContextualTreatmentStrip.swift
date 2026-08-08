import SwiftUI

/// Lightweight develop controls under the expanded active row.
struct ContextualTreatmentStrip: View {
    @Binding var previewMode: TreatmentPreviewMode
    @Binding var offsets: DevelopAdjustments
    @Binding var showDetailed: Bool
    var rowPreviewActive: Bool
    let onPreviewRow: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
            HStack(spacing: LuminaTokens.Spacing.sm) {
                previewChip("Original", mode: .original)
                previewChip("Auto", mode: .auto)
                previewChip("Current", mode: .current)
                Spacer(minLength: 0)
                Button("More…") { showDetailed.toggle() }
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .buttonStyle(LuminaQuietButtonStyle())
            }

            HStack(spacing: LuminaTokens.Spacing.md) {
                compactSlider(title: "Exposure", value: $offsets.exposure, range: -3...3, step: 0.05)
                compactSlider(title: "Warmth", value: $offsets.temperature, range: -400...400, step: 10)
                compactSlider(title: "Shadows", value: $offsets.shadows, range: -100...100, step: 1)
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

            if showDetailed {
                detailedControls
            }
        }
        .padding(LuminaTokens.Spacing.md)
        .background(LuminaTokens.Surface.well)
        .overlay(alignment: .top) {
            Rectangle().fill(LuminaTokens.Line.hairline).frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }

    private func previewChip(_ title: String, mode: TreatmentPreviewMode) -> some View {
        Button {
            previewMode = mode
        } label: {
            Text(title)
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(previewMode == mode ? LuminaTokens.Ink.primary : LuminaTokens.Ink.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(previewMode == mode ? LuminaTokens.Surface.highlight : Color.clear)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(LuminaTokens.Line.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(LuminaQuietButtonStyle())
    }

    private var detailedControls: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
            DevelopSliderRow(title: "Contrast", value: $offsets.contrast, range: -100...100, step: 1)
            DevelopSliderRow(title: "Highlights", value: $offsets.highlights, range: -100...100, step: 1)
            DevelopSliderRow(title: "Whites", value: $offsets.whites, range: -100...100, step: 1)
            DevelopSliderRow(title: "Blacks", value: $offsets.blacks, range: -100...100, step: 1)
            DevelopSliderRow(title: "Tint", value: $offsets.tint, range: -50...50, step: 1)
            DevelopSliderRow(title: "Vibrance", value: $offsets.vibrance, range: -100...100, step: 1)
            DevelopSliderRow(title: "Saturation", value: $offsets.saturation, range: -100...100, step: 1)
            DevelopSliderRow(title: "Clarity", value: $offsets.clarity, range: -100...100, step: 1)
        }
        .padding(.top, LuminaTokens.Spacing.xs)
    }

    private func compactSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
            Slider(value: value, in: range, step: step)
                .controlSize(.mini)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DevelopSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                Spacer(minLength: 8)
                Text(formattedValue)
                    .font(LuminaTokens.Typeface.count(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
        }
    }

    private var formattedValue: String {
        if unit == " EV" {
            return String(format: "%+.2f%@", value, unit)
        }
        if unit == " K" {
            return String(format: "%+.0f%@", value, unit)
        }
        return String(format: "%+.0f", value)
    }
}
