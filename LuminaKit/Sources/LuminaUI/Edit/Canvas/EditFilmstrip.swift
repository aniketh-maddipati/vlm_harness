import SwiftUI
import LuminaCore

// WP-4. Under the canvas (README §3 "Photo column"): the filmstrip of keepers, scene by scene,
// each scene with "{done}/{n}", the current thumbnail centred; and the facts line. Only ±120
// photos around the current one are drawn when there are more than 300 keepers.

struct EditFilmstrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let thumbHeight: CGFloat
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
        let groups = groups(kept), labels = model.windowSize.width >= 1100 && model.windowSize.height >= 760
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .center, spacing: 12.scaled(s)) {
                    ForEach(groups) { g in
                        HStack(alignment: .center, spacing: 6.scaled(s)) {
                            if labels {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(g.hm).font(LuminaFont.small(s, .bold))
                                    Text("\(g.done)/\(g.count)").font(LuminaFont.mono(LuminaFontSize.hint, s)).foregroundStyle(LuminaColor.textTertiary)
                                }
                                .foregroundStyle(g.ids.contains(model.editCur ?? "") ? LuminaColor.textPrimary : LuminaColor.textSecondary)
                                .fixedSize()
                            }
                            HStack(spacing: 3) {
                                ForEach(g.ids, id: \.self) { id in thumb(id).id(id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: model.editCur, initial: true) { _, cur in
                guard let cur else { return }
                // The first time at once, then smoothly.
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
        let a = CGFloat(p?.aspect ?? 1.5), h = thumbHeight
        let w = min(h * 1.6, max(h * 0.75, h * a)).rounded()
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
        .overlay(RoundedRectangle(cornerRadius: LuminaRadius.thumbInner, style: .continuous)
            .strokeBorder(cur ? LuminaColor.accentGold : .clear, lineWidth: 2))
        .opacity(cur || hovered == id ? 1 : 0.6)
        .animation(.easeOut(duration: 0.1), value: hovered)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
        .onTapGesture { model.editSelect(id) }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(p?.file ?? id)
    }
}

/// "{lens} · {shutter} · f/{ap} · ISO {iso} · {fl} mm · {time}", then "{n} of {kept}".
struct EditFactsLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let compact: Bool

    var body: some View {
        if let p = model.shoot.photo(model.editCur) {
            let kept = model.keptIDs, i = kept.firstIndex(of: p.id).map { $0 + 1 }
            let facts = EditLayout.facts(p), line = facts.isEmpty ? p.file : facts
            let pos = i.map { "\($0) of \(kept.count)" } ?? ""
            HStack(spacing: 14.scaled(s)) {
                Text(line).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if !pos.isEmpty { Text(pos).foregroundStyle(LuminaColor.textTertiary).monospacedDigit().fixedSize() }
            }
            .font(LuminaFont.small(s, id: AccessibilityID.Edit.facts)).foregroundStyle(LuminaColor.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .trailing : .leading)
            .luminaStatus(AccessibilityID.Edit.facts, pos.isEmpty ? line : "\(line) · \(pos)")
        } else {
            Color.clear
        }
    }
}
