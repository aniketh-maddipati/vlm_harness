import AppKit
import SwiftUI

/// Debug-only single-photo live editor — production render pipeline, no carousel.
///
/// Launch: `--live-editor` with `LUMINA_DEVELOP_RAW_DIR` or `--develop-raw-dir`.
struct LiveEditorProofView: View {
    @State private var model = DevelopEditorModel(scheduler: DevelopRenderScheduler())
    @State private var frames: [DevelopLabFrame] = []
    @State private var fixtureMessage = ""
    @State private var blocked = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black.opacity(0.92)
                if let image = model.presentedImage {
                    DevelopMetalView(image: image, displayedRevision: model.displayedRevision)
                        .onChange(of: model.displayedRevision) { _, _ in
                            model.absorbPresentedTexture()
                        }
                        .onChange(of: model.scheduler.metrics.completed) { _, _ in
                            model.absorbPresentedTexture()
                        }
                } else {
                    Text(blocked ? fixtureMessage : "Preparing RAW…")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            controlRail
                .frame(width: 320)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: bootstrap)
    }

    private var controlRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Live Editor Proof")
                    .font(.headline)
                Text(fixtureMessage)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(model.statusLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Fidelity: \(model.fidelityLabel)")
                    .font(.system(size: 11, design: .monospaced))

                photoPicker

                Group {
                    proofSlider("Exposure", value: model.draftRecipe.exposure, range: -3...3) {
                        model.setExposure($0)
                    }
                    proofSlider("Warmth (K)", value: model.draftRecipe.temperature, range: 2500...10000) {
                        model.setTemperature($0)
                    }
                    proofSlider("Tint", value: model.draftRecipe.tint, range: -50...50) {
                        model.setTint($0)
                    }
                    proofSlider("Highlights", value: model.draftRecipe.highlights, range: -100...100) {
                        model.setHighlights($0)
                    }
                    proofSlider("Shadows", value: model.draftRecipe.shadows, range: -100...100) {
                        model.setShadows($0)
                    }
                    proofSlider("Contrast", value: model.draftRecipe.contrast, range: -100...100) {
                        model.setContrast($0)
                    }
                    proofSlider("Saturation", value: model.draftRecipe.saturation, range: -100...100) {
                        model.setSaturation($0)
                    }
                    let nrOK = model.capabilities?.luminanceNoiseReduction != .unsupported
                    proofSlider(
                        nrOK ? "RAW Noise Reduction" : "NR unsupported",
                        value: model.draftRecipe.luminanceNR,
                        range: 0...100
                    ) { model.setLuminanceNR($0) }
                    .disabled(!nrOK)
                    let shOK = model.capabilities?.sharpness != .unsupported
                    proofSlider(
                        shOK ? "RAW Sharpening" : "Sharpen unsupported",
                        value: model.draftRecipe.sharpness,
                        range: 0...150
                    ) { model.setSharpness($0) }
                    .disabled(!shOK)
                }

                HStack {
                    Button(model.showBefore ? "After" : "Before") { model.toggleBeforeAfter() }
                    Button(model.oneToOne ? "Fit" : "1:1") { model.toggleOneToOne() }
                    Button("Commit") { model.commitDraft() }
                }

                Text(DevelopMetalLifecycle.summaryLine)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var photoPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Photographs")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(frames) { frame in
                Button {
                    select(frame)
                } label: {
                    HStack {
                        Text(frame.filename)
                            .font(.system(size: 11, design: .monospaced))
                        Spacer()
                        if model.photoID == frame.id {
                            Text("●").foregroundStyle(.orange)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func proofSlider(
        _ title: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.system(size: 10, design: .monospaced))
            }
            Slider(
                value: Binding(get: { value }, set: { onChange($0) }),
                in: range
            )
        }
    }

    private func bootstrap() {
        let dir = DevelopLabFixtures.resolveRawDirectory()
        guard let dir else {
            blocked = true
            fixtureMessage = "No RAW dir — set LUMINA_DEVELOP_RAW_DIR or --develop-raw-dir"
            return
        }
        let urls = DevelopLabFixtures.discoverRAWFiles(in: dir, limit: 4)
        guard let first = urls.first else {
            blocked = true
            fixtureMessage = "No ARW files in \(dir.path)"
            return
        }
        frames = urls.map { DevelopLabFrame(id: UUID(), url: $0) }
        fixtureMessage = "Loaded \(frames.count) from \(dir.path)"
        if let frame = frames.first {
            select(frame)
        } else {
            select(DevelopLabFrame(id: UUID(), url: first))
        }
    }

    private func select(_ frame: DevelopLabFrame) {
        model.selectPhoto(
            photoID: frame.id,
            rawURL: frame.url,
            proxyURL: nil,
            recipe: .neutral
        )
    }
}

/// `--live-editor` entry.
@MainActor
enum LiveEditorProofLauncher {
    static func runIfRequested() -> Bool {
        ProcessInfo.processInfo.arguments.contains("--live-editor")
    }

    static var shouldPresent: Bool {
        ProcessInfo.processInfo.arguments.contains("--live-editor")
    }
}
