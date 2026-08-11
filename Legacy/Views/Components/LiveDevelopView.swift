import CoreImage
import SwiftUI

/// Shared render coordination for the workbench treatment stage.
/// One scheduler for the whole workbench so caches, memory pressure handling
/// and the global concurrency limit are unified.
@MainActor
enum WorkbenchDevelop {
    static let scheduler = DevelopRenderScheduler()
}

/// Live RAW-backed editing surface for the workbench treatment stage.
///
/// Slider changes route through `DevelopRenderScheduler.scrub` (latest-wins,
/// coalesced) and the result is presented via `DevelopMetalView` — no CPU
/// bitmap round trip. When the original RAW is unavailable the view falls
/// back to the proxy-graded path and says so through `fidelity`.
struct LiveDevelopView: View {
    let photoID: UUID
    let asset: AssetPresentation
    var projectName: String?
    /// Full absolute recipe (base + offsets already applied).
    var recipe: DevelopRecipe
    var oneToOne: Bool = false
    var cropState: CropLayoutState? = nil

    @State private var scheduler = WorkbenchDevelop.scheduler

    private var rawURL: URL? {
        guard let rawPath = asset.rawPath,
              FileManager.default.fileExists(atPath: rawPath) else { return nil }
        return URL(fileURLWithPath: rawPath)
    }

    private var proxyURL: URL? {
        (asset.previewPath ?? asset.thumbPath).map { URL(fileURLWithPath: $0) }
    }

    private var editRecipe: EditRecipe {
        var merged = EditRecipe(from: DevelopEngine.clampRecipe(recipe), id: photoID)
        if let cropState {
            merged = merged.updating {
                $0.crop = cropState.effectiveCrop
                $0.straightenDegrees = cropState.straightenDegrees
            }
        }
        return merged
    }

    /// Honest fidelity for the chip in the stage header.
    var liveFidelity: DevelopFidelityState? {
        guard rawURL != nil else { return nil }
        return scheduler.fidelityByPhoto[photoID]
    }

    var body: some View {
        Group {
            if rawURL != nil {
                ZStack {
                    // Underlay until the first live frame lands.
                    if scheduler.presentedCIImage(for: photoID) == nil {
                        StablePhotoView(
                            asset: asset,
                            contentMode: .fit,
                            cornerRadius: 2,
                            maxPixelSize: 2048
                        )
                    }
                    DevelopMetalView(image: scheduler.presentedCIImage(for: photoID))
                        .allowsHitTesting(false)
                }
                .task(id: scrubKey) { scrub() }
            } else {
                // No RAW on disk — proxy-graded fallback, honestly labeled.
                GradedPhotoView(
                    asset: asset,
                    projectName: projectName,
                    baseRecipe: recipe,
                    developOffsets: .zero,
                    previewMix: 1,
                    contentMode: .fit,
                    showDecisionBadge: false,
                    isSelected: false,
                    maxPixelSize: oneToOne ? 4096 : 2400
                )
            }
        }
    }

    private var scrubKey: String {
        "\(photoID)|\(editRecipe.valueFingerprint)|\(oneToOne)"
    }

    private func scrub() {
        guard let rawURL else { return }
        if oneToOne {
            let recipe = editRecipe
            Task {
                await scheduler.renderOneToOne(
                    photoID: photoID,
                    rawURL: rawURL,
                    proxyURL: proxyURL,
                    recipe: recipe,
                    region: .full
                )
            }
        } else {
            scheduler.scrub(
                photoID: photoID,
                rawURL: rawURL,
                proxyURL: proxyURL,
                recipe: editRecipe
            )
        }
    }
}
