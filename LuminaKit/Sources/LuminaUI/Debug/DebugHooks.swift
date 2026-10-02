import SwiftUI
import AppKit
import LuminaCore

// WP-0 contract: the test hooks (ACCESSIBILITY_CONTRACT.md "Test hooks"). On only with
// `-LuminaUITest YES`, compiled only into debug builds.

/// Hidden 1×1 elements: `debug.state`, `debug.metrics`, `debug.memoryMB`, `debug.command`.
public struct DebugHooks: View {
    @Environment(AppModel.self) private var model
    @State private var command = ""
    @State private var metrics = "{}"
    @State private var memory = "0"
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    public init() {}

    public var body: some View {
        #if LUMINA_UITEST
        if model.config.uiTest {
            ZStack(alignment: .topLeading) {
                // Not `Text`: on macOS a static text reports its own string (" ") as its value,
                // over `accessibilityValue`, and the tests read that instead of the JSON.
                Color.clear.frame(width: 1, height: 1).luminaStatus(AccessibilityID.Debug.state, model.debugStateJSON)
                Color.clear.frame(width: 1, height: 1).luminaStatus(AccessibilityID.Debug.metrics, metrics)
                Color.clear.frame(width: 1, height: 1).luminaStatus(AccessibilityID.Debug.memoryMB, memory)
                TextField("", text: $command)
                    .textFieldStyle(.plain).frame(width: 1, height: 1)
                    .accessibilityIdentifier(AccessibilityID.Debug.command)
                    .onSubmit { let c = command; command = ""; DebugCommand.run(c, model) }
            }
            .opacity(0.01)
            .onReceive(tick) { _ in
                let m = Metrics.shared.json; if m != metrics { metrics = m }
                let mb = String(format: "%.1f", DebugCommand.footprintMB()); if mb != memory { memory = mb }
            }
        }
        #endif
    }
}

@MainActor
public enum DebugCommand {
    /// `{"resize":[w,h]}`, `{"drop":[paths]}`, `{"blur":true}`, `{"keyDown":"v"}`, `{"keyUp":"v"}`,
    /// `{"releaseAllKeys":true}`, `{"injectFault":"storageFull"}`, `{"clearFault":…}`,
    /// `{"openSecondWindow":true}`, `{"dragEnter":true}`, `{"relaunchSoon":true}`.
    public static func run(_ json: String, _ model: AppModel) {
        guard let d = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return }
        // The command field took the keyboard to be typed into; give it back to the window.
        NSApp.keyWindow?.makeFirstResponder(nil)
        if let r = d["resize"] as? [Double], r.count == 2 { model.hooks.resize?(CGSize(width: r[0], height: r[1])) }
        if let paths = d["drop"] as? [String] { model.imports.dropTargeted = false; model.importURLs(paths.map { URL(fileURLWithPath: $0) }) }
        if d["dragEnter"] as? Bool == true { model.imports.dropTargeted = true }
        if d["blur"] as? Bool == true { model.windowBlurred(); model.hooks.blur?() }
        if let k = d["keyDown"] as? String { model.handle(KeyEvent(k, isRepeat: model.heldKeys.contains(k))) }
        if let k = d["keyUp"] as? String { model.handle(KeyEvent(k, phase: .up)) }
        if d["releaseAllKeys"] as? Bool == true { model.releaseAllKeys() }
        if let f = (d["injectFault"] as? String).flatMap(Fault.init) { Faults.shared.inject(f) }
        if let f = (d["clearFault"] as? String).flatMap(Fault.init) { Faults.shared.clear(f) }
        if d["openSecondWindow"] as? Bool == true { model.hooks.openSecondWindow?() }
    }

    /// phys_footprint in MB (the soak test, R-92).
    public static func footprintMB() -> Double {
        var info = task_vm_info_data_t(), count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
