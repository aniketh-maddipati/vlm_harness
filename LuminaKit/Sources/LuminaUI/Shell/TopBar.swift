import SwiftUI
import LuminaCore

// WP-1. The top bar (README "Global shell"): wordmark, the four step tabs, shoot meta. Every
// size comes from `TopBarLayout` (tokens × luminaScale); the bar sits in the titlebar area, so
// its content starts after the traffic lights.

struct TopBar: View {
    let layout: TopBarLayout
    @Environment(\.luminaScale) private var s

    var body: some View {
        HStack(spacing: layout.gap) {
            if layout.showsWordmark {
                Text("Lumina").font(LuminaFont.display(LuminaFontSize.wordmark, s))
                    .foregroundStyle(LuminaColor.textPrimary)
                    .lineLimit(1).fixedSize()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // Centred in the space the wordmark and the meta leave, as in the prototype.
            StepTabs(layout: layout).frame(maxWidth: .infinity)
            if layout.showsMeta { ShootMeta(layout: layout) }
        }
        .padding(.leading, layout.leading).padding(.trailing, layout.trailing)
        .frame(maxWidth: .infinity).frame(height: layout.height)
        .background { ZStack { LuminaColor.bgPanel; WindowDragArea() } }
        .overlay(alignment: .bottom) { LuminaColor.hairline.frame(height: 1).allowsHitTesting(false) }
    }
}

/// The four-segment step control: a track, a thumb that slides to the current step, four tabs.
struct StepTabs: View {
    let layout: TopBarLayout
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: layout.thumbRadius, style: .continuous)
                .fill(LuminaColor.bgSelected)
                .shadow(color: LuminaColor.shadowTabThumb, radius: 0.5, x: 0, y: 0.5)
                .frame(width: layout.tabWidth, height: layout.tabHeight)
                .offset(x: layout.thumbOffset(model.step))
                // Only a step change slides it; a resize just puts it where it belongs.
                .animation(LuminaMotion.tabThumb(reduce), value: model.step)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                ForEach(Step.allCases, id: \.self) { StepTab(step: $0, layout: layout) }
            }
        }
        .padding(layout.trackPadding)
        .background {
            RoundedRectangle(cornerRadius: layout.trackRadius, style: .continuous).fill(LuminaColor.fill08)
                .overlay(RoundedRectangle(cornerRadius: layout.trackRadius, style: .continuous).strokeBorder(LuminaColor.fill12, lineWidth: 0.5))
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Steps")
    }
}

private struct StepTab: View {
    let step: Step
    let layout: TopBarLayout
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @State private var hover = false

    var body: some View {
        let selected = model.step == step, id = AccessibilityID.step(step.rawValue)
        Button { model.go(step) } label: {
            HStack(spacing: layout.hintGap) {
                Text(step.title)
                    .font(LuminaFont.body(s, selected ? .bold : .regular, id: id))
                    .foregroundStyle(selected || hover ? LuminaColor.textPrimary : LuminaColor.textTertiary)
                if layout.showsHints {
                    Text(step.tabHint).font(LuminaFont.mono(LuminaFontSize.hint, s)).foregroundStyle(LuminaColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .lineLimit(1)
            .frame(width: layout.tabWidth, height: layout.tabHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(StepTabStyle())
        .onHover { hover = $0 }
        .help(step.tabTooltip ?? "")
        .accessibilityIdentifier(id)
        .accessibilityLabel(step.title)
        .accessibilityHint(step.tabTooltip ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Pressed: the label shrinks to 0.97, as every button in the prototype does.
private struct StepTabStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// "N keepers · S scenes" and the copy status in its fixed slot.
struct ShootMeta: View {
    let layout: TopBarLayout
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s

    var body: some View {
        let status = model.shellCopyStatus
        HStack(alignment: .firstTextBaseline, spacing: layout.metaGap) {
            Text(model.shellShootTitle)
                .foregroundStyle(LuminaColor.textSecondary)
                .truncationMode(.tail)
            Text(status)
                .foregroundStyle(model.shellIsCopying ? LuminaColor.accentGold : LuminaColor.textTertiary)
                .fixedSize()
                .frame(minWidth: layout.copySlot, alignment: .trailing)
                .luminaStatus(AccessibilityID.Shell.copyStatus, status)
        }
        .font(LuminaFont.small(s, id: AccessibilityID.Shell.copyStatus))
        .lineLimit(1)
        .allowsHitTesting(false)
    }
}
