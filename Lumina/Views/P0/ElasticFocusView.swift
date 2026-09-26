import AppKit
import CoreImage
import ImageIO
import SwiftUI

/// The focus route — one photograph on the matte, the always-on Develop rail
/// beside it, and the frame's own facts along the bottom.
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
    @State private var canvasDropTargeted = false

    init(session: P0SessionModel, asset: AssetRecord) {
        self.session = session
        self.asset = asset
        _fallbackImage = State(initialValue: Self.immediateBrowseImage(for: asset))
        _fallbackAssetID = State(initialValue: asset.id)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                photographBand
                statusBar
            }
            if session.noteFloaterOpen {
                ElasticNoteFloater(session: session, asset: asset)
                    .padding(.top, ElasticLayout.noteFloaterInsetTop)
                    .padding(.trailing, ElasticLayout.noteFloaterInsetTrailing)
                    .elasticBorn(ElasticLayout.bornNoteFloaterMs)
                    .transition(.opacity)
            }
        }
        .animation(LuminaTokens.Motion.travel, value: session.noteFloaterOpen)
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

    /// `padding: 24px 28px 12px` — the photograph and the always-on Develop rail
    /// share one centred row. While similar is held the row yields the band to the
    /// neighbours; it stays mounted underneath, so the Metal leaf is never rebuilt.
    private var photographBand: some View {
        let showingRelated = session.peek == .related
        return ZStack {
            HStack(spacing: ElasticLayout.photoRowGap) {
                photograph
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Sticky Develop rail — always on in focus; peeks put it away.
                if session.peek == nil {
                    ElasticDevelopDrawer(session: session, asset: asset)
                        .elasticBorn(ElasticLayout.bornDrawerMs)
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
        // The inspect plate is a settled button. Single press does not decide;
        // double-press returns. Hold still opens before (Law 2). Pinch/scroll
        // stay on FocusZoomMonitor (hitTest is nil).
        ElasticPlateButton(onDoubleTap: {
            session.closeInspection()
        }) {
            photographWell
        }
        .onLongPressGesture(minimumDuration: ElasticLayout.beforePressSeconds) {
            session.setShowingBefore(true)
        } onPressingChanged: { pressing in
            if !pressing {
                session.setShowingBefore(false)
            }
        }
    }

    private var photographWell: some View {
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
        // Drop a photograph onto the canvas to open it. The double-tap-to-return
        // and hold-for-before gestures live on the inspect plate (see `photograph`),
        // not here — duplicating them would put competing recognizers on nested views.
        .overlay {
            if canvasDropTargeted {
                RoundedRectangle(cornerRadius: ElasticLayout.photoRadius, style: .continuous)
                    .inset(by: ElasticLayout.shelfDropRingInset)
                    .strokeBorder(
                        LuminaTokens.Elastic.shellAlt,
                        style: StrokeStyle(
                            lineWidth: ElasticLayout.shelfDropRingWidth,
                            dash: ElasticLayout.shelfDropRingDash
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
        .animation(LuminaTokens.Motion.selection, value: canvasDropTargeted)
        .dropDestination(for: String.self) { payloads, _ in
            openDroppedPhotograph(payloads)
        } isTargeted: { targeted in
            canvasDropTargeted = targeted
        }
    }

    /// Drop on the inspect well travels: focus + open. Never writes cull, recipe, or selection.
    private func openDroppedPhotograph(_ payloads: [String]) -> Bool {
        let ids = payloads.flatMap(ElasticDragPayload.decode)
        guard let id = ids.first, session.asset(id) != nil else { return false }
        session.setFocus(id)
        session.openFocusedPhotograph()
        return true
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

            if session.peek == nil, asset.isUnsupportedVideo != true {
                ElasticOperationButton(
                    title: "Reject",
                    on: session.outToggleIsOn([asset.id])
                ) {
                    session.classifyOut([asset.id])
                }
                .accessibilityIdentifier(P0AccessibilityID.pointerCullReject)
            }

            ElasticHistogram(
                bins: asset.imageStats?.luminanceBins ?? [],
                shift: session.histogramBinShift(for: asset),
                shotShift: 0,
                autoShift: session.autoHistogramShift(for: asset),
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

/// Fading note near the focused photograph — not pinned to the frame. Typing
/// writes `AssetRecord.note`; Esc / two-finger swipe down dismisses.
private struct ElasticNoteFloater: View {
    @Bindable var session: P0SessionModel
    let asset: AssetRecord
    @FocusState private var focused: Bool
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: ElasticLayout.noteFloaterGap) {
            Text(CopyContract.noteFloaterLabel)
                .font(ElasticType.mono(ElasticLayout.noteFloaterLabelSize))
                .opacity(ElasticLayout.drawerMutedOpacity)
            TextField(CopyContract.noteFloaterPlaceholder, text: $draft, axis: .vertical)
                .font(ElasticType.sans(ElasticLayout.noteFloaterTextSize))
                .foregroundStyle(LuminaTokens.Elastic.shellAlt)
                .lineLimit(2...6)
                .focused($focused)
                .onChange(of: draft) { _, next in
                    session.setNote(next, for: asset.id)
                }
        }
        .padding(ElasticLayout.noteFloaterPadding)
        .frame(width: ElasticLayout.noteFloaterWidth, alignment: .leading)
        .background(
            LuminaTokens.Elastic.ink.opacity(ElasticLayout.noteFloaterFillOpacity),
            in: RoundedRectangle(cornerRadius: ElasticLayout.noteFloaterRadius, style: .continuous)
        )
        .gesture(
            DragGesture(minimumDistance: ElasticLayout.noteFloaterSwipeMinimum)
                .onEnded { value in
                    if value.translation.height > ElasticLayout.noteFloaterSwipeDismiss {
                        session.dismissNoteFloater()
                    }
                }
        )
        .onAppear {
            draft = asset.note ?? ""
            focused = true
        }
        .onChange(of: asset.id) { _, _ in
            draft = session.asset(asset.id)?.note ?? ""
        }
    }
}

/// The measured luminance histogram, drawn as the design's 64×20 user space scaled
/// into a 96×30 box, with a salmon tick wherever the frame is clipping.
