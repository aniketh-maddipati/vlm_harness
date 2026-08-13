#!/usr/bin/env python3
"""Static Swift reachability from LuminaApp — legacy severance metrics (W8)."""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LUMINA = ROOT / "Lumina"

SKIP_DIRS = {"Develop/Lab"}

TYPE_DECL = re.compile(
    r"^(?:public\s+|private\s+|fileprivate\s+|internal\s+|@MainActor\s+)*"
    r"(?:final\s+)?(?:struct|class|enum|actor|protocol)\s+(\w+)",
    re.MULTILINE,
)
IDENT = re.compile(r"\b[A-Z][A-Za-z0-9_]+\b")

LEGACY_PREFIXES = ("Lumina/Shell/", "Lumina/Views/Workspace/")
LEGACY_EXPLICIT = frozenset(
    {
        "Lumina/ContentView.swift",
        "Lumina/ViewModels/ProjectViewModel.swift",
        "Lumina/Views/ImportLoadingView.swift",
        "Lumina/Views/ExportPayoffSheet.swift",
        "Lumina/Views/SpeedContractHUD.swift",
        "Lumina/Views/UncertainAndClusterViews.swift",
        "Lumina/Views/UnifiedCanvasView.swift",
        "Lumina/Views/PhotoGridView.swift",
        "Lumina/Views/ProgressivePhotoWall.swift",
        "Lumina/Views/GridOverviewView.swift",
        "Lumina/Views/SpeedBrowseViewer.swift",
        "Lumina/Views/MetalBrowseCanvas.swift",
        "Lumina/Views/LuminaAtmosphere.swift",
    }
)


def rel(p: Path) -> str:
    return p.relative_to(ROOT).as_posix()


def swift_files() -> list[Path]:
    out: list[Path] = []
    for p in sorted(LUMINA.rglob("*.swift")):
        rp = p.relative_to(LUMINA)
        if any(str(rp).startswith(d + "/") or str(rp) == d for d in SKIP_DIRS):
            continue
        out.append(p)
    return out


def line_count(paths: set[str]) -> int:
    total = 0
    for r in paths:
        total += len((ROOT / r).read_text(encoding="utf-8", errors="replace").splitlines())
    return total


def build_index(files: list[Path]) -> tuple[dict[str, str], dict[str, set[str]]]:
    symbol_to_file: dict[str, str] = {}
    file_refs: dict[str, set[str]] = {}
    for path in files:
        r = rel(path)
        text = path.read_text(encoding="utf-8", errors="replace")
        defined = set(TYPE_DECL.findall(text))
        for sym in defined:
            if sym not in symbol_to_file:
                symbol_to_file[sym] = r
        refs = set(IDENT.findall(text)) - defined
        file_refs[r] = refs
    return symbol_to_file, file_refs


def bfs(seed_files: set[str], file_refs: dict[str, set[str]], symbol_to_file: dict[str, str]) -> set[str]:
    seen: set[str] = set(seed_files)
    q: deque[str] = deque(seed_files)
    while q:
        f = q.popleft()
        for sym in file_refs.get(f, ()):
            target = symbol_to_file.get(sym)
            if target and target not in seen:
                seen.add(target)
                q.append(target)
    return seen


def legacy_inventory(all_files: set[str]) -> set[str]:
    return {
        r
        for r in all_files
        if r.startswith(LEGACY_PREFIXES) or r in LEGACY_EXPLICIT
    }


def legacy_only_via_p0_door(all_files: set[str]) -> tuple[set[str], dict[str, int]]:
    """Files in legacy inventory with zero type-name refs from P0 (excl. P0RootView) + P0SessionModel."""
    p0_text = ""
    for path in (LUMINA / "Views" / "P0").glob("*.swift"):
        if path.name == "P0RootView.swift":
            continue
        p0_text += path.read_text(encoding="utf-8", errors="replace")
    p0_text += (LUMINA / "ViewModels" / "P0SessionModel.swift").read_text(encoding="utf-8", errors="replace")

    legacy_only: set[str] = set()
    ref_counts: dict[str, int] = {}
    type_pat = re.compile(r"(?:struct|class|enum|actor)\s+(\w+)")
    for r in sorted(legacy_inventory(all_files)):
        text = (ROOT / r).read_text(encoding="utf-8", errors="replace")
        syms = type_pat.findall(text)
        count = sum(1 for s in syms if re.search(rf"\b{s}\b", p0_text))
        ref_counts[r] = count
        if count == 0:
            legacy_only.add(r)
    return legacy_only, ref_counts


def measure() -> dict:
    files = swift_files()
    all_files = {rel(p) for p in files}
    symbol_to_file, file_refs = build_index(files)
    from_app = bfs({"Lumina/LuminaApp.swift"}, file_refs, symbol_to_file)
    legacy_only, _ = legacy_only_via_p0_door(all_files)
    return {
        "total_files": len(all_files),
        "total_lines": line_count(all_files),
        "from_lumina_app_files": len(from_app),
        "from_lumina_app_lines": line_count(from_app),
        "legacy_only_files": len(legacy_only),
        "legacy_only_lines": line_count(legacy_only),
        "legacy_only_paths": sorted(legacy_only),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    result = measure()
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"total_files={result['total_files']} total_lines={result['total_lines']}")
        print(
            f"from_lumina_app_files={result['from_lumina_app_files']} "
            f"from_lumina_app_lines={result['from_lumina_app_lines']}"
        )
        print(
            f"legacy_only_files={result['legacy_only_files']} "
            f"legacy_only_lines={result['legacy_only_lines']}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
