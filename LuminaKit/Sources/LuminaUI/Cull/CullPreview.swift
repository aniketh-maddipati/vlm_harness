import SwiftUI
import LuminaCore

// WP-3. The preview column (README §2 "Preview column", R-58): the current photo shown whole,
// the line under it, and the Keep / Out buttons.

struct CullPreview: View {
    let photo: Photo
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        let keep = model.decisions.keep[photo.id]
        VStack(alignment: .leading, spacing: 12.scaled(s)) {
            // The photo takes everything the line and the buttons leave.
            GeometryReader { geo in
                CullPreviewImage(photo: photo, size: geo.size, out: keep == false)
            }
            .background(LuminaColor.bgCanvas)
            .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.photo.scaled(s), style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(AccessibilityID.Cull.preview)
            .accessibilityLabel("Preview of \(photo.file)")
            .accessibilityAddTraits(.isImage)

            metaLine(keep)

            HStack(spacing: 6.scaled(s)) {
                Button { model.cullSet(keep: true) } label: { HStack(spacing: 10.scaled(s)) { Text("Keep"); KeyHint("R") } }
                    .buttonStyle(CullDecisionButtonStyle(on: keep == true, keep: true))
                    .accessibilityIdentifier(AccessibilityID.Cull.keep)
                    .accessibilityLabel("Keep")
                Button { model.cullSet(keep: false) } label: { HStack(spacing: 10.scaled(s)) { Text("Out"); KeyHint("X") } }
                    .buttonStyle(CullDecisionButtonStyle(on: keep == false, keep: false))
                    .accessibilityIdentifier(AccessibilityID.Cull.out)
                    .accessibilityLabel("Out")
            }
        }
        .padding(EdgeInsets(top: 16.scaled(s), leading: 4.scaled(s), bottom: 16.scaled(s), trailing: 20.scaled(s)))
    }

    /// File name, camera details, and the decision on the right. On one line when it fits;
    /// otherwise the details drop to a second line. Nothing ever pushes the column wider.
    private func metaLine(_ keep: Bool?) -> some View {
        let details = photo.cullDetails
        let file = Text(photo.file).font(LuminaFont.caption(s, .semibold)).foregroundStyle(LuminaColor.textPrimary).lineLimit(1).truncationMode(.middle)
        let meta = Text(details).font(LuminaFont.caption(s)).foregroundStyle(LuminaColor.textTertiary).lineLimit(1).truncationMode(.tail)
        let state = Text(CullCopy.state(keep)).font(LuminaFont.caption(s))
            .foregroundStyle(keep == true ? LuminaColor.accentGold : LuminaColor.textTertiary).lineLimit(1).fixedSize()
            .luminaStatus(AccessibilityID.Cull.previewState, CullCopy.state(keep))
        let value = details.isEmpty ? photo.file : "\(photo.file) · \(details)"
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10.scaled(s)) {
                HStack(alignment: .firstTextBaseline, spacing: 10.scaled(s)) { file; if !details.isEmpty { meta } }
                    .luminaStatus(AccessibilityID.Cull.previewMeta, value)
                Spacer(minLength: 0)
                state
            }
            VStack(alignment: .leading, spacing: 2.scaled(s)) {
                HStack(alignment: .firstTextBaseline, spacing: 10.scaled(s)) {
                    file.luminaStatus(AccessibilityID.Cull.previewMeta, value)
                    Spacer(minLength: 0)
                    state
                }
                if !details.isEmpty { meta.accessibilityHidden(true) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The photo, whole, as large as the space allows. The tile's picture stands in until the sharp
/// one is decoded, so holding R never flashes an empty frame.
private struct CullPreviewImage: View {
    let photo: Photo
    let size: CGSize
    let out: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown: Shown?

    private struct Shown { let id: String; let image: CGImage }
    private var px: Int { CullThumbs.pixels(aspect: photo.aspect, box: size, fill: false, scale: displayScale) }

    var body: some View {
        ZStack {
            if let shown, shown.id == photo.id {
                Image(decorative: shown.image, scale: 1).resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .saturation(out ? 0 : 1)
                    .overlay(Color.black.opacity(out ? 0.3 : 0))
                    .animation(LuminaMotion.outDim(reduce), value: out)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: "\(photo.id)|\(px)") {
            guard size.width > 1, size.height > 1 else { return }
            let thumbs = model.cullThumbs
            if let sharp = thumbs.cached(photo, px: px) { shown = Shown(id: photo.id, image: sharp); return }
            if shown?.id != photo.id { shown = thumbs.anyCached(photo).map { Shown(id: photo.id, image: $0) } }
            if let sharp = await thumbs.load(photo, px: px, images: model.services.images), !Task.isCancelled {
                shown = Shown(id: photo.id, image: sharp)
            }
        }
    }
}

/// Keep (R) and Out (X): height 36, radius 9, 13pt semibold. Keep is the light fill once the
/// photo is kept; Out is the 0.28 fill once it is out; otherwise both are the 0.1 fill.
struct CullDecisionButtonStyle: ButtonStyle {
    let on: Bool
    let keep: Bool
    func makeBody(configuration: Configuration) -> some View { Content(configuration: configuration, on: on, keep: keep) }
    private struct Content: View {
        let configuration: Configuration; let on: Bool; let keep: Bool
        @Environment(\.luminaScale) private var s
        @State private var hover = false
        var body: some View {
            let fill = on ? (keep ? (hover ? LuminaColor.primaryHover : LuminaColor.primaryFill) : LuminaColor.fill28) : (hover ? LuminaColor.fill16 : LuminaColor.fill10)
            configuration.label
                .font(LuminaFont.body(s, .semibold))
                .foregroundStyle(on && keep ? LuminaColor.textOnPrimary : LuminaColor.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: LuminaHeight.keepOut.scaled(s))
                .background(RoundedRectangle(cornerRadius: LuminaRadius.buttonPrimary.scaled(s), style: .continuous).fill(fill))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Rectangle()).onHover { hover = $0 }
        }
    }
}
