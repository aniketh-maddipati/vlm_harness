#!/usr/bin/env python3
"""Static contract for the progressive rendering hot path."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

REQUIREMENTS: dict[str, tuple[str, ...]] = {
    "Lumina/Views/P0/ElasticFocusView.swift": (
        "DevelopMetalView(",
        "immediateBrowseImage",
        "BrowsePixelService.shared.pinFocused",
        "OrientedDisplayImage.select",
        "session.displayFrame(for: asset.id)",
        "OrientedDisplayImage.ciImage",
    ),
    "Lumina/Rendering/OrientedDisplayImage.swift": (
        "CreateThumbnailWithTransform",
        "stablePresent",
        "aligning",
    ),
    "Lumina/Develop/DevelopRenderGraph.swift": (
        "OrientedDisplayImage.aligning",
        "OrientedDisplayImage.ciImage",
    ),
    "Lumina/Views/P0/ElasticRootView.swift": (
        "ElasticTableView(session: session)",
        "value: session.route",
    ),
    "Lumina/Views/P0/P0ChapterTableView.swift": (
        "ElasticCanvasLayout.plateOpacity",
        "ElasticCanvasLayout.stripThumbLongEdge",
        "inspectStrip",
    ),
    "Lumina/Develop/DevelopRenderScheduler.swift": (
        "visibleRenderGate",
        "speculativeRenderGate",
        "visiblePhotoID == photoID",
        "quality: .interactive",
        "quality: .settled",
    ),
    "Lumina/Services/BrowsePixelService.swift": (
        "guard !rawExtensions.contains(ext) else { return nil }",
        "pinnedPaths",
        "decoded: decoded.cgImage",
    ),
    "Lumina/Views/MetalBrowseCanvas.swift": (
        "BrowsePixelService.shared.prepareTexture",
    ),
    "Lumina/Develop/PreparedRawSession.swift": (
        "materializeInteractiveStage",
        "interactiveCacheLimit = 2",
        "pinnedInteractiveDecode",
        "mtlTexture: texture",
    ),
    "Lumina/Develop/Lab/DevelopMetalView.swift": (
        "LatencyMetrics.editDrawKey",
        "commandBuffer.addCompletedHandler",
    ),
    "Lumina/Models/ShootMigration.swift": (
        "photo.userDecidedAt == nil ? .undecided",
    ),
    "Lumina/Develop/RawDecodeBackend.swift": (
        "static let production: any RawDecodeBackend = AppleRawDecodeBackend()",
        'identifier: "libraw",\n            linked: false',
        'identifier: "rawspeed",\n            linked: false',
    ),
    "Lumina/Services/P0AuthoritativeExportService.swift": (
        "DevelopRenderGraph.renderExportBitmap",
        "DevelopRenderGraph.exportTIFF",
    ),
    "LuminaLogicTests/ProgressiveRenderingArchitectureTests.swift": (
        "testCancelledRenderWaiterDoesNotBlockLatestWork",
        "testLegacyMachineTierCannotBecomeP0Decision",
    ),
    # The version column may only show pixels that depict the version it labels.
    # The browse thumbnail is the camera's rendering, so it is `shot` and nothing
    # else; drawing it under all three made the column claim a difference that was
    # not on screen.
    "Lumina/Views/P0/ElasticVersionColumn.swift": (
        "private func previewPath(for index: Int) -> String?",
        "guard index == 1 else { return nil }",
    ),
    "LuminaLogicTests/PhotoRenderProofTests.swift": (
        "testPhotographIsNeverPresentedUpsideDown",
        "PhotoPresentProof.probe",
    ),
    "Lumina/Rendering/PhotoPresentProof.swift": (
        "destination.isFlipped = true",
    ),
}

FORBIDDEN: dict[str, tuple[str, ...]] = {
    "Lumina/Views/P0/ElasticFocusView.swift": (
        "if let image {\n                    DevelopMetalView(",
        "CIImage(contentsOf:",
    ),
    "Lumina/Views/P0/ElasticRootView.swift": (
        "if session.route == .time {\n                    ElasticTableView",
    ),
    "Lumina/Views/P0/ElasticVersionColumn.swift": (
        "if let path = asset.gridThumbPath ?? asset.thumbPath {",
    ),
    "Lumina/Develop/Lab/DevelopMetalView.swift": (
        # The present geometry lives in PhotoPresentProof so the render proof
        # measures the real transform instead of a copy of it.
        "let fit = min(drawableSize.width / extent.width",
    ),
    "Lumina/Develop/DevelopRenderGraph.swift": (
        "applyOrientationProperty",
        "CIImage(contentsOf:",
    ),
    "Lumina/Services/MetalPreviewPool.swift": (
        "decodeBrowseJPEG",
        "func upload(id: UUID, jpegPath:",
    ),
    "Lumina/Views/Components/StablePhotoView.swift": (
        "PhotoImageCache.shared",
    ),
    "Lumina/Views/ProgressivePhotoWall.swift": (
        "PhotoImageCache.shared",
    ),
    "Lumina/Views/MetalBrowseCanvas.swift": (
        "MetalPreviewPool.shared.scheduleUpload",
    ),
    "Lumina/ViewModels/ProjectViewModel.swift": (
        "PhotoImageCache.shared",
    ),
}


def main() -> int:
    failures: list[str] = []
    for relative, needles in REQUIREMENTS.items():
        path = ROOT / relative
        if not path.is_file():
            failures.append(f"missing {relative}")
            continue
        text = path.read_text(encoding="utf-8")
        for needle in needles:
            if needle not in text:
                failures.append(f"{relative}: missing {needle!r}")

    for relative, needles in FORBIDDEN.items():
        text = (ROOT / relative).read_text(encoding="utf-8")
        for needle in needles:
            if needle in text:
                failures.append(f"{relative}: forbidden remount pattern {needle!r}")

    if failures:
        for failure in failures:
            print(f"FAIL: progressive_render_architecture: {failure}", file=sys.stderr)
        return 1
    print("progressive_render_architecture: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
