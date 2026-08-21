"""Shared parsers for P0 state-probe contract lints (F03)."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[3]

PROBE_MIRROR_SITES: dict[str, Path] = {
    "app": ROOT / "Lumina/Testing/UITestStateProbe.swift",
    "ui_test": ROOT / "LuminaUITests/Support/ProbeSnapshot.swift",
    "robot": ROOT / "LuminaUITests/Robots/LuminaRobot.swift",
    "logic": ROOT / "LuminaLogicTests/P0LogicTests.swift",
}

PROBE_GROWTH_PATHS = (
    ROOT / "Lumina/Testing/UITestStateProbe.swift",
    ROOT / "LuminaUITests/Support/ProbeSnapshot.swift",
)

P0_VIEW_DIR = ROOT / "Lumina/Views/P0"
ROUTE_WATCH_FILES = (
    ROOT / "Lumina/ViewModels/P0SessionModel.swift",
    ROOT / "Lumina/Views/P0/P0RootView.swift",
    ROOT / "Lumina/Testing/UITestStateProbe.swift",
)

FIELD_RE = re.compile(r"^\s*var\s+(\w+):\s+([^/\n]+)")
INIT_FIELD_RE = re.compile(r"(\w+)\s*:")
ROUTE_CASE_RE = re.compile(r"^\+\s*case\s+\.(\w+)")


def git_diff_base() -> str:
    proc = subprocess.run(
        ["git", "rev-parse", "--verify", "origin/main"],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        return "origin/main"
    return "HEAD"


def git_diff_name_only(base: str | None = None) -> list[str]:
    base = base or git_diff_base()
    proc = subprocess.run(
        ["git", "diff", "--name-only", base],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return []
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def git_diff_patch(base: str | None = None, path: str | Path | None = None) -> str:
    base = base or git_diff_base()
    argv = ["git", "diff", base]
    if path is not None:
        argv.extend(["--", str(path)])
    proc = subprocess.run(argv, cwd=str(ROOT), capture_output=True, text=True)
    return proc.stdout if proc.returncode == 0 else ""


def normalize_swift_type(raw: str) -> str:
    typ = raw.strip().rstrip(",")
    typ = typ.split("//", 1)[0].strip()
    typ = re.sub(r"\s+", " ", typ)
    return typ


def parse_struct_fields(source: str, struct_name: str = "ProbeSnapshot") -> list[tuple[str, str]]:
    match = re.search(rf"struct\s+{re.escape(struct_name)}\b[^{{]*\{{", source)
    if not match:
        raise ValueError(f"struct {struct_name} not found")

    start = match.end()
    depth = 1
    end = start
    while end < len(source) and depth:
        ch = source[end]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        end += 1
    body = source[start : end - 1]

    fields: list[tuple[str, str]] = []
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if stripped.startswith("func ") or stripped.startswith("static "):
            continue
        fm = FIELD_RE.match(line)
        if fm:
            fields.append((fm.group(1), normalize_swift_type(fm.group(2))))
    return fields


def parse_probe_initializer_fields(source: str, marker: str) -> list[tuple[str, str]]:
    """Extract `name: value` pairs from a ProbeSnapshot( ... ) literal after marker."""
    idx = source.find(marker)
    if idx < 0:
        raise ValueError(f"marker not found: {marker}")
    open_paren = source.find("ProbeSnapshot(", idx)
    if open_paren < 0:
        raise ValueError("ProbeSnapshot( not found")

    depth = 0
    end = open_paren
    while end < len(source):
        ch = source[end]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                end += 1
                break
        end += 1
    literal = source[open_paren:end]
    fields: list[tuple[str, str]] = []
    for match in INIT_FIELD_RE.finditer(literal):
        name = match.group(1)
        if name == "ProbeSnapshot":
            continue
        fields.append((name, "init"))
    return fields


def compare_field_lists(
    canonical: list[tuple[str, str]],
    other: list[tuple[str, str]],
) -> list[str]:
    errors: list[str] = []
    canon_names = [n for n, _ in canonical]
    other_names = [n for n, _ in other]
    if canon_names != other_names:
        missing = [n for n in canon_names if n not in other_names]
        extra = [n for n in other_names if n not in canon_names]
        if missing:
            errors.append(f"missing fields: {', '.join(missing)}")
        if extra:
            errors.append(f"extra fields: {', '.join(extra)}")
        if not missing and not extra:
            errors.append(f"field order mismatch: expected {canon_names}, got {other_names}")
    for name, typ in canonical:
        other_map = dict(other)
        if name not in other_map:
            continue
        if other_map[name] != typ and other_map[name] != "init":
            errors.append(f"field `{name}` type `{other_map[name]}` != `{typ}`")
    return errors


def added_route_cases(base: str | None = None) -> list[str]:
    cases: list[str] = []
    for path in ROUTE_WATCH_FILES:
        patch = git_diff_patch(base, path.relative_to(ROOT))
        for line in patch.splitlines():
            m = ROUTE_CASE_RE.match(line)
            if m:
                cases.append(m.group(1))
    return cases


# W0: the hot-reload marker is DEBUG-only and adds no surface, no route and no observable
# state, so it cannot require a probe field. The exemption is deliberately as narrow as it can
# be — EVERY changed line in the file must be one of these — so any real surface edit riding
# alongside a workbench line still trips the gate.
WORKBENCH_FENCE_LINE_RE = re.compile(
    r"^\s*(#if\s+DEBUG|#endif|\.workbenchHot\(\)|\.workbenchBoot\([^)]*\))\s*$"
)


def _only_workbench_fence_changed(path: str) -> bool:
    """True when a file's whole diff is DEBUG-fenced workbench wiring."""
    patch = git_diff_patch(path=path)
    if not patch:
        return False
    changed = [
        line[1:]
        for line in patch.splitlines()
        if line[:1] in "+-" and not line.startswith(("+++", "---"))
    ]
    if not changed:
        return False
    return all(WORKBENCH_FENCE_LINE_RE.match(line) for line in changed)


