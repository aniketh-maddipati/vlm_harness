import Foundation
import XCTest

/// Visible application state the explorer reasons about.
enum ExplorerState: String {
    case openShoot
    case contactSheet
    case singlePhoto

    init(route: String) {
        switch route {
        case "singlePhoto": self = .singlePhoto
        case "contactSheet": self = .contactSheet
        default: self = .openShoot
        }
    }
}

/// Legal actions. Availability is state-dependent — the runner never emits an illegal one.
enum ExplorerAction: String, CaseIterable {
    case openShoot
    case focusNext
    case focusPrevious
    case focusUp
    case focusDown
    case keep
    case reject
    case undo
    case toggleSelection
    case extendSelection
    case openFocused
    case closePhoto
    case increaseDensity
    case decreaseDensity
    case relaunch
    case resizeWindow
}

/// One recorded step: the action, the state before/after, and any invariant violations.
struct ExplorerStep: Codable {
    var index: Int
    var action: String
    var stateBefore: String
    var stateAfter: String
    var routeBefore: String
    var routeAfter: String
    var keptBefore: Int
    var keptAfter: Int
    var selectionAfter: Int
    var violations: [String]
}

/// The replayable report every run produces.
struct ExplorerReport: Codable {
    var seed: UInt64
    var fixture: String
    var requestedSteps: Int
    var completedSteps: Int
    var lastSuccessfulAction: String?
    var failedAction: String?
    var failedViolations: [String]
    var steps: [ExplorerStep]

    func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
