import SwiftUI

/// Fidelity chip states — driven by PreviewSpine / source availability, never faked.
enum TreatmentFidelity: Equatable {
    case interactivePreview
    case settling
    case fullPreview
    case oneToOneRAW
    case previewsOnly

    var label: String {
        switch self {
        case .interactivePreview: "Interactive preview"
        case .settling: "Settling"
        case .fullPreview: "Full preview"
        case .oneToOneRAW: "1:1 RAW"
        case .previewsOnly: "Previews only — reconnect for full resolution"
        }
    }

    var voiceOverHint: String {
        switch self {
        case .interactivePreview:
            return "Interactive preview. Good for framing decisions; not final colour."
        case .settling:
            return "Settling. Waiting for a sharper proxy."
        case .fullPreview:
            return "Full preview. Suitable for exposure and colour judgement."
        case .oneToOneRAW:
            return "One-to-one RAW pixels. Use for critical sharpness."
        case .previewsOnly:
            return "Source disconnected. Cached previews only — reconnect for full resolution."
        }
    }
}

/// White balance presets — standard Kelvin targets, applied as offsets from
/// the photo's base recipe so Auto/taste edits compose correctly.
enum WhiteBalancePreset: String, CaseIterable, Identifiable {
    case asShot = "As Shot"
    case auto = "Auto"
    case daylight = "Daylight"
    case cloudy = "Cloudy"
    case shade = "Shade"
    case tungsten = "Tungsten"
    case fluorescent = "Fluorescent"
    case flash = "Flash"

    var id: String { rawValue }

    /// Absolute Kelvin / tint target. Nil means reset (As Shot) or computed (Auto).
    var target: (kelvin: Double, tint: Double)? {
        switch self {
        case .asShot, .auto: return nil
        case .daylight: return (5500, 0)
        case .cloudy: return (6500, 3)
        case .shade: return (7500, 8)
        case .tungsten: return (3200, 0)
        case .fluorescent: return (4000, 20)
        case .flash: return (5500, 0)
        }
    }
}

/// Editing surface — opens on ⌘-double-click or T.
///
/// One persistent Metal editor + one control stack. Filmstrip sends selection
/// intents only; it does not own sessions or controls. Scroll-aligned focus
/// carousel removed for this phase so scrubbing never recreates the editor.
struct TreatmentStageView: View {
    let leader: AssetPresentation
    let references: [AssetPresentation]
    /// Full set for the filmstrip (leader + siblings). Falls back to
    /// leader + references when the caller doesn't pass the set.
    var setPhotos: [AssetPresentation] = []
    let selectionCount: Int
    /// Photos in the leader's set (family row) — target of Apply to set.
    var setCount: Int = 1
    var projectName: String?
    var baseRecipe: DevelopRecipe
    @Binding var offsets: DevelopAdjustments
    @Binding var previewMode: TreatmentPreviewMode
    var stagedRecipe: DevelopRecipe?
    var fidelity: TreatmentFidelity
    var localOverrideNotes: [AssetID: String] = [:]
    var storyStrip: [AssetPresentation]
    var exifLine: String
    var onClose: () -> Void
    var onOffsetsChange: (DevelopAdjustments) -> Void
    var onStageTreat: () -> Void
    var onConfirmTreat: () -> Void
    var onCancelStage: () -> Void
    var onOpenMore: () -> Void
    var onSelectReference: (AssetID) -> Void
    var onApplyToSet: () -> Void = {}
    var onAddRetouch: (RetouchSpot) -> Void = { _ in }
    var onUndoRetouch: () -> Void = {}
    var onClearRetouch: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingOriginalHold = false
    @State private var oneToOne = false
    @State private var healMode = false
    @State private var healRadius: Double = 0.02
    @State private var editor = WorkbenchDevelop.editor
    @State private var receipt: String?
    @State private var autoBusy = false
    @State private var visionHint: String?

    private var effectiveRecipe: DevelopRecipe {
        if showingOriginalHold || previewMode == .original { return .neutral }
        return baseRecipe
    }

