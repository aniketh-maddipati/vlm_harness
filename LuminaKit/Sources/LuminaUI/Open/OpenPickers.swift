import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LuminaCore

// WP-2. The two system pickers ("Open folder…" ⌘O, "Choose photos…") and file drops. Both end in
// `AppModel.importURLs`, which does the rest.

@MainActor
enum OpenPickers {
    private static var showing = false

    /// Puts the pickers behind `model.hooks`, so ⌘O works from every step once Open has been seen.
    static func install(_ model: AppModel) {
        if model.hooks.pickFolder == nil { model.hooks.pickFolder = { [weak model] in if let model { present(folders: true, model) } } }
        if model.hooks.pickPhotos == nil { model.hooks.pickPhotos = { [weak model] in if let model { present(folders: false, model) } } }
    }

    static func present(folders: Bool, _ model: AppModel) {
        // The UI tests can't drive a system panel and must never be left behind one (they mash ⌘O);
        // they import through `debug.command` drops. Offscreen renders have no window to put it on.
        guard !model.config.uiTest, !showing, NSApp.activationPolicy() != .prohibited else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = folders; panel.canChooseFiles = !folders
        panel.allowsMultipleSelection = true; panel.canCreateDirectories = false; panel.resolvesAliases = true
        if !folders { panel.allowedContentTypes = [.image, .rawImage] }
        showing = true
        let done: (NSApplication.ModalResponse) -> Void = { [weak model] response in
            MainActor.assumeIsolated {
                showing = false
                if response == .OK, let model { model.importURLs(panel.urls) }
            }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow { panel.beginSheetModal(for: window, completionHandler: done) } else { panel.begin(completionHandler: done) }
    }
}

/// Files and folders dropped on the view are imported; anything else (text, a link) is not a drop
/// at all (R-17). While a drag is over it, `imports.dropTargeted` is on for the shell's overlay.
struct LuminaFileDrop: ViewModifier {
    @Environment(AppModel.self) private var model
    func body(content: Content) -> some View {
        content.onDrop(of: [.fileURL], isTargeted: Binding(get: { model.imports.dropTargeted }, set: { model.imports.dropTargeted = $0 })) { providers in
            let model = model
            Self.urls(providers) { urls in
                model.imports.dropTargeted = false
                model.importURLs(urls)
            }
            return true
        }
    }

    /// The file URLs in a drop, in the order they were dropped.
    static func urls(_ providers: [NSItemProvider], _ done: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup(), lock = NSLock()
        var found: [(Int, URL)] = []
        for (i, p) in providers.enumerated() where p.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { lock.withLock { found.append((i, url)) } }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = lock.withLock { found.sorted { $0.0 < $1.0 }.map(\.1) }
            MainActor.assumeIsolated { done(urls) }
        }
    }
}

public extension View {
    /// Import what is dropped here. Open uses it; the shell can put it on the whole window so a
    /// drop works on every step.
    func luminaFileDrop() -> some View { modifier(LuminaFileDrop()) }
}

/// Offscreen-render states for Open that keys can't reach (`lumina-snap` has no window to drop on).
/// Debug builds only: `LUMINA_SNAP_OPEN=import:/folder`, `checking`, `reopen` or `armed`.
@MainActor
enum OpenDebug {
    static func apply(_ model: AppModel) {
        #if LUMINA_UITEST
        guard let spec = ProcessInfo.processInfo.environment["LUMINA_SNAP_OPEN"], NSApp.activationPolicy() == .prohibited else { return }
        if spec.hasPrefix("import:") {
            model.importURLs(spec.dropFirst(7).split(separator: "|").map { URL(fileURLWithPath: String($0)) })
            Task { @MainActor in await model.importsIdle(); model.go(.open) }
        } else if spec == "checking" {
            model.imports.busy = true; model.imports.checked = 24; model.imports.toCheck = 400
        } else if spec == "reopen" {
            model.open.reopenName = "Holiday"; model.open.reopenCount = 5
        } else if spec == "armed" {
            model.startOverClick()
        }
        #endif
    }
}
