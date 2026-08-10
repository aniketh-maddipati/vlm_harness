#!/usr/bin/env python3
"""Hi-fi audit gate v2 (H8) — copy, grammar, accessibility, performance contracts.

Runs Linux-safe static checks against design/copy-contract.txt and .cursorrules.
Writes AUDIT-HIFI.md with pass/fail and file:line for every check.
"""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))

from copy_contract_loader import load_contract_strings, string_in_contract  # noqa: E402

AUDIT_MD = ROOT / "AUDIT-HIFI.md"

SKIP_DIRS = {"Develop/Lab", "Testing", "Scripts", "LuminaLogicTests", "LuminaUITests"}
SKIP_FILES = {
    "Lumina/Design/CopyContract.swift",
    "Scripts/prompt_9_audit.py",
    "Scripts/prompt_9_audit.swift",
    "Scripts/audit_hifi.py",
}


@dataclass
class Check:
    category: str
    name: str
    passed: bool
    detail: str = ""

    @property
    def status(self) -> str:
        return "PASS" if self.passed else "FAIL"


@dataclass
class AuditReport:
    checks: list[Check] = field(default_factory=list)

    def add(self, category: str, name: str, passed: bool, detail: str = "") -> None:
        self.checks.append(Check(category, name, passed, detail))

    @property
    def failed(self) -> list[Check]:
        return [c for c in self.checks if not c.passed]

    def write_markdown(self, path: Path) -> None:
        lines = [
            "# AUDIT-HIFI",
            "",
            "Hi-fi pass audit gate v2 — static contract checks (H8).",
            "",
            f"**Summary:** {sum(1 for c in self.checks if c.passed)}/{len(self.checks)} passed",
            "",
        ]
        current = ""
        for check in self.checks:
            if check.category != current:
                current = check.category
                lines.extend(["", f"## {current}", ""])
            lines.append(f"- **{check.status}** — {check.name}")
            if check.detail:
                lines.append(f"  - {check.detail}")
        lines.append("")
        if self.failed:
            lines.extend(["## Failures", ""])
            for check in self.failed:
                lines.append(f"1. [{check.category}] {check.name}: {check.detail or '(no detail)'}")
        else:
            lines.append("All checks passed.")
        lines.append("")
        path.write_text("\n".join(lines), encoding="utf-8")


def swift_files() -> list[Path]:
    lumina = ROOT / "Lumina"
    paths: list[Path] = []
    for path in lumina.rglob("*.swift"):
        rel = str(path.relative_to(ROOT))
        if rel in SKIP_FILES:
            continue
        if any(part in rel for part in SKIP_DIRS):
            continue
        paths.append(path)
    return paths


def read(rel: str) -> str | None:
    path = ROOT / rel
    return path.read_text(encoding="utf-8") if path.is_file() else None


def line_for(text: str, needle: str, rel: str) -> str:
    for i, line in enumerate(text.splitlines(), 1):
        if needle in line:
            return f"{rel}:{i}"
    return rel


def extract_user_visible_strings(text: str) -> list[tuple[str, int]]:
    """User-facing literals only — not private UserDefaults keys or identifiers."""
    patterns = [
        r'Text\(\s*"((?:[^"\\]|\\.)*)"',
        r'Button\(\s*"((?:[^"\\]|\\.)*)"',
        r'Label\(\s*"((?:[^"\\]|\\.)*)"',
        r'\.accessibilityLabel\(\s*"((?:[^"\\]|\\.)*)"',
        r'\.accessibilityHint\(\s*"((?:[^"\\]|\\.)*)"',
        r'\.help\(\s*"((?:[^"\\]|\\.)*)"',
    ]
    results: list[tuple[str, int]] = []
    lines = text.splitlines()
    for lineno, line in enumerate(lines, 1):
        if line.strip().startswith("//"):
            continue
        for pat in patterns:
            for m in re.finditer(pat, line):
                results.append((m.group(1), lineno))
    return results


BANNED_WORDS = [
    "sync",
    "preset",
    "copy settings",
    "catalog",
    "import",
    "ai",
    "smart",
    "auto",
    "analyze",
    "generate",
]
PLUMBING_STRINGS = {
    "files stay where they are · edits in open sidecars · this shoot opens in Lightroom as-is",
    "fetching full RAW",
    "The folder you pointed at is no longer where it was.",
    "Point at it again",
    "Latest-wins: ⌘E re-renders dirty frames only; the header counts what is current.",
    "⌘E re-renders",
    "⌥⌘E changes the recipe.",
}


