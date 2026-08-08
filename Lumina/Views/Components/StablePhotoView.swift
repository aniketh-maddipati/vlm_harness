import AppKit
import SwiftUI

/// Photograph frame with predetermined aspect geometry.
/// Bridged to `PreviewSpine` + `PhotoImageCache` — never flashes the wrong asset,
/// never clears a lower-fidelity image while a higher one loads.
struct StablePhotoView: View {
    let asset: AssetPresentation
    var contentMode: ContentMode = .fit
    var cornerRadius: CGFloat = LuminaTokens.Radius.photographLarge
    var showDecisionBadge: Bool = false
    var isSelected: Bool = false
    var matte: Color? = nil
    var maxPixelSize: Int = 1600

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var boundAssetID: AssetID?
    @State private var image: NSImage?
    @State private var fidelity: Fidelity = .empty
    @State private var loadFailed = false
    @State private var requestGeneration = 0

    private enum Fidelity: Int, Comparable {
        case empty = 0
        case silhouette = 1
        case preview = 2
        case high = 3

        static func < (lhs: Fidelity, rhs: Fidelity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    var body: some View {
        Color.clear
            .aspectRatio(asset.aspectRatio, contentMode: .fit)
            .overlay {
                ZStack {
                    (matte ?? LuminaTokens.Surface.secondary)
                    photoLayer
                    if showDecisionBadge {
                        badge
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .task(id: asset.id) {
                await loadProgressive(for: asset)
            }
            .onChange(of: asset.previewPath) { _, _ in
                Task { await loadProgressive(for: asset, upgradeOnly: true) }
            }
            .onChange(of: asset.thumbPath) { _, _ in
                Task { await loadProgressive(for: asset, upgradeOnly: true) }
            }
    }

    @ViewBuilder
    private var photoLayer: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(fidelity <= .silhouette ? .medium : .high)
                .aspectRatio(contentMode: contentMode)
                .transition(reduceMotion ? .identity : .opacity.animation(LuminaTokens.Motion.fidelity))
        } else if loadFailed {
            Image(systemName: "photo")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
        } else {
            LuminaTokens.Surface.secondary
        }
    }

    @ViewBuilder
    private var badge: some View {
        if asset.decision != .undecided {
            Text(asset.decision.quietMarker)
                .font(LuminaTokens.Typeface.meta(10))
                .foregroundStyle(badgeForeground)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(LuminaTokens.Surface.porcelain.opacity(0.92))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(badgeBorder, lineWidth: 1)
                }
        }
    }

    private var borderColor: Color {
        if isSelected { return LuminaTokens.Status.selection.opacity(0.85) }
        return LuminaTokens.Line.hairline
    }

    private var borderWidth: CGFloat {
        isSelected ? 1.5 : LuminaTokens.Line.hairlineWidth
    }

    private var badgeBorder: Color {
        switch asset.decision {
        case .cut: LuminaTokens.Status.reject.opacity(0.75)
        case .needsMe: LuminaTokens.Status.needsAttention.opacity(0.55)
        case .keep: LuminaTokens.Ink.primary.opacity(0.25)
        case .anchor: LuminaTokens.Ink.primary.opacity(0.35)
        case .undecided: .clear
        }
    }

    private var badgeForeground: Color {
        switch asset.decision {
        case .cut: LuminaTokens.Status.reject
        case .needsMe: LuminaTokens.Status.needsAttention
        case .keep, .anchor: LuminaTokens.Ink.primary
        case .undecided: LuminaTokens.Ink.secondary
        }
    }

    private var accessibilityLabel: String {
        var parts = [asset.filename]
        if asset.decision != .undecided { parts.append(asset.decision.routingTitle) }
        if isSelected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }

    /// Progressive load: silhouette → preview → high. Never clears a shown image for the same AssetID.
    private func loadProgressive(for asset: AssetPresentation, upgradeOnly: Bool = false) async {
        let requestID = asset.id
        requestGeneration &+= 1
        let generation = requestGeneration

        if boundAssetID != requestID {
            boundAssetID = requestID
            if !upgradeOnly {
                if let sil = PreviewSpine.shared.silhouetteImage(for: requestID) {
                    image = sil
                    fidelity = .silhouette
                } else {
                    image = nil
                    fidelity = .empty
                }
                loadFailed = false
            }
        }

        // 1. Instant silhouette from the warm spine.
        if fidelity < .silhouette,
           let sil = PreviewSpine.shared.silhouetteImage(for: requestID) {
            guard generation == requestGeneration, boundAssetID == requestID else { return }
            commit(image: sil, fidelity: .silhouette, reduceMotion: reduceMotion)
        }

        // 2. Spine fidelity gateway (session cache / browse-safe JPEG). Never RAW.
        let photo = PhotoRecord(
            id: requestID,
            rawPath: asset.previewPath ?? asset.thumbPath ?? "",
            filename: asset.filename,
            thumbPath: asset.previewPath,
            gridThumbPath: asset.thumbPath
        )
        if let spineImage = await PreviewSpine.shared.fidelityImage(
            for: photo,
            maxPixelSize: min(maxPixelSize, 1600)
        ) {
            guard generation == requestGeneration, boundAssetID == requestID else { return }
            commit(image: spineImage, fidelity: .preview, reduceMotion: reduceMotion)
        }

        // 3. Higher path via PhotoImageCache if available — keep prior pixels until ready.
        let candidates = [asset.previewPath, asset.thumbPath].compactMap { $0 }.filter { !$0.isEmpty }
        for path in candidates {
            guard generation == requestGeneration, boundAssetID == requestID else { return }
            let outcome = await PhotoImageCache.shared.load(
                path: path,
                maxPixelSize: maxPixelSize,
                allowRAW: false
            )
            guard generation == requestGeneration, boundAssetID == requestID else { return }
            if case .image(let img) = outcome {
                let next: Fidelity = maxPixelSize >= 2000 ? .high : .preview
                if next >= fidelity {
                    commit(image: img, fidelity: next, reduceMotion: reduceMotion)
                }
                loadFailed = false
                return
            }
        }

        if image == nil {
            loadFailed = true
        }
    }

    private func commit(image: NSImage, fidelity: Fidelity, reduceMotion: Bool) {
        if fidelity < self.fidelity { return }
        if reduceMotion {
            self.image = image
            self.fidelity = fidelity
        } else {
            withAnimation(LuminaTokens.Motion.fidelity) {
                self.image = image
                self.fidelity = fidelity
            }
        }
    }
}

/// Compact filmstrip / card thumbnail with reserved geometry.
struct StableThumbView: View {
    let asset: AssetPresentation
    var isSelected: Bool = false
    var label: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            StablePhotoView(
                asset: asset,
                contentMode: .fit,
                cornerRadius: LuminaTokens.Radius.photographThumb,
                showDecisionBadge: false,
                isSelected: isSelected,
                maxPixelSize: PhotoImageTier.gridMaxPixelSize
            )
            .frame(height: 72)
            if let label {
                Text(label)
                    .font(LuminaTokens.Typeface.meta(11, weight: .medium))
                    .foregroundStyle(isSelected ? LuminaTokens.Ink.primary : LuminaTokens.Ink.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Spine-backed active stage (fast browse path)

/// Active photograph stage wired to PreviewSpine + MetalBrowseCanvas.
/// Selection changes paint the spine — they do not reconstruct the shell.
struct SpineActiveStage: View {
    let assetID: AssetID?
    let filename: String
    let imageAspect: CGFloat
    var isFocusMode: Bool = false
    var onDoubleTap: (() -> Void)? = nil

    @State private var spine = PreviewSpine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var imagePixelSize: CGSize {
        let height = max(imageAspect, 0.05)
        return CGSize(width: height * 1000, height: 1000)
    }

    var body: some View {
        GeometryReader { geo in
            let matte = isFocusMode ? LuminaTokens.Surface.focusMatte : LuminaTokens.Surface.mist
            ZStack {
                matte
                MetalBrowseCanvas(
                    photoID: spine.paintedPhotoID,
                    jpegPath: spine.paintedJPEGPath,
                    imageSize: imagePixelSize,
                    generation: UInt64(spine.generation),
                    photonInputTime: spine.paintedPhotoID.flatMap { spine.pendingPhotonTime(for: $0) },
                    matteIsDark: isFocusMode,
                    onPhotonPresent: { input in
                        spine.recordPhotonPresent(inputTime: input)
                    }
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(
                    cornerRadius: isFocusMode ? 8 : LuminaTokens.Radius.photographLarge,
                    style: .continuous
                ))

                if spine.paintedTier == .silhouette, let image = spine.paintedSilhouette {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                        .opacity(0.92)
                        .allowsHitTesting(false)
                        .transition(reduceMotion ? .identity : .opacity)
                } else if spine.paintedTier == .empty {
                    Text(filename)
                        .font(LuminaTokens.Typeface.meta(12))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                }
            }
            .animation(reduceMotion ? nil : LuminaTokens.Motion.fidelity, value: spine.paintedTier)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onDoubleTap?() }
        }
        .onAppear { paintCurrent() }
        .onChange(of: assetID) { _, _ in paintCurrent() }
    }

    private func paintCurrent() {
        guard let assetID else { return }
        // Validate request identity — never paint a stale ID.
        _ = spine.paint(id: assetID, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
    }
}
