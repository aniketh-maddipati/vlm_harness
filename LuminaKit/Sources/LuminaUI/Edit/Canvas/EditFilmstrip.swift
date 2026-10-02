import SwiftUI
import LuminaCore

// WP-4. Under the canvas (README §3 "Photo column"): the filmstrip of keepers, scene by scene,
// each scene's label ("09:12  2/7", or "7" before any is done) above its thumbnails on windows
// 1100 × 760 and up (prototype `stripLbl`), the current thumbnail centred; and the facts line.
// Only ±120 photos around the current one are drawn when there are more than 300 keepers.

struct EditFilmstrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let thumbHeight: CGFloat
    /// Scene labels above the thumbnails, in a line `labelRow` high, `labelGap` above them.
    var labels = false
    var labelRow: CGFloat = 0
    var labelGap: CGFloat = 0
    @State private var hovered: String?

    private struct SceneGroup: Identifiable { let id: Int; let hm: String; let ids: [String]; let done: Int; let count: Int }

    var body: some View {
        let kept = model.keptIDs
        Group {
            if kept.isEmpty {
                Text("No keepers yet. Mark photos to keep in Cull.")
                    .font(LuminaFont.small(s)).foregroundStyle(LuminaColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                strip(kept)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Edit.filmstrip)
    }

    private func strip(_ kept: [String]) -> some View {
        let groups = groups(kept), cur = model.editCur ?? ""
        // The current thumbnail's ring is drawn outside it (prototype `0 0 0 2px #161514, 0 0 0
        // 3.5px #FFD27A`): the content has 4pt around it that the scroll view reaches into.
        let ring: CGFloat = 4
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12.scaled(s)) {
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: labels ? labelGap : 0) {
                            if labels {
                                HStack(alignment: .firstTextBaseline, spacing: 6.scaled(s)) {
                                    Text(g.hm).font(LuminaFont.small(s, .bold))
                                        .foregroundStyle(g.ids.contains(cur) ? LuminaColor.accentGold : LuminaColor.textSecondary)
                                    Text(g.done > 0 ? "\(g.done)/\(g.count)" : "\(g.count)")
                                        .font(LuminaFont.mono(LuminaFontSize.hint, s)).foregroundStyle(LuminaColor.textTertiary)
                                }
                                .lineLimit(1).fixedSize()
                                .frame(height: labelRow, alignment: .leading)
                            }
                            HStack(spacing: 3) {
                                ForEach(g.ids, id: \.self) { id in thumb(id).id(id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, ring).padding(.vertical, ring)
            }
            .padding(.horizontal, -ring).padding(.vertical, -ring)
            .onChange(of: model.editCur, initial: true) { _, cur in
                guard let cur else { return }
                proxy.scrollTo(cur, anchor: .center)
            }
        }
    }

    /// Scenes in shoot order, each with its keepers (only the drawn window of them).
    private func groups(_ kept: [String]) -> [SceneGroup] {
        let keptSet = Set(kept)
        var drawn: Set<String>?
        if kept.count > 300 {
            let i = kept.firstIndex(of: model.editCur ?? "") ?? 0
            drawn = Set(kept[max(0, i - 120)..<min(kept.count, i + 120)])
        }
        let done = model.edits.done
        return model.shoot.scenes.compactMap { scene in
            let ids = scene.ids.filter { keptSet.contains($0) }
            guard !ids.isEmpty else { return nil }
            let shown = drawn.map { d in ids.filter { d.contains($0) } } ?? ids
            guard !shown.isEmpty else { return nil }
            let n = ids.filter { done.contains(model.edits.key(for: $0, decisions: model.decisions)) }.count
            return SceneGroup(id: scene.index, hm: scene.hm, ids: shown, done: n, count: ids.count)
        }
    }

    private func thumb(_ id: String) -> some View {
        let p = model.shoot.photo(id), cur = id == model.editCur
        // Prototype `t.w`: the photo's own proportions, at most 2.4 : 1.
        let a = CGFloat(p?.aspect ?? 1.5), h = thumbHeight
        let w = max(4, (h * min(2.4, a.isFinite && a > 0 ? a : 1.5)).rounded())
        let isDone = model.edits.done.contains(model.edits.key(for: id, decisions: model.decisions))
        return ZStack(alignment: .topTrailing) {
            if let p { PhotoThumb(p, maxPoint: max(w, h), cover: true) } else { LuminaColor.bgPanel }
            if isDone {
                Circle().fill(LuminaColor.textPrimary).frame(width: 7, height: 7)
                    .overlay(Circle().stroke(LuminaColor.bgCanvas.opacity(0.7), lineWidth: 1.5))
                    .padding(4)
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.thumbInner, style: .continuous))
        .overlay {
            if cur {
                RoundedRectangle(cornerRadius: LuminaRadius.thumbInner + 2, style: .continuous)
                    .strokeBorder(LuminaColor.bgCanvas, lineWidth: 2).padding(-2)
                RoundedRectangle(cornerRadius: LuminaRadius.thumbInner + 3.5, style: .continuous)
                    .strokeBorder(LuminaColor.accentGold, lineWidth: 1.5).padding(-3.5)
            }
        }
        .opacity(cur || hovered == id ? 1 : 0.72)
        .animation(.easeOut(duration: 0.1), value: hovered)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
        .onTapGesture { model.editSelect(id) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(p?.file ?? id)
    }
}

/// "{lens} · {shutter} · f/{ap} · ISO {iso} · {fl} mm · {time}", then "{n} of {kept}" at the
/// right (prototype `data-lumina="facts"`; the line itself only from 1100 wide, `lineOn`).
struct EditFactsLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    var showsLine = true

    var body: some View {
        if let p = model.shoot.photo(model.editCur) {
            let kept = model.keptIDs, i = kept.firstIndex(of: p.id).map { $0 + 1 }
            let facts = EditLayout.facts(p), line = facts.isEmpty ? p.file : facts
            let pos = i.map { "\($0) of \(kept.count)" } ?? ""
            HStack(alignment: .firstTextBaseline, spacing: 14.scaled(s)) {
                if showsLine { Text(line).lineLimit(1).truncationMode(.tail) }
                Spacer(minLength: 0)
                if !pos.isEmpty { Text(pos).foregroundStyle(LuminaColor.textTertiary).monospacedDigit().fixedSize() }
            }
            .font(LuminaFont.small(s, id: AccessibilityID.Edit.facts)).foregroundStyle(LuminaColor.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .luminaStatus(AccessibilityID.Edit.facts, pos.isEmpty ? line : "\(line) · \(pos)")
        } else {
            Color.clear
        }
    }
}
