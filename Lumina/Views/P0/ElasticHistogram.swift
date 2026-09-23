import SwiftUI

struct ElasticHistogram: View {
    let bins: [Int]
    let shift: Int
    let clipsShadows: Bool
    let clipsHighlights: Bool

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / ElasticLayout.histogramViewWidth
            let scaleY = size.height / ElasticLayout.histogramViewHeight

            if let path = Self.path(bins: bins, shift: shift) {
                context.fill(
                    path.applying(CGAffineTransform(scaleX: scaleX, y: scaleY)),
                    with: .color(
                        LuminaTokens.Elastic.shellAlt
                            .opacity(ElasticLayout.histogramFillOpacity)
                    )
                )
            }

            if clipsShadows {
                context.fill(tick(at: 0, scaleX: scaleX, height: size.height), with: .color(LuminaTokens.Elastic.warn))
            }
            if clipsHighlights {
                context.fill(
                    tick(at: ElasticLayout.clipTickRight, scaleX: scaleX, height: size.height),
                    with: .color(LuminaTokens.Elastic.warn)
                )
            }
        }
        .frame(width: ElasticLayout.histogramSize.width, height: ElasticLayout.histogramSize.height)
        .accessibilityHidden(true)
    }

    private func tick(at x: CGFloat, scaleX: CGFloat, height: CGFloat) -> Path {
        Path(CGRect(
            x: x * scaleX,
            y: 0,
            width: ElasticLayout.clipTickWidth * scaleX,
            height: height
        ))
    }

    /// `M0 20 L1 … L64 20 Z` — one point per bin, the tallest one unit short of the
    /// top, the whole shape slid by `shift` bins and clamped at both ends.
    static func path(bins: [Int], shift: Int) -> Path? {
        guard !bins.isEmpty, let peak = bins.max(), peak > 0 else { return nil }
        let lastBin = bins.count - 1
        let baseline = ElasticLayout.histogramViewHeight

        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseline))
        for (index, bin) in bins.enumerated() {
            let slot = min(lastBin, max(0, index + shift))
            let x = CGFloat(slot) * ElasticLayout.histogramBinStride + ElasticLayout.histogramBarOffset
            let y = baseline
                - CGFloat(Double(bin) / Double(peak)) * ElasticLayout.histogramPeakHeight
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: ElasticLayout.histogramViewWidth, y: baseline))
        path.closeSubpath()
        return path
    }
}

/// Camera and exposure as the file itself records them.
///
/// Read off the original with ImageIO on a background thread — the status bar is
/// the only place these appear, and nothing in the catalog caches them.
