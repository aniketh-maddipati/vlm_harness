#!/usr/bin/env python3
"""Banned-pattern RATCHET (CQ.3).

The banned-pattern greps fire on pre-existing code. This checkpoint neither
fixes that debt nor silences it: every violation is counted into a baseline,
each cluster carries an owning checkpoint, and the counts may only ever fall.

Rules
  * count above baseline for a (file, pattern)  -> FAIL
  * any hit in a file absent from the baseline  -> FAIL  (new debt, new file)
  * a baseline row without an owner             -> FAIL  (unowned debt)
  * count below baseline                        -> PASS, and the row is
                                                    reported as slack to reap

Zero-tolerance patterns carry no baseline rows at all: any hit fails.

    python3 Scripts/lint/ratchet.py            # check (FAST lane)
    python3 Scripts/lint/ratchet.py --generate # rewrite the baseline
    python3 Scripts/lint/ratchet.py --tighten  # lower baseline to reality
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / "Scripts/lint/baseline/banned_patterns.baseline"

# Source roots that carry product code. Test targets and the harness are out of
# scope: they are allowed spinners in their own fixtures.
SOURCE_ROOTS = ("Lumina", "Legacy", "Salvage", "DesignTokens")


class Pattern:
    def __init__(self, pid, regex, law, zero_tolerance=False, files=None):
        self.pid = pid
        self.regex = re.compile(regex)
        self.law = law
        self.zero_tolerance = zero_tolerance
        self.files = files  # optional path predicate

    def applies(self, rel: str) -> bool:
        return self.files(rel) if self.files else True


def is_view(rel: str) -> bool:
    return "/Views/" in rel or "/Shell/" in rel or rel.endswith("View.swift") \
        or "/Design/" in rel or "/Workspace/" in rel


# Literals owned by design/tokens.yaml. A raw occurrence in view code is a magic
# number (D49 / "magic numbers in UI code" ban); consume HiFiTokens instead.
TOKEN_LITERALS = [252, 1280, 800, 120, 140, 600, 200, 90, 46, 64]
MAGIC = r"(?<![\w.])(?:" + "|".join(str(n) for n in TOKEN_LITERALS) + r")(?![\w.])"

PATTERNS = [
    Pattern("spinner", r"ProgressView\s*\(", "no spinners"),
    Pattern("progress_bar", r"ProgressViewStyle|LinearProgress|CircularProgress",
            "no progress bars"),
    Pattern("skeleton", r"Skeleton|skeletonView|redacted\(reason:\s*\.placeholder\)",
            "no skeletons"),
    Pattern("modal_failure", r"NSAlert\s*\(|\.alert\s*\(",
            "no modals in failure paths (D35)"),
    Pattern("hover", r"\.onHover\b|onHover\s*\(", "hover deleted entirely (D37/D48)"),
    Pattern("timer", r"Timer\s*\.|asyncAfter\s*\(|Task\.sleep",
            "duration never carries meaning (D27)"),
    Pattern("magic_number", MAGIC, "tokens only, no UI literals (D49)", files=is_view),
    Pattern("hand_typed_string", r'(?:Text|Button|Label)\(\s*"[^"]{3,}"',
            "frozen copy table only (design/copy-contract.txt)"),
    # Zero tolerance — these have no lawful occurrence in product code.
    Pattern("timed_double_tap", r"doubleTap|timedDouble|double_tap",
            "no timed double-taps (D10)", zero_tolerance=True),
    Pattern("release_commit", r"releaseCommit|commitOnRelease|onReleaseCommit",
            "release never commits (D13/D60)", zero_tolerance=True),
    Pattern("cached_decision", r"cachedDecision|localStorage",
            "decisions are never cached (D36)", zero_tolerance=True),
    Pattern("network_egress", r"URLSession|https?://",
            "zero egress from the app (D4/D45)", zero_tolerance=True),
]

# Owner map: longest matching path prefix wins. Every owner is a step in
# design/checkpoint-sequence-v6.md. A violating file that matches nothing here
# is unowned debt and fails generation.
OWNERS = [
    # --- salvage ---
    ("Salvage/Services/EmbeddingService.swift", "CP1"),   # grouping-API review
    ("Salvage/Services/ExifToolService.swift", "CP3"),    # ingest metadata
    # --- legacy: ingest + metadata ---
    ("Legacy/Services/ImportPipeline.swift", "CP3"),
    ("Legacy/Services/IngestOrchestrator.swift", "CP3"),
    ("Legacy/Services/CatalogAgent.swift", "CP3"),
    ("Legacy/Services/PhotoAgentOrchestrator.swift", "CP3"),
    ("Legacy/Views/ImportLoadingView.swift", "CP3"),
    ("Legacy/Services/XMPDevelopParser.swift", "CP2"),
    # --- legacy: cull + taste/tier stack (D40 explicit CP4 retirement) ---
    ("Legacy/Services/CullEngine.swift", "CP4"),
    ("Legacy/Services/PeerCullEngine.swift", "CP4"),
    ("Legacy/Services/PhotoScorer.swift", "CP4"),
    ("Legacy/Services/QualityScorer.swift", "CP4"),
    ("Legacy/Services/FaceDetector.swift", "CP4"),
    ("Legacy/Services/BlurScorer.swift", "CP4"),
    ("Legacy/Services/TasteIndex.swift", "CP4"),
    ("Legacy/Services/TasteProfileDescription.swift", "CP4"),
    ("Legacy/Services/FeedbackStore.swift", "CP4"),
    ("Legacy/Services/VisionAssist.swift", "CP6"),
    # --- legacy: browse / cull surfaces ---
    ("Legacy/Views/SpeedBrowseViewer.swift", "CP4"),
    ("Legacy/Views/PhotoGridView.swift", "CP4"),
    ("Legacy/Views/PhotoImageView.swift", "CP4"),
    ("Legacy/Views/ProgressivePhotoWall.swift", "CP4"),
    ("Legacy/Views/GridOverviewView.swift", "CP4"),
    ("Legacy/Views/CompareAndSoftViews.swift", "CP4"),
    ("Legacy/Views/UncertainAndClusterViews.swift", "CP4"),
    ("Legacy/Core/TablePhotographSelection.swift", "CP4"),
    ("Legacy/Views/Workspace/TableRubberBandOverlay.swift", "CP4"),
    ("Legacy/Views/Workspace/TableTileFramePreference.swift", "CP4"),
    # --- legacy: rail / treatment surfaces ---
    ("Legacy/Views/Workspace/ContextualTreatmentStrip.swift", "CP5"),
    ("Legacy/Views/Workspace/TreatmentFamilyRow.swift", "CP5"),
    ("Legacy/Views/Workspace/TreatmentStageView.swift", "CP5"),
    ("Legacy/Views/Components/WorkspaceCommandBar.swift", "CP5"),
    ("Legacy/Views/Components/WorkspaceChrome.swift", "CP5"),
    ("Legacy/Views/Components/GradedPhotoView.swift", "CP5"),
    ("Legacy/Views/Components/FloatingDecisionShelf.swift", "CP5"),
    # --- legacy: focused edit ---
    ("Legacy/Views/Components/LiveDevelopView.swift", "CP6"),
    ("Legacy/Views/Workspace/FocusOverlayView.swift", "CP6"),
    # --- legacy: propagation / lanes ---
    ("Legacy/Views/Workspace/DockedAdaptChipView.swift", "CP7"),
    ("Legacy/Views/Workspace/EmergingSetRail.swift", "CP7"),
    ("Legacy/Views/Components/SwimLaneContainer.swift", "CP7"),
    ("Legacy/Shell/WorkbenchSelection.swift", "CP7"),
    # --- legacy: open / export / endgame ---
    ("Legacy/Views/ExportPayoffSheet.swift", "CP8"),
    ("Legacy/Views/SpeedContractHUD.swift", "CP8"),
    ("Legacy/Views/Workspace/FinishView.swift", "CP8"),
    ("Legacy/Views/Workspace/HomeView.swift", "CP8"),
    ("Legacy/Views/Workspace/ShootSelectionView.swift", "CP8"),
    ("Legacy/Views/Workspace/StoryCanvasView.swift", "CP8"),
    ("Legacy/Views/Workspace/WorkbenchShelf.swift", "CP8"),
    ("Legacy/Views/Workspace/WorkbenchCapture.swift", "CP8"),
    # --- legacy: shell host (last to die) ---
    ("Legacy/Views/Workspace/ContinuousWorkspaceView.swift", "CP8"),
    ("Legacy/Views/Workspace/CommandHandlingModifier.swift", "CP8"),
    ("Legacy/Views/UnifiedCanvasView.swift", "CP8"),
    ("Legacy/Shell/", "CP8"),
    ("Legacy/ContentView.swift", "CP8"),
    ("Legacy/ViewModels/", "CP8"),
    ("Legacy/Presentation/", "CP8"),
    # --- P0 live path, by owning surface ---
    ("Lumina/Views/P0/P0OpenView.swift", "CP8"),          # .alert -> facts-chip
    ("Lumina/Views/P0/P0ContactSheetView.swift", "CP4"),
    ("Lumina/Views/P0/ContactSheetCollection.swift", "CP1"),
    ("Lumina/Views/P0/P0RootView.swift", "CP4"),
    ("Lumina/Views/Components/", "CP5"),
    ("Lumina/Views/LuminaButtons.swift", "CP5"),
    ("Lumina/Views/LuminaAtmosphere.swift", "CP5"),
    ("Lumina/Views/MetalBrowseCanvas.swift", "CP1"),
    ("Lumina/Design/EditRailLayout.swift", "CP5"),
    ("Lumina/Design/TableLayout.swift", "CP1"),
    ("Lumina/Design/LuminaTokens.swift", "CP5"),
    ("Lumina/Design/CopyContract.swift", "CP5"),
    ("Lumina/Design/", "CP5"),
    ("Lumina/Develop/Lab/", "CP6"),
    ("Lumina/Develop/", "CP6"),
    ("Lumina/Services/", "CP3"),
    ("Lumina/Models/", "CP2"),
    ("Lumina/ViewModels/", "CP4"),
    ("Lumina/Core/", "CP7"),
    ("Lumina/Presentation/", "CP1"),
    ("Lumina/Rendering/", "CP1"),
    ("Lumina/Testing/", "CP0"),
    ("Lumina/Views/", "CP4"),
    ("DesignTokens/", "CP0"),
    ("Lumina/LuminaApp.swift", "CP8"),
]


def owner_for(rel: str) -> str | None:
    best = None
    for prefix, own in OWNERS:
        if rel.startswith(prefix) and (best is None or len(prefix) > len(best[0])):
            best = (prefix, own)
    return best[1] if best else None


def strip_comments(src: str) -> str:
    """Blank out comments so a banner or a doc note can never be a violation."""
    src = re.sub(r'/\*.*?\*/', lambda m: "\n" * m.group(0).count("\n"), src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    return src


def sources():
    for root in SOURCE_ROOTS:
        base = ROOT / root
        if not base.exists():
            continue
        for p in sorted(base.rglob("*.swift")):
            yield str(p.relative_to(ROOT)), strip_comments(p.read_text(encoding="utf-8",
                                                                      errors="replace"))


def scan() -> dict[tuple[str, str], int]:
    counts: dict[tuple[str, str], int] = {}
    for rel, code in sources():
        for pat in PATTERNS:
            if not pat.applies(rel):
                continue
            n = len(pat.regex.findall(code))
            if n:
                counts[(rel, pat.pid)] = n
    return counts


def load_baseline() -> dict[tuple[str, str], tuple[int, str]]:
    out = {}
    if not BASELINE.exists():
        return out
    for line in BASELINE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            print(f"FAIL: malformed baseline row: {line}", file=sys.stderr)
            sys.exit(1)
        rel, pid, count, own = parts
        out[(rel, pid)] = (int(count), own)
    return out


def write_baseline(counts, zero_ids):
    rows = []
    unowned = []
    for (rel, pid), n in sorted(counts.items()):
        if pid in zero_ids:
            continue
        own = owner_for(rel)
        if not own:
            unowned.append(rel)
            continue
        rows.append((rel, pid, n, own))
    if unowned:
        print("FAIL: unowned debt — no checkpoint owner for:", file=sys.stderr)
        for u in sorted(set(unowned)):
            print(f"  {u}", file=sys.stderr)
        sys.exit(1)

    by_cluster = defaultdict(int)
    for _, pid, n, _ in rows:
        by_cluster[pid] += n
    total = sum(n for _, _, n, _ in rows)
    files = len({r for r, _, _, _ in rows})

    head = [
        "# Banned-pattern RATCHET baseline — Checkpoint CQ (quarantine & repo cleanup).",
        "# Generated by Scripts/lint/ratchet.py --generate. Counts may only DECREASE.",
        "#",
        "# Pre-existing debt is neither fixed nor silenced here: it is counted, owned by",
        "# a step of design/checkpoint-sequence-v6.md, and ratcheted. Each migration",
        "# deletes its slice and shrinks this file.",
        "#",
        f"# {total} violations baselined across {files} files, all owned.",
        "#",
        "# cluster totals:",
    ]
    for pid in sorted(by_cluster):
        law = next(p.law for p in PATTERNS if p.pid == pid)
        head.append(f"#   {pid:<20} {by_cluster[pid]:>4}   {law}")
    head += [
        "#",
        "# file\tpattern\tcount\towner",
    ]
    BASELINE.parent.mkdir(parents=True, exist_ok=True)
    BASELINE.write_text("\n".join(head) + "\n" +
                        "\n".join(f"{r}\t{p}\t{n}\t{o}" for r, p, n, o in rows) + "\n",
                        encoding="utf-8")
    print(f"baseline written: {total} violations across {files} files, all owned")
    for pid in sorted(by_cluster):
        print(f"  {pid:<20} {by_cluster[pid]:>4}")


def check(counts, base) -> int:
    fails, slack = [], []
    zero_ids = {p.pid for p in PATTERNS if p.zero_tolerance}
    laws = {p.pid: p.law for p in PATTERNS}

    for (rel, pid), n in sorted(counts.items()):
        if pid in zero_ids:
            fails.append(f"{rel}: {n}x {pid} — {laws[pid]} (zero tolerance)")
            continue
        if (rel, pid) not in base:
            fails.append(f"{rel}: {n}x {pid} — {laws[pid]} "
                         f"(NEW: not in baseline; new debt or new file)")
            continue
        allowed, own = base[(rel, pid)]
        if not own:
            fails.append(f"{rel}: {pid} baselined without an owner")
        elif n > allowed:
            fails.append(f"{rel}: {n}x {pid} exceeds baseline {allowed} "
                         f"— {laws[pid]} (owner {own})")
        elif n < allowed:
            slack.append(f"{rel}: {pid} {allowed} -> {n} (owner {own})")

    for (rel, pid), (allowed, own) in sorted(base.items()):
        if not own:
            fails.append(f"{rel}: {pid} baselined without an owner")
        elif (rel, pid) not in counts and allowed:
            slack.append(f"{rel}: {pid} {allowed} -> 0 (owner {own}) — cleared")

    if slack:
        print(f"ratchet: {len(slack)} baseline rows now sit below baseline "
              f"(run --tighten to reap):")
        for s in slack[:20]:
            print(f"  {s}")
        if len(slack) > 20:
            print(f"  ... and {len(slack) - 20} more")

    if fails:
        print("", file=sys.stderr)
        for f in fails:
            print(f"FAIL: {f}", file=sys.stderr)
        print(f"\n{len(fails)} ratchet violation(s). Counts may only decrease; "
              f"new files must be clean.", file=sys.stderr)
        return 1

    total = sum(n for (_, p), n in counts.items() if p not in zero_ids)
    print(f"ratchet.py: OK — {total} baselined violations, none new, none grown")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--generate", action="store_true", help="write the baseline")
    ap.add_argument("--tighten", action="store_true", help="lower baseline to reality")
    args = ap.parse_args()

    counts = scan()
    zero_ids = {p.pid for p in PATTERNS if p.zero_tolerance}

    if args.generate or args.tighten:
        offenders = [(r, p, n) for (r, p), n in sorted(counts.items()) if p in zero_ids]
        if offenders:
            for r, p, n in offenders:
                print(f"FAIL: {r}: {n}x {p} — zero-tolerance pattern cannot be "
                      f"baselined", file=sys.stderr)
            return 1
        write_baseline(counts, zero_ids)
        return 0

    return check(counts, load_baseline())


if __name__ == "__main__":
    sys.exit(main())
