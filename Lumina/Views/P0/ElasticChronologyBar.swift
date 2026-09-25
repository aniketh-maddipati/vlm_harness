import SwiftUI

/// A pinned map of the table. Only its marker follows scrolling; it never moves focus,
/// changes the set, or scrolls the photograph surface in response to geometry updates.
struct ElasticChronologyBar: View {
    let chapters: [ShootChapter]
    let activeID: String?
    let navigate: (String) -> Void

    private var page: ElasticPages.Index {
        let ids = chapters.map(\.id)
        let index = activeID.flatMap { ids.firstIndex(of: $0) } ?? 0
        return ElasticPages.Index(position: chapters.isEmpty ? 0 : index + 1, count: chapters.count)
    }

    var body: some View {
        HStack(spacing: ElasticLayout.shelfGap) {
            stepButton(title: "prev", step: -1, enabled: page.canRetreat)
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
                                    .frame(minHeight: ElasticLayout.pageControlHit)
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
            if !page.label.isEmpty {
                Text(page.label)
                    .font(ElasticType.mono(ElasticLayout.momentTextSize))
                    .foregroundStyle(LuminaTokens.Elastic.muted)
                    .fixedSize()
                    .accessibilityLabel("Moment \(page.label)")
            }
            stepButton(title: "next", step: 1, enabled: page.canAdvance)
        }
        .padding(.horizontal, ElasticLayout.tableGutter)
        .frame(height: ElasticLayout.pageControlHit)
        .background(LuminaTokens.Elastic.paper)
    }

    private func stepButton(title: String, step: Int, enabled: Bool) -> some View {
        Button {
            let ids = chapters.map(\.id)
            let index = activeID.flatMap { ids.firstIndex(of: $0) } ?? 0
            guard let next = ElasticPages.Index.neighbor(current: index, count: ids.count, step: step) else {
                return
            }
            navigate(ids[next])
        } label: {
            Text(title)
                .font(ElasticType.sans(ElasticLayout.badgeTextSize, weight: .medium))
                .foregroundStyle(enabled ? LuminaTokens.Elastic.ink : LuminaTokens.Elastic.muted)
                .frame(minWidth: ElasticLayout.pageControlHit, minHeight: ElasticLayout.pageControlHit)
        }
        .buttonStyle(LuminaElasticButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(step < 0 ? "Previous moment" : "Next moment")
    }
}
