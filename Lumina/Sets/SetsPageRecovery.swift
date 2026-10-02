import Foundation

/// How often the page may be reloaded after its web content process dies (threat model T7).
/// A file that kills the page would otherwise give an endless crash-reload loop: up to `limit`
/// reloads inside `window` seconds, then the next stop is refused and the window asks the user.
/// Pure: the clock is injected, nothing here knows about WebKit.
struct SetsReloadPolicy {
    enum Decision: Equatable { case reload, ask }

    static let limit = 3
    static let window: TimeInterval = 60

    let limit: Int
    let window: TimeInterval
    private let now: () -> TimeInterval
    /// When each reload still inside the window was made, oldest first.
    private(set) var reloads: [TimeInterval] = []

    init(limit: Int = SetsReloadPolicy.limit, window: TimeInterval = SetsReloadPolicy.window,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.limit = limit
        self.window = window
        self.now = now
    }

    /// The page stopped. `.reload` counts the reload it allows; `.ask` counts nothing.
    mutating func pageStopped() -> Decision {
        let t = now()
        reloads.removeAll { t - $0 >= window }
        guard reloads.count < limit else { return .ask }
        reloads.append(t)
        return .reload
    }

    /// "Try Again": the count starts over, and the reload the user asked for is not counted.
    mutating func reset() { reloads.removeAll() }
}

/// The first of an answer or a timeout, delivered exactly once; whatever comes after is dropped.
/// Quit uses it for the unsaved-keepers question, which a hung or dead page may never answer.
/// The timer is injected so the two orders can be tested without waiting.
@MainActor
final class SetsFirstAnswer<Value> {
    typealias Schedule = @MainActor (_ after: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> Void

    private var deliver: (@MainActor (Value) -> Void)?

    init(_ deliver: @escaping @MainActor (Value) -> Void) { self.deliver = deliver }
    // Spelled out: the implicit deinit of this generic main-actor class crashes swift-frontend in
    // optimised builds (Xcode 26.6, EarlyPerfInliner), so Release and the archive did not build.
    // A plain deinit: `nonisolated deinit` does not compile with the Xcode the CI runner has.
    deinit {}

    var isAnswered: Bool { deliver == nil }

    /// True when this call was the one delivered.
    @discardableResult
    func answer(_ value: Value) -> Bool {
        guard let d = deliver else { return false }
        deliver = nil
        d(value)
        return true
    }

    /// Asks `question`; `done` gets its answer, or `fallback` if `timeout` seconds pass first.
    static func ask(timeout: TimeInterval, fallback: Value, schedule: Schedule,
                    question: (_ answer: @escaping @MainActor (Value) -> Void) -> Void,
                    done: @escaping @MainActor (Value) -> Void) {
        let first = SetsFirstAnswer(done)
        schedule(timeout) { first.answer(fallback) }
        question { first.answer($0) }
    }
}

/// The page-keeps-stopping alert's words, in one place (and under test for the numbers they name).
enum SetsPageStoppedAlert {
    static let message = "Lumina keeps stopping"
    static func detail(limit: Int = SetsReloadPolicy.limit) -> String {
        "It stopped again after reloading \(limit) times in a minute. Your decisions so far are saved."
    }
    static let tryAgain = "Try Again"
    static let quit = "Quit"
}
