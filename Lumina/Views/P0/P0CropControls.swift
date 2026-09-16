import SwiftUI

/// Crop / straighten / rotate controls for the P0 edit rail.
struct P0CropControls: View {
    @Bindable var session: P0SessionModel
    let assetID: UUID

    private var recipe: EditRecipe { session.recipe(for: assetID) }

    private var fineStraighten: Double {
        let turns = (recipe.straightenDegrees / 90.0).rounded()
        return recipe.straightenDegrees - turns * 90
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Aspect")
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.tertiary)

            HStack(spacing: 8) {
                ratioButton("Original", ratio: nil)
                ratioButton("1:1", ratio: 1)
                ratioButton("4:5", ratio: 4.0 / 5.0)
                ratioButton("3:2", ratio: 3.0 / 2.0)
            }

            P0EditSlider(
                title: "Straighten",
                value: fineStraighten,
                range: -45...45,
                step: 0.1,
                display: { String(format: "%+.1f°", $0) },
                neutral: 0,
                enabled: true,
                onBegin: { session.beginEditGesture(for: assetID) },
                onScrub: { fine in
                    session.scrubEdit { recipe in
                        let turns = (recipe.straightenDegrees / 90.0).rounded()
                        recipe.straightenDegrees = turns * 90 + fine
                    }
                },
                onEnd: { session.endEditGesture() },
                onReset: {
                    session.applyEditMutation({ recipe in
                        let turns = (recipe.straightenDegrees / 90.0).rounded()
                        recipe.straightenDegrees = turns * 90
                    }, assetID: assetID)
                }
            )

            HStack(spacing: 10) {
                Button {
                    session.applyEditMutation({ $0.straightenDegrees -= 90 }, assetID: assetID)
                } label: {
                    Label("Rotate left", systemImage: "rotate.left")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .help("Rotate 90° counter-clockwise")

                Button {
                    session.applyEditMutation({ $0.straightenDegrees += 90 }, assetID: assetID)
                } label: {
                    Label("Rotate right", systemImage: "rotate.right")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .help("Rotate 90° clockwise")

                Spacer()

                Button("Reset crop") {
                    session.applyEditMutation({ recipe in
                        recipe.crop = nil
                        recipe.straightenDegrees = 0
                    }, assetID: assetID)
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .frame(minHeight: 44)
                .disabled(!recipe.hasGeometry)
            }

            Text("Drag handles on the photograph to refine the crop.")
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ratioButton(_ title: String, ratio: Double?) -> some View {
        let active: Bool = {
            guard let crop = recipe.crop, !crop.isFullFrame else {
                return ratio == nil
            }
            guard let ratio else { return false }
            let current = crop.width / max(crop.height, 0.000_1)
            return abs(current - ratio) < 0.02 || abs(current - (1 / ratio)) < 0.02
        }()

        return Button {
            session.applyEditMutation({ recipe in
                guard let ratio else {
                    recipe.crop = nil
                    return
                }
                recipe.crop = Self.centeredCrop(aspect: ratio)
            }, assetID: assetID)
        } label: {
            Text(title)
                .font(LuminaTokens.Typeface.meta(12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? LuminaTokens.Ink.primary : LuminaTokens.Ink.secondary)
                .frame(minWidth: 64, minHeight: LuminaTokens.HitTarget.minimum)
                .padding(.horizontal, 8)
                .background(active ? LuminaTokens.Surface.highlight : LuminaTokens.Surface.well)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(LuminaTokens.Line.hairline, lineWidth: LuminaTokens.Line.hairlineWidth)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(LuminaQuietButtonStyle())
    }

    /// Centered crop in oriented image space for a target width/height ratio.
    static func centeredCrop(aspect: Double) -> EditCrop {
        let target = max(aspect, 0.01)
        if target >= 1 {
            let height = 1 / target
            let y = (1 - height) / 2
            return EditCrop(x: 0, y: y, width: 1, height: height).normalized()
        } else {
            let width = target
            let x = (1 - width) / 2
            return EditCrop(x: x, y: 0, width: width, height: 1).normalized()
        }
    }
}

/// Direct crop manipulation overlay in oriented image space.
struct P0CropOverlay: View {
    @Bindable var session: P0SessionModel
    let assetID: UUID
    let imageSize: CGSize

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    @State private var dragStartCrop: EditCrop?
    @State private var dragCorner: Corner = .bottomRight

    private var recipe: EditRecipe { session.recipe(for: assetID) }
    private var crop: EditCrop { recipe.crop ?? .full }

    var body: some View {
        GeometryReader { geo in
            let fit = aspectFitRect(imageSize: imageSize, in: geo.size)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(fit)
                    path.addRect(cropRect(in: fit))
                }
                .fill(Color.black.opacity(0.28), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                Rectangle()
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                    .frame(width: cropRect(in: fit).width, height: cropRect(in: fit).height)
                    .position(
                        x: cropRect(in: fit).midX,
                        y: cropRect(in: fit).midY
                    )
                    .allowsHitTesting(false)

                ForEach(Corner.allCases, id: \.self) { corner in
                    handle(for: corner, in: fit)
                }
            }
        }
        .allowsHitTesting(session.expandedAdjustmentSection == .crop)
    }

    private func handle(for corner: Corner, in fit: CGRect) -> some View {
        let point = handlePoint(corner, in: fit)
        return Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .position(point)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartCrop == nil {
                            dragStartCrop = crop
                            dragCorner = corner
                            session.beginEditGesture(for: assetID)
                        }
                        let start = dragStartCrop ?? crop
                        let next = updatedCrop(
                            start: start,
                            corner: dragCorner,
                            translation: value.translation,
                            fit: fit
                        )
                        session.scrubEdit { $0.crop = next.isFullFrame ? nil : next }
                    }
                    .onEnded { _ in
                        session.endEditGesture()
                        dragStartCrop = nil
                    }
            )
    }

    private func cropRect(in fit: CGRect) -> CGRect {
        CGRect(
            x: fit.minX + CGFloat(crop.x) * fit.width,
            y: fit.minY + CGFloat(crop.y) * fit.height,
            width: CGFloat(crop.width) * fit.width,
            height: CGFloat(crop.height) * fit.height
        )
    }

    private func handlePoint(_ corner: Corner, in fit: CGRect) -> CGPoint {
        let r = cropRect(in: fit)
        switch corner {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    private func updatedCrop(
        start: EditCrop,
        corner: Corner,
        translation: CGSize,
        fit: CGRect
    ) -> EditCrop {
        guard fit.width > 1, fit.height > 1 else { return start }
        let dx = Double(translation.width / fit.width)
        let dy = Double(translation.height / fit.height)
        var x = start.x
        var y = start.y
        var w = start.width
        var h = start.height
        switch corner {
        case .topLeft:
            x += dx; y += dy; w -= dx; h -= dy
        case .topRight:
            y += dy; w += dx; h -= dy
        case .bottomLeft:
            x += dx; w -= dx; h += dy
        case .bottomRight:
            w += dx; h += dy
        }
        return EditCrop(x: x, y: y, width: w, height: h).normalized()
    }

    private func aspectFitRect(imageSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(
            x: (bounds.width - w) / 2,
            y: (bounds.height - h) / 2,
            width: w,
            height: h
        )
    }
}
