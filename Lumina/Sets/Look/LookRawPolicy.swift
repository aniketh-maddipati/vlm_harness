import Foundation

/// What one camera body's RAW decoder can do on this Mac (`CIRAWFilter.supportedDecoderVersions`),
/// measured once per body per shoot and kept in the shoot's `Lumina.json` header.
nonisolated struct LookDecoderInfo: Codable, Equatable, Sendable {
    /// Every decoder version Core Image offers for this body, ascending.
    var supported: [Int] = []
    /// `.version9` (macOS 27's tiled Core ML demosaic + denoise) is among them.
    var raw9: Bool = false
    /// The version that developed a 512 px proof fastest; what the Edit canvas uses.
    var fastest: Int? = nil
    /// Develop time per version at 512 px, ms (informational, the report reads it).
    var developMs: [String: Double] = [:]
    /// The RAW that was measured.
    var sample: String? = nil

    var newest: Int? { supported.max() }

    /// The version this body renders RAW 9 tier work with when the shoot pins `pinned`: the pin
    /// when the body supports it, else the body's newest.
    func resolve(pinned: Int?) -> Int? {
        if let p = pinned, supported.contains(p) { return p }
        return newest
    }
}

/// `shoots/<id>/Lumina.json`: the shoot header. Holds the capability map per body and the pinned
/// decoder version (roadmap RAW 9 §1, §7). Never photos, never looks (those stay in session.json).
nonisolated struct LookShootHeader: Codable, Equatable, Sendable {
    var v: Int = 1
    var bodies: [String: LookDecoderInfo] = [:]
    /// The decoder version this shoot's RAW 9 tiers (region, export) render with. Set on first
    /// open to the best available and kept afterwards, so a reopen renders the same pixels even
    /// after a macOS update adds a newer decoder. `decoderUpdate` moves it on purpose.
    var decoderVersion: Int? = nil
    var pinnedAt: Date? = nil
    var pinnedOn: String? = nil     // macOS version when pinned

    static let fileName = "Lumina.json"

    /// True when a body now offers something newer than the pin: the facts line offers an update.
    var offersUpdate: Bool {
        guard let p = decoderVersion else { return false }
        return bodies.values.contains { ($0.newest ?? 0) > p }
    }

    /// The newest version any body supports.
    var newest: Int? { bodies.values.compactMap(\.newest).max() }

    /// Any body has RAW 9 and the pin allows it.
    var raw9Active: Bool { bodies.values.contains(\.raw9) && (decoderVersion ?? 0) >= 9 }

    func encoded() throws -> Data {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        return try enc.encode(self)
    }

    static func decode(_ data: Data) throws -> LookShootHeader {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(LookShootHeader.self, from: data)
    }
}

/// The three RAW tiers by what the user is doing (RAW 9 §2), the thermal and battery gating
/// (§4) and the memory rules (§5), as plain functions so they are the same in the app, the probe
/// and the tests. The measurements live with the callers; nothing here touches Core Image.
nonisolated enum LookRawPolicy {
    enum Tier: String, Sendable { case cull, canvas, region, export }

    /// The decoder version a tier uses for a body, or nil for "the embedded JPEG, never a RAW
    /// decode" (Cull). `canvas` takes the fastest version so sliders stay under a frame; `region`
    /// and `export` take the shoot's pinned version (RAW 9 when it is), falling back to the
    /// body's newest when the body lacks the pin.
    static func version(for tier: Tier, body: LookDecoderInfo?, pinned: Int?) -> Int? {
        switch tier {
        case .cull: return nil
        case .canvas:
            guard let body else { return nil }
            return body.fastest ?? body.supported.filter { $0 < 9 }.max() ?? body.newest
        case .region, .export:
            guard let body else { return pinned }
            return body.resolve(pinned: pinned)
        }
    }

    /// The version to pin a shoot to when it is first opened: the newest any body offers.
    static func pin(for bodies: [String: LookDecoderInfo]) -> Int? { bodies.values.compactMap(\.newest).max() }

    /// After a RAW 9 failure (error, or over `exportTimeout` at export size) the file re-renders
    /// once with the previous supported version, silently.
    static func fallback(after version: Int, supported: [Int]) -> Int? { supported.filter { $0 < version }.max() }

    static let exportTimeout: TimeInterval = 8

    /// `ProcessInfo.ThermalState` as an Int (0 nominal … 3 critical) so this file needs no
    /// Darwin-only type: at `.serious` or worse, or in Low Power Mode, region refinement waits
    /// for `regionStillMs` of stillness before it starts, and export says so in its footer fact.
    /// Never disabled: only deferred.
    static func slowed(thermalState: Int, lowPower: Bool) -> Bool { thermalState >= 2 || lowPower }
    static let regionStillMs: Double = 400
    static func regionDelayMs(thermalState: Int, lowPower: Bool) -> Double { slowed(thermalState: thermalState, lowPower: lowPower) ? regionStillMs : 0 }

    /// Export's Core Image memory target: 512 MB on a Mac with 8 GB or less, none above.
    static func exportMemoryLimitMB(physicalMemory: UInt64) -> Int { physicalMemory <= (8 << 30) ? 512 : 0 }

    /// Region tiles: 512 × 512, their own 150 MB cache, evicted before any base texture.
    static let tileSize = 512
    static let tileCacheBytes = 150 << 20
    /// Bases: the current photo plus its two neighbours, at most 300 MB at a 2560 × 1600 canvas.
    static let baseCacheBytes = 300 << 20
    static let basePhotos = 3
    /// The `base` texture is the canvas plus this margin for panning.
    static let baseMargin = 0.15

    /// Refining shows only when the first tile is slow.
    static let refiningAfterMs: Double = 150

    /// The tile grid covering `roi` (fractions of a `w` × `h` photo) plus one tile of margin,
    /// clamped to the photo, as tile indices (column, row) from the top-left. Panning reuses
    /// tiles already cached; the region is one full tile larger on every side.
    static func tiles(covering roi: LookCanvasSchedule.ROI, width w: Int, height h: Int, tile: Int = tileSize) -> [(col: Int, row: Int)] {
        guard w > 0, h > 0, tile > 0 else { return [] }
        let cols = (w + tile - 1) / tile, rows = (h + tile - 1) / tile
        let x0 = max(0, Int((roi.x * Double(w)).rounded(.down)) / tile - 1), x1 = min(cols - 1, Int(((roi.x + roi.w) * Double(w)).rounded(.up)) / tile + 1)
        let y0 = max(0, Int((roi.y * Double(h)).rounded(.down)) / tile - 1), y1 = min(rows - 1, Int(((roi.y + roi.h) * Double(h)).rounded(.up)) / tile + 1)
        guard x1 >= x0, y1 >= y0 else { return [] }
        var out: [(Int, Int)] = []
        for r in y0...y1 { for c in x0...x1 { out.append((c, r)) } }
        return out
    }

    /// Under memory pressure: region tiles go first, then the neighbours' bases, never the
    /// current photo's. Returns the order in which caches are asked to drop, by name.
    static let pressureOrder = ["tiles", "prefetchBases"]
}
