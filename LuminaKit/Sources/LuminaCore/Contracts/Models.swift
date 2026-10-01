import Foundation
import CoreGraphics

// WP-0 contract. Shared types change only here; a work package never forks one locally.

public enum Step: String, Codable, CaseIterable, Sendable {
    case open, cull, edit, save
    public var index: Int { Step.allCases.firstIndex(of: self)! }
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum SaveFormat: String, Codable, CaseIterable, Sendable { case xmp, folder, jpeg }

/// An edit: setting key → value. Keys and ranges are `EditSetting.all` (README, Edit table).
/// A missing key means the setting's default.
public typealias Look = [String: Double]

/// Where a photo's pixels come from.
public enum PhotoSource: Hashable, Codable, Sendable {
    /// A file on disk (imported folder, copied card).
    case file(URL)
    /// The built-in demo card: a generated picture, no file, no network.
    case demo(seed: Int, bw: Bool)
    /// A remote picture (the Unsplash load-test card). `path` is appended to the image host.
    case remote(path: String)
}

public struct Photo: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    /// File name as shown ("DSC03261", "🌅 sunset ✨.jpg").
    public var file: String
    /// Index into `Shoot.scenes`.
    public var scene: Int
    /// `Burst.id` when the frame belongs to a burst.
    public var burst: String?
    /// Width / height after EXIF orientation.
    public var aspect: Double
    public var shot: Date?
    /// "hh:mm:ss" of `shot`, already formatted (the demo card has no dates).
    public var time: String?
    public var camera: String?
    public var lens: String?
    public var focal: Double?
    public var aperture: Double?
    /// "1/250".
    public var shutter: String?
    public var iso: Int?
    public var source: PhotoSource
    /// Lumina's suggestion (the ring). Only shown while undecided.
    public var suggested: Bool
    /// Import identity (R-14): relative path, size, modified time.
    public var rel: String?
    public var size: Int64?
    public var modified: Date?

    public init(id: String, file: String, scene: Int = 0, burst: String? = nil, aspect: Double = 1.5,
                shot: Date? = nil, time: String? = nil, camera: String? = nil, lens: String? = nil,
                focal: Double? = nil, aperture: Double? = nil, shutter: String? = nil, iso: Int? = nil,
                source: PhotoSource, suggested: Bool = false, rel: String? = nil, size: Int64? = nil,
                modified: Date? = nil) {
        self.id = id; self.file = file; self.scene = scene; self.burst = burst; self.aspect = aspect
        self.shot = shot; self.time = time; self.camera = camera; self.lens = lens; self.focal = focal
        self.aperture = aperture; self.shutter = shutter; self.iso = iso; self.source = source
        self.suggested = suggested; self.rel = rel; self.size = size; self.modified = modified
    }
}

/// A scene: photos taken together. (Named PhotoScene because SwiftUI owns `Scene`.)
public struct PhotoScene: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var index: Int
    public var start: Date?
    /// "hh:mm" shown in the header.
    public var hm: String
    /// Subfolder name for imported shoots.
    public var title: String?
    public var ids: [String]
    public init(id: String, index: Int, start: Date? = nil, hm: String, title: String? = nil, ids: [String]) {
        self.id = id; self.index = index; self.start = start; self.hm = hm; self.title = title; self.ids = ids
    }
    /// "09:12" or "09:12 · Day 1".
    public var header: String { title.map { hm.isEmpty ? $0 : "\(hm) · \($0)" } ?? hm }
}

public struct Burst: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var ids: [String]
    public init(id: String, ids: [String]) { self.id = id; self.ids = ids }
}

public struct Shoot: Codable, Sendable {
    public var photos: [Photo]
    public var scenes: [PhotoScene]
    public var bursts: [Burst]
    /// "Untitled" for the card, the folder name for an import.
    public var name: String
    /// Camera label on the card tile ("ILCE-7M4").
    public var label: String?
    /// "09:12–19:14".
    public var span: String?
    /// True for an imported folder / dropped files (no copy step); false for a card.
    public var local: Bool
    /// Stable identity for persistence (decisions are stored per shoot).
    public var key: String

    public init(photos: [Photo] = [], scenes: [PhotoScene] = [], bursts: [Burst] = [], name: String = "Untitled",
                label: String? = nil, span: String? = nil, local: Bool = false, key: String = "empty") {
        self.photos = photos; self.scenes = scenes; self.bursts = bursts; self.name = name
        self.label = label; self.span = span; self.local = local; self.key = key
        reindex()
    }