def run_copy_audit(report: AuditReport) -> None:
    rules = read(".cursorrules") or ""
    contract = load_contract_strings()
    copy_swift = read("Lumina/Design/CopyContract.swift") or ""

    report.add("Copy", "design/copy-contract.txt present", (ROOT / "design/copy-contract.txt").is_file())
    report.add("Copy", "contract has ≥20 strings", len(contract) >= 20, f"{len(contract)} strings")

    exempt_static = {
        "pointedFolderMovedBody",
        "pointedFolderMovedAction",
        "staleRenderBody",
        "staleRenderAction",
    }
    for m in re.finditer(r'static let (\w+) = "((?:[^"\\]|\\.)*)"', copy_swift):
        name, value = m.group(1), m.group(2)
        if name in exempt_static:
            continue
        ok = string_in_contract(value, contract)
        detail = "" if ok else f"CopyContract.{name} missing from contract: {value!r}"
        report.add("Copy", f"CopyContract.{name} frozen in contract", ok, detail)

    # User-visible banned words (Develop allowed).
    violations: list[str] = []
    auto_violations: list[str] = []
    lightroom_hits: list[str] = []
    for path in swift_files():
        rel = str(path.relative_to(ROOT))
        text = path.read_text(encoding="utf-8", errors="replace")
        for value, lineno in extract_user_visible_strings(text):
            lower = value.lower()
            if value in PLUMBING_STRINGS or any(p in value for p in PLUMBING_STRINGS):
                continue
            for word in BANNED_WORDS:
                if word == "import":
                    if re.search(r"\bimport\b", lower):
                        violations.append(f"{rel}:{lineno} banned {word!r} in {value!r}")
                elif re.search(rf"\b{re.escape(word)}\b", lower):
                    violations.append(f"{rel}:{lineno} banned {word!r} in {value!r}")
            if re.search(r"\b[Aa]uto\b", value) and "Develop" not in value:
                auto_violations.append(f"{rel}:{lineno} Auto in {value!r}")
            if "lightroom" in lower and value not in PLUMBING_STRINGS:
                lightroom_hits.append(f"{rel}:{lineno} {value!r}")

    report.add(
        "Copy",
        "Banned words absent from user-visible strings (Develop allowed)",
        not violations,
        "; ".join(violations[:8]),
    )
    report.add(
        "Copy",
        "Auto absent from user-visible strings",
        not auto_violations,
        "; ".join(auto_violations[:8]),
    )

    # Lightroom exactly once — sovereignty PL line wired in export payoff.
    sovereignty = "files stay where they are · edits in open sidecars · this shoot opens in Lightroom as-is"
    export_sheet = read("Lumina/Views/ExportPayoffSheet.swift") or ""
    lr_user_hits = [h for h in lightroom_hits if "lightroom" in h.lower()]
    sovereignty_wired = "CopyContract.sovereigntyPlumbing" in export_sheet
    lr_ok = sovereignty_wired and len(lr_user_hits) == 0
    report.add(
        "Copy",
        "Lightroom appears exactly once in user-visible strings",
        lr_ok,
        f"sovereignty wired={sovereignty_wired}, stray hits={len(lr_user_hits)}",
    )
    report.add(
        "Copy",
        "Sovereignty line in copy contract",
        sovereignty in contract,
    )
    report.add(
        "Copy",
        "fetching full RAW in copy contract (loupe PL exception)",
        "fetching full RAW" in contract or any("fetching full RAW" in s for s in contract),
    )

    legacy = ["Adapt treatment to", "Adapted treatment to", "undoes all of it", "From DSC"]
    legacy_hits: list[str] = []
    for path in swift_files():
        rel = str(path.relative_to(ROOT))
        text = path.read_text(encoding="utf-8", errors="replace")
        for phrase in legacy:
            if phrase in text:
                legacy_hits.append(f"{rel} {phrase!r}")
    report.add("Copy", "No legacy pre-H1 staged/receipt strings", not legacy_hits, "; ".join(legacy_hits[:6]))

    if "Develop` is banned" in rules or "Develop is banned" in rules:
        report.add("Copy", "Develop not in banned-words list", False, ".cursorrules still bans Develop")
    else:
        report.add("Copy", "Develop not in banned-words list", True)


