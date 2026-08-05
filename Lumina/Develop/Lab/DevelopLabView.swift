import AppKit
import SwiftUI

/// Isolated Develop Lab — launch with `--develop-lab`.
struct DevelopLabView: View {
    @State private var model = DevelopLabModel()
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 0) {
            imagePlane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            controlRail
                .frame(width: 300)
        }
        .background(LuminaTokens.Surface.porcelain)
        .onAppear {
            model.bootstrap()
            installKeys()
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            model.scheduler.cancelAll()
        }
    }

    // MARK: - Image plane (no controls over important content)

    private var imagePlane: some View {
        VStack(spacing: LuminaTokens.Spacing.sm) {
            statusBar
            GeometryReader { geo in
                let leaderH = geo.size.height * 0.66
                VStack(spacing: LuminaTokens.Spacing.sm) {
                    leaderFrame
                        .frame(height: leaderH)
                    referenceRow
                        .frame(maxHeight: .infinity)
                }
                .padding(LuminaTokens.Spacing.md)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: LuminaTokens.Spacing.md) {
            Text("Develop Lab")
                .font(LuminaTokens.Typeface.navigation(13, weight: .semibold))
                .foregroundStyle(LuminaTokens.Ink.primary)
            Text(model.fidelityLabel)
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(LuminaTokens.Surface.well)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            if model.batch.phase == .staged {
                Text("Staged batch")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.primary)
            }
            Spacer()
            Text(model.metricsLine)
                .font(LuminaTokens.Typeface.meta(10))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, LuminaTokens.Spacing.md)
        .padding(.top, LuminaTokens.Spacing.sm)
    }

    private var leaderFrame: some View {
        ZStack {
            LuminaTokens.Surface.well
            if let leader = model.leader {
                labImage(for: leader, oneToOne: model.oneToOne)
                    .onTapGesture(count: 2) {
                        model.toggleOneToOne()
                    }
            }
            VStack {
                HStack {
                    Text(model.leader?.filename ?? "—")
                        .font(LuminaTokens.Typeface.meta(11))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                        .padding(6)
                    Spacer()
                    fidelityChip
                }
                Spacer()
                histogramStrip
                    .frame(height: 48)
                    .padding(8)
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: LuminaTokens.Radius.photographLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LuminaTokens.Radius.photographLarge, style: .continuous)
                .strokeBorder(LuminaTokens.Line.hairline, lineWidth: LuminaTokens.Line.hairlineWidth)
        }
    }

    private var fidelityChip: some View {
        Text(model.fidelityLabel)
            .font(LuminaTokens.Typeface.meta(10, weight: .medium))
            .foregroundStyle(LuminaTokens.Ink.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(LuminaTokens.Surface.porcelain.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(8)
    }

    private var referenceRow: some View {
        HStack(spacing: LuminaTokens.Spacing.sm) {
            ForEach(model.references) { frame in
                ZStack {
                    LuminaTokens.Surface.well
                    labImage(for: frame, oneToOne: false)
                    VStack {
                        HStack {
                            Text(frame.filename)
                                .font(LuminaTokens.Typeface.meta(10))
                                .foregroundStyle(LuminaTokens.Ink.tertiary)
                                .padding(4)
                            Spacer()
                            if model.store.binding(for: frame.id).hasLocalDivergence {
                                Text("Local")
                                    .font(LuminaTokens.Typeface.meta(9))
                                    .padding(3)
                                    .background(LuminaTokens.Surface.highlight)
                            }
                        }
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: LuminaTokens.Radius.photographLarge, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LuminaTokens.Radius.photographLarge, style: .continuous)
                        .strokeBorder(
                            model.selectedIDs.contains(frame.id) ? LuminaTokens.Ink.primary.opacity(0.45) : LuminaTokens.Line.hairline,
                            lineWidth: model.selectedIDs.contains(frame.id) ? 1.5 : LuminaTokens.Line.hairlineWidth
                        )
                }
                .onTapGesture {
                    if model.commandHeld {
                        model.toggleCommandSelect(frame.id)
                    } else {
                        model.selectLeader(frame.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func labImage(for frame: DevelopLabFrame, oneToOne: Bool) -> some View {
        if let image = model.displayImage(for: frame) {
            DevelopMetalView(
                image: image,
                zoom: oneToOne && frame.id == model.leader?.id ? 2.2 : 1,
                panOffset: oneToOne && frame.id == model.leader?.id ? model.panOffset : .zero
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard oneToOne else { return }
                        model.panOffset = value.translation
                    }
            )
        } else if model.liveRAWBlocked {
            Text("RAW unavailable")
                .font(LuminaTokens.Typeface.meta(12))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var histogramStrip: some View {
        Canvas { ctx, size in
            let bins = model.histogram.luminance
            let maxV = max(bins.max() ?? 1, 1)
            let barW = size.width / CGFloat(bins.count)
            for (i, v) in bins.enumerated() {
                let h = CGFloat(v) / CGFloat(maxV) * size.height
                let rect = CGRect(x: CGFloat(i) * barW, y: size.height - h, width: max(barW, 0.5), height: h)
                ctx.fill(Path(rect), with: .color(LuminaTokens.Ink.primary.opacity(0.35)))
            }
        }
        .background(LuminaTokens.Surface.porcelain.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    // MARK: - Control rail (beside image, not over it)

    private var controlRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
                Text("Treatment")
                    .font(LuminaTokens.Typeface.navigation(14, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.primary)

                if model.liveRAWBlocked {
                    Text(model.fixtureStatusMessage)
                        .font(LuminaTokens.Typeface.meta(11))
                        .foregroundStyle(LuminaTokens.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(model.fixtureStatusMessage)
                        .font(LuminaTokens.Typeface.meta(10))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                        .lineLimit(3)
                }

                labSlider("Exposure", value: model.recipe.exposure, range: -3...3, step: 0.05) { v in
                    model.scrubRecipe { $0.exposure = v }
                }
                labSlider("Temperature", value: model.recipe.temperature, range: 2500...10000, step: 50) { v in
                    model.scrubRecipe { $0.temperature = v }
                }
                labSlider("Tint", value: model.recipe.tint, range: -50...50, step: 1) { v in
                    model.scrubRecipe { $0.tint = v }
                }
                labSlider("Highlights", value: model.recipe.highlights, range: -100...100, step: 1) { v in
                    model.scrubRecipe { $0.highlights = v }
                }
                labSlider("Shadows", value: model.recipe.shadows, range: -100...100, step: 1) { v in
                    model.scrubRecipe { $0.shadows = v }
                }
                Text("Whites / Blacks / Texture / Clarity / Dehaze are disabled — no honest algorithm in this stage. Stored values migrate without effect.")
                    .font(LuminaTokens.Typeface.meta(10))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                labSlider("Contrast", value: model.recipe.contrast, range: -100...100, step: 1) { v in
                    model.scrubRecipe { $0.contrast = v }
                }
                labSlider("Straighten°", value: model.recipe.straightenDegrees, range: -45...45, step: 0.1) { v in
                    model.scrubRecipe { $0.straightenDegrees = v }
                }
                let nrSupported = model.leaderCapabilities?.luminanceNoiseReduction != .unsupported
                let sharpenSupported = model.leaderCapabilities?.sharpness != .unsupported
                labSlider(
                    nrSupported ? "Noise Reduction (RAW)" : "Noise Reduction — unsupported for this file",
                    value: model.recipe.luminanceNR, range: 0...100, step: 1
                ) { v in
                    model.scrubRecipe { $0.luminanceNR = v }
                }
                .disabled(!nrSupported)
                .opacity(nrSupported ? 1 : 0.4)
                labSlider(
                    sharpenSupported ? "Sharpening (RAW)" : "Sharpening — unsupported for this file",
                    value: model.recipe.sharpness, range: 0...150, step: 1
                ) { v in
                    model.scrubRecipe { $0.sharpness = v }
                }
                .disabled(!sharpenSupported)
                .opacity(sharpenSupported ? 1 : 0.4)

                if !model.capabilityLine.isEmpty {
                    Text(model.capabilityLine)
                        .font(LuminaTokens.Typeface.meta(9))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                        .lineLimit(2)
                }

                Text("Crop uses normalized EditCrop when set; default is full frame.")
                    .font(LuminaTokens.Typeface.meta(10))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)

                Divider()

                HStack {
                    Button(model.showBefore ? "After" : "Before") {
                        model.toggleBeforeAfter()
                    }
                    .buttonStyle(LuminaQuietButtonStyle())
                    Button(model.oneToOne ? "Fit" : "1:1") {
                        model.toggleOneToOne()
                    }
                    .buttonStyle(LuminaQuietButtonStyle())
                }

                Divider()

                Text("Batch (hold ⌘)")
                    .font(LuminaTokens.Typeface.meta(10, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                Text("⌘Return stage · Return again commit · Esc cancel · ⌘Z undo")
                    .font(LuminaTokens.Typeface.meta(10))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                HStack {
                    Button("Stage") { model.stageBatch(isARepeat: false) }
                        .buttonStyle(LuminaQuietButtonStyle())
                    Button("Commit") { model.confirmBatch(isARepeat: false) }
                        .buttonStyle(LuminaQuietButtonStyle())
                    Button("Cancel") { model.cancelBatch() }
                        .buttonStyle(LuminaQuietButtonStyle())
                }
                Button("Local override on leader") { model.applyLocalOverride() }
                    .buttonStyle(LuminaQuietButtonStyle())

                Divider()

                Button("Hand off to Lightroom") { model.handOffLeaderToLightroom() }
                    .buttonStyle(LuminaQuietButtonStyle())
                Text("Writes 16-bit ProPhoto TIFF to ~/Pictures/LuminaHandoff, merges the XMP sidecar next to the RAW, and drops a verification receipt.")
                    .font(LuminaTokens.Typeface.meta(9))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.commandHeld {
                    commandShelf
                }

                Spacer(minLength: 24)
            }
            .padding(LuminaTokens.Spacing.md)
        }
        .background(LuminaTokens.Surface.rail)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(width: LuminaTokens.Line.hairlineWidth)
        }
    }

    private var commandShelf: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shared actions")
                .font(.system(size: 12, weight: .semibold))
            Text("Selection \(model.selectedIDs.count) · \(model.batch.phase.rawValue)")
                .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 66)
        .padding(.horizontal, 12)
        .background(LuminaTokens.Surface.highlight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func labSlider(
        _ title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(LuminaTokens.Typeface.count(10))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
            Slider(value: Binding(
                get: { value },
                set: { onChange($0) }
            ), in: range, step: step)
            .controlSize(.small)
        }
    }

    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { event in
            if event.type == .flagsChanged {
                model.commandHeld = event.modifierFlags.contains(.command)
                return event
            }
            if event.type == .keyUp, event.keyCode == 36 { // Return
                model.noteReturnReleased()
                return event
            }
            guard event.type == .keyDown else { return event }

            if event.keyCode == 53 { // Esc
                model.cancelBatch()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
                model.undoBatch()
                return nil
            }
            if event.keyCode == 36 { // Return
                if event.modifierFlags.contains(.command) {
                    if model.batch.phase == .staged, model.batch.awaitingConfirmReturn {
                        model.confirmBatch(isARepeat: event.isARepeat)
                    } else {
                        model.stageBatch(isARepeat: event.isARepeat)
                    }
                    return nil
                }
                if model.batch.phase == .staged, model.batch.awaitingConfirmReturn, model.commandHeld {
                    model.confirmBatch(isARepeat: event.isARepeat)
                    return nil
                }
            }
            if event.charactersIgnoringModifiers == "b" {
                model.toggleBeforeAfter()
                return nil
            }
            return event
        }
    }
}
