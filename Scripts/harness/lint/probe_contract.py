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


# ---------------------------------------------------------------------------
# Non-observable edit exemption (token routing + file-private renames).
#
# A lint fix that replaces a hand-typed literal with the token that already carries the
# same value, or renames a file-private symbol, adds no surface, no route and no observable
# state — so it cannot honestly require a probe field either. A regex over the diff would be
# too weak to prove that, so this exemption proves it by normalization instead:
#
#   * each side of the diff is resolved against ITS OWN version of the token tables — the
#     pre-image against `base`, the post-image against the working tree — so a token whose
#     VALUE moved in the same change resolves differently and trips the gate;
#   * numeric literals are canonicalized, so `220` and `220.0` compare equal;
#   * what remains must be identical token-for-token, up to a bijective rename of
#     identifiers that are `private` in this file and appear in no other tracked Swift file.
#
# Anything else — a property, a modifier, a reordered call, a changed value, a rename that
# reaches another file — leaves a residue and still trips the gate.
# ---------------------------------------------------------------------------

TOKEN_SOURCES = (
    "DesignTokens/HiFiTokens.generated.swift",
    "Lumina/Design/LuminaTokens.swift",
)
TOKEN_ROOTS = ("HiFiTokens", "LuminaTokens")
_ENUM_DECL_RE = re.compile(r"\benum\s+([A-Za-z_]\w*)\s*\{")
_STATIC_LET_RE = re.compile(r"^\s*static\s+(?:let|var)\s+([A-Za-z_]\w*)\s*(?::[^=]+)?=\s*(.+?)\s*$")
_TOKEN_REF_RE = re.compile(
    r"\b(?:" + "|".join(TOKEN_ROOTS) + r")(?:\.[A-Za-z_]\w*)+\b"
)
_NUMBER_RE = re.compile(r"\b\d+(?:\.\d+)?\b")
_ATOM_RE = re.compile(r'\d+(?:\.\d+)?|"[^"\\]*"|[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*')
_WORD_RE = re.compile(r"[A-Za-z_]\w*")
_LEXER_RE = re.compile(r"[A-Za-z_]\w*|\d+(?:\.\d+)?|\s+|.", re.DOTALL)
_PRIVATE_DECL_KINDS = "struct|enum|class|actor|protocol|typealias|func|var|let|case"


def git_show(rev: str, path: str) -> str | None:
    proc = subprocess.run(
        ["git", "show", f"{rev}:{path}"],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    return proc.stdout if proc.returncode == 0 else None


def _read_version(rev: str | None, path: str) -> str | None:
    """Working-tree text when rev is None, otherwise the blob at rev."""
    if rev is None:
        fs = ROOT / path
        return fs.read_text(encoding="utf-8") if fs.is_file() else None
    return git_show(rev, path)


def _strip_trailing_comment(text: str) -> str:
    """Drop a `//` trailer that is not inside a string literal."""
    idx = 0
    while True:
        idx = text.find("//", idx)
        if idx < 0:
            return text.strip()
        if text[:idx].count('"') % 2 == 0:
            return text[:idx].strip()
        idx += 2


def _token_table(rev: str | None) -> dict[str, str]:
    """Map `HiFiTokens.Layout.foo` → the literal text it generates, at one revision."""
    table: dict[str, str] = {}
    for rel in TOKEN_SOURCES:
        source = _read_version(rev, rel)
        if source is None:
            continue
        scope: list[str] = []
        depth = 0
        pending: list[tuple[int, str]] = []
        for line in source.splitlines():
            decl = _ENUM_DECL_RE.search(line)
            let = _STATIC_LET_RE.match(line)
            if let and scope:
                value = _strip_trailing_comment(let.group(2))
                if value:
                    table[".".join(scope) + "." + let.group(1)] = value
            opens = line.count("{")
            closes = line.count("}")
            if decl:
                pending.append((depth, decl.group(1)))
                scope.append(decl.group(1))
            depth += opens - closes
            while pending and depth <= pending[-1][0]:
                pending.pop()
                scope.pop()
    return table


def _resolve_tokens(source: str, table: dict[str, str]) -> str:
    """Substitute token references with their literal text, to a fixpoint.

    Only atoms — a number, a string literal, or a dotted identifier — are substituted.
    A compound right-hand side is left alone rather than spliced in without its
    parentheses, so no substitution can silently change an expression's meaning. An
    unresolved reference simply has to match the other side textually.
    """

    def sub(match: re.Match[str]) -> str:
        parts = match.group(0).split(".")
        for stop in range(len(parts), 1, -1):
            key = ".".join(parts[:stop])
            value = table.get(key)
            if value is not None and _ATOM_RE.fullmatch(value):
                return value + ".".join([""] + parts[stop:])
        return match.group(0)

    text = source
    for _ in range(8):
        nxt = _TOKEN_REF_RE.sub(sub, text)
        if nxt == text:
            break
        text = nxt
    return _NUMBER_RE.sub(lambda m: repr(float(m.group(0))), text)


def _lex(text: str) -> list[str]:
    return [" " if tok.isspace() else tok for tok in _LEXER_RE.findall(text)]


def _rename_map(before: list[str], after: list[str]) -> dict[str, str] | None:
    """Bijection old→new when the two token streams differ only at identifier slots."""
    if len(before) != len(after):
        return None
    forward: dict[str, str] = {}
    backward: dict[str, str] = {}
    for old, new in zip(before, after):
        if old == new:
            continue
        if not (_WORD_RE.fullmatch(old) and _WORD_RE.fullmatch(new)):
            return None
        if forward.setdefault(old, new) != new:
            return None
        if backward.setdefault(new, old) != old:
            return None
    return forward


def _symbol_is_file_local(rev: str | None, path: str, name: str, source: str) -> bool:
    """The symbol is declared `private` here and referenced in no other tracked Swift file."""
    if not re.search(rf"\bprivate\s+(?:{_PRIVATE_DECL_KINDS})\s+{re.escape(name)}\b", source):
        return False
    argv = ["git", "grep", "-l", "-w", name]
    if rev is not None:
        argv.append(rev)
    argv.extend(["--", "*.swift"])
    proc = subprocess.run(argv, cwd=str(ROOT), capture_output=True, text=True)
    if proc.returncode not in (0, 1):
        return False
    hits = set()
    for line in proc.stdout.splitlines():
        hit = line.strip()
        if not hit:
            continue
        if rev is not None and hit.startswith(f"{rev}:"):
            hit = hit[len(rev) + 1 :]
        hits.add(hit)
    hits.discard(path)
    return not hits


def _only_non_observable_changes(path: str, base: str | None = None) -> bool:
    """True when a file's whole diff provably renders the same thing it did before."""
    base = base or git_diff_base()
    before = git_show(base, path)
    after = _read_version(None, path)
    if before is None or after is None or before == after:
        return False

    lex_before = _lex(_resolve_tokens(before, _token_table(base)))
    lex_after = _lex(_resolve_tokens(after, _token_table(None)))
    renames = _rename_map(lex_before, lex_after)
    if renames is None:
        return False
    for old, new in renames.items():
        if not _symbol_is_file_local(base, path, old, before):
            return False
        if not _symbol_is_file_local(None, path, new, after):
            return False
    return True


def p0_view_surfaces_changed(changed: Iterable[str]) -> list[str]:
    surfaces: list[str] = []
    prefix = "Lumina/Views/P0/"
    for name in changed:
        if name.startswith(prefix):
            if _only_workbench_fence_changed(name):
                continue
            if _only_non_observable_changes(name):
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
