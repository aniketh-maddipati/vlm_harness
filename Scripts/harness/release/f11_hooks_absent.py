#!/usr/bin/env python3
"""F11.1 — DEBUG hooks absent from Release (source fence + symbol check).

macOS only. Requires a built Release Lumina.app (or LUMINA_RELEASE_APP path).
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError as exc:  # pragma: no cover
    raise SystemExit("PyYAML required: pip install pyyaml") from exc

ROOT = Path(__file__).resolve().parents[3]
INVENTORY = Path(__file__).with_name("hook_inventory.yaml")

RELEASE_FENCE = re.compile(r"#if\s+(?:DEBUG|!LUMINA_SHIPPING_APP)\b")
DEBUG_END = re.compile(r"#endif\b")


def load_inventory() -> dict:
    return yaml.safe_load(INVENTORY.read_text(encoding="utf-8"))


def file_release_fenced(path: Path) -> tuple[bool, str]:
    """Return (ok, detail). Entire file must be wrapped in a Release-excluding fence."""
    if not path.is_file():
        return True, "missing (optional hook file not present)"
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines:
        return True, "empty"
    first_non_comment = next(
        (i for i, line in enumerate(lines) if line.strip() and not line.strip().startswith("//")),
        0,
    )
    if first_non_comment >= len(lines):
        return True, "comments only"
    if not RELEASE_FENCE.search(lines[first_non_comment]):
        return False, (
            f"first code line {first_non_comment + 1} not under "
            "#if DEBUG or #if !LUMINA_SHIPPING_APP"
        )
    tail = [ln for ln in lines if ln.strip()]
    if not tail or not DEBUG_END.search(tail[-1]):
        for line in reversed(tail):
            if DEBUG_END.search(line):
                break
            if line.strip() and not line.strip().startswith("//"):
                return False, "missing trailing #endif for file-level Release fence"
        else:
            return False, "missing #endif"
    return True, "file-level Release exclusion fence"


def file_debug_fenced(path: Path) -> tuple[bool, str]:
    return file_release_fenced(path)


def check_source_hooks(inventory: dict) -> list[dict]:
    results: list[dict] = []
    for hook in inventory["hooks"]:
        hook_id = hook["id"]
        label = hook["label"]
        globs = hook.get("source_globs") or []
        paths: list[Path] = []
        for pattern in globs:
            paths.extend(sorted(ROOT.glob(pattern)))
        if not paths:
            results.append(
                {
                    "hook": hook_id,
                    "label": label,
                    "source": "SKIP",
                    "detail": "no matching source files (hook not implemented)",
                }
            )
            continue
        for path in paths:
            ok, detail = file_debug_fenced(path.relative_to(ROOT))
            results.append(
                {
                    "hook": hook_id,
                    "label": label,
                    "source": "PASS" if ok else "FAIL",
                    "file": str(path.relative_to(ROOT)),
                    "detail": detail,
                }
            )
    return results


def find_release_app(explicit: Path | None) -> Path | None:
    if explicit and explicit.is_dir():
        return explicit
    candidates = [
        ROOT / "build" / "Release" / "Lumina.app",
        ROOT / "build" / "Release" / "Lumina.app",
    ]
    for c in candidates:
        binary = c / "Contents" / "MacOS" / "Lumina"
        if binary.is_file():
            return c
    return None


def nm_symbols(binary: Path) -> set[str]:
    proc = subprocess.run(["nm", "-gU", str(binary)], capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"nm failed: {proc.stderr.strip()}")
    symbols: set[str] = set()
    for line in proc.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            symbols.add(parts[-1])
    return symbols


def check_release_symbols(inventory: dict, app: Path) -> tuple[str, list[dict]]:
    binary = app / "Contents" / "MacOS" / "Lumina"
    if not binary.is_file():
        return "PLATFORM-UNAVAILABLE", [
            {"detail": f"Release binary missing: {binary}"}
        ]
    try:
        symbols = nm_symbols(binary)
    except RuntimeError as exc:
        return "PLATFORM-UNAVAILABLE", [{"detail": str(exc)}]

    allow = set(inventory.get("allowlist_release_symbols") or [])
    results: list[dict] = []
    for hook in inventory["hooks"]:
        forbidden = hook.get("forbidden_symbols") or []
        for name in forbidden:
            if name in allow:
                continue
            present = name in symbols or any(s.startswith(name) for s in symbols)
            results.append(
                {
                    "hook": hook["id"],
                    "symbol": name,
                    "symbols": "PASS" if not present else "FAIL",
                    "detail": "absent" if not present else "present in Release binary",
                }
            )
    return "OK", results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--app",
        type=Path,
        help="Path to built Release Lumina.app",
    )
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    if sys.platform != "darwin":
        print("F11.1 hooks absent: PLATFORM-UNAVAILABLE (macOS only)")
        return 2

    inventory = load_inventory()
    source_results = check_source_hooks(inventory)
    source_fail = any(r.get("source") == "FAIL" for r in source_results)

    app = find_release_app(args.app)
    if app is None:
        sym_status = "PLATFORM-UNAVAILABLE"
        sym_results = [{"detail": "Release Lumina.app not built — pass --app or build Release first"}]
        sym_fail = False
    else:
        sym_status, sym_results = check_release_symbols(inventory, app)
        sym_fail = sym_status == "OK" and any(r.get("symbols") == "FAIL" for r in sym_results)

    print("=== F11.1 hooks absent ===")
    print("\n--- Source (Release exclusion fencing) ---")
    for row in source_results:
        status = row.get("source", "?")
        file = row.get("file", "")
        print(f"  [{status}] {row['hook']}: {row['label']}")
        if file:
            print(f"         {file} — {row.get('detail', '')}")
        else:
            print(f"         {row.get('detail', '')}")

    print(f"\n--- Release symbols ({app or 'not found'}) ---")
    if sym_status == "PLATFORM-UNAVAILABLE":
        print(f"  PLATFORM-UNAVAILABLE: {sym_results[0]['detail']}")
    else:
        for row in sym_results:
            print(f"  [{row.get('symbols', '?')}] {row.get('symbol', row.get('hook', ''))}: {row.get('detail', '')}")

    print("\n--- Allowlist (ships in Release by design) ---")
    for name in inventory.get("allowlist_release_symbols") or []:
        print(f"  {name} — P0AccessibilityID / probe types are accessibility identifiers, not harness hooks.")

    if source_fail or sym_fail:
        print("\nF11.1: FAIL")
        return 1
    if sym_status == "PLATFORM-UNAVAILABLE":
        print("\nF11.1: INCOMPLETE (source OK; symbol check PLATFORM-UNAVAILABLE)")
        return 2
    print("\nF11.1: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
