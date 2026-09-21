import AppKit
import CoreImage
import SwiftUI

/// Finalized P0 single-photograph editing surface.
/// Warm-white shell, middle-gray matte, Metal RAW preview, adjustment rail, filmstrip.
struct P0SinglePhotoEditor: View {
    @Bindable var session: P0SessionModel
    let asset: AssetRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var oneToOne = false
    @State private var panOffset: CGSize = .zero
    @State private var drawableSize: CGSize = .zero
    @State private var backingScale: CGFloat = 1
    @State private var oneToOneCenter = CGPoint(x: 0.5, y: 0.5)
    /// The clicked photograph's browse pixels remain mounted until RAW
    /// promotion succeeds. Quality changes never replace the view itself.
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
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                photographStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                filmstrip
            }
            .background(LuminaTokens.Surface.mist)

            P0AdjustmentRail(session: session, assetID: asset.id)
        }
        .background(LuminaTokens.Surface.mist)
        .onDisappear {
            session.flushPendingEditIfNeeded()
            session.setShowingBefore(false)
            session.cancelEditVariants()
            Task { await BrowsePixelService.shared.clearFocusedPin() }
        }
        .onChange(of: asset.id) { _, _ in
            oneToOne = false
            panOffset = .zero
            oneToOneCenter = CGPoint(x: 0.5, y: 0.5)
            fallbackAssetID = asset.id
            fallbackImage = Self.immediateBrowseImage(for: asset)
            // Inspection warm is owned by setFocus debounce — avoid a second settle storm.
        }
        .onChange(of: session.holdingLoupe) { _, holding in
            if holding != oneToOne {
                toggleOneToOneZoom()
            }
        }
        .task(id: asset.id) {
            await loadStableFallback()
        }
    }

    private var header: some View {
        HStack(spacing: LuminaTokens.Spacing.md) {
            Button {
                session.closeInspection()
            } label: {
                Label("Grid", systemImage: "square.grid.2x2")
                    .font(LuminaTokens.Typeface.navigation(14))
                    .foregroundStyle(LuminaTokens.Ink.primary)
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .accessibilityLabel("Return to contact sheet")
            .accessibilityIdentifier(P0AccessibilityID.gridReturn)

            Text(asset.filename)
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .lineLimit(1)
                .accessibilityIdentifier(P0AccessibilityID.singlePhotoFilename)

            if asset.source.availability == .missing {
                // Factual, in-place affordance: the cached preview is shown but the original file
                // is unavailable. Previously only a global toolbar status hinted at this.
                Text("Original offline")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(LuminaTokens.Surface.well.opacity(0.6))
                    .clipShape(Capsule())
                    .help("Cached preview shown — the original file is currently unavailable")
                    .accessibilityIdentifier(P0AccessibilityID.singlePhotoOriginalOffline)
            }

            cullStatusChip
                .accessibilityIdentifier(P0AccessibilityID.singlePhotoCullChip)
                .accessibilityValue(asset.cull.rawValue)

            if recipe.hasSettings {
                Text("Edited")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(LuminaTokens.Surface.well)
            }

            Spacer(minLength: 8)

            Button {
                toggleOneToOneZoom()
            } label: {
                Text(oneToOne ? "Fit" : "1:1")
                    .font(LuminaTokens.Typeface.meta(12, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(LuminaTokens.Surface.well)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .help("Double-click the photograph to zoom")
            .accessibilityLabel(oneToOne ? "Fit photograph" : "Zoom to 1:1")

            if let notice = session.fidelityNotice {
                Text(notice)
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .lineLimit(1)
            } else if let fidelity = session.developFidelity(for: asset.id) {
                Text(session.showingBefore ? "Original" : fidelity.label)
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }

            if session.exportCount > 0 {
                Button {
                    session.chooseAndExportKept()
                } label: {
                    Text(session.exportStatusLine ?? "\(session.exportCount) export")
                        .font(LuminaTokens.Typeface.meta(12))
                        .foregroundStyle(LuminaTokens.Ink.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(LuminaTokens.Surface.well)
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .disabled(session.isExporting)
            }

            if session.canUndo {
                Button(session.undoLabel ?? "Undo") { session.undoLast() }
                    .buttonStyle(LuminaQuietButtonStyle())
                    .keyboardShortcut("z", modifiers: .command)
            }
        }
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        .frame(height: LuminaTokens.HitTarget.header)
        .background(LuminaTokens.Surface.porcelain.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline.opacity(0.65))
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }

    @ViewBuilder
    private var cullStatusChip: some View {
        switch asset.cull {
        case .keep:
            Text("Kept")
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.primary)
        case .reject:
            Text("Rejected")
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.secondary)
        case .undecided, .hold:
            EmptyView()
        }
    }

    private var photographStage: some View {
        ZStack {
            LuminaTokens.Surface.focusMatte.ignoresSafeArea(edges: .bottom)

            let promoted = session.displayedCIImage(for: asset.id)
            let fallback = fallbackAssetID == asset.id ? fallbackImage : nil
            let image = OrientedDisplayImage.stablePresent(promoted: promoted, fallback: fallback)
            let extent = image?.extent.size ?? CGSize(
                width: max(asset.previewLongEdge, 1),
                height: max(asset.previewLongEdge, 1)
            )

            ZStack {
                // One permanent Metal leaf owns this click. The clicked JPEG,
                // interactive RAW, and settled RAW replace pixels in place;
                // none of those promotions remounts or moves the photograph.
                DevelopMetalView(
                    image: image,
                    zoom: 1,
                    panOffset: oneToOne ? panOffset : .zero,
                    onDrawableSizeChange: {
                        drawableSize = $0
                        session.updateInspectionDrawableSize($0)
                    },
                    onBackingScaleChange: { backingScale = $0 }
                )
                .padding(18)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: oneToOne ? 1 : 10_000)
                        .onChanged { value in
                            guard oneToOne else { return }
                            panOffset = value.translation
                        }
                        .onEnded { value in
                            guard oneToOne else { return }
                            commitOneToOnePan(value.translation)
                        }
                )
                .onTapGesture(count: 2) {
                    toggleOneToOneZoom()
                }
                .accessibilityElement()
                .accessibilityIdentifier(P0AccessibilityID.singlePhotoImage)
                .accessibilityValue(asset.source.availability.rawValue)
                .accessibilityHint("Double-click to zoom")

                if image == nil {
                    Text(session.fidelityNotice ?? "Preparing photograph…")
                        .font(LuminaTokens.Typeface.body(17))
                        .foregroundStyle(LuminaTokens.Ink.inspection)
                        .accessibilityIdentifier(P0AccessibilityID.singlePhotoUnavailable)
                        .allowsHitTesting(false)
                }

                if session.holdingClipping {
                    Color.red.blendMode(.difference)
                        .opacity(HiFiTokens.Color.clippingOverlayOpacity)
                        .padding(18)
                        .allowsHitTesting(false)
                }

                if session.expandedAdjustmentSection == .crop {
                    P0CropOverlay(
                        session: session,
                        assetID: asset.id,
                        imageSize: extent
                    )
                    .padding(18)
                }
            }

            if session.workspaceState.editVariants?.assetID == asset.id {
                editVariantTray
                    .padding(LuminaTokens.Spacing.lg)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var editVariantTray: some View {
        VStack(spacing: LuminaTokens.Spacing.sm) {
            Text("Variants · ⏎ chooses · Esc cancels")
                .font(LuminaTokens.Typeface.meta(12, weight: .medium))
                .foregroundStyle(LuminaTokens.Ink.primary)

            HStack(spacing: LuminaTokens.Spacing.xs) {
                ForEach(0..<EditVariantSession.count, id: \.self) { index in
                    editVariantCard(index)
                }
            }

            HStack(spacing: LuminaTokens.Spacing.xs) {
                Button("Shared exposure −") { session.nudgeSharedVariantExposure(up: false) }
                    .buttonStyle(LuminaQuietButtonStyle())
                Button("Shared exposure +") { session.nudgeSharedVariantExposure(up: true) }
                    .buttonStyle(LuminaQuietButtonStyle())
                Divider().frame(height: LuminaTokens.Spacing.md)
                Button("Exposure −") { session.nudgeFocusedVariantExposure(up: false) }
                    .buttonStyle(LuminaQuietButtonStyle())
                Button("Exposure +") { session.nudgeFocusedVariantExposure(up: true) }
                    .buttonStyle(LuminaQuietButtonStyle())
                Button("Temp −") { session.nudgeFocusedVariantTemperature(up: false) }
                    .buttonStyle(LuminaQuietButtonStyle())
                Button("Temp +") { session.nudgeFocusedVariantTemperature(up: true) }
                    .buttonStyle(LuminaQuietButtonStyle())
                Button("Tint −") { session.nudgeFocusedVariantTint(up: false) }
                    .buttonStyle(LuminaQuietButtonStyle())
                Button("Tint +") { session.nudgeFocusedVariantTint(up: true) }
                    .buttonStyle(LuminaQuietButtonStyle())
            }
            .controlSize(.small)
        }
        .padding(LuminaTokens.Spacing.sm)
        .background(LuminaTokens.Surface.porcelain.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: LuminaTokens.Radius.photographLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LuminaTokens.Radius.photographLarge, style: .continuous)
                .strokeBorder(LuminaTokens.Line.hairline, lineWidth: LuminaTokens.Line.hairlineWidth)
        }
    }

    private func editVariantCard(_ index: Int) -> some View {
        let variant = session.workspaceState.editVariants?.recipe(forVariantAt: index)
        let focused = session.workspaceState.focusedEditVariantIndex == index
        return Button {
            session.focusEditVariant(at: index)
        } label: {
            VStack(alignment: .leading, spacing: LuminaTokens.Spacing.xs) {
                Text("Variant \(index + 1)")
                    .font(LuminaTokens.Typeface.meta(12, weight: .medium))
                Text(String(format: "Exposure %+.2f", variant?.exposure ?? 0))
                Text(String(format: "WB %.0f · %+.0f", variant?.temperature ?? 0, variant?.tint ?? 0))
            }
            .font(LuminaTokens.Typeface.meta(11))
            .foregroundStyle(LuminaTokens.Ink.primary)
            .frame(minWidth: 118, alignment: .leading)
            .padding(LuminaTokens.Spacing.xs)
            .background(focused ? LuminaTokens.Status.selection.opacity(0.18) : LuminaTokens.Surface.well)
            .overlay {
                RoundedRectangle(
                    cornerRadius: LuminaTokens.Radius.photographLarge,
                    style: .continuous
                )
                    .strokeBorder(
                        focused ? LuminaTokens.Status.selection : LuminaTokens.Line.hairline,
                        lineWidth: focused ? 2 : LuminaTokens.Line.hairlineWidth
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Variant \(index + 1)")
        .accessibilityAddTraits(focused ? .isSelected : [])
    }

    /// Resolve the clicked asset's durable browse currency once and pin it.
    /// A stale completion is ignored after focus moves to another photograph.
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

    /// ImageIO-oriented JPEG seed. Pixels are baked upright before the first
    /// Metal present so click-through cannot flash an inverted file image.
    private static func immediateBrowseImage(for asset: AssetRecord) -> CIImage? {
        let path = asset.thumbPath ?? asset.gridThumbPath ?? asset.proxyPath
        guard let path else { return nil }
        return OrientedDisplayImage.ciImage(
            at: URL(fileURLWithPath: path),
            maxPixelSize: PhotoImageTier.focusedPreviewLongEdge
        )
    }

    private func toggleOneToOneZoom() {
        oneToOne.toggle()
        if !oneToOne {
            panOffset = .zero
            return
        }
        panOffset = .zero
        oneToOneCenter = CGPoint(x: 0.5, y: 0.5)
        session.requestOneToOneZoom(
            for: asset.id,
            center: oneToOneCenter,
            drawableSize: drawableSize
        )
    }

    private func commitOneToOnePan(_ translation: CGSize) {
        let imageSize = session.renderedPixelSize(for: asset.id)
        guard imageSize.width > 0, imageSize.height > 0 else {
            panOffset = .zero
            return
        }
        oneToOneCenter = CGPoint(
            x: min(
                max(
                    oneToOneCenter.x - translation.width * backingScale / imageSize.width,
                    0
                ),
                1
            ),
            y: min(
                max(
                    oneToOneCenter.y - translation.height * backingScale / imageSize.height,
                    0
                ),
                1
            )
        )
        panOffset = .zero
        session.requestOneToOneZoom(
            for: asset.id,
            center: oneToOneCenter,
            drawableSize: drawableSize
        )
    }

    private var filmstrip: some View {
        let neighbors = filmstripNeighbors()
        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(neighbors, id: \.id) { item in
                            filmstripThumb(item)
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
                    .padding(.bottom, 12)
                    .padding(.top, 2)
                }
                .scrollBounceBehavior(.always)
                .frame(height: 86)
                .onChange(of: session.focusedAssetID) { _, id in
                    guard let id else { return }
                    // No spring on every key — animation under arrow-repeat was a major lag source.
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .background(LuminaTokens.Surface.porcelain.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline.opacity(0.65))
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }

    private func filmstripThumb(_ item: ContactSheetItem) -> some View {
        let focused = item.id == session.focusedAssetID
        let selected = item.marks.selected
        return ZStack {
            if let path = item.asset.thumbPath ?? item.asset.gridThumbPath {
                ChapterPlateImage(path: path)
                    .frame(width: 92, height: 68)
                    .clipped()
            } else {
                Rectangle()
                    .fill(LuminaTokens.Surface.well)
                    .frame(width: 92, height: 68)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(
                    focused
                        ? LuminaTokens.Ink.primary
                        : (selected ? LuminaTokens.Status.selection.opacity(0.85) : Color.clear),
                    lineWidth: focused ? 2.5 : 2
                )
        }
        .scaleEffect(focused ? 1.06 : 1.0)
        .shadow(
            color: focused ? LuminaTokens.Ink.primary.opacity(0.12) : .clear,
            radius: focused ? 8 : 0,
            y: focused ? 2 : 0
        )
        .opacity(item.marks.rejected ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if session.focusedAssetID != item.id {
                session.setFocus(item.id)
            }
            session.selectClick(id: item.id, command: true, shift: false)
        }
        .animation(
            LuminaSpringAnimation.transform(
                reduceMotion: reduceMotion,
                durationMs: Double(HiFiTokens.Motion.photoFocusMs),
                curve: .interactive
            ),
            value: focused
        )
        .accessibilityLabel(item.asset.filename)
        .accessibilityAddTraits(focused ? .isSelected : [])
        .accessibilityHint("Tap to focus and select")
        .accessibilityIdentifier(P0AccessibilityID.filmstripItem(item.id))
    }

    private func filmstripNeighbors() -> [ContactSheetItem] {
        let items = session.visibleItems
        guard let focus = session.focusedAssetID,
              let idx = items.firstIndex(where: { $0.id == focus }) else {
            return Array(items.prefix(16))
        }
        // Wider window so the elastic strip feels continuous while browsing.
        let lo = max(0, idx - 14)
        let hi = min(items.count, idx + 15)
        return Array(items[lo..<hi])
    }
}