    private var effectiveOffsets: DevelopAdjustments {
        if showingOriginalHold || previewMode == .original { return .zero }
        return offsets
    }

    /// Absolute recipe rendered by the live pipeline.
    private var liveRecipe: DevelopRecipe {
        effectiveRecipe.applying(effectiveOffsets)
    }

    private var hasLiveRAW: Bool {
        guard let rawPath = leader.rawPath else { return false }
        return FileManager.default.fileExists(atPath: rawPath)
    }

    /// Honest fidelity — live scheduler state when the RAW pipeline is active.
    private var effectiveFidelity: TreatmentFidelity {
        guard hasLiveRAW, fidelity != .previewsOnly,
              let live = editor.scheduler.fidelityByPhoto[leader.id] else { return fidelity }
        switch live {
        case .interactive: return .interactivePreview
        case .settling: return .settling
        case .rawSettled, .exportQuality, .beforeOriginal: return .fullPreview
        case .oneToOneRAW: return .oneToOneRAW
        case .proxyFallback: return .interactivePreview
        }
    }

    private var retouchCount: Int {
        baseRecipe.retouch.count
    }

    /// Filmstrip contents — set when available, otherwise leader + refs.
    private var focusStrip: [AssetPresentation] {
        if !setPhotos.isEmpty { return setPhotos }
        var seen = Set<AssetID>()
        var ordered: [AssetPresentation] = []
        for asset in [leader] + references {
            if seen.insert(asset.id).inserted { ordered.append(asset) }
        }
        return ordered
    }

    var body: some View {
        HStack(spacing: 0) {
            filmstripColumn
                .frame(width: 96)

            focusedEditorColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            controlsColumn
                .frame(width: 324)
                .frame(maxHeight: .infinity)
        }
        .background(LuminaTokens.Surface.table)
        .onExitCommand(perform: onClose)
        .onAppear { syncEditor() }
        .onChange(of: leader.id) { _, _ in syncEditor() }
        .onChange(of: showingOriginalHold) { _, _ in syncEditor() }
        .onChange(of: previewMode) { _, _ in syncEditor() }
    }

    private func syncEditor() {
        let rawURL: URL? = {
            guard let path = leader.rawPath, FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }()
        let proxy = (leader.previewPath ?? leader.thumbPath).map { URL(fileURLWithPath: $0) }
        let edit = EditRecipe(from: DevelopEngine.clampRecipe(liveRecipe), id: leader.id)
        editor.selectPhoto(photoID: leader.id, rawURL: rawURL, proxyURL: proxy, recipe: edit)
        editor.showBefore = showingOriginalHold || previewMode == .original
    }

    // MARK: - Filmstrip (selection intents only)

