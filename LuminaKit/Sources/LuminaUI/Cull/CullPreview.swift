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

    /// File name, shot details, and the decision on the right, wrapping as the prototype's line
    /// does (`flex-wrap`, gap 10 both ways): all on one line when it fits; else the state drops to
    /// a second line, right-aligned; else the details drop too. Nothing pushes the column wider.
    /// The camera body shows too (README §2; ruled 2026-10-02: pros want to see the body).
    private func metaLine(_ keep: Bool?) -> some View {
        let details = photo.cullDetails, gap = 10.scaled(s)
        let file = Text(photo.file).font(LuminaFont.caption(s, .semibold)).foregroundStyle(LuminaColor.textPrimary).lineLimit(1).truncationMode(.middle)
        let meta = Text(details).font(LuminaFont.caption(s)).foregroundStyle(LuminaColor.textTertiary).lineLimit(1).truncationMode(.tail)
        let stateText = CullCopy.state(keep, suggested: photo.suggested)
        let state = Text(stateText).font(LuminaFont.caption(s))
            .foregroundStyle(keep == true ? LuminaColor.accentGold : LuminaColor.textTertiary).lineLimit(1).fixedSize()
            .luminaStatus(AccessibilityID.Cull.previewState, stateText)
        let all = photo.cullDetails
        let value = all.isEmpty ? photo.file : "\(photo.file) · \(all)"
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: gap) {
                HStack(alignment: .firstTextBaseline, spacing: gap) { file; if !details.isEmpty { meta } }
                    .luminaStatus(AccessibilityID.Cull.previewMeta, value)
                Spacer(minLength: 0)
                state
            }
            VStack(alignment: .leading, spacing: gap) {
                HStack(alignment: .firstTextBaseline, spacing: gap) { file; if !details.isEmpty { meta } }
                    .fixedSize()
                    .luminaStatus(AccessibilityID.Cull.previewMeta, value)
                HStack(spacing: 0) { Spacer(minLength: 0); state }
            }
            VStack(alignment: .leading, spacing: gap) {
                file.luminaStatus(AccessibilityID.Cull.previewMeta, value)
                if !details.isEmpty { meta.accessibilityHidden(true) }
                HStack(spacing: 0) { Spacer(minLength: 0); state }
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
    /// The Out picture (`OutDim`) made from `shown`, faded in over it while the photo is out.
    @State private var dimmed: Shown?

    private struct Shown { let id: String; let image: CGImage }
    private var px: Int { CullThumbs.pixels(aspect: photo.aspect, box: size, fill: false, scale: displayScale) }
    /// Changes when the Out picture is wanted for another picture; empty while the photo isn't out.
    private var dimRequest: String {
        guard out, let shown, shown.id == photo.id else { return "" }
        return "\(shown.id)|\(shown.image.width)x\(shown.image.height)"
    }

    var body: some View {
        ZStack {
            if let shown, shown.id == photo.id {
                ZStack {
                    Image(decorative: shown.image, scale: 1).resizable().interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .saturation(out ? 0 : 1)
                        .overlay(Color.black.opacity(out ? 0.3 : 0))
                    if out, let dimmed, dimmed.id == photo.id {
                        Image(decorative: dimmed.image, scale: 1).resizable().interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .transition(.opacity)
                    }
                }
                .animation(LuminaMotion.outDim(reduce), value: out)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: dimRequest) {
            guard out, let shown, shown.id == photo.id else { return }
            let thumbs = model.cullThumbs
            let result: CGImage?
            if let c = thumbs.cachedDimmed(photo, from: shown.image) { result = c } else { result = await thumbs.dimmed(photo, from: shown.image) }
            guard let made = result, !Task.isCancelled else { return }
            withAnimation(LuminaMotion.outDim(reduce)) { dimmed = Shown(id: shown.id, image: made) }
        }
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