def p0_view_surfaces_changed(changed: Iterable[str]) -> list[str]:
    surfaces: list[str] = []
    prefix = "Lumina/Views/P0/"
    for name in changed:
        if name.startswith(prefix):
            if _only_workbench_fence_changed(name):
                continue
            surfaces.append(name.removeprefix(prefix))
    return surfaces


def probe_types_changed(changed: Iterable[str]) -> bool:
    probe_rel = {p.relative_to(ROOT).as_posix() for p in PROBE_GROWTH_PATHS}
    return any(name in probe_rel for name in changed)


FORBIDDEN_CONTAINER_MEMBERS = (
    "openView",
    "contactSheet",
    "singlePhoto",
    "toolbar",
    "filmstrip",
)
FORBIDDEN_CONTAINER_ID_RE = re.compile(
    r"P0AccessibilityID\.(" + "|".join(FORBIDDEN_CONTAINER_MEMBERS) + r")(?![A-Za-z])"
)


def iter_swift_view_property_bodies(source: str) -> list[tuple[str, str, int]]:
    """Yield (name, body, line_offset) for each `var …: some View { … }` block."""
    pattern = re.compile(
        r"(?:private\s+)?var\s+(\w+)\s*:\s*some\s+View\s*\{",
        re.MULTILINE,
    )
    out: list[tuple[str, str, int]] = []
    for match in pattern.finditer(source):
        name = match.group(1)
        start = match.end()
        depth = 1
        end = start
        while end < len(source) and depth:
            ch = source[end]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
            end += 1
        line_offset = source[: match.start()].count("\n")
        out.append((name, source[start : end - 1], line_offset))
    return out


def swiftui_leaf_violations(source: str, rel_path: str) -> list[str]:
    violations: list[str] = []
    lines = source.splitlines()

    for idx, line in enumerate(lines):
        if ".accessibilityIdentifier(" not in line:
            continue
        match = FORBIDDEN_CONTAINER_ID_RE.search(line)
        if match:
            violations.append(
                f"{rel_path}:{idx + 1}: forbidden container identifier "
                f"`P0AccessibilityID.{match.group(1)}` on a view with identified children — "
                f"use probe route instead (postmortem §3.1)"
            )

    for prop_name, body, line_offset in iter_swift_view_property_bodies(source):
        if ".accessibilityIdentifier(" not in body:
            continue
        prop_lines = body.splitlines()
        id_line_idxs = [i for i, line in enumerate(prop_lines) if ".accessibilityIdentifier(" in line]
        if len(id_line_idxs) < 2:
            continue
        for idx, line in enumerate(prop_lines):
            if not re.search(r"^\s*\}\s*\.accessibilityIdentifier\(", line):
                continue
            inner = [j + line_offset + 1 for j in id_line_idxs if j < idx]
            if inner:
                violations.append(
                    f"{rel_path}:{idx + line_offset + 1}: `{prop_name}` "
                    f"`.accessibilityIdentifier` on container clobbers leaf ids at lines {inner} "
                    f"(postmortem §3.1)"
                )

    return violations


def appkit_duplicate_accessibility(source: str, rel_path: str) -> list[str]:
    """§3.4 — inner views must not remain accessibility elements beside a labeled cell."""
    violations: list[str] = []
    if "setAccessibilityIdentifier(" not in source:
        return violations

    blocks = re.split(r"\n\s*(?:func |override func )", source)
    for block in blocks:
        if "setAccessibilityIdentifier(" not in block:
            continue
        id_lines = [
            line.strip()
            for line in block.splitlines()
            if "setAccessibilityIdentifier(" in line
        ]
        false_lines = [
            line.strip()
            for line in block.splitlines()
            if "setAccessibilityElement(false)" in line
        ]
        if len(id_lines) > 1 and not false_lines:
            first_line_no = source[: source.find(block)].count("\n") + 1
            violations.append(
                f"{rel_path}:{first_line_no}: multiple setAccessibilityIdentifier calls "
                f"without setAccessibilityElement(false) on inner views (postmortem §3.4)"
            )
    return violations
