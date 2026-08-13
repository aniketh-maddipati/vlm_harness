import AppKit
import CoreImage
import SwiftUI

/// Finalized P0 single-photograph editing surface.
/// Warm-white shell, middle-gray matte, Metal RAW preview, adjustment rail, filmstrip.
struct P0SinglePhotoEditor: View {
    @Bindable var session: P0SessionModel
    let asset: AssetRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyMonitor: Any?
    @State private var oneToOne = false
    @State private var panOffset: CGSize = .zero

    private var recipe: EditRecipe { session.recipe(for: asset.id) }

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
        .onAppear {
            installBeforeKeyMonitor()
            session.prewarmInspection(around: asset.id)
        }
        .onDisappear {
            session.flushPendingEditIfNeeded()
            removeBeforeKeyMonitor()
        }
        .onChange(of: asset.id) { _, _ in
            oneToOne = false
            panOffset = .zero
            // Inspection warm is owned by setFocus debounce — avoid a second settle storm.
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
            } else if let fidelity = session.developScheduler.fidelityByPhoto[asset.id] {
                Text(session.showingBefore ? "Original" : fidelity.label)
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }

            if session.exportCount > 0 {
                Text("\(session.exportCount) export")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(LuminaTokens.Surface.well)
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

            let image = session.displayedCIImage(for: asset.id)
            let extent = image?.extent.size ?? CGSize(
                width: max(asset.previewLongEdge, 1),
                height: max(asset.previewLongEdge, 1)
            )

            ZStack {
                // Retain last valid frame while scrubbing the same asset — unmount Metal when
                // the focused asset has no rendered surface yet so neighbor nav cannot show the
                // previous photograph's drawable.
                // `singlePhotoImage` rides whichever leaf is actually presenting the photograph —
                // Metal when a render exists, cached preview or placeholder otherwise — never this
                // container: SwiftUI creates no accessibility element for a plain ZStack, so an
                // identifier put there is undiscoverable. Exactly one leaf carries it at a time.
                if let image {
                    DevelopMetalView(
                        image: image,
                        zoom: oneToOne ? 2.2 : 1,
                        panOffset: oneToOne ? panOffset : .zero
                    )
                    .padding(18)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: oneToOne ? 1 : 10_000)
                            .onChanged { value in
                                guard oneToOne else { return }
                                panOffset = value.translation
                            }
                    )
                    .onTapGesture(count: 2) {
                        toggleOneToOneZoom()
                    }
                    .accessibilityElement()
                    .accessibilityIdentifier(P0AccessibilityID.singlePhotoImage)
                    .accessibilityValue(asset.source.availability.rawValue)
                    .accessibilityHint("Double-click to zoom")
                } else if let path = asset.thumbPath ?? asset.gridThumbPath {
                    ContactSheetInspectImage(path: path)
                        .padding(18)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier(P0AccessibilityID.singlePhotoImage)
                        .accessibilityValue(asset.source.availability.rawValue)
                } else {
                    Text(session.fidelityNotice ?? "Preparing photograph…")
                        .font(LuminaTokens.Typeface.body(17))
                        .foregroundStyle(LuminaTokens.Ink.inspection)
                        .accessibilityIdentifier(P0AccessibilityID.singlePhotoUnavailable)
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
        }
    }

    private func toggleOneToOneZoom() {
        oneToOne.toggle()
        if !oneToOne {
            panOffset = .zero
            return
        }
        panOffset = .zero
        session.requestOneToOneZoom(for: asset.id)
    }

    private var filmstrip: some View {
        let neighbors = filmstripNeighbors()
        let focusedSelected = session.focusedIsSelected
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    session.toggleSelectionOfFocused()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: focusedSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .semibold))
                        Text(focusedSelected ? "Selected" : "Select")
                            .font(LuminaTokens.Typeface.navigation(15, weight: .semibold))
                        Text("Space")
                            .font(LuminaTokens.Typeface.meta(11, weight: .medium))
                            .foregroundStyle(LuminaTokens.Ink.tertiary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(LuminaTokens.Surface.well)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .foregroundStyle(focusedSelected ? LuminaTokens.Ink.primary : LuminaTokens.Ink.primary)
                    .frame(minWidth: 168, minHeight: 44)
                    .padding(.horizontal, 14)
                    .background(focusedSelected ? LuminaTokens.Surface.highlight : LuminaTokens.Surface.well)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                focusedSelected
                                    ? LuminaTokens.Status.selection.opacity(0.55)
                                    : LuminaTokens.Line.hairline,
                                lineWidth: focusedSelected ? 1.5 : LuminaTokens.Line.hairlineWidth
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel(focusedSelected ? "Deselect photograph" : "Select photograph")
                .accessibilityHint("Space")

                Text("Hover to browse · click to select · ← → move")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if session.selectionCount > 0 {
                    Text("\(session.selectionCount) selected")
                        .font(LuminaTokens.Typeface.meta(12, weight: .medium))
                        .foregroundStyle(LuminaTokens.Ink.primary)
                }
            }
            .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
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
                ContactSheetInspectImage(path: path)
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
        .animation(reduceMotion ? nil : LuminaTokens.Motion.photo, value: focused)
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

    private func installBeforeKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            guard chars == "b", !event.modifierFlags.contains(.command) else { return event }
            if event.type == .keyDown, !event.isARepeat {
                session.setShowingBefore(true)
                return nil
            }
            if event.type == .keyUp {
                session.setShowingBefore(false)
                return nil
            }
            return nil
        }
    }

    private func removeBeforeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        session.setShowingBefore(false)
    }
}
