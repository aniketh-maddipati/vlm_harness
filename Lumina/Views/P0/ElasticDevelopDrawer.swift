import AppKit
import SwiftUI

/// The develop drawer (`E`), beside the photograph: nine honest sliders, the crop
/// ratios and a quarter turn, straighten, the camera profile, the match chips, and
/// auto · match · reset. Everything it does goes through the session's one batch,
/// so a nudge ripples to the group and one ⌘Z brings it all back.
struct ElasticDevelopDrawer: View {
    @Bindable var session: P0SessionModel
    let asset: AssetRecord

    private var recipe: EditRecipe { session.recipe(for: asset.id) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: ElasticLayout.drawerGap) {
                titleRow
                ForEach(ElasticDevelopControl.exposed) { control in
                    sliderRow(control)
                }
                sectionLabel("crop", detail: session.cropSummary(for: recipe))
                ratioRow
                straightenRow
                profileRow
                sectionLabel("match", detail: session.matchScopeLine(for: asset.id))
                matchChips
                actionRow
                Text(session.developSourceLine(for: asset))
                    .font(ElasticType.mono(ElasticLayout.drawerSourceSize))
                    .lineSpacing(ElasticType.lineSpacing(
                        size: ElasticLayout.drawerSourceSize, lineHeight: ElasticLayout.drawerSourceLineHeight
                    ))
                    .opacity(ElasticLayout.drawerMutedOpacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, ElasticLayout.drawerPaddingV)
            .padding(.horizontal, ElasticLayout.drawerPaddingH)
        }
        .font(ElasticType.mono(ElasticLayout.drawerTextSize))
        .foregroundStyle(LuminaTokens.Elastic.shellAlt)
        .frame(width: ElasticLayout.drawerWidth)
        .frame(maxHeight: .infinity)
        .background(
            LuminaTokens.Elastic.ink.opacity(ElasticLayout.drawerFillOpacity),
            in: RoundedRectangle(cornerRadius: ElasticLayout.drawerRadius, style: .continuous)
        )
        .accessibilityIdentifier(P0AccessibilityID.elasticDevelopDrawer)
    }

    // MARK: - Rows

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(session.versionLabel(for: asset))
                .font(ElasticType.mono(ElasticLayout.drawerTitleSize, weight: .semibold))
            Spacer(minLength: 0)
            Text(session.drawerScopeLine(for: asset.id))
                .font(ElasticType.mono(ElasticLayout.drawerScopeSize))
                .opacity(ElasticLayout.drawerScopeOpacity)
        }
        .lineLimit(1)
    }

    private func sectionLabel(_ name: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
            Spacer(minLength: 0)
            Text(detail).lineLimit(1).truncationMode(.tail)
        }
        .opacity(ElasticLayout.drawerMutedOpacity)
        .padding(.top, ElasticLayout.drawerSectionTop)
    }

    private func sliderRow(_ control: ElasticDevelopControl) -> some View {
        let value = recipe[keyPath: control.keyPath]
        return ElasticDrawerSlider(
            name: control.name,
            value: value,
            range: control.range,
            step: control.step,
            changed: value != control.zero,
            label: control.label,
            onBegin: { session.beginEditGesture(for: asset.id) },
            onScrub: { next in session.scrubEdit { $0[keyPath: control.keyPath] = next } },
            onEnd: { session.endDevelopGesture(control.keyPath, range: control.range) }
        )
    }

    private var ratioRow: some View {
        let current = ElasticCropRatio(aspect: recipe.cropAspect)
        return FlowChips {
            ForEach(ElasticCropRatio.allCases, id: \.self) { ratio in
                chip(ratio.rawValue, on: ratio == current) {
                    session.setCropRatio(ratio)
                }
            }
            Button {
                session.rotateFocusedPhotograph()
            } label: {
                HStack(spacing: ElasticLayout.chipGap) {
                    Text("↻ \(Int(ElasticLayout.quarterTurnDegrees))°")
                    Text("R").opacity(ElasticLayout.drawerMutedOpacity)
                }
                .modifier(ChipCostume(on: false))
            }
            .buttonStyle(LuminaElasticButtonStyle())
        }
    }

    private var straightenRow: some View {
        let fine = P0SessionModel.splitStraighten(recipe.straightenDegrees).fine
        return ElasticDrawerSlider(
            name: "Straighten",
            value: fine,
            range: -ElasticLayout.straightenRange...ElasticLayout.straightenRange,
            step: ElasticLayout.straightenStep,
            changed: abs(fine) >= ElasticLayout.straightenStep / 2,
            label: P0SessionModel.angleLabel,
            onBegin: { session.beginEditGesture(for: asset.id) },
            onScrub: { next in
                session.scrubEdit { recipe in
                    let turns = P0SessionModel.splitStraighten(recipe.straightenDegrees).turns
                    recipe.straightenDegrees = turns * ElasticLayout.quarterTurnDegrees + next
                }
            },
            onEnd: {
                session.endDevelopGesture(
                    \.straightenDegrees,
                    range: -(ElasticLayout.straightenRange + 360)...(ElasticLayout.straightenRange + 360)
                )
            }
        )
    }

    private var profileRow: some View {
        HStack(alignment: .center) {
            Text("profile").opacity(ElasticLayout.drawerMutedOpacity)
            Spacer(minLength: 0)
            Picker("", selection: Binding(
                get: { recipe.cameraProfile },
                set: { session.setCameraProfile($0) }
            )) {
                ForEach(P0SessionModel.cameraProfiles, id: \.self) { profile in
                    Text(profile).tag(profile)
                }
                if !P0SessionModel.cameraProfiles.contains(recipe.cameraProfile) {
                    // A sidecar's own profile, kept as it is rather than silently replaced.
                    Text(recipe.cameraProfile).tag(recipe.cameraProfile)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(height: ElasticLayout.chipHeight)
            .fixedSize()
        }
        .padding(.top, ElasticLayout.drawerSectionTop)
    }

    private var matchChips: some View {
        FlowChips {
            ForEach(ElasticMatchGroup.allCases, id: \.self) { group in
                chip(group.rawValue, on: session.matchGroups.contains(group)) {
                    session.toggleMatchGroup(group)
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: ElasticLayout.drawerButtonGap) {
            actionButton(primary: false) {
                session.pickVersion(2, for: asset.id)
            } label: {
                HStack(spacing: ElasticLayout.chipGap) {
                    Text("auto")
                    Text("A").opacity(ElasticLayout.drawerMutedOpacity)
                }
            }
            actionButton(primary: true) {
                session.matchToCursor()
            } label: {
                HStack(spacing: ElasticLayout.chipGap) {
                    Text("match").fontWeight(.semibold)
                    Text("M").opacity(ElasticLayout.drawerMutedOpacity)
                }
            }
            Button {
                session.pickVersion(1, for: asset.id)
            } label: {
                Text("reset")
                    .opacity(ElasticLayout.drawerScopeOpacity)
                    .padding(.horizontal, ElasticLayout.drawerResetPaddingH)
                    .frame(height: ElasticLayout.drawerButtonHeight)
            }
            .buttonStyle(LuminaElasticButtonStyle())
        }
        .font(ElasticType.mono(ElasticLayout.headerTextSize))
        .padding(.top, ElasticLayout.drawerSectionTop)
    }

    // MARK: - Pieces

    private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).modifier(ChipCostume(on: on))
        }
        .buttonStyle(LuminaElasticButtonStyle())
    }

    private func actionButton<Label: View>(
        primary: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(primary ? LuminaTokens.Elastic.ink : LuminaTokens.Elastic.shell)
                .frame(maxWidth: .infinity)
                .frame(height: ElasticLayout.drawerButtonHeight)
                .background(
                    primary
                        ? LuminaTokens.Elastic.warmAccent
                        : LuminaTokens.Elastic.shell.opacity(ElasticLayout.chipFillOpacity),
                    in: RoundedRectangle(cornerRadius: ElasticLayout.drawerButtonRadius, style: .continuous)
                )
        }
        .buttonStyle(LuminaElasticButtonStyle())
    }
}

