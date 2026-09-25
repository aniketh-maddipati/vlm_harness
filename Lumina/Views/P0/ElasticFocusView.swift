import AppKit
import CoreImage
import ImageIO
import SwiftUI

/// The focus route — one photograph on the matte, its three versions beside it,
/// and the frame's own facts along the bottom.
///
/// Pixels come through the one permanent Metal leaf; this view owns layout, marks
/// and copy only. The photograph is sized to its own aspect-fit box rather than
/// filling the band, so the corner radius and the drop shadow trace the picture
/// instead of the well it sits in. Peeks, before, and the develop drawer land in
/// later checkpoints.
struct ElasticFocusView: View {
    @Bindable var session: P0SessionModel
    let asset: AssetRecord

    @State private var fallbackImage: CIImage?
    @State private var fallbackAssetID: UUID?
    @State private var retainedFrame: OrientedDisplayImage.DisplayFrame?
    @State private var retainedSince = ProcessInfo.processInfo.systemUptime
    @State private var captureFacts = ElasticCaptureFacts.unknown
    @State private var focusZoom = FocusZoom()
    @State private var placedExtent: CGSize = .zero
    @State private var glide = CGSize.zero
    @State private var glidePages = true

    init(session: P0SessionModel, asset: AssetRecord) {
        self.session = session
        self.asset = asset
        _fallbackImage = State(initialValue: Self.immediateBrowseImage(for: asset))
        _fallbackAssetID = State(initialValue: asset.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            photographBand
            statusBar
        }
        .background(LuminaTokens.Elastic.matte)
        .onDisappear {
            session.flushPendingEditIfNeeded()
            Task { await BrowsePixelService.shared.clearFocusedPin() }
        }
        .onChange(of: asset.id) { _, _ in
            retainedFrame = nil
            fallbackAssetID = asset.id
            fallbackImage = Self.immediateBrowseImage(for: asset)
            focusZoom = FocusZoom()
            placedExtent = .zero
            glide = .zero
            glidePages = true
        }
        .task(id: asset.id) {
            await loadStableFallback()
        }
        .task(id: asset.source.originalPath) {
            let path = asset.source.originalPath
            captureFacts = await ElasticCaptureFacts.read(atPath: path)
        }
    }

    // MARK: - Photograph

