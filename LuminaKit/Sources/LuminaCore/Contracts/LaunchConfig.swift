import Foundation
import CoreGraphics
import os

// WP-0 contract: launch hooks, faults, the error funnel and signposts (ACCESSIBILITY_CONTRACT.md).

public enum Fault: Hashable, Sendable {
    case storageFull, imageLoadFail, offline, slowDecode(ms: Int)
    public init?(_ s: String) {
        switch s {
        case "storageFull": self = .storageFull
        case "imageLoadFail": self = .imageLoadFail
        case "offline": self = .offline
        default:
            guard s.hasPrefix("slowDecode:"), let ms = Int(s.dropFirst("slowDecode:".count)) else { return nil }
            self = .slowDecode(ms: ms)
        }
    }
}

/// Faults are process-wide so the default services can see them without a model reference.
public final class Faults: @unchecked Sendable {
    public static let shared = Faults()
    private let lock = NSLock(); private var set: Set<Fault> = []
    public func inject(_ f: Fault) { lock.lock(); set.insert(f); lock.unlock() }
    public func clear(_ f: Fault) { lock.lock(); set.remove(f); lock.unlock() }
    public func clearAll() { lock.lock(); set.removeAll(); lock.unlock() }
    public func has(_ f: Fault) -> Bool { lock.lock(); defer { lock.unlock() }; return set.contains(f) }
    public var slowDecodeMs: Int? { lock.lock(); defer { lock.unlock() }; for case .slowDecode(let ms) in set { return ms }; return nil }
}

public struct LaunchConfig: Sendable {
    public enum Card: Equatable, Sendable { case demo(Int), unsplash(Int), path(URL), none }
    /// `-LuminaUITest YES`: the debug hooks are on.
    public var uiTest = false
    public var storeDir: URL?
    public var fixture: URL?
    public var card: Card = .none
    /// Photos per second for the simulated copy; nil = real speed.
    public var copyRate: Double?
    public var window: CGSize?
    public var skipIntro = false
    public var faults: [Fault] = []

    public init() {}
    public init(arguments: [String] = ProcessInfo.processInfo.arguments, environment e: [String: String] = ProcessInfo.processInfo.environment) {
        if let i = arguments.firstIndex(of: "-LuminaUITest"), arguments.indices.contains(i + 1) { uiTest = arguments[i + 1].uppercased() == "YES" }
        storeDir = e["LUMINA_STORE_DIR"].map { URL(fileURLWithPath: $0) }
        fixture = e["LUMINA_FIXTURE"].map { URL(fileURLWithPath: $0) }
        if let c = e["LUMINA_CARD"] {
            if c == "demo117" { card = .demo(117) }
            else if c.hasPrefix("demo:"), let n = Int(c.dropFirst(5)) { card = .demo(n) }
            else if c.hasPrefix("unsplash:"), let n = Int(c.dropFirst(9)) { card = .unsplash(n) }
            else if c.hasPrefix("/") { card = .path(URL(fileURLWithPath: c)) }
        }
        copyRate = e["LUMINA_COPY_RATE"].flatMap(Double.init)
        if let w = e["LUMINA_WINDOW"]?.split(separator: "x").compactMap({ Double($0) }), w.count == 2 { window = CGSize(width: w[0], height: w[1]) }
        skipIntro = e["LUMINA_INTRO"] == "skip"
        faults = (e["LUMINA_FAULTS"] ?? "").split(separator: ",").compactMap { Fault(String($0)) }
    }
}

/// Caught-but-unexpected errors (R-73). `debug.state.errors` reads the count.
public enum ErrorFunnel {
    private static let lock = NSLock(); nonisolated(unsafe) private static var n = 0
    nonisolated(unsafe) public static var last: String?
    public static var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    public static func report(_ what: String, _ error: Error? = nil) {
        lock.lock(); n += 1; last = error.map { "\(what): \($0)" } ?? what; lock.unlock()
        Perf.log.error("unexpected: \(what, privacy: .public) \(String(describing: error), privacy: .public)")
    }
    public static func reset() { lock.lock(); n = 0; last = nil; lock.unlock() }
}

/// os_signpost intervals the load tests measure: subsystem "com.lumina", category "perf",
/// names "PhotoSwitch", "CullKey", "Save", "Import".
public enum Perf {
    public static let log = Logger(subsystem: "com.lumina", category: "app")
    public static let signposter = OSSignposter(subsystem: "com.lumina", category: "perf")
    public static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let s = signposter.beginInterval(name); defer { signposter.endInterval(name, s) }
        return try body()
    }
    public static func begin(_ name: StaticString) -> OSSignpostIntervalState { signposter.beginInterval(name) }
    public static func end(_ name: StaticString, _ s: OSSignpostIntervalState) { signposter.endInterval(name, s) }
}
