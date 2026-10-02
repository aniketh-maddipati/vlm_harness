import SwiftUI
import LuminaCore

// WP-3. One Cull tile (README §2 "Tiles"): the photo, and its state drawn on top.

enum CullTileState: String { case kept, out, undecided, suggested }

struct CullTile: View, Equatable {
    let photo: Photo
    let width: CGFloat
    let height: CGFloat
    /// A strip narrower than 1:2: shown whole inside a dotted box.
    let contain: Bool
    let state: CullTileState
    let current: Bool
    let s: CGFloat
    let select: (String) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var image: CGImage?
    /// On screen already: a badge that arrives now pops; one that was there when the tile scrolled in doesn't.
    @State private var settled = false
    /// The Out picture (grey, 70 %), made from `image` while the photo is out.
    @State private var dimmed: CGImage?

    nonisolated static func == (a: CullTile, b: CullTile) -> Bool {
        a.photo.id == b.photo.id && a.photo.source == b.photo.source && a.photo.aspect == b.photo.aspect && a.photo.burst == b.photo.burst
            && a.width == b.width && a.height == b.height && a.contain == b.contain && a.state == b.state && a.current == b.current && a.s == b.s
    }

    private var px: Int { CullThumbs.pixels(aspect: photo.aspect, box: CGSize(width: width, height: height), fill: !contain, scale: displayScale) }

    var body: some View {
        let radius = LuminaRadius.tile.scaled(s), out = state == .out
        ZStack(alignment: .topLeading) {
            LuminaColor.bgCanvas
            if let image {
                picture(image, out: out)
                    .frame(width: width, height: height)
                    .transition(.opacity)
            }
            if photo.burst != nil {
                LuminaColor.fill50.frame(height: 3.scaled(s)).frame(maxHeight: .infinity, alignment: .bottom)
            }
            if state == .kept {
                KeptBadge(s: s, pop: settled && !reduce).padding(5.scaled(s))
            } else if state == .suggested {
                Circle().strokeBorder(LuminaColor.accentGold, lineWidth: 1.5 * s)
                    .frame(width: 10.scaled(s), height: 10.scaled(s))
                    .shadow(color: .black.opacity(0.6), radius: 1)
                    .padding(6.scaled(s))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            if contain {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LuminaColor.textPrimary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 3.5]))
            }
        }
        .overlay {
            if current {
                // Outline 2pt, offset 2pt: drawn in the gap around the tile.
                RoundedRectangle(cornerRadius: radius + 3 * s, style: .continuous)
                    .strokeBorder(LuminaColor.textPrimary, lineWidth: 2)
                    .padding(-4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { select(photo.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.Cull.tile(photo.id))
        .accessibilityLabel(photo.file)
        .accessibilityValue(state.rawValue)
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(photo.id) }
        .onAppear { settled = true }
        .task(id: "\(photo.id)|\(px)") { await load() }
        .task(id: dimRequest) { await loadDimmed() }
    }

    /// Out: grey and dimmed to 70 % over 120 ms. The grey picture (`OutDim`) fades in over the
    /// colour one, so the grey shows wherever the view is drawn, Core Animation filters or not
    /// (lumina-snap's `cacheDisplay` draws none); the filters under it answer at once while the
    /// grey picture is made.
    @ViewBuilder private func picture(_ image: CGImage, out: Bool) -> some View {
        ZStack {
            Image(decorative: image, scale: 1).resizable().interpolation(.medium)
                .aspectRatio(contentMode: contain ? .fit : .fill)
                .saturation(out ? 0 : 1)
                .overlay(Color.black.opacity(out ? 0.3 : 0))
            if out, let dimmed {
                Image(decorative: dimmed, scale: 1).resizable().interpolation(.medium)
                    .aspectRatio(contentMode: contain ? .fit : .fill)
                    .transition(.opacity)
            }
        }
        .animation(LuminaMotion.outDim(reduce), value: out)
    }

    /// Changes when the Out picture is wanted for another picture; empty while the photo isn't out.
    private var dimRequest: String {
        guard state == .out, let image else { return "" }
        return "\(photo.id)|\(image.width)x\(image.height)"
    }

    private func loadDimmed() async {
        guard state == .out, let image else { return }
        let thumbs = model.cullThumbs
        let result: CGImage?
        if let c = thumbs.cachedDimmed(photo, from: image) { result = c } else { result = await thumbs.dimmed(photo, from: image) }
        guard let made = result, !Task.isCancelled else { return }
        withAnimation(LuminaMotion.outDim(reduce)) { dimmed = made }
    }

    private func load() async {
        let thumbs = model.cullThumbs
        if let c = thumbs.cached(photo, px: px) { image = c; return }    // seen before: no fade
        guard let loaded = await thumbs.load(photo, px: px, images: model.services.images), !Task.isCancelled else { return }
        let first = image == nil
        withAnimation(first ? LuminaMotion.tileFade(reduce) : nil) { image = loaded }
    }
}

/// The 16pt gold circle with a tick. Pops in (0.4 → 1.18 → 1 over 200 ms) when the photo is kept.
private struct KeptBadge: View {
    let s: CGFloat
    let pop: Bool
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1

    var body: some View {
        Circle().fill(LuminaColor.accentGold)
            .frame(width: 16.scaled(s), height: 16.scaled(s))
            .overlay(Tick().stroke(LuminaColor.textOnPrimary, style: StrokeStyle(lineWidth: 1.7 * s, lineCap: .round, lineJoin: .round)).padding(4.5 * s))
            .scaleEffect(scale).opacity(opacity)
            .onAppear {
                guard pop else { return }
                scale = 0.4; opacity = 0
                let total = LuminaMotion.keepPopSeconds
                withAnimation(.easeOut(duration: total * 0.6)) { scale = 1.18; opacity = 1 } completion: {
                    withAnimation(.easeOut(duration: total * 0.4)) { scale = 1 }
                }
            }
    }
}

/// ✓ as a shape, so it scales with the badge and no text falls below the 11pt floor.
private struct Tick: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY - r.height * 0.08))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.1))
        return p
    }
}
