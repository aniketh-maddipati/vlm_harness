import SwiftUI

/// Grid-tier plate for a chapter cover, a table tile, or a strip thumb.
struct ChapterPlateImage: View {
    let path: String
    @State private var image: NSImage?
    @Environment(\.elasticScrollTracker) private var scrollTracker

    var body: some View {
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
            image = await BrowsePixelService.shared.image(path: path, tier: .grid)
        }
        // Realization is what the scroll path asks for; report it where a
        // tracker is listening so scroll can be measured against it.
        .onAppear { scrollTracker?.plateAppeared(path: path) }
        .onDisappear { scrollTracker?.plateDisappeared(path: path) }
        .onChange(of: path) { old, new in scrollTracker?.plateChanged(from: old, to: new) }
    }
}
