import Foundation

/// The one peek. Hold `⇥` for similar; `↑↓` or `⇥` cycles similar → set → flags;
/// release returns. A short tap pins it; `Esc`, or `⇥` past the end, closes.
enum ElasticPeek: String, CaseIterable, Sendable {
    case related
    case set
    case flags
}

/// One frame in a peek: which frame, how it relates to the cursor, and the key that
/// jumps to it. Pure presentation data — the view decides sizes, the session decides
/// membership and order.
struct ElasticPeekItem: Identifiable, Equatable, Sendable {
    var id: UUID
    /// `1`…`9`, or `·` for the cursor itself.
    var key: String
    /// `burst` · `+9 s` · `same moment` · `phone` — or the capture time in the set peek.
    var relation: String
    /// The warm word on the right: `this one`, `cursor`, or nothing to say.
    var facts: String
    var isCursor: Bool
    /// Drawn with the cursor ring.
    var ringed: Bool
    /// Drawn with the in-set outline.
    var outlined: Bool
}

@MainActor
extension P0SessionModel {

    // MARK: - Open · cycle · close

    /// A `⇥` released this soon after it opened the peek pins it rather than closing it.
    static let peekPinTapSeconds: TimeInterval = 0.22

    /// The table shows the peek bar for similar and the set; flags open the bursts instead.
    var tablePeekVisible: Bool {
        route == .time && (peek == .related || peek == .set)
    }

    /// `⇥` went down with nothing held.
    func openPeek(_ mode: ElasticPeek, at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        guard peek == nil else { return }
        peekOpenedAt = now
        peekPinned = false
        applyPeek(mode)
    }

    /// `↑↓` (wrapping) or a pinned `⇥` (closing past the end). A set that is empty is
    /// stepped over in the direction of travel.
    func cyclePeek(by delta: Int, wrap: Bool = true) {
        guard let current = peek, let position = ElasticPeek.allCases.firstIndex(of: current) else { return }
        let order = ElasticPeek.allCases
        var index = position + delta
        if index >= order.count {
            guard wrap else {
                closePeek()
                return
            }
            index = 0
        }
        if index < 0 { index = order.count - 1 }
        if order[index] == .set, finalSetAssetIDs.isEmpty {
            index = (index + delta + order.count) % order.count
        }
        applyPeek(order[index])
    }

    func closePeek() {
        peek = nil
        peekPinned = false
        peekOpenedAt = nil
        walkingKeptRail = false
    }

    /// `⇥` came back up. A tap pins; a hold returns.
    func releasePeekKey(at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        guard peek != nil, !peekPinned else { return }
        if let opened = peekOpenedAt, now - opened < Self.peekPinTapSeconds {
            peekPinned = true
        } else {
            closePeek()
        }
    }

    /// The prototype's `peekPatch`: the set peek falls through to flags when nothing is
    /// kept, and walking the set moves the cursor onto it first.
    private func applyPeek(_ requested: ElasticPeek) {
        var mode = requested
        if mode == .set, finalSetAssetIDs.isEmpty {
            mode = .flags
        }
        peek = mode
        if mode == .flags {
            measureForInference()
        }
        guard mode == .set else {
            walkingKeptRail = false
            return
        }
        walkingKeptRail = true
        if let focus = focusedAssetID, finalSetAssetIDs.contains(focus) { return }
        if let nearest = nearestInSet(to: focusedAssetID) {
            setFocus(nearest)
        }
    }

    /// The set member closest to `id` in shoot order; the first member with no cursor.
    func nearestInSet(to id: UUID?) -> UUID? {
        let set = finalSetAssetIDs
        guard let id, let here = assetIndex(id) else { return set.first }
        return set.min { lhs, rhs in
            distance(from: here, to: lhs) < distance(from: here, to: rhs)
        }
    }

    private func distance(from index: Int, to id: UUID) -> Int {
        guard let other = assetIndex(id) else { return Int.max }
        return abs(other - index)
    }

    // MARK: - Inside a peek