/// `height 24; padding 0 8; radius 6` — warm when on, shell over the drawer when off.
private struct ChipCostume: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        content
            .font(ElasticType.mono(ElasticLayout.drawerTextSize))
            .foregroundStyle(on ? LuminaTokens.Elastic.ink : LuminaTokens.Elastic.shell)
            .lineLimit(1)
            .padding(.horizontal, ElasticLayout.chipPaddingH)
            .frame(height: ElasticLayout.chipHeight)
            .background(
                on ? LuminaTokens.Elastic.warmAccent : LuminaTokens.Elastic.shell.opacity(ElasticLayout.chipFillOpacity),
                in: RoundedRectangle(cornerRadius: ElasticLayout.chipRadius, style: .continuous)
            )
    }
}

/// `display:flex; gap:4px; flex-wrap:wrap` for chips.
private struct FlowChips<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ElasticWrapLayout(horizontalSpacing: ElasticLayout.chipGap, verticalSpacing: ElasticLayout.chipGap) {
            content
        }
    }
}

/// `grid-template-columns: 78px 1fr 44px; gap 8; font 11px; input height 18` — the
/// drawer's slider. Same contract as `P0EditSlider` (begin · scrub at ~40 Hz · end,
/// ⌥ for fine travel, snap to step) at the design's size.
struct ElasticDrawerSlider: View {
    let name: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let changed: Bool
    let label: (Double) -> String
    let onBegin: () -> Void
    let onScrub: (Double) -> Void
    let onEnd: () -> Void

