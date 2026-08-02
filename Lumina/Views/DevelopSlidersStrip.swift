import SwiftUI

/// Live develop controls — compact strip for loupe focus, full stack for sidebar.
struct DevelopSlidersStrip: View {
    @Binding var adjustments: DevelopAdjustments
    var compact: Bool = false
    var showApplyButton: Bool = true
    var onApplyToKeeps: (() -> Void)?

    var body: some View {
        if compact {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    miniSlider("Exposure", value: $adjustments.exposure, range: -2...2, step: 0.05)
                    miniSlider("Temp Δ", value: $adjustments.temperature, range: -800...800, step: 10)
                    miniSlider("Highlights", value: $adjustments.highlights, range: -100...100, step: 1)
                    miniSlider("Shadows", value: $adjustments.shadows, range: -100...100, step: 1)
                    if showApplyButton, let onApplyToKeeps {
                        Button("Apply to keeps") { onApplyToKeeps() }
                            .font(.caption)
                            .buttonStyle(LuminaPressStyle())
                    }
                }
                .padding(.vertical, 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                fullSlider("Exposure", value: $adjustments.exposure, range: -2...2)
                fullSlider("Temp Δ", value: $adjustments.temperature, range: -800...800)
                fullSlider("Highlights", value: $adjustments.highlights, range: -100...100)
                fullSlider("Shadows", value: $adjustments.shadows, range: -100...100)
                if showApplyButton, let onApplyToKeeps {
                    Button("Apply to keeps") { onApplyToKeeps() }
                        .font(.caption)
                }
            }
        }
    }

    private func miniSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(value: value, in: range, step: step)
                .frame(width: 120)
            Text(String(format: "%.1f", value.wrappedValue))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private func fullSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: "%.1f", value.wrappedValue))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
