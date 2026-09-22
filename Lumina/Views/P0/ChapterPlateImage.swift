import SwiftUI

/// Grid-tier plate for a chapter cover, a table tile, or a strip thumb.
///
/// The body samples what is already resident and draws it in the same pass —
/// no state hop, so a row whose pixels are in the cache never shows the well.
/// Only a miss enqueues, and the enqueue awaits; it never decodes inline.
struct ChapterPlateImage: View {
    let path: String
    /// Pixels that arrived after a miss, tagged with the path they belong to
    /// so a recycled plate never shows the previous frame.
    @State private var loaded: (path: String, image: NSImage)?
    @Environment(\.elasticScrollTracker) private var scrollTracker

    var body: some View {
        let image = resident
        ZStack {
            LuminaTokens.Surface.well
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .antialiased(true)
                    .scaledToFill()
            }
        }
        .clipped()
        .task(id: path) {
            guard image == nil else { return }
            if let fetched = await BrowsePixelService.shared.image(path: path, tier: .grid) {
                loaded = (path, fetched)
            }
        }
        // Realization is what the scroll path asks for; report it where a
        // tracker is listening so scroll can be measured against it.
        .onAppear { scrollTracker?.plateAppeared(path: path) }
        .onDisappear { scrollTracker?.plateDisappeared(path: path) }
        .onChange(of: path) { old, new in scrollTracker?.plateChanged(from: old, to: new) }
    }

    /// Resident pixels for this path, from the cache mirror or from the last
    /// completed miss — whichever answers without waiting.
    private var resident: NSImage? {
        if let loaded, loaded.path == path { return loaded.image }
        return BrowsePixelService.shared.residentPixel(path: path, tier: .grid)?.nsImage
    }
}
