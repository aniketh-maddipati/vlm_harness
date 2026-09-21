#!/usr/bin/env python3
"""Static contract for the progressive rendering hot path."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

REQUIREMENTS: dict[str, tuple[str, ...]] = {
    "Lumina/Views/P0/P0SinglePhotoEditor.swift": (
        "DevelopMetalView(",
        "immediateBrowseImage",
        "BrowsePixelService.shared.pinFocused",
        "OrientedDisplayImage.stablePresent",
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
    "Lumina/Views/P0/P0ContactSheetView.swift": (
        "P0ChapterTableView(session: session)",
        "value: session.inspectingAssetID",
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
}

FORBIDDEN: dict[str, tuple[str, ...]] = {
    "Lumina/Views/P0/P0SinglePhotoEditor.swift": (
        "if let image {\n                    DevelopMetalView(",
        "CIImage(contentsOf:",
    ),
    "Lumina/Views/P0/P0ContactSheetView.swift": (
        "if session.inspectingAssetID == nil {\n                VStack(spacing: 0) {\n                    toolbar\n                    P0ChapterTableView",
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
