import SwiftUI
import AppKit
import LuminaCore

// WP-1. The window: top bar with the four step tabs, the step's screen, the drop overlay.
// (WP-0 wrote this as a working stub; WP-1 owns it from here.)

public struct AppShell: View {
    @State private var model: AppModel
    @State private var keys = KeyMonitor()
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init(model: AppModel) { _model = State(initialValue: model) }

    public var body: some View {
        GeometryReader { geo in
            let s = LayoutScale.scale(for: geo.size)
            VStack(spacing: 0) {
                TopBar()
                ZStack {
                    switch model.step {
                    case .open: OpenScreen().transition(.opacity)
                    case .cull: CullScreen().transition(.opacity)
                    case .edit: EditScreen().transition(.opacity)
                    case .save: SaveScreen().transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(LuminaMotion.stepFade(reduce), value: model.step)
            }
            .overlay { if model.imports.dropTargeted { DropOverlay().transition(.opacity) } }
            .overlay(alignment: .topLeading) { DebugHooks() }
            .environment(\.luminaScale, s)
            .onAppear { model.windowSize = geo.size; Metrics.shared.scale = Double(s) }
            .onChange(of: geo.size) { _, size in model.windowSize = size; Metrics.shared.scale = Double(LayoutScale.scale(for: size)) }
        }
        .background(LuminaColor.bgApp)
        .foregroundStyle(LuminaColor.textPrimary)
        .ignoresSafeArea()
        .environment(model)
        .preferredColorScheme(.dark)
        .background(WindowAccessor { w in
            keys.window = w; keys.install(model)
            model.hooks.resize = { [weak w] size in w?.setContentSize(size) }
            if let size = model.config.window { w.setContentSize(size) }
        })
        .onDisappear { keys.remove() }
    }
}

/// The top bar (README "Global shell"): wordmark, step tabs, shoot meta.
struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        let bp = model.breakpoints
        ZStack {
            HStack(spacing: 2) {
                ForEach(Step.allCases, id: \.self) { step in
                    Button { model.go(step) } label: {
                        Text(step.title).font(LuminaFont.body(s, model.step == step ? .bold : .regular, id: AccessibilityID.step(step.rawValue)))
                            .foregroundStyle(model.step == step ? LuminaColor.textPrimary : LuminaColor.textTertiary)
                            .frame(width: bp.tabWidth.scaled(s), height: LuminaHeight.tab.scaled(s))
                            .background(RoundedRectangle(cornerRadius: LuminaRadius.tabThumb.scaled(s)).fill(model.step == step ? LuminaColor.bgSelected : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.step(step.rawValue))
                    .accessibilityLabel(step.title)
                    .accessibilityAddTraits(model.step == step ? .isSelected : [])
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: LuminaRadius.tabTrack.scaled(s)).fill(LuminaColor.fill08))
        }
        .frame(maxWidth: .infinity).frame(height: bp.topBarHeight.scaled(s))
        .background(LuminaColor.bgPanel)
        .overlay(alignment: .bottom) { LuminaColor.hairline.frame(height: 1) }
    }
}

/// "Drop to add photos" (README "Drop overlay").
struct DropOverlay: View {
    @Environment(\.luminaScale) private var s
    var body: some View {
        RoundedRectangle(cornerRadius: LuminaRadius.dropOverlay.scaled(s)).fill(LuminaColor.overlayScrim)
            .overlay(RoundedRectangle(cornerRadius: LuminaRadius.dropOverlay.scaled(s)).strokeBorder(LuminaColor.accentGoldDash, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
            .overlay {
                VStack(spacing: 8) {
                    Text("Drop to add photos").font(LuminaFont.ui(LuminaFontSize.overlayTitle, .semibold, s))
                    Text("Photos or whole folders. Anything that isn’t a photo is skipped.").font(LuminaFont.body(s)).foregroundStyle(LuminaColor.textSecondary)
                }
            }
            .padding(10)
            .accessibilityElement(children: .combine).accessibilityIdentifier(AccessibilityID.Shell.dropOverlay)
    }
}
