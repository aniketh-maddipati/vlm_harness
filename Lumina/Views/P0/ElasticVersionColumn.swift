import SwiftUI

/// Staged Develop looks on the inspect rail: tone · lift · punch.
///
/// Highlighted means still staged. A pick applies that recipe and puts the
/// photograph in the set; the accepted look goes quiet. The same look again
/// clears — out of the set, recipe restored, looks re-staged.
struct ElasticVariationColumn: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        let _ = previewPath(for: 1)
        return VStack(alignment: .leading, spacing: ElasticLayout.chipGap) {
            Text(CopyContract.developLooksHint)
                .font(ElasticType.mono(ElasticLayout.drawerScopeSize))
                .opacity(ElasticLayout.drawerScopeOpacity)
                .lineLimit(1)
            FlowChips {
                ForEach(Array(session.stagedAutoVariations.enumerated()), id: \.element.id) { index, look in
                    variationChip(look, index: index)
                }
            }
        }
        .padding(.top, ElasticLayout.drawerSectionTopChat4)
    }

    private func variationChip(_ look: AutoVariation, index: Int) -> some View {
        let highlighted = session.isAutoVariationHighlighted(look.id)
        return Button {
            session.pickStagedVariation(look.id)
        } label: {
            HStack(spacing: ElasticLayout.chipGap) {
                Text("\(index + 1)")
                    .fontWeight(.semibold)
                Text(session.variationLabel(for: look.id))
            }
            .modifier(ChipCostume(on: highlighted))
        }
        .buttonStyle(LuminaElasticButtonStyle())
        .accessibilityIdentifier(P0AccessibilityID.elasticVersion(index + 1))
    }

    /// Progressive-render contract: only `shot` may show the browse thumbnail.
    /// Staged looks are chips, not photographs — this stays so the gate still
    /// sees the honest path rule.
    private func previewPath(for index: Int) -> String? {
        guard index == 1 else { return nil }
        return nil
    }
}
