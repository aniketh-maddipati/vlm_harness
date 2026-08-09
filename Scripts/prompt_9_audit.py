#!/usr/bin/env python3
"""Prompt-9 contract audit — banned-word scan + hi-fi ruling checks (Linux-safe)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def pass_(message: str) -> None:
    print(f"PASS: {message}")


def read(rel: str) -> str | None:
    path = ROOT / rel
    if not path.is_file():
        return None
    return path.read_text(encoding="utf-8")


# MARK: - .cursorrules contract

rules = read(".cursorrules")
if rules is None:
    fail(".cursorrules missing")

if "pdf is wrong" in rules.lower():
    fail(".cursorrules still contains deleted PDF-is-wrong ruling")
pass_("No PDF-is-wrong ruling in .cursorrules")

required_ruling_snippets = [
    "`P`, `X`, `⏎`, `⇧⏎`, `A`",
    "All five swallow key-repeat",
    "`design/hifi.pdf` is the visual authority",
    "`design/copy-contract.txt`",
    "Default scope = the row",
    "Each additional ⇧⏎ widens exactly one ring",
    "**Develop** is the sanctioned physical word",
    "multi-select (drag-box + ⇧-arrows)",
    "cross-row / shoot-wide propagation via the ⇧⏎ ripple",
    "the `?` shortcuts surface",
    "Still shelved, verbatim",
    "Ship the plain 1.5 pt halo",
    "brighter-ring fallback lives behind a debug flag only",
]
for snippet in required_ruling_snippets:
    if snippet not in rules:
        fail(f".cursorrules missing ruling snippet: {snippet}")
pass_(".cursorrules contains all H0 ruling deltas")

if "Develop` is banned" in rules or "Develop is banned" in rules:
    fail(".cursorrules still bans Develop in user-visible strings")
pass_("Develop removed from banned-words list")

# MARK: - No PDF-is-wrong in source

source_skip = {"Scripts/prompt_9_audit.swift", "Scripts/prompt_9_audit.py"}

for root_name in ["Lumina", "Scripts", "LuminaLogicTests", "LuminaUITests", "DesignTokens"]:
    root = ROOT / root_name
    if not root.exists():
        continue
    for path in root.rglob("*"):
        if path.suffix not in {".swift", ".md", ".sh", ".txt"}:
            continue
        rel = str(path.relative_to(ROOT))
        if rel in source_skip:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if "pdf is wrong" in text.lower():
            fail(f"Source file references deleted PDF-is-wrong ruling: {path}")

pass_("No source file references the deleted PDF-is-wrong ruling")

# MARK: - Banned words policy (.cursorrules is source of truth for H0)

banned_section = rules.split("### Banned words", 1)
if len(banned_section) < 2:
    fail(".cursorrules missing ### Banned words section")
banned_lower = banned_section[1].lower()
for word in ["sync", "preset", "copy settings", "catalog", "import", "ai", "smart", "auto", "analyze", "generate"]:
    if word not in banned_lower:
        fail(f".cursorrules banned-words section missing: {word}")
if "banned everywhere: develop" in banned_lower or "banned: develop" in banned_lower:
    fail(".cursorrules still lists Develop among banned words")
pass_("Banned-words policy matches hi-fi contract (Develop allowed)")

# MARK: - DesignTokens compile contract (static structure)

tokens = read("DesignTokens/Tokens.swift")
if tokens is None:
    fail("DesignTokens/Tokens.swift missing")

required_token_snippets = [
    "static let fill",
    "opacity: 0.07",
    "static let width: CGFloat = 252",
    "static let height: CGFloat = 64",
    "static let handleSize: CGFloat = 18",
    "static let minimumHit: CGFloat = 44",
    'static let selection = Color(hex: "2E2E2C")',
    "static let halo = Color(red: 255 / 255, green: 236 / 255, blue: 205 / 255)",
    "static let secondOrderOpacity: Double = 0.45",
    "static let grabDuration: TimeInterval = 0.100",
    "static let carryDuration: TimeInterval = 0.180",
    "static let placeDuration: TimeInterval = 0.140",
    "assert(selection != halo",
]
for snippet in required_token_snippets:
    if snippet not in tokens:
        fail(f"DesignTokens/Tokens.swift missing: {snippet}")

pass_("DesignTokens/Tokens.swift contains required hi-fi token contract")

# MARK: - Copy contract diff (H1)

sys.path.insert(0, str(ROOT / "Scripts"))
from copy_contract_loader import load_contract_strings, string_in_contract  # noqa: E402

contract_path = ROOT / "design" / "copy-contract.txt"
if not contract_path.is_file():
    fail("design/copy-contract.txt missing")
contract = load_contract_strings()
if len(contract) < 20:
    fail(f"copy-contract.txt looks truncated ({len(contract)} strings)")

copy_contract_swift = read("Lumina/Design/CopyContract.swift")
if copy_contract_swift is None:
    fail("Lumina/Design/CopyContract.swift missing")

# Static headline copy in CopyContract must appear verbatim in the contract.
static_literal = re.compile(r'static let \w+ = "((?:[^"\\]|\\.)*)"')
exempt_static = {
    "pointedFolderMovedBody",
    "pointedFolderMovedAction",
    "staleRenderBody",
    "staleRenderAction",
}
for match in re.finditer(r'static let (\w+) = "((?:[^"\\]|\\.)*)"', copy_contract_swift):
    name, value = match.group(1), match.group(2)
    if name in exempt_static:
        continue
    if not string_in_contract(value, contract):
        fail(f"CopyContract.{name} not in design/copy-contract.txt: {value!r}")

pass_("CopyContract static strings are frozen in design/copy-contract.txt")


def staged_header(scope: int, row: int, lane: str, excluded: int = 0, ring: str = "row") -> str:
    if excluded > 0:
        ring_label = f"row {row}" if ring == "row" else ring
        return f"STAGED · {ring_label} · {scope} selected · {excluded} excluded · ⏎ applies · Esc cancels"
    return (
        f"STAGED · row {row} · {lane} · {scope} selected · ⏎ applies · Esc cancels, nothing applied"
    )


def adapt_banner(scope: int, excluded: int = 0, ring: str = "row") -> str:
    if excluded > 0 and ring == "shoot":
        return f"Adapt → {scope} · {excluded} excluded ⏎ · ⇧⏎ shoot"
    if ring == "scene":
        return f"Adapt → {scope} ⏎ · ⇧⏎ scene · Esc"
    return f"Adapt → {scope} ⏎ · Esc"


formatter_samples = [
    staged_header(4, 4, "18:17"),
    staged_header(12, 4, "18:17", excluded=2, ring="scene"),
    adapt_banner(4),
    adapt_banner(12, excluded=2, ring="shoot"),
    f"Develop → 4 ⏎ · Esc",
    "Adapted → 4 · ⌘Z",
    "← 8288 · 4",
    "6/8 kept · 2 out · resume = first undecided frame",
]
for sample in formatter_samples:
    if sample not in contract:
        fail(f"Formatter sample missing from contract: {sample!r}")
pass_("Copy contract covers staged/receipt/header formatter samples")

legacy_banned = [
    "Adapt treatment to",
    "Adapted treatment to",
    "undoes all of it",
    "From DSC",
]
for root_name in ["Lumina"]:
    root = ROOT / root_name
    for path in root.rglob("*.swift"):
        rel = str(path.relative_to(ROOT))
        if rel == "Lumina/Design/CopyContract.swift":
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for phrase in legacy_banned:
            if phrase in text:
                fail(f"Legacy hi-fi copy still present ({phrase!r}) in {rel}")

pass_("No legacy pre-H1 staged/receipt strings in Lumina")

# Hi-fi surface literals outside CopyContract must not duplicate contract copy.
hifi_outside = re.compile(
    r'Text\(\s*"(STAGED ·|Adapt →|Adapted →|Develop →|← \d|nothing leaves this Mac|'
    r'file damaged — preview only|Pointed folder moved|Stale render)"'
)
for path in (ROOT / "Lumina").rglob("*.swift"):
    rel = str(path.relative_to(ROOT))
    if rel.endswith("CopyContract.swift"):
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    if hifi_outside.search(text):
        fail(f"Hardcoded hi-fi copy outside CopyContract.swift: {rel}")

pass_("Hi-fi copy surfaces route through CopyContract")

print("Prompt-9 audit: all checks passed")
