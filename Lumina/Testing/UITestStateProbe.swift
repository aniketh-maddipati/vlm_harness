import AppKit
import SwiftUI

/// Machine-readable snapshot of P0 session state. The XCUITest harness reads this (never UI text)
/// to assert structured invariants: counts, focus/selection independence, cull map, availability.
struct ProbeSnapshot: Codable, Equatable {
    var route: String                 // "open" | "contactSheet" | "singlePhoto"
    var shootName: String?
    var fixture: String?
    var seed: String
    var assetCount: Int
    var visibleCount: Int
    var selectionCount: Int
    var keptCount: Int
    var rejectedCount: Int
    var unreviewedCount: Int
    var editedCount: Int
    var densityColumns: Int
    var filter: String
    var canUndo: Bool
    var focusedAssetID: String?
    var focusedVisible: Bool
    var focusedAvailability: String?
    var focusedCull: String?
    /// Deterministic fingerprint of the focused asset's canonical `EditRecipe` (nil when nothing is
    /// focused). Lets the harness assert an edit gesture changed/reverted state without exposing
    /// pixel data, file paths, or the full recipe payload.
    var focusedRecipeFingerprint: String?
    var inspectingAssetID: String?
    var selectedAssetIDs: [String]
    var missingOriginalCount: Int
    var previewReadyCount: Int
    var phaseDetail: String
    var scrollAnchor: Double
    /// assetID → cull decision, for exact undo diffing and per-asset invariants.
    var culls: [String: String]
    var editedIDs: [String]
    /// Ordered visible asset IDs (current filter/sort) so the harness can address the Nth cell
    /// without depending on machine-specific derived UUIDs.
    var visibleAssetIDs: [String]
    /// Assets whose original file is currently unavailable (cached preview may still exist).
    var missingAssetIDs: [String]

    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

extension P0SessionModel {
    /// Build the structured snapshot the UI-test harness observes.
    func uiTestSnapshot() -> ProbeSnapshot {
        let visible = filteredAssets
        let visibleIDs = Set(visible.map(\.id))
        let rejected = assets.filter { $0.cull == .reject }.count
        let unreviewed = assets.filter { $0.cull == .undecided || $0.cull == .hold }.count
        let editedIDs = assets.filter { $0.recipe != nil }.map(\.id.uuidString)

        let route: String
        if self.route == .open {
            route = "open"
        } else if inspectingAssetID != nil {
            route = "singlePhoto"
        } else {
            route = "contactSheet"
        }

        let focused = focusedAssetID.flatMap { id in assets.first(where: { $0.id == id }) }

        var culls: [String: String] = [:]
        culls.reserveCapacity(assets.count)
        for asset in assets {
            culls[asset.id.uuidString] = asset.cull.rawValue
        }

        return ProbeSnapshot(
            route: route,
            shootName: shoot?.name,
            fixture: UITestSupport.fixtureName,
            seed: String(UITestSupport.seed),
            assetCount: assets.count,
            visibleCount: visible.count,
            selectionCount: selectionCount,
            keptCount: keptCount,
            rejectedCount: rejected,
            unreviewedCount: unreviewed,
            editedCount: editedIDs.count,
            densityColumns: densityColumns,
            filter: filter.rawValue,
            canUndo: canUndo,
            focusedAssetID: focusedAssetID?.uuidString,
            focusedVisible: focusedAssetID.map { visibleIDs.contains($0) } ?? false,
            focusedAvailability: focused?.source.availability.rawValue,
            focusedCull: focused?.cull.rawValue,
            focusedRecipeFingerprint: focused.map { recipe(for: $0.id).valueFingerprint },
            inspectingAssetID: inspectingAssetID?.uuidString,
            selectedAssetIDs: selectedAssetIDs.map(\.uuidString).sorted(),
            missingOriginalCount: status.missingOriginalCount,
            previewReadyCount: status.previewReadyCount,
            phaseDetail: status.phaseDetail,
            scrollAnchor: scrollAnchor,
            culls: culls,
            editedIDs: editedIDs.sorted(),
            visibleAssetIDs: visible.map(\.id.uuidString),
            missingAssetIDs: assets.filter { $0.source.availability == .missing }.map(\.id.uuidString)
        )
    }
}

/// Zero-footprint accessibility element that publishes the session snapshot as its
/// `accessibilityValue`. Only present when the UI-test harness is active, so it never affects a
/// normal (or Release) run. Backed by an `NSView` for reliable macOS accessibility exposure.
struct UITestStateProbe: NSViewRepresentable {
    let json: String

    func makeNSView(context: Context) -> ProbeNSView {
        let view = ProbeNSView()
        view.json = json
        return view
    }

    func updateNSView(_ nsView: ProbeNSView, context: Context) {
        nsView.json = json
    }

    final class ProbeNSView: NSView {
        var json: String = "{}" {
            didSet { setAccessibilityValue(json) }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setAccessibilityElement(true)
            setAccessibilityRole(.staticText)
            setAccessibilityIdentifier(P0AccessibilityID.stateProbe)
            setAccessibilityLabel(P0AccessibilityID.stateProbe)
            setAccessibilityValue(json)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var intrinsicContentSize: NSSize { NSSize(width: 1, height: 1) }
    }
}

/// Pins the host window to an exact content size (and disables the zoom button) so visual and
/// layout tests are deterministic across machines. Active only under the UI-test harness.
struct UITestWindowSizer: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = SizerNSView()
        view.targetSize = size
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? SizerNSView)?.targetSize = size
        (nsView as? SizerNSView)?.applyIfPossible()
    }

    final class SizerNSView: NSView {
        var targetSize: CGSize = .zero

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyIfPossible()
        }

        func applyIfPossible() {
            guard let window, targetSize.width > 0, targetSize.height > 0 else { return }
            if window.contentView?.frame.size == targetSize { return }
            window.setContentSize(targetSize)
            window.center()
            window.styleMask.remove(.resizable) // stable size for the run
        }
    }
}

/// Forces the app to become active with a key window under the UI-test harness. Without this, a
/// freshly launched instance sometimes stays in the background, and macOS then exposes only a
/// collapsed accessibility tree (window but no descendants), making element queries flaky.
struct UITestActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ActivatorNSView() }
    func updateNSView(_ nsView: NSView, context: Context) { (nsView as? ActivatorNSView)?.activate() }

    final class ActivatorNSView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            activate()
        }
        func activate() {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }
}

extension View {
    /// Attach the structured state probe (plus activation and optional pinned window size) when the
    /// UI-test harness is active.
    @ViewBuilder
    func uiTestStateProbe(_ session: P0SessionModel) -> some View {
        if UITestSupport.isActive {
            self
                .overlay(alignment: .bottomTrailing) {
                    UITestStateProbe(json: session.uiTestSnapshot().jsonString())
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                }
                .background {
                    UITestActivator().frame(width: 0, height: 0)
                    if let size = UITestSupport.forcedWindowSize {
                        UITestWindowSizer(size: size)
                            .frame(width: 0, height: 0)
                    }
                }
        } else {
            self
        }
    }
}
