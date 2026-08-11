import SwiftUI

/// Drag on empty table space — selects every photograph the band touches (trackpad act only).
struct TableRubberBandOverlay: View {
    let tileFrames: [AssetID: CGRect]
    let onRubberBand: ([AssetID]) -> Void

    @State private var origin: CGPoint?
    @State private var current: CGPoint?

    private var bandRect: CGRect? {
        guard let origin, let current else { return nil }
        return CGRect(
            x: min(origin.x, current.x),
            y: min(origin.y, current.y),
            width: abs(current.x - origin.x),
            height: abs(current.y - origin.y)
        )
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { value in
                                if origin == nil { origin = value.startLocation }
                                current = value.location
                            }
                            .onEnded { value in
                                let start = origin ?? value.startLocation
                                let end = value.location
                                let rect = CGRect(
                                    x: min(start.x, end.x),
                                    y: min(start.y, end.y),
                                    width: abs(end.x - start.x),
                                    height: abs(end.y - start.y)
                                )
                                let touched = tileFrames.compactMap { id, frame -> AssetID? in
                                    rect.intersects(frame) ? id : nil
                                }
                                if !touched.isEmpty {
                                    onRubberBand(touched)
                                }
                                origin = nil
                                current = nil
                            }
                    )

                if let rect = bandRect {
                    Rectangle()
                        .strokeBorder(HiFiTokens.Ring.selection.opacity(0.85), lineWidth: 1)
                        .background(HiFiTokens.Ring.selection.opacity(0.08))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
