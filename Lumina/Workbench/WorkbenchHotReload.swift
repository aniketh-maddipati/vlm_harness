#if DEBUG
import SwiftUI
import Combine
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
/// InjectionIII posts `INJECTION_BUNDLE_NOTIFICATION` off the main thread. The Inject package's
/// `@ObserveInjection` sometimes misses that hop on macOS, so the eval dylib loads (code is
/// patched) but SwiftUI never redraws. This host re-broadcasts on the main queue and forces a
/// fresh view identity via `.id(generation)`.
@MainActor
private final class WorkbenchInjectionPulse: ObservableObject {
    static let shared = WorkbenchInjectionPulse()

    @Published private(set) var generation = 0
    private var bag = Set<AnyCancellable>()

    private init() {
        _ = InjectConfiguration.load
        NotificationCenter.default.publisher(for: Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.generation += 1
                WorkbenchTrace.log("inject pulse generation=\(self?.generation ?? -1)")
            }
            .store(in: &bag)
    }
}

private struct WorkbenchHotHost<Content: View>: View {
    @ObserveInjection private var inject
    @ObservedObject private var pulse = WorkbenchInjectionPulse.shared
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        let generation = max(InjectConfiguration.observer.injectionNumber, pulse.generation)
        return content()
            .id(generation)
            .enableInjection()
            .overlay(alignment: .topTrailing) {
                Text(generation == 0 ? "Hot" : "Hot · \(generation)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(generation == 0 ? Color.secondary : Color.green)
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
