#!/usr/bin/env python3
"""Costume lint (W0 Gate 3) — the law that arrives with the hot loop.

Two clauses, one pass over the app sources.

CLAUSE 1 — costume, in shipped (non-DEBUG) UI code:
  * `Button(` wearing anything outside the named `Lumina*Style` set (including nothing at all,
    which is the system costume) — affordance drift.
  * `.onTapGesture` / `.gesture(TapGesture` on an undecorated `Text` / `Image` — a tap target
    with no visible affordance, and never a >=44pt one (D47 / `hit.minimum`).
  Existing violations live in `artifacts/harness/costume_allowlist.txt` under the E1 ratchet:
  debt may shrink, never grow. That count is the polish thread's backlog, not W0's to fix.

CLAUSE 2 — the workbench fence:
  W0 workbench symbols (Inject, the hot-reload shim, the launch-arg parser, the playground
  boot types) must appear only inside `#if DEBUG`. Release must contain none of it, and this
  proves it in the tree rather than in a binary.

Runs in well under the 1 s FAST budget (Gate 2.4 precedent) — a single read of ~156 files.
"""
from __future__ import annotations

import re
from collections import Counter
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "Lumina"
ALLOWLIST = ROOT / "artifacts" / "harness" / "costume_allowlist.txt"

# Directories that are DEBUG/harness-only by construction — not shipped UI.
EXCLUDED_DIRS = {"Testing", "Workbench"}

# ---------------------------------------------------------------------------
# Clause 2 — workbench symbols that may never appear outside #if DEBUG.
# Exact names only: the tree already has unrelated legacy "Workbench*" types
# (WorkbenchCapture, WorkbenchShelf, WorkbenchSelection) fenced by
# #if !LUMINA_SHIPPING_APP, and they are not this session's to police.
# ---------------------------------------------------------------------------
WORKBENCH_SYMBOLS = (
    "Inject",
    "enableInjection",
    "ObserveInjection",
    "InjectConfiguration",
    "workbenchHot",
    "workbenchBoot",
    "WorkbenchHotHost",
    "WorkbenchLaunch",
    "WorkbenchDeepLink",
    "WorkbenchBootPlan",
    "WorkbenchBootModifier",
)
WORKBENCH_RE = re.compile(r"\b(" + "|".join(WORKBENCH_SYMBOLS) + r")\b")

# A style is "named" when it is one of the project's own Lumina* styles.
NAMED_STYLE_RE = re.compile(r"^Lumina[A-Za-z0-9]*Style$")
BUTTON_STYLE_RE = re.compile(r"\.buttonStyle\(\s*([A-Za-z_][A-Za-z0-9_.]*)")
# A bare SwiftUI `Button(` only. `LuminaDecisionButton(` / `ratioButton(` are named wrappers —
# the pattern this lint wants people to use — and must not match on the substring.
BUTTON_CALL_RE = re.compile(r"(?<![A-Za-z0-9_])Button\s*\(")
# Contexts macOS renders itself, where a ButtonStyle is inert: menu-bar commands and
# `Menu { ... }` items. These are not affordance drift and can never be "fixed", so they are
# scoped out rather than parked in the allowlist — the debt count must mean something.
MENU_CONTEXT_RE = re.compile(r"\bMenu\s*[({]|\bCommandMenu\s*\(|\bCommandGroup\s*\(|\.commands\s*\{")
TAP_RE = re.compile(r"\.onTapGesture\b|\.gesture\(\s*TapGesture")
# Modifiers that give a Text/Image a real, visible, hittable body.
DECORATION_RE = re.compile(
    r"\.(background|padding|frame|contentShape|overlay|border|clipShape|buttonStyle"
    r"|accessibilityAddTraits|hitTestPadding|containerShape)\b"
)
BASE_TEXT_IMAGE_RE = re.compile(r"\b(Text|Image|Label)\s*\(")


def strip_debug_blocks(lines: list[str]) -> list[str | None]:
    """Blank out every `#if DEBUG` region (nesting-aware), keeping line numbering intact.

    `#if DEBUG` regions are shipped-invisible, so clause 1 must not judge them and clause 2
    requires symbols to live inside them. Returns a list where excluded lines are None.
    """
    out: list[str | None] = []
    # Stack of booleans: True when the enclosing conditional region is DEBUG-only.
    stack: list[bool] = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("#if"):
            condition = stripped[3:].strip()
            # `#if DEBUG`, `#if DEBUG && X` — anything that requires DEBUG to compile.
            is_debug = bool(re.match(r"^DEBUG\b", condition))
            stack.append(is_debug or any(stack))
            out.append(None)
            continue
        if stripped.startswith("#elseif") or stripped.startswith("#else"):
            if stack:
                # The #else of a DEBUG block is the shipped branch — stop excluding.
                enclosing = any(stack[:-1])
                stack[-1] = enclosing
            out.append(None)
            continue
        if stripped.startswith("#endif"):
            if stack:
                stack.pop()
            out.append(None)
            continue
        out.append(None if any(stack) else line)
    return out


def debt_key(finding: str) -> str:
    """`path:line text` -> `path text`.

    The register keeps line numbers so a human can find the code, but the ratchet compares
    without them: an unrelated edit higher up a file must not manufacture a violation. Counts
    still have to match exactly, so a genuinely NEW violation in an already-registered file
    is still caught.
    """
    location, _, text = finding.partition(" ")
    path = location.rsplit(":", 1)[0]
    return f"{path} {text}"