    @State private var draft: Double?
    @State private var isDragging = false
    @State private var lastScrubAt: CFAbsoluteTime = 0

    private var shown: Double { draft ?? value }
    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((shown - range.lowerBound) / span)
    }

    var body: some View {
        HStack(spacing: ElasticLayout.drawerRowGap) {
            Text(name)
                .opacity(ElasticLayout.drawerLabelOpacity)
                .frame(width: ElasticLayout.drawerLabelWidth, alignment: .leading)
            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let thumb = ElasticLayout.drawerThumbSize
                let travel = max(width - thumb, 1)
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(LuminaTokens.Elastic.shell.opacity(ElasticLayout.drawerTrackOpacity))
                        .frame(height: ElasticLayout.drawerTrackHeight)
                    Capsule(style: .continuous)
                        .fill(LuminaTokens.Elastic.warmAccent)
                        .frame(width: fraction * travel + thumb / 2, height: ElasticLayout.drawerTrackHeight)
                    Circle()
                        .fill(LuminaTokens.Elastic.warmAccent)
                        .frame(width: thumb, height: thumb)
                        .offset(x: fraction * travel)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: width, thumb: thumb))
            }
            .frame(height: ElasticLayout.drawerSliderHeight)
            Text(label(shown))
                .fontWeight(changed ? .bold : .regular)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: ElasticLayout.drawerValueWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue(label(shown))
        .accessibilityAdjustableAction { direction in
            let delta = step * (direction == .increment ? 1 : -1)
            onBegin()
            onScrub(clamp(shown + delta))
            onEnd()
        }
        .onChange(of: value) { _, _ in
            if !isDragging { draft = nil }
        }
    }

    private func dragGesture(width: CGFloat, thumb: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isDragging {
                    isDragging = true
                    onBegin()
                }
                let travel = max(width - thumb, 1)
                let x = min(max(gesture.location.x - thumb / 2, 0), travel)
                let raw = range.lowerBound + Double(x / travel) * (range.upperBound - range.lowerBound)
                let next: Double
                if NSEvent.modifierFlags.contains(.option) {
                    let from = draft ?? value
                    next = from + (raw - from) * ElasticLayout.sliderFineTravel
                } else {
                    next = clamp((raw / step).rounded() * step)
                }
                draft = next
                let now = CFAbsoluteTimeGetCurrent()
                if now - lastScrubAt >= P0EditSliderTuning.scrubInterval {
                    lastScrubAt = now
                    onScrub(next)
                }
            }
            .onEnded { _ in
                let final = draft ?? value
                onScrub(final)
                onEnd()
                isDragging = false
                draft = nil
            }
    }

    private func clamp(_ raw: Double) -> Double {
        min(max(raw, range.lowerBound), range.upperBound)
    }
}

/// The scrub cadence `P0EditSlider` uses, named so the drawer's slider shares it.
enum P0EditSliderTuning {
    /// ~40 Hz to the session while the thumb itself moves every frame.
    static let scrubInterval: CFAbsoluteTime = 0.024
}
