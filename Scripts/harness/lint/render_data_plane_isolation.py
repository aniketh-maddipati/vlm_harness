#!/usr/bin/env python3
"""Guard the render/export data plane under SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor.

The project sets default actor isolation to MainActor. Value types and extensions
used from actors, Task.detached, or nonisolated render code must be explicitly
marked nonisolated — otherwise xcodebuild fails with errors like:

  Main actor-isolated property 'lookIntent' cannot be accessed from outside of the actor
  Missing argument for parameter 'at' in call  (actor static mis-read from sync context)

This lint is static structure only; the compile lock in
LuminaLogicTests/ProgressiveRenderingArchitectureTests.swift and hosted
compile-logic (xcodebuild) are the authoritative proof.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# Types/extensions that must be reachable off the main actor.
NONISOLATED_TYPE_MARKERS: dict[str, tuple[str, ...]] = {
    "Lumina/Develop/DevelopRenderGraph.swift": ("nonisolated enum DevelopRenderGraph",),
    "Lumina/Develop/RawRenderRequest.swift": (
        "nonisolated struct RawRenderRequest",
        "nonisolated struct DevelopRenderResult",
    ),
    "Lumina/Develop/DevelopIntents.swift": ("nonisolated extension EditRecipe",),
    "Lumina/Develop/EditRecipe.swift": ("nonisolated struct EditRecipe",),
    "Lumina/Develop/DevelopColorPolicy.swift": ("nonisolated enum DevelopColorPolicy",),
    "Lumina/Develop/RawDecodeBackend.swift": ("nonisolated enum RawDecodeBackendRegistry",),
    "Lumina/Services/P0AuthoritativeExportService.swift": (
        "nonisolated enum P0AuthoritativeExportService",
    ),
    "Lumina/Services/DevelopEngine.swift": ("nonisolated enum DevelopEngine",),
    "Lumina/Services/PhotoImageCache.swift": (
        "nonisolated enum PhotoImageTier",
        "nonisolated enum PhotoLoadOutcome",
    ),
    "Lumina/Services/PhotoImageCacheBudget.swift": ("nonisolated enum PhotoImageCacheBudget",),
    "Lumina/Services/BrowsePixelService.swift": ("nonisolated enum Tier",),
    "Lumina/Models/P0State.swift": ("nonisolated struct AssetRecord",),
    "Lumina/Models/PhotoRecord.swift": (
        "nonisolated struct DevelopAdjustments",
        "nonisolated struct DevelopRecipe",
        "nonisolated struct PhotoRecord",
        "nonisolated enum PhotoTier",
        "nonisolated enum PreviewOrigin",
    ),
    "Lumina/Models/AssetIdentity.swift": ("nonisolated enum AssetIdentity",),
    "Lumina/Services/ProjectStore.swift": ("nonisolated enum ProjectStore",),
    "Lumina/Services/AutoDevelop.swift": ("nonisolated enum AutoDevelop",),
    "Lumina/Services/VisionAssist.swift": ("nonisolated enum VisionAssist",),
}

FORBIDDEN_PATTERNS: tuple[tuple[str, str], ...] = (
    ("Lumina/Develop/RawRenderRequest.swift", "PreparedRawSession.decoderMappingVersion"),
    ("LuminaLogicTests/ProgressiveRenderingArchitectureTests.swift", "PreparedRawSession.decoderMappingVersion"),
)

REQUIRED_PATTERNS: tuple[tuple[str, str], ...] = (
    ("Lumina/Develop/DevelopIntents.swift", "nonisolated extension EditRecipe"),
    ("Lumina/Develop/RawDecodeBackend.swift", "static let mappingVersion"),
    ("Lumina/Develop/PreparedRawSession.swift", "nonisolated enum Tier"),
    (
        "LuminaLogicTests/ProgressiveRenderingArchitectureTests.swift",
        "nonisolated func nonisolatedLookIntentFingerprint",
    ),
    (
        "LuminaLogicTests/ProgressiveRenderingArchitectureTests.swift",
        "nonisolated func nonisolatedRenderCacheKey",
    ),
    (
        "LuminaLogicTests/ProgressiveRenderingArchitectureTests.swift",
        "nonisolated func nonisolatedEnsureProxy",
    ),
    ("Lumina/Models/P0State.swift", "nonisolated extension AssetRecord"),
)

# Actor nested statics/constants read synchronously from nonisolated decode paths.
RAW_EXTENSION_MARKERS: tuple[tuple[str, str], ...] = (
    ("Lumina/Services/PhotoImageCache.swift", "nonisolated private static let rawExtensions"),
    ("Lumina/Services/BrowsePixelService.swift", "nonisolated private static let rawExtensions"),
)


def main() -> int:
    failures: list[str] = []

    for rel, needles in NONISOLATED_TYPE_MARKERS.items():
        path = ROOT / rel
        if not path.is_file():
            failures.append(f"missing {rel}")
            continue
        text = path.read_text(encoding="utf-8")
        for needle in needles:
            if needle not in text:
                failures.append(f"{rel}: expected {needle!r}")

    for rel, pattern in FORBIDDEN_PATTERNS:
        text = (ROOT / rel).read_text(encoding="utf-8")
        if pattern in text:
            failures.append(f"{rel}: forbidden {pattern!r} — use RawDecodeBackendRegistry.mappingVersion")

    for rel, pattern in REQUIRED_PATTERNS:
        text = (ROOT / rel).read_text(encoding="utf-8")
        if pattern not in text:
            failures.append(f"{rel}: missing required {pattern!r}")

    for rel, pattern in RAW_EXTENSION_MARKERS:
        text = (ROOT / rel).read_text(encoding="utf-8")
        if pattern not in text:
            failures.append(f"{rel}: missing {pattern!r}")

    # Unmarked EditRecipe intent extension is the original lookIntent failure class.
    intents = (ROOT / "Lumina/Develop/DevelopIntents.swift").read_text(encoding="utf-8")
    if re.search(r"(?m)^extension EditRecipe \{", intents):
        failures.append(
            "Lumina/Develop/DevelopIntents.swift: use nonisolated extension EditRecipe"
        )

    if failures:
        for failure in failures:
            print(f"FAIL: render_data_plane_isolation: {failure}", file=sys.stderr)
        return 1

    print("render_data_plane_isolation: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