def load_allowlist() -> Counter[str]:
    if not ALLOWLIST.is_file():
        return Counter()
    entries: Counter[str] = Counter()
    for line in ALLOWLIST.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        entries[debt_key(stripped)] += 1
    return entries


def swift_sources() -> list[Path]:
    files = []
    for path in sorted(APP.rglob("*.swift")):
        if EXCLUDED_DIRS & set(path.relative_to(APP).parts[:-1]):
            continue
        files.append(path)
    return files


def button_indent(line: str) -> int:
    return len(line) - len(line.lstrip())


def in_menu_context(lines: list[str | None], index: int, indent: int) -> bool:
    """True when the nearest enclosing block is a menu-bar command or a `Menu { }`."""
    for back in range(index - 1, -1, -1):
        prior = lines[back]
        if prior is None:
            continue
        stripped = prior.strip()
        if not stripped:
            continue
        prior_indent = button_indent(prior)
        if prior_indent < indent:
            if MENU_CONTEXT_RE.search(stripped):
                return True
            # A `label:` trailing closure ends the menu's item list.
            if stripped.startswith("} label:"):
                return False
            indent = prior_indent
    return False


def scan_buttons(rel: str, lines: list[str | None]) -> list[str]:
    """A `Button(` must wear a named Lumina style somewhere in its modifier chain."""
    findings = []
    for index, line in enumerate(lines):
        if line is None or not BUTTON_CALL_RE.search(line):
            continue
        # Skip declarations/styles, not call sites.
        if re.search(r"\b(func|struct|class|enum)\b", line):
            continue
        indent = button_indent(line)
        if in_menu_context(lines, index, indent):
            continue
        styled = False
        # The modifier chain runs until the source dedents back past the Button.
        for follow in lines[index : index + 40]:
            if follow is None:
                continue
            if follow is not line:
                stripped = follow.strip()
                if stripped and button_indent(follow) < indent and not stripped.startswith("."):
                    break
            match = BUTTON_STYLE_RE.search(follow)
            if match:
                name = match.group(1).split(".")[-1]
                if NAMED_STYLE_RE.match(name):
                    styled = True
                break
        if not styled:
            findings.append(f"{rel}:{index + 1} Button without a named Lumina*Style")
    return findings


def scan_taps(rel: str, lines: list[str | None]) -> list[str]:
    """A tap gesture on an undecorated Text/Image/Label is an invisible affordance."""
    findings = []
    for index, line in enumerate(lines):
        if line is None or not TAP_RE.search(line):
            continue
        indent = button_indent(line)
        base = None
        decorated = False
        # Walk back up the modifier chain to the base expression.
        for back in range(index - 1, max(index - 25, -1), -1):
            prior = lines[back]
            if prior is None:
                continue
            stripped = prior.strip()
            if not stripped:
                continue
            if DECORATION_RE.search(stripped):
                decorated = True
                break
            if stripped.startswith("."):
                continue
            if button_indent(prior) <= indent:
                base = stripped
                break
        if decorated or base is None:
            continue
        if BASE_TEXT_IMAGE_RE.match(base):
            findings.append(f"{rel}:{index + 1} tap gesture on undecorated {base.split('(')[0]}")
    return findings


def scan_workbench_fence(rel: str, lines: list[str | None], raw: list[str]) -> list[str]:
    """Clause 2 — workbench symbols outside `#if DEBUG` are a Release leak."""
    findings = []
    for index, line in enumerate(lines):
        if line is None:
            continue
        # Comments describing the fence are not the fence being breached.
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("///"):
            continue
        match = WORKBENCH_RE.search(line)
        if match:
            findings.append(
                f"{rel}:{index + 1} workbench symbol '{match.group(1)}' outside #if DEBUG"
            )
    return findings


def main() -> int:
    allowlist = load_allowlist()
    costume: list[str] = []
    fence: list[str] = []

    for path in swift_sources():
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_text(encoding="utf-8").splitlines()
        shipped = strip_debug_blocks(raw)
        costume.extend(scan_buttons(rel, shipped))
        costume.extend(scan_taps(rel, shipped))
        fence.extend(scan_workbench_fence(rel, shipped, raw))

    # Clause 2 is absolute — no allowlist, no ratchet. A leak is a leak.
    if fence:
        for item in fence:
            print(f"FAIL: {item}", file=sys.stderr)
        print(
            f"costume_lint: {len(fence)} workbench fence violation(s) — "
            "every W0 symbol must sit inside #if DEBUG",
            file=sys.stderr,
        )
        return 1

    found = Counter(debt_key(item) for item in costume)
    failed = False

    over = found - allowlist
    if over:
        for item in costume:
            key = debt_key(item)
            if over.get(key):
                print(f"FAIL: {item}", file=sys.stderr)
                over[key] -= 1
        print(
            f"costume_lint: {sum((found - allowlist).values())} new costume violation(s); "
            f"{sum(allowlist.values())} registered. Add a named Lumina*Style, or give the tap "
            "target a body — do not grow artifacts/harness/costume_allowlist.txt.",
            file=sys.stderr,
        )
        failed = True

    # The ratchet only bites downward: a fixed violation must leave the register, or the
    # debt count lies about how much is left.
    stale = allowlist - found
    if stale:
        for key, count in sorted(stale.items()):
            print(
                f"FAIL: {count} stale register entr(y/ies) — already fixed: {key}",
                file=sys.stderr,
            )
        failed = True

    if failed:
        return 1

    print(
        f"costume_lint: OK — {sum(found.values())} registered costume debt, "
        "0 fence violations"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
