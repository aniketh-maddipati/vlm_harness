import Foundation
import XCTest

/// Owns evidence capture: screenshots, accessibility hierarchy, and structured context.
/// Attachments use `.keepAlways` so failures always leave replayable evidence, while passing
/// runs stay lean.
struct DiagnosticsRobot {
    let app: XCUIApplication
    unowned let test: XCTestCase

    /// Capture the full diagnostic bundle described in the harness spec.
    func captureFailureEvidence(reason: String, context: [String: String]) {
        attachScreenshot(name: "main-window", element: app.windows.firstMatch)
        attachScreenshot(name: "full-screen", element: nil)
        attachText(name: "accessibility-hierarchy", string: app.debugDescription)

        var ctx = context
        ctx["reason"] = reason
        attachText(name: "diagnostic-context", string: formatted(ctx))

        if let probe = readProbeJSON() {
            attachText(name: "state-probe", string: probe)
        }
    }

    /// Screenshot of a specific element, or the whole screen when `element` is nil.
    func attachScreenshot(name: String, element: XCUIElement?) {
        let screenshot: XCUIScreenshot
        if let element, element.exists {
            screenshot = element.screenshot()
        } else {
            screenshot = XCUIScreen.main.screenshot()
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    func attachText(name: String, string: String) {
        let attachment = XCTAttachment(string: string)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    /// Attach an arbitrary file (e.g. the persisted shoot.json snapshot). No-op if missing.
    func attachFileIfPresent(name: String, url: URL) {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }
        let attachment = XCTAttachment(data: data)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    /// Raw JSON from the state probe (nil if not present, e.g. still on the Open surface).
    func readProbeJSON() -> String? {
        let element = app.descendants(matching: .any)
            .matching(identifier: P0AXID.stateProbe)
            .firstMatch
        guard element.exists else { return nil }
        return element.value as? String
    }

    private func formatted(_ dict: [String: String]) -> String {
        dict.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }
}
