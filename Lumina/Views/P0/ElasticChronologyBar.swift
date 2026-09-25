import SwiftUI

/// A pinned map of the table. Only its marker follows scrolling; it never moves focus,
/// changes the set, or scrolls the photograph surface in response to geometry updates.
struct ElasticChronologyBar: View {
    let chapters: [ShootChapter]
    let activeID: String?
    let navigate: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ElasticLayout.groupGap) {
                    ForEach(chapters) { chapter in
                        Button { navigate(chapter.id) } label: {
                            Text(ElasticChronology.label(for: chapter))
                                .font(ElasticType.mono(ElasticLayout.momentTextSize))
                                .foregroundStyle(chapter.id == activeID
                                    ? LuminaTokens.Elastic.ink : LuminaTokens.Elastic.muted)
                                .padding(.horizontal, ElasticLayout.autoPadding)
                                .frame(minHeight: ElasticLayout.badgeMinWidth)
                                .background(chapter.id == activeID
                                    ? LuminaTokens.Elastic.warmAccent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: ElasticLayout.chipRadius))
                        }
                        .buttonStyle(LuminaElasticButtonStyle())
                        .accessibilityAddTraits(chapter.id == activeID ? .isSelected : [])
                        .accessibilityIdentifier("p0.chronology.\(chapter.id)")
                        .id(chapter.id)
                    }
                }
                .padding(.horizontal, ElasticLayout.tableGutter)
            }
            .onChange(of: activeID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .frame(height: ElasticLayout.badgeMinWidth)
        .background(LuminaTokens.Elastic.paper)
    }
}
