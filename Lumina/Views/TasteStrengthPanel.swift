import SwiftUI

/// Single taste-strength control — scales extracted profile offsets, never replaces them.
struct TasteStrengthPanel: View {
    @Binding var strength: Double
    let profile: DevelopRecipe
    let sourceCount: Int

    private var percentLabel: String {
        "\(Int((strength * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your look")
                .font(.subheadline.weight(.semibold))

            if TasteProfileDescription.isLowConfidence(sourceCount: sourceCount) {
                Text(TasteProfileDescription.lowConfidenceExplanation())
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(TasteProfileDescription.summary(profile: profile, sourceCount: sourceCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Taste strength")
                    .font(.caption)
                Spacer()
                Text(percentLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $strength, in: 0...1.5, step: 0.05)
        }
    }
}
