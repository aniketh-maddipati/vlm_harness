import Foundation

/// Cross-row hand selection — whole photographs, row scope ignored (hi-fi frame D).
struct TablePhotographSelection: Equatable, Sendable {
    /// Ordered membership — banner count and staging scope derive from this list.
    var ids: [AssetID] = []
    /// Keyboard / sequential-path focus — anchor for ⇧-arrow extension.
    var focusID: AssetID?
    /// Extension anchor frozen at focus until the next plain focus change.
    var extensionAnchor: AssetID?

    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }
    var set: Set<AssetID> { Set(ids) }

    mutating func clear() {
        ids = []
        focusID = nil
        extensionAnchor = nil
    }

    /// Plain focus — sets single-member selection when not extending.
    mutating func focus(_ id: AssetID, replaceSelection: Bool = true) {
        focusID = id
        extensionAnchor = id
        if replaceSelection {
            ids = [id]
        } else if !ids.contains(id) {
            ids.append(id)
        }
    }

    /// Toggle membership — used while staged and for additive clicks.
    mutating func toggle(_ id: AssetID) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        focusID = id
        if extensionAnchor == nil { extensionAnchor = id }
    }

    mutating func setMembers(_ newIDs: [AssetID]) {
        var seen = Set<AssetID>()
        ids = newIDs.filter { seen.insert($0).inserted }
        focusID = ids.last
        extensionAnchor = focusID
    }

    /// ⇧-arrow sequential extension along table order.
    mutating func extend(in tableOrder: [AssetID], to target: AssetID) {
        let anchor = extensionAnchor ?? focusID ?? target
        guard let a = tableOrder.firstIndex(of: anchor),
              let b = tableOrder.firstIndex(of: target) else {
            focus(target)
            return
        }
        let slice = a <= b ? tableOrder[a...b] : tableOrder[b...a]
        ids = Array(Set(ids).union(slice))
        focusID = target
        extensionAnchor = anchor
    }

    /// Rubber-band — replaces selection with every id the band touched.
    mutating func rubberBand(_ touched: [AssetID]) {
        setMembers(touched)
    }

    func contains(_ id: AssetID) -> Bool {
        ids.contains(id)
    }
}

extension TablePhotographSelection {
    /// Table traversal order — all active photographs across swim lanes / rows.
    static func tableOrder(from groups: [GroupPresentation]) -> [AssetID] {
        groups.flatMap { group in
            group.captureOrderedAssets
                .filter { $0.decision != .cut }
                .map(\.id)
        }
    }
}
