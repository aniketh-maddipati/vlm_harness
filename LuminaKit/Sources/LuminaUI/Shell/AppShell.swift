import SwiftUI
import AppKit
import LuminaCore

// WP-1. The window: the top bar with the four step tabs, the step's screen, the drop overlay.
// The top bar is the only chrome above content; it sits in the titlebar area (full-size content
// view, transparent hidden-title titlebar: `WindowChrome`), so there is no toolbar and no title gap.

public struct AppShell: View {
    @State private var model: AppModel
    @State private var keys = KeyMonitor()
    @State private var chrome = ShellChrome()
    /// `stepChangedAt` when this window's view was made: a screen fades in only after a step
    /// change the user made here, never the screen the window opens on.
    @State private var openedAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init(model: AppModel) {
        _model = State(initialValue: model)
        _openedAt = State(initialValue: model.stepChangedAt)
    }

    public var body: some View {
        GeometryReader { geo in
            let s = LayoutScale.scale(for: geo.size)
            VStack(spacing: 0) {
                // Focus mode (H in Edit) is only the photo, edge to edge.
                if !(model.step == .edit && model.edit.focus) {
                    TopBar(layout: TopBarLayout(window: geo.size, scale: s, trafficLights: chrome.trafficLights))
                }
                screen
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Fade only, no slide (R-60); with reduced motion, no fade either.
                    .luminaStepFade(reduce, animated: model.stepChangedAt != openedAt)
                    .id(model.step)
            }
            .overlay {
                ZStack { if model.imports.dropTargeted { DropOverlay().transition(.opacity) } }
                    .animation(LuminaMotion.panelFade(reduce), value: model.imports.dropTargeted)
            }
            // Clear of the window's rounded corner, its resize edges and the traffic lights, so
            // the UI tests can click `debug.command`.
            .overlay(alignment: .topLeading) { DebugHooks().offset(x: 12, y: 31) }
            .environment(\.luminaScale, s)
            .onAppear { sized(geo.size) }
            .onChange(of: geo.size) { _, size in sized(size) }
        }
        .background(LuminaColor.bgApp)
        .foregroundStyle(LuminaColor.textPrimary)
        .onDrop(of: ShellDrop.types, delegate: ShellDrop(model: model))
        .ignoresSafeArea()
        .environment(model)
        .preferredColorScheme(.dark)
        .background(WindowAccessor { keys.attach($0, model: model, chrome: chrome) })
        .onAppear {
            if let w = keys.window { keys.attach(w, model: model, chrome: chrome) }
            // ⌘O works on every step from the start, not only once Open has been shown (WP2.md #4).
            OpenPickers.install(model)
        }
        .onDisappear { keys.remove() }
    }

    @ViewBuilder private var screen: some View {
        switch model.step {
        case .open: OpenScreen()
        case .cull: CullScreen()
        case .edit: EditScreen()
        case .save: SaveScreen()
        }
    }

    private func sized(_ size: CGSize) {
        if model.windowSize != size { model.windowSize = size }
        Metrics.shared.scale = Double(LayoutScale.scale(for: size))
    }
}
