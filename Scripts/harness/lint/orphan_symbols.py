#!/usr/bin/env python3
"""Orphan/dead symbol gate — sealed types with no live wiring."""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
REGISTER = ROOT / "artifacts" / "harness" / "orphan_register.txt"

SCAN_DIRS = (
    ROOT / "Lumina" / "Core",
    ROOT / "Lumina" / "Design",
    ROOT / "Lumina" / "Views" / "Components",
)
TEST_DIR_NAMES = ("LuminaLogicTests", "LuminaUITests")

TYPE_DECL = re.compile(
    r"^(?:public\s+|private\s+|fileprivate\s+|internal\s+)?"
    r"(?:final\s+)?(?:struct|class|enum|actor)\s+(\w+)",
    re.MULTILINE,
)
WORD = re.compile(r"\b\w+\b")

LIVE_PREFIXES = (
    "Lumina/Views/",
    "Lumina/ViewModels/",
    "Lumina/Services/",
    "Lumina/Persistence/",
    "Lumina/Models/",
    "Lumina/Shell/",
)
LIVE_FILES = ("Lumina/LuminaApp.swift", "Lumina/ContentView.swift")
# Design bridges consumed by the P0 live path (W4 motion wiring).
LIVE_BRIDGE_FILES = frozenset(
    {
        "Lumina/Design/LuminaSpringAnimation.swift",
        "Lumina/Design/LuminaTokens.swift",
    }
)

# Files whose types are dead (zero wiring) — W8 deletes; not orphan-register rows.
DEAD_FILES = frozenset(
    {
        "Lumina/Views/Components/DecisionDock.swift",
    }
)


@dataclass(frozen=True)
class SymbolRef:
    rel_path: str
    symbol: str
    test_refs: tuple[str, ...]
    live_refs: tuple[str, ...]
    external_refs: int


@dataclass(frozen=True)
class RegisterEntry:
    rel_path: str
    symbol: str
    owner: str
    reason: str


def is_live_path(rel: str) -> bool:
    if rel in LIVE_FILES or rel in LIVE_BRIDGE_FILES:
        return True
    if not any(rel.startswith(p) for p in LIVE_PREFIXES):
        return False
    # Live views under P0 etc., but not orphan scan dirs.
    for scan in SCAN_DIRS:
        scan_rel = scan.relative_to(ROOT).as_posix()
        if rel.startswith(scan_rel + "/") or rel == scan_rel:
            return False
    return True


def is_test_path(rel: str) -> bool:
    return any(rel.startswith(name + "/") for name in TEST_DIR_NAMES)


def is_scan_path(rel: str) -> bool:
    return any(
        rel.startswith(scan.relative_to(ROOT).as_posix() + "/")
        or rel == scan.relative_to(ROOT).as_posix()
        for scan in SCAN_DIRS
    )


def collect_sources() -> dict[str, str]:
    files: dict[str, str] = {}
    for path in ROOT.rglob("*.swift"):
        rel = path.relative_to(ROOT).as_posix()
        try:
            files[rel] = path.read_text(encoding="utf-8")
        except OSError:
            continue
    return files


def analyze() -> tuple[list[SymbolRef], list[SymbolRef]]:
    sources = collect_sources()
    source_words = {
        rel: frozenset(WORD.findall(body))
        for rel, body in sources.items()
    }
    orphans: list[SymbolRef] = []
    dead: list[SymbolRef] = []

    for scan in SCAN_DIRS:
        if not scan.is_dir():
            continue
        for path in sorted(scan.rglob("*.swift")):
            decl_rel = path.relative_to(ROOT).as_posix()
            text = sources[decl_rel]
            for match in TYPE_DECL.finditer(text):
                symbol = match.group(1)
                test_refs: list[str] = []
                live_refs: list[str] = []
                external = 0
                for rel in sources:
                    if rel == decl_rel:
                        continue
                    if symbol not in source_words[rel]:
                        continue
                    external += 1
                    if is_test_path(rel):
                        test_refs.append(rel)
                    elif is_live_path(rel):
                        live_refs.append(rel)

                ref = SymbolRef(
                    rel_path=decl_rel,
                    symbol=symbol,
                    test_refs=tuple(sorted(test_refs)),
                    live_refs=tuple(sorted(live_refs)),
                    external_refs=external,
                )

                if live_refs:
                    continue

                if decl_rel in DEAD_FILES and external == 0:
                    dead.append(ref)
                    continue

                orphans.append(ref)

    return orphans, dead


def parse_register() -> dict[tuple[str, str], RegisterEntry]:
    entries: dict[tuple[str, str], RegisterEntry] = {}
    if not REGISTER.is_file():
        return entries
    owner = ""
    reason = ""
    for raw in REGISTER.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            owner_match = re.search(r"owned-by-(\S+)", line)
            if owner_match:
                owner = owner_match.group(1)
            reason = line.lstrip("#").strip()
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        path, symbol = parts
        entries[(path, symbol)] = RegisterEntry(path, symbol, owner, reason)
    return entries


def main() -> int:
    orphans, dead = analyze()
    registered = parse_register()
    fail = 0

    for ref in sorted(orphans, key=lambda r: (r.rel_path, r.symbol)):
        key = (ref.rel_path, ref.symbol)
        if key not in registered:
            tests = ", ".join(ref.test_refs) if ref.test_refs else "self-only"
            print(
                f"FAIL: orphan {ref.rel_path} · {ref.symbol} · {tests} — "
                f"register in {REGISTER} with # owned-by-CP<N>",
                file=sys.stderr,
            )
            fail = 1

    if dead:
        print("NOTE: dead symbols (zero references — W8 deletes):", file=sys.stderr)
        for ref in sorted(dead, key=lambda r: (r.rel_path, r.symbol)):
            print(f"  {ref.rel_path} · {ref.symbol}", file=sys.stderr)

    if fail:
        return 1

    print(
        f"orphan_symbols.py: OK "
        f"({len(orphans)} orphans registered, {len(dead)} dead reported)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
