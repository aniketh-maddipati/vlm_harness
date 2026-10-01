import SwiftUI
import UniformTypeIdentifiers
import LuminaCore

// WP-1. Dropping photos or folders on the window, on any step (README "Drop overlay", R-17).
// The shell shows the overlay and hands the file URLs to `model.dropFiles` → `importURLs`
// (WP-2 walks, checks and adds them). The app never opens a dropped file itself.

/// "Drop to add photos": inset 10, radius 14, a 2pt dashed gold border over a dark scrim.
struct DropOverlay: View {
    @Environment(\.luminaScale) private var s

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LuminaRadius.dropOverlay.scaled(s), style: .continuous)
        shape.fill(LuminaColor.overlayScrim)
            .overlay(shape.strokeBorder(LuminaColor.accentGoldDash, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .overlay {
                VStack(spacing: 6.scaled(s)) {
                    Text("Drop to add photos").font(LuminaFont.ui(LuminaFontSize.overlayTitle, .semibold, s))
                        .foregroundStyle(LuminaColor.textPrimary)
                    Text("Photos or whole folders. Anything that isn’t a photo is skipped.").font(LuminaFont.body(s))
                        .foregroundStyle(LuminaColor.textSecondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24.scaled(s))
            }
            .padding(10.scaled(s))
            // The drag goes through it to the window's drop target.
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.Shell.dropOverlay)
    }
}

/// The window-wide drop target. Only drags that carry files count: a drag of text never shows
/// the overlay and its drop does nothing.
struct ShellDrop: DropDelegate {
    let model: AppModel
    static let types: [UTType] = [.fileURL]

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: Self.types) }
    func dropEntered(info: DropInfo) { model.dropHover(true) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }
    func dropExited(info: DropInfo) { model.dropHover(false) }

    func performDrop(info: DropInfo) -> Bool {
        // The overlay goes now, whatever the providers do later (it must never stick).
        model.dropHover(false)
        let providers = info.itemProviders(for: Self.types)
        guard !providers.isEmpty else { return false }
        let model = model
        Self.fileURLs(providers) { model.dropFiles($0) }
        return true
    }

    /// The providers' file URLs, in drop order, delivered once on the main actor.
    static func fileURLs(_ providers: [NSItemProvider], _ done: @escaping @MainActor ([URL]) -> Void) {
        let found = Found(count: providers.count), group = DispatchGroup()
        for (i, p) in providers.enumerated() {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in found.set(i, url); group.leave() }
        }
        group.notify(queue: .main) { MainActor.assumeIsolated { done(found.urls) } }
    }

    private final class Found: @unchecked Sendable {
        private let lock = NSLock()
        private var slots: [URL?]
        init(count: Int) { slots = Array(repeating: nil, count: count) }
        func set(_ i: Int, _ url: URL?) { lock.withLock { slots[i] = url } }
        var urls: [URL] { lock.withLock { slots.compactMap { $0 }.filter(\.isFileURL) } }
    }
}