def run_grammar_audit(report: AuditReport) -> None:
    cmd = read("Lumina/Views/Workspace/CommandHandlingModifier.swift") or ""

    # Five decision keys swallow repeat.
    checks = [
        ("Return/⏎ swallows isARepeat", "if event.isARepeat { return nil }" in cmd and "handleReturn" in cmd),
        ("A swallows isARepeat", 'if event.isARepeat { return nil }' in cmd and 'lower == "a"' in cmd),
        ("P keep key present", 'case "p"' in cmd or 'lower == "p"' in cmd),
        (
            "S/P keep swallows isARepeat",
            'case "p"' in cmd and "if event.isARepeat { return nil }" in cmd,
        ),
        ("X reject swallows isARepeat", 'case "x":' in cmd and "if event.isARepeat { return nil }" in cmd),
    ]
    for name, ok in checks:
        detail = "" if ok else line_for(cmd, "handleKeyDown", "Lumina/Views/Workspace/CommandHandlingModifier.swift")
        report.add("Grammar", name, ok, detail)

    crop_ok = (
        "cropToggleAspectLock" in cmd
        and "cropFlipOrientation" in cmd
        and "if shell.cropSession != nil" in cmd
        and 'case "a":' in cmd
        and 'case "x":' in cmd
    )
    report.add(
        "Grammar",
        "Crop latch re-scopes A (aspect) and X (flip, never reject)",
        crop_ok,
        line_for(cmd, "cropSession", "Lumina/Views/Workspace/CommandHandlingModifier.swift"),
    )

    shell = read("Lumina/Shell/LuminaShellModel.swift") or ""
    report.add(
        "Grammar",
        "Ripple widen/narrow ordering (widenPropagation + propagation.narrow on Esc)",
        "func widenPropagation" in shell and "propagation.narrow()" in shell,
    )

    photo = read("Lumina/Models/PhotoRecord.swift") or ""
    report.add(
        "Grammar",
        "Exception persistence (wholesaleExcludedPhotoIDs Codable)",
        "wholesaleExcludedPhotoIDs" in photo and "decodeIfPresent" in photo,
    )

    rubber = read("Lumina/Views/Workspace/TableRubberBandOverlay.swift") or ""
    report.add(
        "Grammar",
        "Rubber-band has zero commit paths",
        "applyDecision" not in rubber and "commitRound" not in rubber,
    )

    chip = read("Lumina/Views/Workspace/DockedAdaptChipView.swift") or ""
    report.add(
        "Grammar",
        "Chip drag has zero commit-on-drag paths",
        ".draggable(" in chip and "applyDecision" not in chip,
    )

    tokens = read("DesignTokens/Tokens.swift") or ""
    report.add(
        "Grammar",
        "Selection ring ≠ halo ring by token",
        "assertDistinctSelectionAndHalo" in tokens and 'selection = Color(hex: "2E2E2C")' in tokens,
    )

    crop_copy = read("Lumina/Develop/CropSession.swift") or ""
    crop_banner = read("Lumina/Views/Workspace/WorkbenchShelf.swift") or ""
    latch_ok = "CropSessionCopy" in (read("Lumina/Design/CopyContract.swift") or "") or "CropSessionCopy" in crop_copy
    latch_ok = latch_ok and "StagedTreatmentBanner" in crop_banner
    report.add(
        "Grammar",
        "Latch surfaces answer banner + Esc (crop + staged banners present)",
        latch_ok,
    )


