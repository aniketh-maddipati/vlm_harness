#if DEBUG
import SwiftUI
#if LUMINA_WORKBENCH
import Inject
#endif

/// The hot loop.
///
/// `.workbenchHot()` marks a view as hot: editing its source and saving re-renders it in the
/// running app, without relaunch and without losing session state.
///
/// **This is the only file in the codebase that names an Inject symbol.** Every other call site
/// says `.workbenchHot()`, so the dependency has exactly one seam. Two fences guard it:
///
/// 1. `#if DEBUG` — Release compiles this file to nothing.
/// 2. `#if LUMINA_WORKBENCH` — Lumina Debug defines it; Release does not link this path.
///
/// `costume_lint.py` enforces fence 1 mechanically.
extension View {
    /// Compiles to `WorkbenchHotHost { self }` in Lumina Debug; plain `self` in Release.
    @ViewBuilder
    func workbenchHot() -> some View {
        #if LUMINA_WORKBENCH
        WorkbenchHotHost { self }
        #else
        self
        #endif
    }
}

#if LUMINA_WORKBENCH
/// Observes the injection bundle and rebuilds `content` when its source file is recompiled.
///
/// Inject needs both halves to work: `@ObserveInjection` supplies the observable that triggers
/// the rebuild, `enableInjection()` loads the bundle and boxes the view so its structure may
/// change between edits. Hosting them here rather than in each view keeps the property wrapper
/// out of product types.
private struct WorkbenchHotHost<Content: View>: View {
    @ObserveInjection private var inject
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        // Re-run the builder on each injection so edited SwiftUI bodies take effect.
        let _ = inject
        return content()
            .enableInjection()
            .overlay(alignment: .topTrailing) {
                Text("Hot")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(10)
                    .allowsHitTesting(false)
            }
    }
}
#endif
#endif
