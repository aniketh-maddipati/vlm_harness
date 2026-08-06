import CoreImage
import SwiftUI

/// Shared render coordination for the workbench treatment stage.
/// One scheduler + one editor model for the whole workbench so caches,
/// memory pressure handling, and editor identity stay unified.
@MainActor
enum WorkbenchDevelop {
    static let scheduler = DevelopRenderScheduler()
    static let editor = DevelopEditorModel(scheduler: scheduler)
}

/// Live RAW-backed editing surface for the workbench treatment stage.
///
/// Presentation only — recipe mutations happen on `DevelopEditorModel` so
/// slider ticks never wait on `.task(id:)` or release-to-apply. The Metal
/// view is stable for the lifetime of this surface.
struct LiveDevelopView: View {
    let photoID: UUID
    let asset: AssetPresentation
    var projectName: String?
    /// Absolute recipe — kept for callers that still push values; preferred
    /// path is `WorkbenchDevelop.editor` mutations.
    var recipe: DevelopRecipe
    var oneToOne: Bool = false
    var editor: DevelopEditorModel = WorkbenchDevelop.editor

    private var rawURL: URL? {
        guard let rawPath = asset.rawPath,
              FileManager.default.fileExists(atPath: rawPath) else { return nil }
        return URL(fileURLWithPath: rawPath)
    }

    private var proxyURL: URL? {
        (asset.previewPath ?? asset.thumbPath).map { URL(fileURLWithPath: $0) }
    }

    /// Honest fidelity for the chip in the stage header.
    var liveFidelity: DevelopFidelityState? {
        guard rawURL != nil else { return nil }
        return editor.scheduler.fidelityByPhoto[photoID]
    }

    var body: some View {
        Group {
            if rawURL != nil {
                ZStack {
                    // Underlay until the first live frame lands — never flash blank.
                    if editor.presentedImage == nil {
                        StablePhotoView(
                            asset: asset,
                            contentMode: .fit,
                            cornerRadius: 2,
                            maxPixelSize: 2048
                        )
                    }
                    DevelopMetalView(
                        image: editor.presentedImage,
                        displayedRevision: editor.displayedRevision
                    )
                    .allowsHitTesting(false)
                }
                .onAppear {
                    syncSelection()
                }
                .onChange(of: photoID) { _, _ in
                    syncSelection()
                }
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

    private func syncSelection() {
        let edit = EditRecipe(from: DevelopEngine.clampRecipe(recipe), id: photoID)
        editor.selectPhoto(
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: edit
        )
        if oneToOne != editor.oneToOne {
            editor.toggleOneToOne()
        }
    }
}