    /// `1`…`9` jumps to that frame of the peek; the peek stays open.
    func jumpInPeek(to number: Int) {
        guard number >= 1 else { return }
        switch peek {
        case .related:
            guard let focus = focusedAssetID else { return }
            let related = relatedFrames(to: focus)
            guard related.indices.contains(number - 1) else { return }
            setFocus(related[number - 1].id)
        case .set:
            let set = finalSetAssetIDs
            guard set.indices.contains(number - 1) else { return }
            setFocus(set[number - 1])
        case .flags, .none:
            break
        }
    }

    /// A click on a peek tile. In similar it is a pick — go there and come back; in
    /// the set it only moves the cursor along the set.
    func pickInPeek(_ id: UUID) {
        switch peek {
        case .related:
            if id != focusedAssetID {
                setFocus(id)
            }
            closePeek()
        case .set:
            setFocus(id)
        case .flags, .none:
            break
        }
    }

    // MARK: - Similar

    /// Neighbours closer than this are named by the seconds between them.
    static let relatedNearSeconds = 30

    /// Frames that belong with the cursor, nearest kin first: its burst mates, then the
    /// rest of the moment by how far apart they were taken, then the phone frames. At
    /// most `relatedLimit`, and never the cursor itself.
    func relatedFrames(to id: UUID) -> [ElasticPeekItem] {
        guard let chapter = ShootChapterArrangement.chapter(containing: id, in: chapters) else { return [] }
        let ownBurst = chapter.bursts.first { $0.assetIDs.contains(id) }
        let burstMates = Set(ownBurst?.frames.map(\.coverID) ?? [])
        let focusTime = asset(id)?.capturedAt

        var burst: [ElasticPeekItem] = []
        var near: [ElasticPeekItem] = []
        var phone: [ElasticPeekItem] = []
        for frame in chapter.bursts.flatMap(\.frames) where !frame.assetIDs.contains(id) {
            let other = frame.coverID
            if isPhoneFrame(other) {
                if !burstMates.contains(other) {
                    phone.append(relatedItem(other, relation: "phone"))
                }
                continue
            }
            if burstMates.contains(other) {
                burst.append(relatedItem(other, relation: "burst"))
                continue
            }
            var relation = "same moment"
            if let focusTime, let time = asset(other)?.capturedAt {
                let seconds = Int(abs(time.timeIntervalSince(focusTime)).rounded())
                if seconds < Self.relatedNearSeconds {
                    relation = "+\(seconds) s"
                }
            }
            near.append(relatedItem(other, relation: relation))
        }
        var items = Array((burst + near + phone).prefix(Self.relatedLimit))
        for index in items.indices {
            items[index].key = String(index + 1)
        }
        return items
    }

    private func relatedItem(_ id: UUID, relation: String) -> ElasticPeekItem {
        ElasticPeekItem(
            id: id,
            key: "",
            relation: relation,
            facts: "",
            isCursor: false,
            ringed: false,
            outlined: isInFinalSet(id)
        )
    }

    /// The similar peek never shows more neighbours than this at once.
    static let relatedShown = 5

    /// What the similar peek shows: up to five neighbours with the cursor seated among them.
    var relatedPeekItems: [ElasticPeekItem] {
        guard let focus = focusedAssetID else { return [] }
        let related = relatedFrames(to: focus)
        var items = Array(related.prefix(Self.relatedShown))
        let cursor = ElasticPeekItem(
            id: focus,
            key: "·",
            relation: "this one",
            facts: related.isEmpty ? "nothing else in this moment" : "",
            isCursor: true,
            ringed: true,
            outlined: isInFinalSet(focus)
        )
        items.insert(cursor, at: items.count / 2)
        return items
    }

    // MARK: - The set

    /// The set in its own order, numbered, with the cursor named.
    var setPeekItems: [ElasticPeekItem] {
        finalSetAssetIDs.enumerated().map { index, id in
            let isCursor = id == focusedAssetID
            return ElasticPeekItem(
                id: id,
                key: String(index + 1),
                relation: asset(id).map { focusTimeLabel(for: $0) } ?? "",
                facts: isCursor ? "cursor" : "",
                isCursor: isCursor,
                ringed: isCursor,
                outlined: false
            )
        }
    }

