#!/usr/bin/env python3
"""The app's copies of the design's page, checked byte for byte on Linux.

SetsPageBytesTests (LuminaLogicTests, macOS) holds the list of (design file, bundled copy) pairs.
This reads the same list out of the test and compares the same bytes, so a change that only
touches those copies is fully checked by CI's `design handoff` job and needs no Mac build
(Scripts/ci_changes.py leaves them out of the `swift` area).

    python3 Scripts/page_bytes.py        # exit 1 and name each copy that drifted
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEST = os.path.join(ROOT, "LuminaLogicTests", "SetsPageBytesTests.swift")
PAIR = re.compile(r'\(\s*"([^"]+)"\s*,\s*"(Lumina/Sets/Web/[^"]+)"\s*\)')


def pairs():
    """[(design, bundled)] as SetsPageBytesTests lists them, paths relative to the repo."""
    with open(TEST, encoding="utf-8") as fh:
        return PAIR.findall(fh.read())


def copies():
    """The bundled paths the test covers: Lumina/Sets/Web files that are byte copies of the design."""
    return {b for _, b in pairs()}


def main():
    found = pairs()
    if not found:
        sys.exit(f"no (design, Lumina/Sets/Web/…) pairs found in {os.path.relpath(TEST, ROOT)}")
    bad = 0
    for design, bundled in found:
        a, b = (open(os.path.join(ROOT, p), "rb").read() for p in (design, bundled))
        if a != b:
            print(f"FAIL {bundled} drifted from {design}: run Scripts/sets_sync_ui.sh")
            bad += 1
    print(f"{len(found) - bad} / {len(found)} page copies identical to the design")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
