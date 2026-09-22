import AppKit
import CoreImage
import SwiftUI

/// The focus route — one photograph, centered, walked in shoot order.
///
/// Pixels come through the existing Metal canvas; this view owns layout and marks
/// only. Peeks, before, and the develop drawer land in later checkpoints.
struct ElasticFocusView: View {
    @Bindable var session: P0SessionModel
    let asset: AssetRecord

    @State private var fallbackImage: CIImage?
    @State private var fallbackAssetID: UUID?

    private var recipe: EditRecipe { session.recipe(for: asset.id) }

    init(session: P0SessionModel, asset: AssetRecord) {
        self.session = session
        self.asset = asset
        _fallbackImage = State(initialValue: Self.immediateBrowseImage(for: asset))
        _fallbackAssetID = State(initialValue: asset.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                photograph
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ElasticVersionColumn(session: session, asset: asset)
                    .frame(width: ElasticLayout.versionColumnWidth)
            }
            metadataBar
        }
        .background(LuminaTokens.Elastic.shell)
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

    private var photograph: some View {
        ZStack {
            LuminaTokens.Elastic.matte

            let promoted = session.displayedCIImage(for: asset.id)
            let fallback = fallbackAssetID == asset.id ? fallbackImage : nil
            let image = OrientedDisplayImage.stablePresent(promoted: promoted, fallback: fallback)

            // One permanent Metal leaf owns this click. The clicked JPEG, interactive
            // RAW, and settled RAW replace pixels in place; no promotion remounts or
            // moves the photograph.
            DevelopMetalView(image: image)
                .padding(LuminaTokens.Spacing.lg)
                .accessibilityElement()
                .accessibilityIdentifier(P0AccessibilityID.singlePhotoImage)
                .accessibilityValue(asset.source.availability.rawValue)

            if image == nil {
                Text(session.fidelityNotice ?? "Preparing photograph…")
                    .font(LuminaTokens.Typeface.body(17))
                    .foregroundStyle(LuminaTokens.Ink.inspection)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            session.closeInspection()
        }
    }

    /// time · body+focal · shutter · aperture · iso · file · state
    private var metadataBar: some View {
        HStack(spacing: LuminaTokens.Spacing.md) {
            Text(asset.filename)
                .foregroundStyle(LuminaTokens.Elastic.ink)
            Text(session.focusStateWord(for: asset))
                .foregroundStyle(LuminaTokens.Elastic.muted)
            Spacer()
            if asset.source.availability == .missing {
                Text("Original offline")
                    .foregroundStyle(LuminaTokens.Elastic.muted)
            }
            if recipe.hasSettings {
                Text("edited")
                    .foregroundStyle(LuminaTokens.Elastic.muted)
            }
        }
        .font(LuminaTokens.Typeface.meta(11))
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        .frame(height: LuminaTokens.HitTarget.minimum)
        .background(LuminaTokens.Elastic.shellAlt)
    }

    private static func immediateBrowseImage(for asset: AssetRecord) -> CIImage? {
        guard let path = asset.thumbPath ?? asset.gridThumbPath ?? asset.proxyPath else { return nil }
        return OrientedDisplayImage.ciImage(
            at: URL(fileURLWithPath: path),
            maxPixelSize: PhotoImageTier.focusedPreviewLongEdge
        )
    }
}

/// Three fixed versions: as shot · auto · yours. Tagged 1 / 2 / 3 individually.
struct ElasticVersionColumn: View {
    @Bindable var session: P0SessionModel
    let asset: AssetRecord

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
            version(index: 1, title: "as shot", active: asset.recipeSource == .shot)
            version(index: 2, title: "auto", active: asset.recipeSource == .auto)
            version(
                index: 3,
                title: "yours",
                active: asset.recipeSource == .hand
                    || asset.recipeSource == .autoHand
                    || asset.recipeSource == .sidecar
            )
            Spacer()
        }
        .padding(LuminaTokens.Spacing.sm)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LuminaTokens.Elastic.shellAlt)
    }

    private func version(index: Int, title: String, active: Bool) -> some View {
        Button {
            session.pickVersion(index, for: asset.id)
        } label: {
            VStack(alignment: .leading, spacing: LuminaTokens.Spacing.xs) {
                ZStack {
                    if let path = asset.gridThumbPath ?? asset.thumbPath {
                        ChapterPlateImage(path: path)
                    } else {
                        LuminaTokens.Elastic.shell
                    }
                }
                .frame(height: ElasticLayout.filmstripFocusedTile.height)
                .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous))

                Text("\(index) \(title)")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(active ? LuminaTokens.Elastic.ink : LuminaTokens.Elastic.muted)
            }
            .padding(LuminaTokens.Spacing.xs)
            .background(active ? LuminaTokens.Elastic.warmAccent : .clear)
            .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(P0AccessibilityID.elasticVersion(index))
    }
}

/// Shoot-order filmstrip. Wider gap where one moment ends and the next begins.
struct ElasticFilmstrip: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LuminaTokens.Spacing.xs) {
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
                .padding(.horizontal, LuminaTokens.Spacing.md)
            }
            .onChange(of: session.focusedAssetID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
        .frame(height: ElasticLayout.filmstripHeight)
        .background(LuminaTokens.Elastic.shellAlt)
    }

    private func tile(_ asset: AssetRecord) -> some View {
        let focused = session.focusedAssetID == asset.id
        let size = focused ? ElasticLayout.filmstripFocusedTile : ElasticLayout.filmstripTile
        return Group {
            if let path = asset.gridThumbPath ?? asset.thumbPath {
                ChapterPlateImage(path: path)
            } else {
                LuminaTokens.Elastic.shell
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous))
        .opacity(asset.cull == .reject ? ElasticLayout.outOpacity : 1)
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous)
                    .strokeBorder(LuminaTokens.Elastic.ink, lineWidth: ElasticLayout.focusRingWidth)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { session.setFocus(asset.id) }
    }
}
