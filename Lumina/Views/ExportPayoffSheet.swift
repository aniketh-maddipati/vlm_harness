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

/// Finished work as atmosphere — not a dialog.
struct ExportPayoffSheet: View {
    let payoff: ExportPayoffState
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 28) {
                Spacer(minLength: 40)

                Text("Finished")
                    .font(LuminaAtmosphere.Typeface.brand(40))
                    .foregroundStyle(Color.white.opacity(0.94))

                Text("\(payoff.highlightCount) highlights · \(payoff.keepCount) keeps")
                    .font(LuminaAtmosphere.Typeface.body(15))
                    .foregroundStyle(LuminaAtmosphere.whisper)

                if !payoff.tasteSummary.isEmpty {
                    Text(payoff.tasteSummary)
                        .font(LuminaAtmosphere.Typeface.caption(12))
                        .foregroundStyle(LuminaAtmosphere.breath)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                if !payoff.imageURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(payoff.imageURLs.prefix(12).enumerated()), id: \.offset) { _, url in
                                ExportThumb(url: url)
                            }
                        }
                        .padding(.horizontal, 40)
                    }
                    .frame(height: 220)
                }

                Spacer(minLength: 20)

                HStack(spacing: 20) {
                    if let folder = payoff.carouselFolder ?? payoff.imageURLs.first?.deletingLastPathComponent() {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        }
                        .buttonStyle(LuminaGhostButtonStyle())
                    }
                    Button("Done") { onDismiss() }
                        .buttonStyle(LuminaPrimaryButtonStyle())
                }
                .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        }
        .frame(width: 140, height: 175)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        .task {
            image = NSImage(contentsOf: url)
        }
    }
}
