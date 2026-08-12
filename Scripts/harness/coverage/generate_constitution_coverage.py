#!/usr/bin/env python3
"""Generate constitution coverage matrix (F03.4 / F03.5).

Every D/R entry from contract-v5, contract-v6 headings, and R-* citations.
Cells are filled ONLY from artifact_registry.yaml — no inference.
Shelved-register rows → SHELVED. Battery column stays empty (F10 gated).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None

ROOT = Path(__file__).resolve().parents[3]
COVERAGE_DIR = ROOT / "artifacts" / "harness" / "coverage"
REGISTRY = Path(__file__).resolve().parent / "artifact_registry.yaml"
SHELVED = Path(__file__).resolve().parent / "shelved_register.yaml"
V5 = ROOT / "design" / "contract-v5.md"
V6 = ROOT / "design" / "contract-v6.md"
COLUMNS = ("lint", "logic", "flow", "golden", "battery", "not_covered")


def load_yaml(path: Path) -> dict[str, Any]:
    if yaml is None:
        raise RuntimeError("PyYAML required — install pyyaml")
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def parse_v5_decisions(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for match in re.finditer(r"^\*\*D(\d+)\.\s*(.+?)\*\*", text, re.MULTILINE):
        out[match.group(1)] = match.group(2).strip()
    return out


def parse_v6_decisions(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for match in re.finditer(r"^### D(\d+)[^\n]*", text, re.MULTILINE):
        key = match.group(1)
        heading = match.group(0)
        title = re.sub(r"^### D\d+\s*—\s*", "", heading)
        title = re.sub(r"\s*\(.*\)\s*$", "", title).strip()
        out[key] = title
    return out


def parse_r_citations(*texts: str) -> dict[str, str]:
    found: set[str] = set()
    for text in texts:
        for token in re.findall(r"R-[A-Z0-9.]+", text):
            found.add(token.rstrip("."))
    titles = {
        "R-5.1": "Chip copy in consequence language",
        "R-5.2": "Clipping hold grammar (Hold-J)",
        "R-5.3": "Settle-as-confirmation",
        "R-8.1": "⌥⌘E recipe re-entry",
        "R-9.1": "Diagnostics local-only or absent",
        "R-A.1": "Amateur pivot / Develop gate",
        "R-A.2": "Pointer path to culling (shelf → MVP)",
        "R-I.1": "Distribution Developer ID",
        "R-I.2": "Silent updates",
        "R-I.3": "Offline licensing",
        "R-M.1": "Rejects endgame / Trash offer",
        "R-M.2": "Device-plug ingestion",
        "R-M.3": "Sample shoot onboarding",
        "R-M.4": "Share sheet destination",
        "R-M.5": "Videos copied, counted, not shown",
        "R-Q.1": "90 px / PERSUADE",
        "R-X.1": "Hover deleted / value-echo at-rest",
        "R-X.2": "Layout quantized everywhere",
    }
    return {rid: titles.get(rid, rid) for rid in sorted(found)}


def build_entries() -> list[dict[str, Any]]:
    v5 = parse_v5_decisions(V5.read_text(encoding="utf-8"))
    v6 = parse_v6_decisions(V6.read_text(encoding="utf-8"))
    rs = parse_r_citations(V5.read_text(encoding="utf-8"), V6.read_text(encoding="utf-8"))
    registry = load_yaml(REGISTRY).get("entries") or {}
    shelved = load_yaml(SHELVED).get("entries") or {}

    entries: list[dict[str, Any]] = []
    for n in range(1, 67):
        key = str(n)
        sources: list[str] = []
        if key in v5:
            sources.append("v5")
        if key in v6:
            sources.append("v6")
        if not sources:
            continue
        title = v6.get(key) or v5.get(key) or f"D{key}"
        artifacts = registry.get(f"D{key}", registry.get(key, {}))
        entries.append(_compose_entry(f"D{key}", "D", title, sources, artifacts, shelved))

    for rid, title in rs.items():
        artifacts = registry.get(rid, {})
        entries.append(_compose_entry(rid, "R", title, ["v6"], artifacts, shelved))

    entries.sort(key=lambda e: (0 if e["kind"] == "D" else 1, _sort_key(e["id"])))
    return entries


def _sort_key(entry_id: str) -> tuple:
    if entry_id.startswith("D"):
        return (int(entry_id[1:]), "")
    return (999, entry_id)


def _compose_entry(
    entry_id: str,
    kind: str,
    title: str,
    sources: list[str],
    artifacts: dict[str, Any],
    shelved: dict[str, Any],
) -> dict[str, Any]:
    cols = {c: list(artifacts.get(c, []) or []) for c in COLUMNS if c != "not_covered"}
    cols["battery"] = []
    covered = any(cols[c] for c in ("lint", "logic", "flow", "golden"))
    shelf_meta = shelved.get(entry_id) or shelved.get(entry_id.replace("D", ""))
    if shelf_meta:
        status = "SHELVED"
        not_covered_cell = "SHELVED"
    elif covered:
        status = "COVERED"
        not_covered_cell = ""
    else:
        status = "NOT-COVERED"
        not_covered_cell = "NOT-COVERED"
    return {
        "id": entry_id,
        "kind": kind,
        "title": title,
        "sources": sources,
        "lint": cols["lint"],
        "logic": cols["logic"],
        "flow": cols["flow"],
        "golden": cols["golden"],
        "battery": cols["battery"],
        "not_covered": not_covered_cell,
        "status": status,
    }


def summarize(entries: list[dict[str, Any]]) -> dict[str, int]:
    return {
        "total": len(entries),
        "covered": sum(1 for e in entries if e["status"] == "COVERED"),
        "shelved": sum(1 for e in entries if e["status"] == "SHELVED"),
        "not_covered": sum(1 for e in entries if e["status"] == "NOT-COVERED"),
    }


def render_md(entries: list[dict[str, Any]], summary: dict[str, int]) -> str:
    lines = [
        "# Constitution coverage matrix",
        "",
        "Generated from `design/contract-v5.md`, `design/contract-v6.md`, and "
        "`Scripts/harness/coverage/artifact_registry.yaml`. "
        "Cells list **named artifacts only** — no adjacency inference. "
        "Battery column empty (F10 gated).",
        "",
        "## Summary",
        "",
        "| Total entries | Covered | Shelved | NOT-COVERED |",
        "|--------------:|--------:|--------:|------------:|",
        f"| {summary['total']} | {summary['covered']} | {summary['shelved']} | **{summary['not_covered']}** |",
        "",
        "> A low NOT-COVERED count would be suspicious; honest gaps are expected pre-CP1.",
        "",
        "## NOT-COVERED (printed)",
        "",
    ]
    not_cov = [e["id"] for e in entries if e["status"] == "NOT-COVERED"]
    if not_cov:
        lines.extend(f"- `{eid}`" for eid in not_cov)
    else:
        lines.append("- _(none)_")
    lines.extend(
        [
            "",
            "## Matrix",
            "",
            "| Entry | Title | lint | logic | flow | golden | battery | NOT-COVERED |",
            "|-------|-------|------|-------|------|--------|---------|-------------|",
        ]
    )
    for e in entries:
        lines.append(
            "| {id} | {title} | {lint} | {logic} | {flow} | {golden} | {battery} | {nc} |".format(
                id=e["id"],
                title=e["title"].replace("|", "\\|")[:72],
                lint=_cell(e["lint"]),
                logic=_cell(e["logic"]),
                flow=_cell(e["flow"]),
                golden=_cell(e["golden"]),
                battery=_cell(e["battery"]),
                nc=e["not_covered"],
            )
        )
    lines.append("")
    return "\n".join(lines)


def _cell(items: list[str]) -> str:
    return "<br>".join(f"`{x}`" for x in items) if items else ""


def write_outputs(entries: list[dict[str, Any]], summary: dict[str, int]) -> None:
    COVERAGE_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "schemaVersion": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": summary,
        "not_covered": [e["id"] for e in entries if e["status"] == "NOT-COVERED"],
        "shelved": [e["id"] for e in entries if e["status"] == "SHELVED"],
        "entries": entries,
    }
    (COVERAGE_DIR / "constitution-coverage.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8"
    )
    (COVERAGE_DIR / "constitution-coverage.md").write_text(
        render_md(entries, summary), encoding="utf-8"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Write coverage artifacts")
    parser.add_argument("--check", action="store_true", help="Verify committed artifacts are current")
    args = parser.parse_args(argv)

    entries = build_entries()
    summary = summarize(entries)
    not_cov = summary["not_covered"]

    print(
        f"constitution_coverage: total={summary['total']} covered={summary['covered']} "
        f"shelved={summary['shelved']} NOT-COVERED={not_cov}"
    )
    if not_cov:
        print("NOT-COVERED entries:")
        for eid in [e["id"] for e in entries if e["status"] == "NOT-COVERED"]:
            print(f"  - {eid}")

    if args.check:
        json_path = COVERAGE_DIR / "constitution-coverage.json"
        if not json_path.is_file():
            print(f"FAIL: missing {json_path.relative_to(ROOT)}", file=sys.stderr)
            return 1
        current = json.loads(json_path.read_text(encoding="utf-8"))
        if current.get("entries") != entries or current.get("summary") != summary:
            print("FAIL: constitution-coverage artifacts stale — run with --write", file=sys.stderr)
            return 1
        print("constitution_coverage --check: OK")
        return 0

    if args.write or (not args.write and not args.check):
        write_outputs(entries, summary)
        print(f"wrote {COVERAGE_DIR.relative_to(ROOT)}/constitution-coverage.{{md,json}}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