    /// `padding: 24px 28px 12px` — the photograph and the version column share one
    /// centred row inside it. While similar is held the row yields the band to the
    /// neighbours; it stays mounted underneath, so the Metal leaf is never rebuilt.
    private var photographBand: some View {
        let showingRelated = session.peek == .related
        return ZStack {
            HStack(spacing: ElasticLayout.photoRowGap) {
                photograph
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // `develop: s.develop && !s.hold` — a held peek puts the drawer away.
                if session.developDrawerOpen, session.peek == nil {
                    ElasticDevelopDrawer(session: session, asset: asset)
                        .elasticBorn(ElasticLayout.bornDrawerMs)
                }
                // `variantsCol: none` while developing or holding.
                if session.versionColumnVisible {
                    ElasticVersionColumn(session: session, asset: asset)
                }
            }
            .opacity(showingRelated ? 0 : 1)
            .allowsHitTesting(!showingRelated)

            if showingRelated {
                ElasticRelatedRow(session: session)
                    .elasticBorn(ElasticLayout.bornRelatedMs)
            }
        }
        .padding(.top, ElasticLayout.photoPaddingTop)
        .padding(.horizontal, ElasticLayout.tableGutter)
        .padding(.bottom, ElasticLayout.photoPaddingBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var photograph: some View {
        GeometryReader { geometry in
            let selection = selectedFrame
            let image = selection?.image
            // With no pixels yet the leaf keeps the whole well, so its own clear
            // path runs instead of leaving the last photograph resident.
            let box = selection.map { Self.fit($0.layoutSize, in: geometry.size) } ?? geometry.size

            ZStack {
                // One permanent Metal leaf owns this click. The clicked JPEG,
                // interactive RAW, and settled RAW replace pixels in place; no
                // promotion remounts or moves the photograph.
                DevelopMetalView(
                    image: image,
                    measurementIdentity: selection?.identity,
                    rawStageBacking: selection?.rawStageBacking ?? .unattributed,
                    zoom: focusZoom.zoom,
                    panOffset: focusZoom.pan
                )
                    .frame(width: box.width, height: box.height)
                    .clipShape(
                        RoundedRectangle(cornerRadius: ElasticLayout.photoRadius, style: .continuous)
                    )
                    .shadow(
                        color: LuminaTokens.Elastic.shadowInk
                            .opacity(ElasticLayout.photoShadowOpacity),
                        radius: ElasticLayout.photoShadowRadius,
                        x: 0,
                        y: ElasticLayout.photoShadowY
                    )
                    .accessibilityElement()
                    .accessibilityIdentifier(P0AccessibilityID.singlePhotoImage)
                    .accessibilityValue(asset.source.availability.rawValue)

                if image == nil {
                    Text(session.fidelityNotice ?? "Preparing photograph…")
                        .font(ElasticType.mono(ElasticLayout.statusTextSize))
                        .foregroundStyle(
                            LuminaTokens.Elastic.shellAlt
                                .opacity(ElasticLayout.statusTextOpacity)
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onChange(of: image, initial: true) { _, _ in
                DevelopPresentationTrace.shared.record("canvas-selected-frame", identity: selection?.identity,
                    values: ["requestedRecipeFingerprint": requestedRecipe.valueFingerprint,
                             "previousFrameAgeMs": (ProcessInfo.processInfo.systemUptime - retainedSince) * 1000,
                             "boxWidth": box.width, "boxHeight": box.height,
                             "matchesRequest": selection?.recipe?.valueFingerprint == requestedRecipe.valueFingerprint])
                retainedFrame = selection
                retainedSince = ProcessInfo.processInfo.systemUptime
                let extent = image?.extent.size ?? .zero
                if placedExtent.width > 1, extent.width > 1 {
                    focusZoom.rebase(from: placedExtent, to: extent)
                }
                placedExtent = extent
            }
            .onChange(of: requestedRecipe.valueFingerprint, initial: true) { _, _ in
                DevelopPresentationTrace.shared.record("canvas-selection", identity: selection?.identity,
                    values: ["requestedRecipeFingerprint": requestedRecipe.valueFingerprint,
                             "selectedFrameAgeMs": (ProcessInfo.processInfo.systemUptime - retainedSince) * 1000,
                             "matchesRequest": selection?.recipe?.valueFingerprint == requestedRecipe.valueFingerprint])
            }
            .overlay {
                FocusZoomMonitor(
                    enabled: session.peek == nil,
                    well: geometry.size,
                    photo: box,
                    onMagnify: { delta, point, ended, backing in
                        let limit = zoomLimit(box: box, backing: backing)
                        focusZoom.magnify(by: delta, at: point, in: box, maxZoom: limit, rubber: true)
                        if ended { settleZoom(in: box, backing: backing) }
                    },
                    onScroll: { dx, dy, began, ended, backing in
                        if began {
                            glide = .zero
                            glidePages = true
                        }
                        if focusZoom.zoom > FocusZoom.fit {
                            focusZoom.pan(by: CGSize(width: dx, height: -dy), in: box, rubber: true)
                        } else {
                            glide.width += dx
                            glide.height += dy
                            if glidePages, let step = FocusZoom.page(dx: glide.width, dy: glide.height, zoom: focusZoom.zoom) {
                                glidePages = false
                                session.moveFocus(dx: step, dy: 0, columns: 1)
                            }
                        }
                        if ended { settleZoom(in: box, backing: backing) }
                    },
                    onSmartZoom: { point, backing in
                        let limit = zoomLimit(box: box, backing: backing)
                        focusZoom.toggleSmart(at: point, in: box, maxZoom: limit)
                    }
                )
            }
        }
        .contentShape(Rectangle())
        // Double-click returns to the table. It is not a zoom.
        .onTapGesture(count: 2) {
            session.closeInspection()
        }
        // Pointer parity for hold-␣: press and hold the photograph for before.
        .onLongPressGesture(minimumDuration: ElasticLayout.beforePressSeconds) {
            session.setShowingBefore(true)
        } onPressingChanged: { pressing in
            if !pressing {
                session.setShowingBefore(false)
            }
        }
    }

    private func zoomLimit(box: CGSize, backing: CGFloat) -> CGFloat {
        FocusZoom.maximum(
            sensor: session.renderedPixelSize(for: asset.id),
            box: box,
            backingScale: backing
        )
    }

    private func settleZoom(in box: CGSize, backing: CGFloat) {
        let limit = zoomLimit(box: box, backing: backing)
        withAnimation(LuminaTokens.Motion.travel) {
            focusZoom.settle(in: box, maxZoom: limit)
        }
    }

    private var requestedRecipe: EditRecipe {
        session.showingBefore ? .neutral : session.recipe(for: asset.id)
    }

    private var selectedFrame: OrientedDisplayImage.DisplayFrame? {
        let fallback = fallbackImage.flatMap { image -> OrientedDisplayImage.DisplayFrame? in
            guard let fallbackAssetID else { return nil }
            return OrientedDisplayImage.DisplayFrame(assetID: fallbackAssetID, image: image, recipe: nil,
                layoutSize: image.extent.size,
                identity: session.displayedImageIdentity(for: fallbackAssetID, selected: image))
        }
        return OrientedDisplayImage.select(assetID: asset.id, recipe: requestedRecipe,
            promoted: session.displayFrame(for: asset.id), fallback: fallback, retained: retainedFrame)
    }

    /// `object-fit: contain` — the picture's own box inside the space it is given.
    private static func fit(_ extent: CGSize, in available: CGSize) -> CGSize {
        guard extent.width > 0, extent.height > 0,
              available.width > 0, available.height > 0 else { return available }
        let scale = min(available.width / extent.width, available.height / extent.height)
        return CGSize(width: extent.width * scale, height: extent.height * scale)
    }

    /// Resolve the clicked asset's durable browse currency once and pin it, so the
    /// photograph never blanks while RAW promotion is still in flight. A stale
    /// completion is ignored after the cursor moves on.
    @MainActor
    private func loadStableFallback() async {
        let requestedID = asset.id
        let paths = [asset.thumbPath, asset.gridThumbPath, asset.proxyPath]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        await BrowsePixelService.shared.pinFocused(paths: paths)

        guard !Task.isCancelled, asset.id == requestedID else { return }
        fallbackAssetID = requestedID
        let started = CFAbsoluteTimeGetCurrent()
        for path in paths {
            guard !Task.isCancelled else { return }
            if let pixel = await BrowsePixelService.shared.pixel(path: path, tier: .focused) {
                guard !Task.isCancelled, asset.id == requestedID else { return }
                fallbackImage = OrientedDisplayImage.ciImage(fromOrientedPixels: pixel.cgImage)
                LatencyMetrics.record(
                    "p0.edit.open_preview_ms",
                    milliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000
                )
                return
            }
        }
    }

    private static func immediateBrowseImage(for asset: AssetRecord) -> CIImage? {
        guard let path = asset.thumbPath ?? asset.gridThumbPath ?? asset.proxyPath else { return nil }
        return OrientedDisplayImage.ciImage(
            at: URL(fileURLWithPath: path),
            maxPixelSize: PhotoImageTier.focusedPreviewLongEdge
        )
    }


    // MARK: - Status bar

    /// time · camera · exposure · file · — · histogram · readout · state.
    private var statusBar: some View {
        HStack(spacing: ElasticLayout.statusGap) {
            Text(session.focusTimeLabel(for: asset))
            Text(captureFacts.camera)
            Text(captureFacts.exposure)
            Text(session.focusFileStem(for: asset))

            // `<span style="flex:1">` — an empty child, so the bar's own gap still
            // sits on both sides of it.
            Spacer(minLength: 0)

            ElasticHistogram(
                bins: asset.imageStats?.luminanceBins ?? [],
                shift: session.histogramBinShift(for: asset),
                clipsShadows: session.showsShadowClipTick(for: asset),
                clipsHighlights: session.showsHighlightClipTick(for: asset)
            )
            Text(session.histogramReadout(for: asset))
            Text(selectedFrame?.recipe?.valueFingerprint == requestedRecipe.valueFingerprint
                 ? session.focusStateWord(for: asset) : CopyContract.staleRender)
                // Held `before` is the one thing the bar says in the warm accent.
                .foregroundStyle(
                    session.showingBefore
                        ? LuminaTokens.Elastic.warmAccent
                        : LuminaTokens.Elastic.shellAlt.opacity(ElasticLayout.statusTextOpacity)
                )
        }
        .font(ElasticType.mono(ElasticLayout.statusTextSize))
        .foregroundStyle(LuminaTokens.Elastic.shellAlt.opacity(ElasticLayout.statusTextOpacity))
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, ElasticLayout.tableGutter)
        .padding(.top, ElasticLayout.statusPaddingTop)
        .padding(.bottom, ElasticLayout.statusPaddingBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LuminaTokens.Elastic.matte)
    }
}

/// The measured luminance histogram, drawn as the design's 64×20 user space scaled
/// into a 96×30 box, with a salmon tick wherever the frame is clipping.
