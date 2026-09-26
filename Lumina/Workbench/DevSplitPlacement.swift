#if DEBUG
import AppKit
import SwiftUI

/// DEBUG playground placement. `--dev-split` puts Lumina on the trailing half of the
/// visible screen so the leading half stays free for prompts while InjectionIII reloads.
///
/// The product minimum (1280 × 800) stays in force for every other launch. This display
/// is 1728 points wide, so a half-screen tile is narrower than that minimum; the flag
/// is what allows the playground window to take the trailing half.
enum DevSplitPlacement {
    nonisolated static let flag = "--dev-split"

    nonisolated static func requested(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains(flag)
    }

    /// Trailing half of `visible`. Leading half stays free.
    nonisolated static func trailingFrame(visible: CGRect) -> CGRect {
        let width = (visible.width / 2).rounded(.down)
        return CGRect(
            x: visible.maxX - width,
            y: visible.minY,
            width: width,
            height: visible.height
        )
    }

    /// Leading half of `visible` — the prompt window.
    nonisolated static func leadingFrame(visible: CGRect) -> CGRect {
        let width = (visible.width / 2).rounded(.down)
        return CGRect(
            x: visible.minX,
            y: visible.minY,
            width: width,
            height: visible.height
        )
    }

    @MainActor
    static func liveTrailingFrame(screen: NSScreen? = NSScreen.main) -> CGRect? {
        guard requested(), let screen else { return nil }
        return trailingFrame(visible: screen.visibleFrame)
    }
}

/// Moves the playground window onto the trailing half once, after it exists.
/// Later drags in the same run stick; the next Xcode launch places it again.
struct DevSplitWindowAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        AnchorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard DevSplitPlacement.requested() else { return }
            place()
            // SwiftUI applies its own frame after the view joins the window.
            DispatchQueue.main.async { [weak self] in self?.place() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.place() }
        }

        private func place() {
            guard let window else { return }
            guard let screen = window.screen ?? NSScreen.main else { return }
            let frame = DevSplitPlacement.trailingFrame(visible: screen.visibleFrame)
            window.isRestorable = false
            guard window.frame.integral != frame.integral else { return }
            window.setFrame(frame, display: true, animate: false)
            fputs(
                "[DevSplit] trailing \(Int(frame.width))×\(Int(frame.height)) "
                    + "at \(Int(frame.minX)),\(Int(frame.minY))\n",
                stderr
            )
        }
    }
}
#endif
