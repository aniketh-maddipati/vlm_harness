#!/usr/bin/env python3
"""Prove the D40 quarantine moved files without changing code (CQ prime constraint).

Compares the set of sources the Lumina target compiles, and their comment-stripped
content, against a base git ref. Directory location changes; code does not.

    python3 Scripts/ci/prove_no_behavior_change.py [base-ref]

Sources are keyed by basename because the quarantine deliberately relocates them
(Lumina/Shell/X.swift -> Legacy/Shell/X.swift). A rename plus an identical
normalised digest is the whole claim.
"""
from __future__ import annotations

import hashlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BEFORE_ROOTS = ("Lumina", "DesignTokens")
AFTER_ROOTS = ("Lumina", "DesignTokens", "Legacy", "Salvage")


def normalise(src: str) -> str:
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    return hashlib.sha256(re.sub(r"\s+", " ", src).strip().encode()).hexdigest()[:16]


def main() -> int:
    base = sys.argv[1] if len(sys.argv) > 1 else "origin/main"
    try:
        listing = subprocess.check_output(
            ["git", "ls-tree", "-r", "--name-only", base], cwd=ROOT, text=True).split()
    except subprocess.CalledProcessError:
        print(f"FAIL: cannot read base ref {base}", file=sys.stderr)
        return 1

    before = {}
    for f in listing:
        if f.endswith(".swift") and f.split("/")[0] in BEFORE_ROOTS:
            src = subprocess.check_output(["git", "show", f"{base}:{f}"],
                                          cwd=ROOT, text=True)
            before[Path(f).name] = (f, normalise(src))

    after = {}
    for r in AFTER_ROOTS:
        for p in (ROOT / r).rglob("*.swift"):
            rel = str(p.relative_to(ROOT))
            after[p.name] = (rel, normalise(p.read_text(encoding="utf-8",
                                                        errors="replace")))

    added = sorted(set(after) - set(before))
    removed = sorted(set(before) - set(after))
    changed = [n for n in sorted(set(before) & set(after))
               if before[n][1] != after[n][1]]
    moved = [n for n in sorted(set(before) & set(after))
             if before[n][0] != after[n][0]]

    print(f"base {base}: {len(before)} app-target sources")
    print(f"head       : {len(after)} app-target sources")
    print(f"relocated  : {len(moved)}")
    for n in moved[:5]:
        print(f"    {before[n][0]}  ->  {after[n][0]}")
    if len(moved) > 5:
        print(f"    ... and {len(moved) - 5} more")

    if added or removed or changed:
        print("", file=sys.stderr)
        for n in added:
            print(f"FAIL: source added to the app target: {after[n][0]}", file=sys.stderr)
        for n in removed:
            print(f"FAIL: source dropped from the app target: {before[n][0]}",
                  file=sys.stderr)
        for n in changed:
            print(f"FAIL: code changed (not a comment): {after[n][0]}", file=sys.stderr)
        return 1

    print(f"\nOK — same {len(after)} sources, all byte-identical with comments "
          f"stripped.\nThe quarantine relocated {len(moved)} files and changed no code.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