    private var index: [String: Int] = [:]
    private var burstIndex: [String: Int] = [:]
    private enum CodingKeys: String, CodingKey { case photos, scenes, bursts, name, label, span, local, key }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        photos = try c.decode([Photo].self, forKey: .photos); scenes = try c.decode([PhotoScene].self, forKey: .scenes)
        bursts = try c.decode([Burst].self, forKey: .bursts); name = try c.decode(String.self, forKey: .name)
        label = try c.decodeIfPresent(String.self, forKey: .label); span = try c.decodeIfPresent(String.self, forKey: .span)
        local = try c.decode(Bool.self, forKey: .local); key = try c.decode(String.self, forKey: .key)
        reindex()
    }
    /// Call after changing `photos` or `bursts` in place.
    public mutating func reindex() {
        index = Dictionary(photos.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        burstIndex = Dictionary(bursts.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    public func photo(_ id: String?) -> Photo? { id.flatMap { index[$0] }.map { photos[$0] } }
    public func position(_ id: String?) -> Int? { id.flatMap { index[$0] } }
    public func burst(_ id: String?) -> Burst? { id.flatMap { burstIndex[$0] }.map { bursts[$0] } }
    public var isEmpty: Bool { photos.isEmpty }
    public static let empty = Shoot()
}

public struct SavedRecord: Codable, Equatable, Sendable {
    public var sig: String
    /// Photos saved, and how many of them with edits.
    public var n: Int
    public var ne: Int
    public var fmt: SaveFormat
    public var at: Date
    /// True when this save replaced an earlier one ("Saved again").
    public var again: Bool
    public init(sig: String, n: Int, ne: Int, fmt: SaveFormat, at: Date = Date(), again: Bool) {
        self.sig = sig; self.n = n; self.ne = ne; self.fmt = fmt; self.at = at; self.again = again
    }
}

// MARK: Edit settings (README, Edit table). The single list of sliders.

public enum EditSection: String, CaseIterable, Codable, Sendable { case light, curve, colour, effects }

public struct EditSetting: Hashable, Sendable {
    public let key: String, label: String, section: EditSection
    public let min: Double, max: Double, step: Double, def: Double
    /// Temperature moves on a log scale.
    public let log: Bool
    public init(_ key: String, _ label: String, _ section: EditSection, _ min: Double, _ max: Double, _ step: Double, _ def: Double, log: Bool = false) {
        self.key = key; self.label = label; self.section = section; self.min = min; self.max = max; self.step = step; self.def = def; self.log = log
    }
    public func clamp(_ v: Double) -> Double { Swift.min(max, Swift.max(min, (v / step).rounded() * step)) }

    public static let colours = ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"]
    public static let colourAxes = ["hue", "sat", "lum"]
    /// As-shot temperature when the file gives none.
    public static let asShotKelvin = 5200.0

    public static let all: [EditSetting] = {
        var a: [EditSetting] = [
            .init("ev", "Exposure", .light, -5, 5, 0.05, 0),
            .init("wb", "Temperature", .light, 2500, 10000, 10, asShotKelvin, log: true),
            .init("tint", "Tint", .light, -150, 150, 1, 0),
            .init("hl", "Highlights", .light, -100, 100, 1, 0),
            .init("sh", "Shadows", .light, -100, 100, 1, 0),
            .init("con", "Contrast", .light, -100, 100, 1, 0),
            .init("sat", "Saturation", .light, -100, 100, 1, 0),
            .init("cDark", "Dark tones", .curve, -50, 50, 1, 0),
            .init("cMid", "Midtones", .curve, -50, 50, 1, 0),
            .init("cLight", "Light tones", .curve, -50, 50, 1, 0),
        ]
        for axis in colourAxes { for c in colours { a.append(.init("\(axis)_\(c)", c.prefix(1).uppercased() + c.dropFirst(), .colour, -100, 100, 1, 0)) } }
        a += [
            .init("vig", "Vignette", .effects, -100, 100, 1, 0),
            .init("vMid", "Midpoint", .effects, 0, 100, 1, 50),
            .init("vRound", "Roundness", .effects, -100, 100, 1, 0),
            .init("vFeather", "Feather", .effects, 0, 100, 1, 50),
            .init("vHl", "Keep highlights", .effects, 0, 100, 1, 0),
            .init("shp", "Sharpening", .effects, 0, 150, 1, 40),
            .init("nr", "Noise", .effects, 0, 100, 1, 0),
        ]
        return a
    }()
    public static let byKey: [String: EditSetting] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    public static func of(_ section: EditSection) -> [EditSetting] { all.filter { $0.section == section } }
    /// The setting Variations and nudges use when the pointer is over none.
    public static func main(_ section: EditSection) -> String {
        switch section { case .light: "ev"; case .curve: "cMid"; case .colour: "sat_red"; case .effects: "vig" }
    }
}

/// Crop keys inside a `Look` (fractions of the frame, quarter turns, straighten angle).
public enum CropKey { public static let x = "cropX", y = "cropY", w = "cropW", h = "cropH", turns = "turns", angle = "angle"
    public static let all = [x, y, w, h, turns, angle] }
