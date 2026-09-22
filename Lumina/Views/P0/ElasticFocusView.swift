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
    @State private var captureFacts = ElasticCaptureFacts.unknown

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
            fallbackAssetID = asset.id
            fallbackImage = Self.immediateBrowseImage(for: asset)
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
    /// centred row inside it.
    private var photographBand: some View {
        HStack(spacing: ElasticLayout.photoRowGap) {
            photograph
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            versionColumn
        }
        .padding(.top, ElasticLayout.photoPaddingTop)
        .padding(.horizontal, ElasticLayout.tableGutter)
        .padding(.bottom, ElasticLayout.photoPaddingBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var photograph: some View {
        GeometryReader { geometry in
            let image = presentedImage
            // With no pixels yet the leaf keeps the whole well, so its own clear
            // path runs instead of leaving the last photograph resident.
            let box = image.map { Self.fit($0.extent.size, in: geometry.size) } ?? geometry.size

            ZStack {
                // One permanent Metal leaf owns this click. The clicked JPEG,
                // interactive RAW, and settled RAW replace pixels in place; no
                // promotion remounts or moves the photograph.
                DevelopMetalView(image: image)
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
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            session.closeInspection()
        }
    }

    private var presentedImage: CIImage? {
        let promoted = session.displayedCIImage(for: asset.id)
        let fallback = fallbackAssetID == asset.id ? fallbackImage : nil
        return OrientedDisplayImage.stablePresent(promoted: promoted, fallback: fallback)
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

    // MARK: - Versions

    /// Three fixed versions, stacked beside the photograph: 1 shot · 2 auto · 3 yours.
    private var versionColumn: some View {
        VStack(spacing: ElasticLayout.versionGap) {
            versionTile(1, word: "shot")
            versionTile(2, word: "auto")
            versionTile(3, word: "yours")
        }
        .frame(width: ElasticLayout.versionColumnWidth)
    }

    private func versionTile(_ index: Int, word: String) -> some View {
        let active = session.versionIndex(for: asset) == index
        // `yours` stays legible but unfinished until there is a hand recipe to go back to.
        let unauthored = index == 3 && asset.handRecipe == nil

        return Button {
            session.pickVersion(index, for: asset.id)
        } label: {
            ZStack {
                LuminaTokens.Elastic.deep
                if let path = asset.gridThumbPath ?? asset.thumbPath {
                    ChapterPlateImage(path: path)
                }
            }
            .opacity(unauthored ? ElasticLayout.versionUnauthoredOpacity : 1)
            .aspectRatio(ElasticLayout.tileAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                versionBadge(index, word: word)
                    .padding(ElasticLayout.versionBadgeInset)
            }
            .elasticMarked(radius: ElasticLayout.tileRadius, ringed: active, inSet: false)
        }
        .buttonStyle(LuminaElasticButtonStyle())
        .accessibilityIdentifier(P0AccessibilityID.elasticVersion(index))
    }

    /// `1 shot` — the number in ink, the word in the softer ink beside it.
    private func versionBadge(_ index: Int, word: String) -> some View {
        HStack(spacing: ElasticLayout.versionBadgeGap) {
            Text("\(index)")
                .font(ElasticType.mono(ElasticLayout.versionBadgeTextSize, weight: .semibold))
                .foregroundStyle(LuminaTokens.Elastic.ink)
            Text(word)
                .font(ElasticType.mono(ElasticLayout.versionBadgeTextSize))
                .foregroundStyle(LuminaTokens.Elastic.inkSoft)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, ElasticLayout.versionBadgePaddingH)
        .frame(height: ElasticLayout.versionBadgeHeight)
        .background(
            LuminaTokens.Elastic.shell,
            in: RoundedRectangle(cornerRadius: ElasticLayout.chipRadius, style: .continuous)
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
            Text(session.focusStateWord(for: asset))
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
struct ElasticCaptureFacts: Equatable, Sendable {
    var camera: String
    var exposure: String

    static let unknown = ElasticCaptureFacts(camera: "", exposure: "")

    static func read(atPath path: String) async -> ElasticCaptureFacts {
        guard !path.isEmpty else { return .unknown }
        return await Task.detached(priority: .utility) {
            readSynchronously(atPath: path)
        }.value
    }

    /// `a7 iii · 35 mm` and `1/250 · f/2.8 · iso 400`, leaving out whatever the
    /// file does not say rather than inventing a placeholder for it.
    nonisolated static func readSynchronously(atPath path: String) -> ElasticCaptureFacts {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return .unknown }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        var camera: [String] = []
        if let model = (tiff[kCGImagePropertyTIFFModel] as? String)?
            .trimmingCharacters(in: .whitespaces), !model.isEmpty {
            camera.append(model.lowercased())
        }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double, focal > 0 {
            camera.append("\(Int(focal.rounded())) mm")
        }

        var exposure: [String] = []
        if let seconds = exif[kCGImagePropertyExifExposureTime] as? Double, seconds > 0 {
            exposure.append(shutterLabel(seconds))
        }
        if let aperture = exif[kCGImagePropertyExifFNumber] as? Double, aperture > 0 {
            exposure.append("f/" + trimmed(aperture))
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first, iso > 0 {
            exposure.append("iso \(iso)")
        }

        return ElasticCaptureFacts(
            camera: camera.joined(separator: " · "),
            exposure: exposure.joined(separator: " · ")
        )
    }

    /// `1/250` under a second, `2s` over it — how the camera itself says it.
    nonisolated private static func shutterLabel(_ seconds: Double) -> String {
        if seconds >= 1 { return trimmed(seconds) + "s" }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    /// `2.8` keeps its decimal, `4.0` loses it — apertures read as the lens says them.
    nonisolated private static func trimmed(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

/// The table, compressed. Shoot order, the cursor tile bigger than the rest, and a
/// wider gap wherever one moment ends and the next begins.
struct ElasticFilmstrip: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ElasticLayout.filmstripGap) {
                    Text("time")
                        .font(ElasticType.mono(ElasticLayout.stripLabelSize))
                        .lineSpacing(ElasticType.lineSpacing(
                            size: ElasticLayout.stripLabelSize,
                            lineHeight: ElasticLayout.stripLabelLineHeight
                        ))
                        .foregroundStyle(
                            LuminaTokens.Elastic.shellAlt
                                .opacity(ElasticLayout.stripLabelOpacity)
                        )
                        .frame(width: ElasticLayout.stripLabelWidth, alignment: .leading)

                    ForEach(session.assets) { asset in
                        tile(asset)
                            .id(asset.id)
                            .padding(
                                .trailing,
                                session.startsNewMoment(after: asset.id)
                                    ? ElasticLayout.filmstripMomentGap
                                    : 0
                            )
                    }
                }
                .padding(.horizontal, ElasticLayout.tableGutter)
                .frame(height: ElasticLayout.filmstripHeight)
            }
            .onChange(of: session.focusedAssetID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
        .frame(height: ElasticLayout.filmstripHeight)
        .background(
            LuminaTokens.Elastic.shadowInk.opacity(ElasticLayout.filmstripFillOpacity)
        )
    }

    private func tile(_ asset: AssetRecord) -> some View {
        let focused = session.focusedAssetID == asset.id
        let ringed = focused || session.selectedAssetIDs.contains(asset.id)
        let inSet = session.isInFinalSet(asset.id)
        let size = focused ? ElasticLayout.filmstripFocusedTile : ElasticLayout.filmstripTile

        return ZStack {
            LuminaTokens.Elastic.deep
            if let path = asset.gridThumbPath ?? asset.thumbPath {
                ChapterPlateImage(path: path)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous))
        .elasticMarked(radius: ElasticLayout.tileRadius, ringed: ringed, inSet: inSet)
        .opacity(asset.cull == .reject ? ElasticLayout.outOpacity : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(P0AccessibilityID.elasticTile(asset.id))
        .onTapGesture { session.setFocus(asset.id) }
    }
}
