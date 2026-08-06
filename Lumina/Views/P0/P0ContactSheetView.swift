import AppKit
import SwiftUI

struct P0ContactSheetView: View {
    @Bindable var session: P0SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LuminaTokens.Surface.mist.ignoresSafeArea()

            VStack(spacing: 0) {
                toolbar
                ContactSheetRepresentable(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let id = session.inspectingAssetID,
               let asset = session.assets.first(where: { $0.id == id }) {
                inspectionPlaceholder(asset)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)))
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
            session.openFocusedPhotograph()
            return .handled
        }
        .onKeyPress(keys: [.init("="), .init("+")]) { _ in
            session.adjustDensity(-1)
            return .handled
        }
        .onKeyPress(keys: [.init("-"), .init("_")]) { _ in
            session.adjustDensity(1)
            return .handled
        }
        .onKeyPress(.escape) {
            if session.inspectingAssetID != nil {
                session.closeInspection()
                return .handled
            }
            return .ignored
        }
        .animation(reduceMotion ? nil : LuminaTokens.Motion.route, value: session.inspectingAssetID)
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

            VStack(alignment: .leading, spacing: 2) {
                Text(session.shoot?.name ?? "Shoot")
                    .font(LuminaTokens.Typeface.editorial(22))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                Text(session.preparationLine)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if session.selectionCount > 0 {
                Text("\(session.selectionCount) selected")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(LuminaTokens.Surface.well)
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
        HStack(spacing: 6) {
            Button("-") { session.adjustDensity(1) }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("Show more photographs")
            Text("\(session.densityColumns)")
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .frame(minWidth: 16)
            Button("+") { session.adjustDensity(-1) }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("Show fewer photographs")
        }
    }

    private func inspectionPlaceholder(_ asset: AssetRecord) -> some View {
        ZStack {
            LuminaTokens.Surface.inspectionMatte.opacity(0.92).ignoresSafeArea()
            VStack(spacing: LuminaTokens.Spacing.lg) {
                if let path = asset.thumbPath ?? asset.gridThumbPath {
                    ContactSheetInspectImage(path: path)
                        .frame(maxWidth: 1100, maxHeight: 720)
                } else {
                    Text("Preview unavailable")
                        .font(LuminaTokens.Typeface.body(17))
                        .foregroundStyle(LuminaTokens.Ink.inspection)
                }
                Text(asset.filename)
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.inspection)
                Text("Editing rail arrives in the next checkpoint — Esc to return")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                Button("Close") { session.closeInspection() }
                    .buttonStyle(LuminaQuietButtonStyle())
            }
            .padding(40)
        }
        .onTapGesture { session.closeInspection() }
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
        controller.apply(
            items: session.visibleItems,
            focusedID: session.focusedAssetID,
            selectedIDs: session.selectedAssetIDs,
            densityColumns: session.densityColumns,
            restoreScrollAnchor: session.scrollAnchor
        )
    }
}

/// Lightweight inspect image — editing rail is a later checkpoint.
private struct ContactSheetInspectImage: View {
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