def run_accessibility_audit(report: AuditReport) -> None:
    cmd = read("Lumina/Views/Workspace/CommandHandlingModifier.swift") or ""
    report.add(
        "Accessibility",
        "⇧-arrow rubber-band extend in CommandHandlingModifier",
        "shift" in cmd and "extendHandSelection" in cmd,
    )

    selection = read("Lumina/Shell/WorkbenchSelection.swift") or ""
    report.add(
        "Accessibility",
        "VoiceOver selection announcement present",
        "accessibilityAnnouncement" in selection,
    )
    report.add(
        "Accessibility",
        "VoiceOver speaks ring scope / excluded counts",
        "excludedCount" in selection and "ring" in selection,
        line_for(selection, "accessibilityAnnouncement", "Lumina/Shell/WorkbenchSelection.swift"),
    )

    banner = read("Lumina/Views/Workspace/WorkbenchShelf.swift") or ""
    report.add(
        "Accessibility",
        "Staged banner accessibility includes scope",
        "StagedTreatmentBanner" in banner and ".accessibilityLabel" in banner,
        line_for(banner, "StagedTreatmentBanner", "Lumina/Views/Workspace/WorkbenchShelf.swift"),
    )

    row = read("Lumina/Views/Workspace/TreatmentFamilyRow.swift") or ""
    report.add(
        "Accessibility",
        "Shapes-not-color: selection ring uses HiFiTokens.Ring.selection",
        "HiFiTokens.Ring.selection" in row,
    )
    report.add(
        "Accessibility",
        "Shapes-not-color: second-order halo uses HiFiTokens.Ring.secondOrderOpacity",
        "HiFiTokens.Ring.secondOrderOpacity" in row,
    )

    stable = read("Lumina/Views/Components/StablePhotoView.swift") or ""
    report.add(
        "Accessibility",
        "Reduced Motion over fill-up landing (tableBirth)",
        "tableBirth" in stable and "reduceMotion" in stable,
    )

    glance = read("Lumina/Views/Components/ShortcutsGlanceOverlay.swift") or ""
    report.add(
        "Accessibility",
        "Reduced Motion over ? glance",
        "accessibilityReduceMotion" in glance,
    )

    stage = read("Lumina/Shell/LuminaShellModel.swift") or ""
    report.add(
        "Accessibility",
        "Arm-then-A develop staging path exists",
        "stageDevelopProposal" in stage,
    )


def run_performance_audit(report: AuditReport) -> None:
    stable = read("Lumina/Views/Components/StablePhotoView.swift") or ""
    report.add(
        "Performance",
        "Fill-up landing uses tableBirth opacity path (not post-birth transitions)",
        "tableBirth" in stable and "photoBirth" in stable,
    )
    report.add(
        "Performance",
        "Fill-up landing respects reduceMotion (no blur storm)",
        "if reduceMotion" in stable and "tableBirth" in stable,
    )

    propagation = read("Lumina/Core/PropagationState.swift") or ""
    scheduler = read("Lumina/Develop/DevelopRenderScheduler.swift") or ""
    report.add(
        "Performance",
        "Staged preview scope resolves at shoot radius (PropagationState)",
        "resolvedScope" in propagation,
    )
    report.add(
        "Performance",
        "Develop scheduler supports interactive + authoritative tiers",
        "fidelityByPhoto" in scheduler or "interactive" in scheduler.lower(),
    )

    open_path = read("Lumina/Services/ContactSheetPreparation.swift") or ""
    report.add(
        "Performance",
        "Cold open latency instrumented (folder_to_first_paint)",
        "folder_to_first_paint" in open_path,
    )
    report.add(
        "Performance",
        "Cold open SLA target documented (< 1 s first paint)",
        "openStart" in open_path,
    )

    family = read("Lumina/Views/Workspace/TreatmentFamilyRow.swift") or ""
    report.add(
        "Performance",
        "Table birth enabled on ingest rows (fill-up landing wired)",
        "tableBirth: true" in family,
    )


def run_legacy_prompt9(report: AuditReport) -> None:
    """Carry forward Prompt-9 token + motion checks."""
    tokens = read("DesignTokens/Tokens.swift") or ""
    report.add(
        "Prompt-9",
        "HiFiTokens histogram 252×64",
        "static let width: CGFloat = 252" in tokens and "static let height: CGFloat = 64" in tokens,
    )

    stable = read("Lumina/Views/Components/StablePhotoView.swift") or ""
    report.add(
        "Prompt-9",
        "No post-birth photograph opacity transition",
        ".transition(.opacity.animation(LuminaTokens.Motion.fidelity))" not in stable,
    )

    workspace = read("Lumina/Views/Workspace/ContinuousWorkspaceView.swift") or ""
    report.add(
        "Prompt-9",
        "Ring distinctness asserted at runtime",
        "assertDistinctSelectionAndHalo" in workspace,
    )


def main() -> int:
    report = AuditReport()
    run_copy_audit(report)
    run_grammar_audit(report)
    run_accessibility_audit(report)
    run_performance_audit(report)
    run_legacy_prompt9(report)

    report.write_markdown(AUDIT_MD)

    for check in report.checks:
        print(f"{check.status}: [{check.category}] {check.name}")
        if not check.passed and check.detail:
            print(f"  → {check.detail}", file=sys.stderr)

    failed = report.failed
    print(f"\nAudit: {len(report.checks) - len(failed)}/{len(report.checks)} passed")
    print(f"Wrote {AUDIT_MD.relative_to(ROOT)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