    private var filmstripColumn: some View {
        VStack(spacing: 8) {
            Text("Set")
                .font(LuminaTokens.Typeface.meta(10))
                .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(focusStrip) { asset in
                        Button {
                            onSelectReference(asset.id)
                        } label: {
                            StablePhotoView(
                                asset: asset,
                                contentMode: .fit,
                                cornerRadius: 2,
                                maxPixelSize: 240
                            )
                            .frame(width: 64, height: 64 * (1 / max(asset.aspectRatio, 0.1)))
                            .frame(maxHeight: 64)
                            .opacity(asset.id == leader.id ? 1.0 : 0.55)
                            .overlay {
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(
                                        asset.id == leader.id ? Color.white.opacity(0.85) : .clear,
                                        lineWidth: 1.5
                                    )
                            }
                        }
                        .buttonStyle(LuminaQuietButtonStyle())
                        .accessibilityLabel("Select \(asset.filename)")
                    }
                }
            }
            Spacer(minLength: 0)
            Button("Done") { onClose() }
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("Done — close treatment")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(LuminaTokens.Surface.tableHead)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
        }
    }

    // MARK: - Persistent focused photograph

    private var focusedEditorColumn: some View {
        VStack(spacing: 10) {
            ZStack {
                if hasLiveRAW {
                    // Persistent Metal surface — not inside LazyVStack / carousel.
                    // Retains lastValidImage across photo switches until the next frame.
                    DevelopMetalView(
                        image: editor.presentedImage,
                        displayedRevision: editor.displayedRevision
                    )
                    .allowsHitTesting(false)
                    .onChange(of: editor.displayedRevision) { _, _ in
                        editor.absorbPresentedTexture()
                    }
                    .onChange(of: editor.scheduler.metrics.completed) { _, _ in
                        editor.absorbPresentedTexture()
                    }
                } else {
                    GradedPhotoView(
                        asset: leader,
                        projectName: projectName,
                        baseRecipe: liveRecipe,
                        developOffsets: .zero,
                        previewMix: 1,
                        contentMode: .fit,
                        showDecisionBadge: false,
                        isSelected: false,
                        maxPixelSize: oneToOne ? 4096 : 2400
                    )
                }
                if healMode {
                    healOverlay
                }
            }
            .aspectRatio(leader.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .accessibilityLabel("Photograph being treated: \(leader.filename)")

            metadataStrip
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    /// EXIF plus the effective develop values — evolves live as sliders move.
    private var metadataStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(exifLine)
                    .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let visionHint {
                    Text(visionHint)
                        .font(LuminaTokens.Typeface.meta(11))
                        .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                        .transition(.opacity)
                }
                if let receipt {
                    Text(receipt)
                        .font(LuminaTokens.Typeface.meta(11))
                        .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                        .transition(.opacity)
                }
                fidelityChip
            }
            Text(liveDevelopLine)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(LuminaTokens.Ink.onTable)
                .lineLimit(1)
                .accessibilityLabel("Current develop values: \(liveDevelopLine)")
            Text(editor.statusLine)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    /// The rendered recipe as a readable line — updates on every adjustment.
    private var liveDevelopLine: String {
        let r = liveRecipe
        var parts: [String] = []
        parts.append(String(format: "WB %.0fK %+.0f", r.temperature, r.tint))
        parts.append(String(format: "EV %+.2f", r.exposure))
        parts.append(String(format: "HL %+.0f", r.highlights))
        parts.append(String(format: "SH %+.0f", r.shadows))
        parts.append(String(format: "C %+.0f", r.contrast))
        if r.vibrance != 0 || r.saturation != 0 {
            parts.append(String(format: "Vib %+.0f · Sat %+.0f", r.vibrance, r.saturation))
        }
        if r.luminanceNR > 0 { parts.append(String(format: "NR %.0f", r.luminanceNR)) }
        if r.sharpness > 0 { parts.append(String(format: "Shp %.0f", r.sharpness)) }
        if retouchCount > 0 { parts.append("\(retouchCount) heal\(retouchCount == 1 ? "" : "s")") }
        return parts.joined(separator: "   ")
    }

    private var healOverlay: some View {
        GeometryReader { geo in
            ZStack {
                // Existing spots.
                ForEach(baseRecipe.retouch) { spot in
                    let d = CGFloat(spot.radius) * geo.size.width * 2
                    Circle()
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .frame(width: d, height: d)
                        .position(
                            x: CGFloat(spot.x) * geo.size.width,
                            y: CGFloat(spot.y) * geo.size.height
                        )
                }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        addHealSpot(at: location, in: geo.size)
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            Text("Heal — click a blemish. Clone-based, applies to export.")
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .padding(8)
        }
    }

    private func addHealSpot(at location: CGPoint, in size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let nx = min(max(Double(location.x / size.width), 0), 1)
        let ny = min(max(Double(location.y / size.height), 0), 1)
        let path = leader.previewPath ?? leader.thumbPath
        let radius = healRadius
        Task {
            let donor = await VisionAssist.healDonor(
                for: (x: nx, y: ny, radius: radius),
                imagePath: path
            )
            let spot = RetouchSpot(
                x: nx, y: ny, radius: radius,
                sourceDX: donor.dx, sourceDY: donor.dy
            )
            onAddRetouch(spot)
            LuminaHaptics.decision()
        }
    }

    private var fidelityChip: some View {
        Text(effectiveFidelity.label)
            .font(LuminaTokens.Typeface.meta(11))
            .foregroundStyle(LuminaTokens.Ink.onTable)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .accessibilityLabel(effectiveFidelity.label)
            .accessibilityHint(effectiveFidelity.voiceOverHint)
            .animation(reduceMotion ? nil : LuminaTokens.Motion.fidelityCrossfade, value: effectiveFidelity)
    }

    // MARK: - Controls

    private var controlsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if stagedRecipe != nil {
                Text("Staged across \(selectionCount) · ↩ commits, Esc cancels")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }

            // Preview modes and Auto edit each get their own space at the top.
            chipRow
                .padding(.bottom, 8)
            autoEditButton
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    panel("White balance") {
                        whiteBalanceSection
                        slider("Warmth", value: binding(\.temperature), range: -2000...2000)
                        slider("Tint", value: binding(\.tint), range: -50...50)
                    }
                    panel("Tone") {
                        slider("Exposure", value: binding(\.exposure), range: -2...2)
                        slider("Highlights", value: binding(\.highlights), range: -100...100)
                        slider("Shadows", value: binding(\.shadows), range: -100...100)
                        slider("Contrast", value: binding(\.contrast), range: -100...100)
                    }
                    panel("Color") {
                        slider("Vibrance", value: binding(\.vibrance), range: -100...100)
                        slider("Saturation", value: binding(\.saturation), range: -100...100)
                    }
                    panel("Detail") { detailSection }
                    panel("Erase / heal") { healSection }
                }
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            Divider()
                .padding(.vertical, 10)

            actionButtons
        }
        .padding(16)
        .background(LuminaTokens.Surface.side)
        .overlay(alignment: .leading) {
            Rectangle().fill(LuminaTokens.Line.hairline).frame(width: 1)
        }
    }

    /// Card container so each control family has its own visual space.
    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(LuminaTokens.Typeface.meta(10, weight: .medium))
                .kerning(0.8)
                .foregroundStyle(LuminaTokens.Ink.tertiary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LuminaTokens.Surface.mist.opacity(0.55))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var autoEditButton: some View {
        Button { applyAutoEdit() } label: {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12))
                Text(autoBusy ? "Analyzing…" : "Auto edit")
                    .font(LuminaTokens.Typeface.navigation(12, weight: .medium))
            }
            .foregroundStyle(LuminaTokens.Ink.primary)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LuminaTokens.Surface.mist)
            )
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .disabled(autoBusy)
        .accessibilityLabel("Auto edit")
        .accessibilityHint("Vision-assisted auto: face-weighted exposure when faces are present, otherwise whole-frame histogram. Sliders update to match.")
    }

    private func applyAutoEdit() {
        let path = leader.previewPath ?? leader.thumbPath
        guard let path, !autoBusy else { return }
        autoBusy = true
        Task {
            defer { autoBusy = false }
            // Vision-weighted when faces are present; whole-frame otherwise.
            guard let s = await VisionAssist.suggest(imagePath: path) else { return }
            let map = await VisionAssist.subjectMap(imagePath: path)
            var next = offsets
            // Suggestion values are absolute targets — convert to offsets so
            // taste/base edits compose, and so the sliders land on the result.
            next.exposure = min(max(s.exposure - baseRecipe.exposure, -2), 2)
            next.contrast = min(max(s.contrast - baseRecipe.contrast, -100), 100)
            next.highlights = min(max(s.highlights - baseRecipe.highlights, -100), 100)
            next.shadows = min(max(s.shadows - baseRecipe.shadows, -100), 100)
            next.vibrance = min(max(s.vibrance - baseRecipe.vibrance, -100), 100)
            next.temperature = min(max(s.kelvin - baseRecipe.temperature, -2000), 2000)
            next.tint = min(max(s.tint - baseRecipe.tint, -50), 50)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                commit(next)
            }
            if map?.hasFace == true {
                visionHint = "Vision · face-weighted"
            } else if map?.attentionPeak != nil {
                visionHint = "Vision · subject-aware"
            } else {
                visionHint = nil
            }
            showReceipt("Auto edit applied — sliders updated")
            if visionHint != nil {
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation { visionHint = nil }
                }
            }
        }
    }

    private func showReceipt(_ text: String) {
        withAnimation { receipt = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation { receipt = nil }
        }
    }

    private var whiteBalanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 5)], spacing: 5) {
                ForEach(WhiteBalancePreset.allCases) { preset in
                    Button {
                        applyWhiteBalancePreset(preset)
                    } label: {
                        Text(preset.rawValue)
                            .font(LuminaTokens.Typeface.meta(11))
                            .foregroundStyle(LuminaTokens.Ink.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(LuminaTokens.Surface.mist)
                            )
                    }
                    .buttonStyle(LuminaQuietButtonStyle())
                    .accessibilityLabel("White balance: \(preset.rawValue)")
                }
            }
            slider("Temperature", value: binding(\.temperature), range: -2000...2000)
            slider("Tint", value: binding(\.tint), range: -50...50)
        }
    }

    private func applyWhiteBalancePreset(_ preset: WhiteBalancePreset) {
        var next = offsets
        switch preset {
        case .asShot:
            next.temperature = 0
            next.tint = 0
            commit(next)
        case .auto:
            let path = leader.previewPath ?? leader.thumbPath
            let base = baseRecipe
            Task {
                guard let path,
                      let estimate = await AutoWhiteBalance.estimate(imagePath: path) else { return }
                var auto = offsets
                auto.temperature = min(max(estimate.kelvin - base.temperature, -2000), 2000)
                auto.tint = min(max(estimate.tint - base.tint, -50), 50)
                commit(auto)
            }
        default:
            guard let target = preset.target else { return }
            next.temperature = min(max(target.kelvin - baseRecipe.temperature, -2000), 2000)
            next.tint = min(max(target.tint - baseRecipe.tint, -50), 50)
            commit(next)
        }
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            slider("Noise reduction", value: binding(\.luminanceNR), range: 0...100)
            slider("Sharpening", value: binding(\.sharpness), range: 0...150)
            Text("RAW-domain when supported · Crop — ⌘⌥C opens the rest")
                .font(LuminaTokens.Typeface.meta(10))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .onTapGesture(perform: onOpenMore)
        }
    }

    private var healSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(retouchCount > 0 ? "\(retouchCount) spot\(retouchCount == 1 ? "" : "s")" : "Clone-based")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                Spacer()
                Button {
                    healMode.toggle()
                } label: {
                    Text(healMode ? "Healing on" : "Heal")
                        .font(LuminaTokens.Typeface.meta(11, weight: healMode ? .medium : .regular))
                        .foregroundStyle(LuminaTokens.Ink.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(healMode ? LuminaTokens.Status.selection.opacity(0.25) : LuminaTokens.Surface.mist)
                        )
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel(healMode ? "Turn heal mode off" : "Turn heal mode on")
                .accessibilityHint("Click the photograph to remove a blemish with a clone-based heal.")
            }

            if healMode {
                slider("Spot size", value: $healRadius, range: 0.005...0.06)
                HStack(spacing: 8) {
                    if retouchCount > 0 {
                        Button("Undo spot") { onUndoRetouch() }
                            .font(LuminaTokens.Typeface.meta(11))
                            .buttonStyle(LuminaQuietButtonStyle())
                            .accessibilityLabel("Undo last heal spot")
                        Button("Clear \(retouchCount)") { onClearRetouch() }
                            .font(LuminaTokens.Typeface.meta(11))
                            .buttonStyle(LuminaQuietButtonStyle())
                            .accessibilityLabel("Clear all heal spots")
                    }
                }
                Text("Clone-based heal — not generative fill. Renders identically in preview and export.")
                    .font(LuminaTokens.Typeface.meta(10))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            if setCount > 1 {
                Button {
                    onApplyToSet()
                    showReceipt("Applied to \(setCount) in set")
                } label: {
                    Text("Apply to set (\(setCount))  ⌘⇧A")
                        .font(LuminaTokens.Typeface.navigation(13, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(LuminaTokens.Surface.mist)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("Apply current treatment to all \(setCount) photographs in this set")
                .accessibilityHint("Each photograph re-evaluates the same recipe on its own file.")
            }

            if selectionCount > 1 {
                Button {
                    if stagedRecipe == nil { onStageTreat() } else { onConfirmTreat() }
                } label: {
                    Text(stagedRecipe == nil ? "Stage across \(selectionCount)  ⌘↩" : "Commit treatment  ↩")
                        .font(LuminaTokens.Typeface.navigation(13, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(LuminaTokens.Surface.mist)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel(stagedRecipe == nil
                    ? "Stage treatment across \(selectionCount) gathered photographs"
                    : "Commit staged treatment")
            }

            if stagedRecipe != nil {
                Button("Cancel staging", action: onCancelStage)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .buttonStyle(LuminaQuietButtonStyle())
                    .accessibilityLabel("Cancel staged treatment")
            }
        }
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach([TreatmentPreviewMode.original, .auto, .current], id: \.self) { mode in
                Button {
                    previewMode = mode
                } label: {
                    Text(modeLabel(mode))
                        .font(LuminaTokens.Typeface.meta(12, weight: previewMode == mode ? .medium : .regular))
                        .foregroundStyle(LuminaTokens.Ink.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(previewMode == mode ? LuminaTokens.Surface.well : Color.clear)
                        )
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("Preview \(modeLabel(mode))")
                .accessibilityAddTraits(previewMode == mode ? .isSelected : [])
            }
        }
    }

    private func modeLabel(_ mode: TreatmentPreviewMode) -> String {
        switch mode {
        case .original: "Original"
        case .auto: "Auto"
        case .current: "Current"
        }
    }

    private func commit(_ next: DevelopAdjustments) {
        offsets = next
        previewMode = .current
        onOffsetsChange(next)
        // Synchronous draft update on the persistent editor — do not wait for
        // slider release or a SwiftUI `.task(id:)` boundary.
        let absolute = EditRecipe(
            from: DevelopEngine.clampRecipe(effectiveRecipe.applying(next)),
            id: leader.id
        )
        editor.setDraftRecipe(absolute, controlName: "offsets")
    }

    private func binding(_ keyPath: WritableKeyPath<DevelopAdjustments, Double>) -> Binding<Double> {
        Binding(
            get: { offsets[keyPath: keyPath] },
            set: { newValue in
                var next = offsets
                next[keyPath: keyPath] = newValue
                commit(next)
            }
        )
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                Spacer()
                Text(valueLabel(value.wrappedValue, range: range))
                    .font(.system(size: 10, weight: value.wrappedValue == 0 ? .regular : .medium, design: .monospaced))
                    .foregroundStyle(value.wrappedValue == 0 ? LuminaTokens.Ink.tertiary : LuminaTokens.Ink.primary)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { value.wrappedValue = max(0, range.lowerBound) }
            .help("Double-click to reset \(title)")
            Slider(value: value, in: range)
                .controlSize(.small)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
                .accessibilityLabel(title)
                .accessibilityValue(valueLabel(value.wrappedValue, range: range))
                .accessibilityHint("Changes render live. Double-click the label to reset.")
        }
    }

    private func valueLabel(_ v: Double, range: ClosedRange<Double>) -> String {
        if range.upperBound <= 3 { return String(format: "%+.2f", v) }
        if range.upperBound >= 1000 { return String(format: "%+.0fK", v) }
        return String(format: "%+.0f", v)
    }
}
