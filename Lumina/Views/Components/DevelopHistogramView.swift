import AppKit
import SwiftUI

/// RAW-honest histogram at contract size — 252 × 64 above the treatment rail (hi-fi H7).
struct DevelopHistogramView: View {
    var bins: DevelopHistogram.Bins
    var visible: Bool = true

    var body: some View {
        Group {
            if visible {
                Canvas { ctx, size in
                    let luminance = bins.luminance
                    let maxV = max(luminance.max() ?? 1, 1)
                    let barW = size.width / CGFloat(luminance.count)
                    for (index, value) in luminance.enumerated() {
                        let height = CGFloat(value) / CGFloat(maxV) * size.height
                        let rect = CGRect(
                            x: CGFloat(index) * barW,
                            y: size.height - height,
                            width: max(barW, 0.5),
                            height: height
                        )
                        ctx.fill(Path(rect), with: .color(LuminaTokens.Ink.onTable.opacity(0.38)))
                    }
                    // RGB overlay — subtle channel traces.
                    drawChannel(bins.red, in: ctx, size: size, maxV: maxV, opacity: 0.18, hue: 0.0)
                    drawChannel(bins.green, in: ctx, size: size, maxV: maxV, opacity: 0.14, hue: 0.33)
                    drawChannel(bins.blue, in: ctx, size: size, maxV: maxV, opacity: 0.14, hue: 0.62)
                }
                .frame(width: HiFiTokens.Histogram.width, height: HiFiTokens.Histogram.height)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .accessibilityLabel("Develop histogram")
            }
        }
        .frame(width: HiFiTokens.Histogram.width, height: visible ? HiFiTokens.Histogram.height : 0)
        .clipped()
        .opacity(visible ? 1 : 0)
        .accessibilityHidden(!visible)
    }

    private func drawChannel(
        _ channel: [Int],
        in ctx: GraphicsContext,
        size: CGSize,
        maxV: Int,
        opacity: Double,
        hue: Double
    ) {
        let barW = size.width / CGFloat(channel.count)
        var path = Path()
        for (index, value) in channel.enumerated() where value > 0 {
            let height = CGFloat(value) / CGFloat(maxV) * size.height * 0.85
            let x = CGFloat(index) * barW
            path.move(to: CGPoint(x: x, y: size.height))
            path.addLine(to: CGPoint(x: x, y: size.height - height))
        }
        ctx.stroke(path, with: .color(Color(hue: hue, saturation: 0.55, brightness: 0.92).opacity(opacity)), lineWidth: 0.8)
    }
}

extension DevelopHistogramView {
    /// Build bins from the settled display surface, else preview/thumb on disk.
    @MainActor
    static func bins(
        for photoID: AssetID,
        asset: AssetPresentation,
        scheduler: DevelopRenderScheduler = WorkbenchDevelop.scheduler
    ) -> DevelopHistogram.Bins {
        if let cg = scheduler.presentedImage(for: photoID) {
            return DevelopHistogram.compute(from: cg)
        }
        if let path = asset.previewPath ?? asset.thumbPath,
           let image = NSImage(contentsOfFile: path),
           let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return DevelopHistogram.compute(from: cg)
        }
        return .empty
    }
}
