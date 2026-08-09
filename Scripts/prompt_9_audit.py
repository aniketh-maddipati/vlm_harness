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
print("Prompt-9 audit: all checks passed")
