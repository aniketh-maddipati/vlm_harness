import AppKit
import SwiftUI

struct P0ContactSheetView: View {
    @Bindable var session: P0SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Reduced motion when the system setting asks for it, or when the UI-test harness forces it.
    private var effectiveReduceMotion: Bool { reduceMotion || UITestSupport.reduceMotionForced }

    var body: some View {
        ZStack {
            LuminaTokens.Surface.mist.ignoresSafeArea()

            VStack(spacing: 0) {
                toolbar
                ContactSheetRepresentable(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(session.inspectingAssetID == nil ? 1 : 0)
                    .allowsHitTesting(session.inspectingAssetID == nil)
            }

            if let id = session.inspectingAssetID,
               let asset = session.assets.first(where: { $0.id == id }) {
                P0SinglePhotoPlaceholder(session: session, asset: asset)
                    .transition(effectiveReduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            session.moveFocus(dx: -1, dy: 0, columns: session.densityColumns)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            session.moveFocus(dx: 1, dy: 0, columns: session.densityColumns)
            return .handled
        }
        .onKeyPress(.upArrow) {
            session.moveFocus(dx: 0, dy: -1, columns: session.densityColumns)
            return .handled
        }
        .onKeyPress(.downArrow) {
            session.moveFocus(dx: 0, dy: 1, columns: session.densityColumns)
            return .handled
        }
        .onKeyPress(.return) {
            if session.inspectingAssetID == nil {
                session.openFocusedPhotograph()
            }
            return .handled
        }
        .onKeyPress(keys: [.init("="), .init("+")]) { _ in
            guard session.inspectingAssetID == nil else { return .ignored }
            session.adjustDensity(-1)
            return .handled
        }
        .onKeyPress(keys: [.init("-"), .init("_")]) { _ in
            guard session.inspectingAssetID == nil else { return .ignored }
            session.adjustDensity(1)
            return .handled
        }
        .onKeyPress(keys: [.init("p"), .init("P")]) { _ in
            session.pressKeep()
            return .handled
        }
        .onKeyPress(keys: [.init("x"), .init("X")]) { _ in
            session.pressReject()
            return .handled
        }
        .onKeyPress(keys: [.init("z"), .init("Z")]) { press in
            if press.modifiers.contains(.command) {
                session.undoLastCull()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if session.inspectingAssetID != nil {
                session.closeInspection()
                return .handled
            }
            return .ignored
        }
        .animation(effectiveReduceMotion ? nil : LuminaTokens.Motion.route, value: session.inspectingAssetID)
    }

    private var toolbar: some View {
        HStack(spacing: LuminaTokens.Spacing.md) {
            Button(action: { session.goHome() }) {
                Image(systemName: "chevron.left")
                    .font(LuminaTokens.Typeface.navigation(13, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .frame(width: LuminaTokens.HitTarget.minimum, height: LuminaTokens.HitTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .accessibilityLabel("Back to open")
            .accessibilityIdentifier(P0AccessibilityID.homeButton)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.shoot?.name ?? "Shoot")
                    .font(LuminaTokens.Typeface.editorial(22))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .accessibilityIdentifier(P0AccessibilityID.shootTitle)
                Text(session.preparationLine)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier(P0AccessibilityID.preparationStatus)
            }

            Spacer(minLength: 12)

            if session.exportCount > 0 {
                Text("\(session.exportCount) export")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(LuminaTokens.Surface.well)
                    .help("Export count equals the complete kept set")
                    .accessibilityIdentifier(P0AccessibilityID.exportCount)
                    .accessibilityValue("\(session.exportCount)")
            }

            if session.selectionCount > 0 {
                Text("\(session.selectionCount) selected")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(LuminaTokens.Surface.well)
                    .accessibilityIdentifier(P0AccessibilityID.selectionCount)
                    .accessibilityValue("\(session.selectionCount)")
            }

            if session.canUndo {
                Button("Undo") { session.undoLastCull() }
                    .buttonStyle(LuminaQuietButtonStyle())
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityIdentifier(P0AccessibilityID.undoButton)
            }

            densityControls
        }
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        .frame(height: LuminaTokens.HitTarget.header)
        .background(LuminaTokens.Surface.porcelain.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline.opacity(0.65))
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }

    private var densityControls: some View {
        // Comfortable hit targets — the bare glyphs were ~6pt wide, well under Lumina's own minimum.
        let hit: CGFloat = 28
        return HStack(spacing: 6) {
            Button { session.adjustDensity(1) } label: {
                Text("-").frame(width: hit, height: hit).contentShape(Rectangle())
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .accessibilityLabel("Show more photographs")
            .accessibilityIdentifier(P0AccessibilityID.densityDecrease)
            Text("\(session.densityColumns)")
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .frame(minWidth: 16)
                .accessibilityIdentifier(P0AccessibilityID.densityValue)
                .accessibilityValue("\(session.densityColumns)")
            Button { session.adjustDensity(-1) } label: {
                Text("+").frame(width: hit, height: hit).contentShape(Rectangle())
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .accessibilityLabel("Show fewer photographs")
            .accessibilityIdentifier(P0AccessibilityID.densityIncrease)
        }
    }
}

/// Basic single-photo surface — no editing rail yet.
struct P0SinglePhotoPlaceholder: View {
    @Bindable var session: P0SessionModel
    let asset: AssetRecord

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: LuminaTokens.Spacing.md) {
                Button {
                    session.closeInspection()
                } label: {
                    Label("Grid", systemImage: "square.grid.2x2")
                        .font(LuminaTokens.Typeface.navigation(14))
                        .foregroundStyle(LuminaTokens.Ink.inspection)
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("Return to contact sheet")
                .accessibilityIdentifier(P0AccessibilityID.gridReturn)

                Text(asset.filename)
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.inspection)
                    .accessibilityIdentifier(P0AccessibilityID.singlePhotoFilename)

                Spacer()

                if asset.source.availability == .missing {
                    // Factual, in-place affordance: the cached preview is shown but the original
                    // file is unavailable. Previously only a global toolbar status hinted at this.
                    Text(CopyContract.fileDamagedPreviewOnly)
                        .font(LuminaTokens.Typeface.meta(12))
                        .foregroundStyle(LuminaTokens.Ink.inspection)
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

                Text("P keep · X reject · Esc grid")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
            }
            .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
            .frame(height: LuminaTokens.HitTarget.header)

            ZStack {
                LuminaTokens.Surface.inspectionMatte.ignoresSafeArea()
                if let path = asset.thumbPath ?? asset.gridThumbPath {
                    ContactSheetInspectImage(path: path)
                        .padding(24)
                        .accessibilityIdentifier(P0AccessibilityID.singlePhotoImage)
                        .accessibilityValue(asset.source.availability.rawValue)
                } else {
                    Text("Preview unavailable — cached preview missing")
                        .font(LuminaTokens.Typeface.body(17))
                        .foregroundStyle(LuminaTokens.Ink.inspection)
                        .accessibilityIdentifier(P0AccessibilityID.singlePhotoUnavailable)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Minimal filmstrip navigation — not an editing rail.
            filmstrip
        }
        .background(LuminaTokens.Surface.inspectionMatte)
    }

    @ViewBuilder
    private var cullStatusChip: some View {
        switch asset.cull {
        case .keep:
            Text("Kept")
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.inspection)
        case .reject:
            Text("Rejected")
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.inspection)
        case .undecided, .hold:
            Text("Unreviewed")
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
        }
    }

    private var filmstrip: some View {
        let neighbors = filmstripNeighbors()
        return ScrollView(.horizontal, showsIndicators: false) {
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
                                        ? LuminaTokens.Ink.inspection
                                        : Color.clear,
                                    lineWidth: 2
                                )
                        }
                        .opacity(item.marks.rejected ? 0.5 : 1)
                    }
                    .buttonStyle(LuminaQuietButtonStyle())
                    .accessibilityIdentifier(P0AccessibilityID.filmstripItem(item.id))
                }
            }
            .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
            .padding(.vertical, 10)
        }
        .frame(height: 74)
        .background(LuminaTokens.Surface.tableHead.opacity(0.92))
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
}

struct ContactSheetRepresentable: NSViewControllerRepresentable {
    @Bindable var session: P0SessionModel

    func makeNSViewController(context: Context) -> ContactSheetCollectionController {
        let controller = ContactSheetCollectionController()
        controller.onFocus = { [weak session] id in
            session?.setFocus(id)
        }
        controller.onSelectClick = { [weak session] id, command, shift in
            session?.selectClick(id: id, command: command, shift: shift)
        }
        controller.onOpen = { [weak session] id in
            session?.setFocus(id)
            session?.openFocusedPhotograph()
        }
        controller.onDensityDelta = { [weak session] delta in
            session?.adjustDensity(delta)
        }
        controller.onScrollAnchor = { [weak session] anchor in
            session?.setScrollAnchor(anchor)
        }
        return controller
    }

    func updateNSViewController(_ controller: ContactSheetCollectionController, context: Context) {
        let force = session.pendingScrollRestore
        controller.apply(
            items: session.visibleItems,
            focusedID: session.focusedAssetID,
            selectedIDs: session.selectedAssetIDs,
            densityColumns: session.densityColumns,
            restoreScrollAnchor: session.scrollAnchor,
            forceScrollRestore: force
        )
        if force {
            session.pendingScrollRestore = false
        }
    }
}

/// Lightweight inspect image — editing rail is a later checkpoint.
struct ContactSheetInspectImage: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(LuminaTokens.Surface.well)
            }
        }
        .task(id: path) {
            let outcome = await PhotoImageCache.shared.load(path: path, maxPixelSize: 2400, allowRAW: false)
            if case .image(let img) = outcome {
                image = img
            }
        }
    }
}
