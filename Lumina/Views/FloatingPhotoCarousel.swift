import AppKit
import SwiftUI

/// Apple-style horizontal photo strip — scale, depth, and drift as items move in/out of center.
struct FloatingPhotoCarousel<Item: Identifiable, ID: Hashable, Content: View>: View {
    let items: [Item]
    @Binding var selection: ID?
    var itemID: KeyPath<Item, ID>
    var spacing: CGFloat = 28
    var peek: Int = 5
    var onSelectionChange: ((Item) -> Void)?
    var content: (Item, Bool) -> Content

    @State private var scrollID: ID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) {
                ForEach(items) { item in
                    let id = item[keyPath: itemID]
                    let centered = scrollID == id || (scrollID == nil && selection == id)

                    carouselItem(item, id: id, centered: centered)
                        .containerRelativeFrame(.horizontal, count: peek, spacing: spacing)
                        .id(id)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 12)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollID)
        .scrollClipDisabled()
        .onAppear {
            // Quarantined: repeating float / bounce carousels impair control.
            scrollID = selection ?? items.first.map { $0[keyPath: itemID] }
        }
        .onChange(of: selection) { _, new in
            guard let new, scrollID != new else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                scrollID = new
            }
            notifySelection(new)
        }
        .onChange(of: scrollID) { _, new in
            guard let new, selection != new else { return }
            selection = new
            notifySelection(new)
        }
        .onChange(of: items.count) { _, _ in
            guard let last = items.last else { return }
            let id = last[keyPath: itemID]
            withAnimation(.easeOut(duration: 0.18)) {
                scrollID = id
            }
        }
    }

    private func notifySelection(_ id: ID) {
        guard let item = items.first(where: { $0[keyPath: itemID] == id }) else { return }
        onSelectionChange?(item)
    }

    @ViewBuilder
    private func carouselItem(_ item: Item, id: ID, centered: Bool) -> some View {
        content(item, centered)
            .scrollTransition(.interactive) { view, phase in
                // Soft scale/opacity only — no 3D rotation or floating bounce.
                view
                    .scaleEffect(1 - abs(phase.value) * 0.06)
                    .opacity(1 - abs(phase.value) * 0.22)
            }
            .shadow(color: .black.opacity(centered ? 0.08 : 0.04), radius: centered ? 10 : 4, y: 4)
    }
}

struct FloatingPathSlide: Identifiable, Hashable {
    let id: String
    let path: String

    init(path: String) {
        self.path = path
        self.id = path
    }
}

struct FloatingPathCard: View {
    let path: String
    var centered: Bool

    var body: some View {
        PhotoPathImageView(path: path, contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: centered ? 18 : 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: centered ? 18 : 14, style: .continuous)
                    .strokeBorder(.white.opacity(centered ? 0.22 : 0.08), lineWidth: 1)
            }
    }
}

struct FloatingPhotoCard: View {
    let photo: PhotoRecord
    var projectName: String?
    var centered: Bool
    var selected: Bool = false

    private var tier: PhotoImageTier { centered ? .proxy : .preview }

    var body: some View {
        PhotoImageView(
            photo: photo,
            tier: tier,
            projectName: centered ? projectName : nil,
            contentMode: .fit
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    selected ? Color.accentColor : .white.opacity(centered ? 0.2 : 0.06),
                    lineWidth: selected ? 3 : 1
                )
        }
    }
}
