import SwiftUI
import AppKit

struct ExportPayoffState: Equatable {
    var exportRoot: URL
    var carouselFolder: URL?
    var imageURLs: [URL]
    var tasteSummary: String
    var keepCount: Int
    /// Burst-hero carousel subset (`grid_carousel`), not total keeps.
    var highlightCount: Int
}

struct ExportPayoffSheet: View {
    let payoff: ExportPayoffState
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Ready to post")
                .font(.title2.weight(.semibold))

            Text("\(payoff.keepCount) keeps · \(payoff.highlightCount) highlights exported with your look applied")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(payoff.tasteSummary)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            if !payoff.imageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(payoff.imageURLs.prefix(12).enumerated()), id: \.offset) { _, url in
                            ExportThumb(url: url)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 120)
            }

            HStack(spacing: 12) {
                if let folder = payoff.carouselFolder ?? payoff.imageURLs.first?.deletingLastPathComponent() {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                    .buttonStyle(LuminaPressStyle())
                }
                Button("Done") { onDismiss() }
                    .buttonStyle(LuminaPrimaryButtonStyle())
            }
        }
        .padding(28)
        .frame(width: 520)
    }
}

private struct ExportThumb: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(4 / 5, contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: 72, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task {
            image = NSImage(contentsOf: url)
        }
    }
}
