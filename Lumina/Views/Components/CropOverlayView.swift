import SwiftUI

/// Fixed crop boundary; photograph repositions beneath it. Grid rises only while dragging outside.
struct CropOverlayView: View {
    @Binding var session: CropSession
    let aspectRatio: CGFloat

    @State private var dragStart: CropLayoutState?
    @State private var draggingOutside = false

    private var boundaryAspect: CGFloat {
        if session.working.orientationFlipped {
            return max(1 / max(aspectRatio, 0.5), 0.5)
        }
        if session.working.aspectUnlocked {
            return max(aspectRatio, 0.5)
        }
        return max(aspectRatio, 0.5)
    }

    var body: some View {
        GeometryReader { geo in
            let boundary = fixedBoundary(in: geo.size)
            ZStack {
                // Matte outside the boundary
                Color.black.opacity(0.55)
                    .mask {
                        Rectangle()
                            .overlay {
                                Rectangle()
                                    .frame(width: boundary.width, height: boundary.height)
                                    .position(x: boundary.midX, y: boundary.midY)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)

                // Alignment grid — visible only while rotating outside the boundary
                if session.isDraggingOutside || draggingOutside {
                    alignmentGrid(in: boundary)
                        .transition(.opacity)
                }

                // Fixed boundary + handles (18 pt drawn, ≥44 pt hit)
                boundaryChrome(boundary)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragStart == nil { dragStart = session.working }
                        let start = dragStart ?? session.working
                        let inside = boundary.contains(value.startLocation)
                        draggingOutside = !inside
                        session.isDraggingOutside = !inside
                        if inside {
                            let ndx = Double(value.translation.width / max(boundary.width, 1))
                            let ndy = Double(value.translation.height / max(boundary.height, 1))
                            session.working.photoPanX = min(max(start.photoPanX + ndx, -1), 1)
                            session.working.photoPanY = min(max(start.photoPanY + ndy, -1), 1)
                        } else {
                            let delta = Double(value.translation.width / 120)
                            session.setStraighten(start.straightenDegrees + delta)
                        }
                    }
                    .onEnded { _ in
                        dragStart = nil
                        draggingOutside = false
                        session.isDraggingOutside = false
                    }
            )
        }
    }

    private func fixedBoundary(in size: CGSize) -> CGRect {
        let inset: CGFloat = 24
        let maxW = size.width - inset * 2
        let maxH = size.height - inset * 2
        let ratio = max(boundaryAspect, 0.5)
        var w = maxW
        var h = w / ratio
        if h > maxH {
            h = maxH
            w = h * ratio
        }
        return CGRect(
            x: (size.width - w) / 2,
            y: (size.height - h) / 2,
            width: w,
            height: h
        )
    }

    private func boundaryChrome(_ rect: CGRect) -> some View {
        ZStack {
            Rectangle()
                .strokeBorder(Color.white.opacity(0.92), lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            ForEach(handleCenters(rect), id: \.self) { center in
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .position(center)
                    .frame(width: 44, height: 44)
                    .position(center)
                    .contentShape(Circle().scale(44 / 18))
            }
        }
        .allowsHitTesting(false)
    }

    private func handleCenters(_ rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY),
        ]
    }

    private func alignmentGrid(in rect: CGRect) -> some View {
        Path { path in
            let thirdsX = [rect.minX + rect.width / 3, rect.minX + 2 * rect.width / 3]
            let thirdsY = [rect.minY + rect.height / 3, rect.minY + 2 * rect.height / 3]
            for x in thirdsX {
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            for y in thirdsY {
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
    }
}
