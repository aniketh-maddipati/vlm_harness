import SwiftUI

/// Right adjustment rail for P0 single-photo editing.
/// Wide, tactile controls — only one section expands; Whites/Blacks omitted.
struct P0AdjustmentRail: View {
    @Bindable var session: P0SessionModel
    let assetID: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var recipe: EditRecipe { session.recipe(for: assetID) }
    private var nrSupported: Bool {
        session.rawCapabilities?.luminanceNoiseReduction != .unsupported
    }
    private var sharpenSupported: Bool {
        session.rawCapabilities?.sharpness != .unsupported
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Adjust")
                .font(LuminaTokens.Typeface.navigation(18, weight: .semibold))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .padding(.bottom, 14)

            section(.light) { lightControls }
            section(.color) { colorControls }
            section(.detail) { detailControls }
            section(.crop) { P0CropControls(session: session, assetID: assetID) }

            Spacer(minLength: 12)

            if recipe.hasSettings {
                Button("Reset photo") {
                    session.resetRecipeToNeutral(assetID: assetID)
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .frame(maxWidth: .infinity, minHeight: LuminaTokens.HitTarget.minimum)
                .background(LuminaTokens.Surface.well)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 352, alignment: .topLeading)
        .background(LuminaTokens.Surface.rail)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(width: LuminaTokens.Line.hairlineWidth)
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ section: P0AdjustmentSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let expanded = session.expandedAdjustmentSection == section
        VStack(alignment: .leading, spacing: 10) {
            P0RailSectionHeader(title: section.title, expanded: expanded) {
                withAnimation(
                    LuminaSpringAnimation.transform(
                        reduceMotion: reduceMotion,
                        durationMs: Double(HiFiTokens.Motion.travelMs),
                        curve: .easeOut
                    )
                ) {
                    if session.expandedAdjustmentSection == section {
                        session.expandedAdjustmentSection = nil
                    } else {
                        session.expandedAdjustmentSection = section
                    }
                }
            }
            if expanded {
                content()
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, 12)
    }

    private var lightControls: some View {
        VStack(spacing: 14) {
            fieldSlider(
                "Exposure", keyPath: \.exposure, range: -3...3, step: 0.1, neutral: 0,
                identifier: P0AccessibilityID.singlePhotoExposureSlider
            ) {
                String(format: "%+.2f EV", $0)
            }
            fieldSlider("Contrast", keyPath: \.contrast, range: -100...100, step: 1, neutral: 0) {
                String(format: "%.0f", $0)
            }
            fieldSlider("Highlights", keyPath: \.highlights, range: -100...100, step: 1, neutral: 0) {
                String(format: "%.0f", $0)
            }
            fieldSlider("Shadows", keyPath: \.shadows, range: -100...100, step: 1, neutral: 0) {
                String(format: "%.0f", $0)
            }
        }
    }

    private var colorControls: some View {
        VStack(spacing: 14) {
            temperatureSlider
            fieldSlider("Tint", keyPath: \.tint, range: -150...150, step: 1, neutral: 0) {
                String(format: "%+.0f", $0)
            }
            fieldSlider("Vibrance", keyPath: \.vibrance, range: -100...100, step: 1, neutral: 0) {
                String(format: "%.0f", $0)
            }
            fieldSlider("Saturation", keyPath: \.saturation, range: -100...100, step: 1, neutral: 0) {
                String(format: "%.0f", $0)
            }
        }
    }

    private var detailControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldSlider(
                sharpenSupported ? "Sharpening" : "Sharpening — unsupported",
                keyPath: \.sharpness,
                range: 0...150,
                step: 1,
                neutral: 0,
                enabled: sharpenSupported
            ) { String(format: "%.0f", $0) }
            fieldSlider(
                nrSupported ? "Noise reduction" : "Noise reduction — unsupported",
                keyPath: \.luminanceNR,
                range: 0...100,
                step: 1,
                neutral: 0,
                enabled: nrSupported
            ) { String(format: "%.0f", $0) }
            if !sharpenSupported || !nrSupported {
                Text("Unsupported Detail controls stay disabled for this file.")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var temperatureSlider: some View {
        let native = session.rawNativeTemperature
        let displayed = recipe.rawIntent.isAsShotWhiteBalance
            ? (native ?? recipe.temperature)
            : recipe.temperature
        let neutralDisplay = native ?? 6500
        return P0EditSlider(
            title: "Temperature",
            value: displayed,
            range: 2000...10000,
            step: 50,
            display: { String(format: "%.0f K", $0) },
            neutral: neutralDisplay,
            enabled: true,
            onBegin: { session.beginEditGesture(for: assetID) },
            onScrub: { kelvin in
                session.scrubEdit { recipe in
                    if let native, abs(kelvin - native) < 25 {
                        recipe.temperature = 6500
                    } else {
                        recipe.temperature = kelvin
                    }
                }
            },
            onEnd: { session.endEditGesture() },
            onReset: {
                session.applyEditMutation({ $0.temperature = 6500 }, assetID: assetID)
            }
        )
    }

    private func fieldSlider(
        _ title: String,
        keyPath: WritableKeyPath<EditRecipe, Double>,
        range: ClosedRange<Double>,
        step: Double,
        neutral: Double,
        enabled: Bool = true,
        identifier: String? = nil,
        display: @escaping (Double) -> String
    ) -> some View {
        P0EditSlider(
            title: title,
            value: recipe[keyPath: keyPath],
            range: range,
            step: step,
            display: display,
            neutral: neutral,
            enabled: enabled,
            onBegin: { session.beginEditGesture(for: assetID) },
            onScrub: { next in
                session.scrubEdit { $0[keyPath: keyPath] = next }
            },
            onEnd: { session.endEditGesture() },
            onReset: {
                session.applyEditMutation({ $0[keyPath: keyPath] = neutral }, assetID: assetID)
            },
            identifier: identifier
        )
    }
}
