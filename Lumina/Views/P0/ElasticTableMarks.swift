import SwiftUI

/// One word, settled fill when the operation is on. Used only for work larger
/// than a single frame — never as a chip on a photograph.
struct ElasticOperationButton: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ElasticType.sans(ElasticLayout.badgeTextSize, weight: .medium))
                .foregroundStyle(on ? LuminaTokens.Elastic.shell : LuminaTokens.Elastic.ink)
                .padding(.horizontal, ElasticLayout.badgePaddingH)
                .frame(minHeight: ElasticLayout.badgeHeight, maxHeight: ElasticLayout.badgeHeight)
                .background(
                    on ? LuminaTokens.Elastic.ink : LuminaTokens.Elastic.shell,
                    in: RoundedRectangle(cornerRadius: ElasticLayout.badgeRadius, style: .continuous)
                )
        }
        .buttonStyle(LuminaElasticButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(on ? "on" : "off")
    }
}

/// First and last frames of the burst the cursor is in. Facts, not buttons.
enum ElasticSequenceMark: String, Equatable, Sendable {
    case lead
    case trail
}

/// `lead` / `trail` — a word on the plate so the highlight is never color alone.
struct ElasticSequenceChip: View {
    let mark: ElasticSequenceMark

    var body: some View {
        Text(mark.rawValue)
            .font(ElasticType.mono(ElasticLayout.sequenceChipSize, weight: .semibold))
            .foregroundStyle(LuminaTokens.Elastic.ink)
            .padding(.horizontal, ElasticLayout.sequenceChipPaddingH)
            .padding(.vertical, ElasticLayout.sequenceChipPaddingV)
            .background(
                LuminaTokens.Elastic.shell,
                in: RoundedRectangle(cornerRadius: ElasticLayout.chipRadius, style: .continuous)
            )
            .allowsHitTesting(false)
            .accessibilityLabel(mark.rawValue)
    }
}
