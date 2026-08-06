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
        .onChange(of: asset.id) { _, newID in
            session.prewarmInspection(around: newID)
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
                // Retain last valid frame — never clear on scrub.
                DevelopMetalView(image: image)
                    .padding(18)

                if image == nil {
                    if let path = asset.thumbPath ?? asset.gridThumbPath {
                        ContactSheetInspectImage(path: path)
                            .padding(18)
                            .opacity(0.92)
                    } else {
                        Text(session.fidelityNotice ?? "Preparing photograph…")
                            .font(LuminaTokens.Typeface.body(17))
                            .foregroundStyle(LuminaTokens.Ink.inspection)
                            .accessibilityIdentifier(P0AccessibilityID.singlePhotoUnavailable)
                    }
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
            .accessibilityIdentifier(P0AccessibilityID.singlePhotoImage)
            .accessibilityValue(asset.source.availability.rawValue)
        }
    }

    private var filmstrip: some View {
        let neighbors = filmstripNeighbors()
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(neighbors, id: \.id) { item in
                        Button {
                            session.setFocus(item.id)
                        } label: {
                            ZStack {
                                if let path = item.asset.gridThumbPath ?? item.asset.thumbPath {
                                    ContactSheetInspectImage(path: path)
                                        .frame(width: 72, height: 54)
                                        .clipped()
                                } else {
                                    Rectangle()
                                        .fill(LuminaTokens.Surface.well)
                                        .frame(width: 72, height: 54)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(
                                        item.id == session.focusedAssetID
                                            ? LuminaTokens.Ink.primary
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            }
                            .opacity(item.marks.rejected ? 0.5 : 1)
                        }
                        .buttonStyle(LuminaQuietButtonStyle())
                        .accessibilityIdentifier(P0AccessibilityID.filmstripItem(item.id))
                        .id(item.id)
                    }
                }
                .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
                .padding(.vertical, 10)
            }
            .frame(height: 74)
            .background(LuminaTokens.Surface.porcelain.opacity(0.94))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(LuminaTokens.Line.hairline.opacity(0.65))
                    .frame(height: LuminaTokens.Line.hairlineWidth)
            }
            .onChange(of: session.focusedAssetID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : LuminaTokens.Motion.control) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func filmstripNeighbors() -> [ContactSheetItem] {
        let items = session.visibleItems
        guard let focus = session.focusedAssetID,
              let idx = items.firstIndex(where: { $0.id == focus }) else {
            return Array(items.prefix(12))
        }
        let lo = max(0, idx - 8)
        let hi = min(items.count, idx + 9)
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