    // MARK: - Flags

    /// The inferred groups, from what has been measured so far.
    var inferredGroups: [ElasticInferredGroup] {
        ElasticInferredGroups.infer(
            chapters: chapters,
            assets: assets,
            measurements: inferredMeasurements,
            context: ElasticInferredGroups.Context(
                isPhone: { [weak self] in self?.isPhoneFrame($0) ?? false },
                momentTimeLabel: { [weak self] in self?.momentTimeLabel($0) ?? "" },
                momentLightWord: { [weak self] in self?.momentLightWord($0) ?? "" }
            )
        )
    }

    /// Frames the peek would send to the set that are not there yet.
    var inferredPickCount: Int {
        var seen: Set<UUID> = []
        return inferredGroups.flatMap(\.takeIDs).filter { id in
            seen.insert(id).inserted && !isInFinalSet(id) && asset(id)?.cull != .reject
        }.count
    }

    /// `soft · clips · drift` on a table tile while flags are held; nil otherwise.
    func flagLine(for id: UUID) -> String? {
        guard peek == .flags, let asset = asset(id) else { return nil }
        let mates = chapters.flatMap(\.bursts)
            .first { $0.assetIDs.contains(id) }?
            .frames.compactMap { self.asset($0.coverID) } ?? []
        return ElasticInferredGroups.flags(for: asset, burstMates: mates, measurements: inferredMeasurements)
    }

    /// How many frames carry any flag right now.
    var flaggedFrameCount: Int {
        guard peek == .flags else { return 0 }
        return assets.filter { flagLine(for: $0.id) != nil }.count
    }

    var groupsHeadline: String {
        "\(inferredGroups.count) groups inferred"
    }

    var groupsSubtitle: String {
        "\(inferredPickCount) picks would go to the set · "
            + "\(flaggedFrameCount) frames need a hand (soft · clips · drift)"
    }

    static let groupsKeyLine = "holding ⇥ · ↑↓ or ⇥ cycles similar → set → flags · G takes the picks · ⌘Z undoes"

    // MARK: - Copy

    var peekTitle: String {
        peek == .set ? "the set" : "similar"
    }

    var peekSubtitle: String {
        if peek == .set {
            return "\(finalSetAssetIDs.count) frames · ←→ walks · P drops in or out · ↑↓ ⇥ cycles · release to go back"
        }
        return "1–9 jumps · ↑↓ ⇥ cycles · release to go back"
    }

    /// What the strip walks: the set while it is held, otherwise the whole shoot.
    var stripAssetIDs: [UUID] {
        peek == .set ? finalSetAssetIDs : assets.map(\.id)
    }

    /// `time`, or `set` with the way back under it.
    var stripLabel: String {
        peek == .set ? "set\nrelease ⇥" : "time"
    }
}

// MARK: - Clicking a frame (the README's ruling: ⇧-click range · ⌘-click toggle)

@MainActor
extension P0SessionModel {
    /// A click on a frame of the table or a group row. Plain: the cursor goes there,
    /// the anchor moves with it, the selection clears. ⌘: the frame toggles in the
    /// selection and the cursor stays. ⇧: everything from the anchor to the frame, in
    /// shoot order, becomes the selection and the cursor goes to the frame.
    func clickFrame(_ id: UUID, shift: Bool, command: Bool) {
        guard assetIndex(id) != nil else { return }
        autoReceipt = nil
        versionAutoStatus = nil
        if command {
            if selectionAnchorID == nil { selectionAnchorID = focusedAssetID }
            workspaceState.toggleSelection(id)
            return
        }
        if shift {
            let anchor = selectionAnchorID ?? focusedAssetID ?? id
            guard let from = assetIndex(anchor), let to = assetIndex(id) else { return }
            let range = min(from, to)...max(from, to)
            selectedAssetIDs = assets[range].map(\.id)
            setFocus(id)
            return
        }
        setFocus(id)
        selectionAnchorID = id
        selectedAssetIDs = []
    }
}
