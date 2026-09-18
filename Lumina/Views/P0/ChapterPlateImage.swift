import AppKit
import SwiftUI

/// Grid-tier photograph for a chapter plate — never the 2400 px browse decode.
struct ChapterPlateImage: View {
    let path: String
    @State private var image: NSImage?

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
    }
}
