#!/usr/bin/env python3
"""Two-direction artifact registry staleness lint (S14 A2 / #7).

Forward: every registry lint/golden id resolves to a manifest test id; every
logic/flow symbol resolves to a real XCTest method in-tree.

Reverse: every FAST manifest orchestration id and every logic/flow test method
either appears in the registry or is printed as unregistered (report-only).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "Scripts" / "harness" / "lanes" / "manifests.json"
REGISTRY = ROOT / "Scripts" / "harness" / "coverage" / "artifact_registry.yaml"


def _manifest_ids() -> set[str]:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    return {t["id"] for lane in data["lanes"].values() for t in lane["tests"]}


def _fast_manifest_ids() -> set[str]:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    return {t["id"] for t in data["lanes"]["fast"]["tests"]}


def _logic_symbols() -> set[str]:
    out: set[str] = set()
    logic_dir = ROOT / "LuminaLogicTests"
    if not logic_dir.is_dir():
        return out
    for path in logic_dir.rglob("*Tests.swift"):
        text = path.read_text(encoding="utf-8")
        cls = re.search(r"class (\w+)", text)
        if not cls:
            continue
        for match in re.finditer(r"func (test\w+)", text):
            out.add(f"{cls.group(1)}.{match.group(1)}")
    return out


def _flow_symbols() -> set[str]:
    out: set[str] = set()
    ui_dir = ROOT / "LuminaUITests"
    if not ui_dir.is_dir():
        return out
    for path in ui_dir.rglob("*Tests.swift"):
        text = path.read_text(encoding="utf-8")
        cls = re.search(r"class (\w+)", text)
        if not cls:
            continue
        for match in re.finditer(r"func (test\w+)", text):
            out.add(f"{cls.group(1)}.{match.group(1)}")
    return out


def _registry_refs() -> tuple[set[str], set[str], set[str], set[str]]:
    if yaml is None:
        raise RuntimeError("PyYAML required")
    reg = yaml.safe_load(REGISTRY.read_text(encoding="utf-8")) or {}
    lint_refs: set[str] = set()
    logic_refs: set[str] = set()
    flow_refs: set[str] = set()
    golden_refs: set[str] = set()
    for arts in (reg.get("entries") or {}).values():
        lint_refs.update(arts.get("lint") or [])
        logic_refs.update(arts.get("logic") or [])
        flow_refs.update(arts.get("flow") or [])
        golden_refs.update(arts.get("golden") or [])
    return lint_refs, logic_refs, flow_refs, golden_refs


def main() -> int:
    manifest_ids = _manifest_ids()
    fast_ids = _fast_manifest_ids()
    logic = _logic_symbols()
    flow = _flow_symbols()
    lint_refs, logic_refs, flow_refs, golden_refs = _registry_refs()

    failures: list[str] = []

    for ref in sorted(lint_refs | golden_refs):
        if ref not in manifest_ids:
            failures.append(f"registry lint/golden id does not resolve to manifest: {ref}")

    for ref in sorted(logic_refs):
        if ref not in logic:
            failures.append(f"registry logic symbol missing from tree: {ref}")

    for ref in sorted(flow_refs):
        if ref not in flow:
            failures.append(f"registry flow symbol missing from tree: {ref}")

    registry_lint_golden = lint_refs | golden_refs
    unregistered_fast = sorted(fast_ids - registry_lint_golden)
    unregistered_logic = sorted(logic - logic_refs)
    unregistered_flow = sorted(flow - flow_refs)

    print(
        f"registry_staleness: manifest={len(manifest_ids)} fast={len(fast_ids)} "
        f"registry_lint={len(lint_refs)} registry_logic={len(logic_refs)} "
        f"registry_flow={len(flow_refs)}"
    )

    if unregistered_fast:
        print(f"unregistered FAST manifest ids ({len(unregistered_fast)}):")
        for item in unregistered_fast:
            print(f"  - {item}")

    if unregistered_logic:
        print(f"unregistered logic tests ({len(unregistered_logic)}):")
        for item in unregistered_logic:
            print(f"  - {item}")

    if unregistered_flow:
        print(f"unregistered flow tests ({len(unregistered_flow)}):")
        for item in unregistered_flow:
            print(f"  - {item}")

    if failures:
        print("FAIL: unresolved registry references:", file=sys.stderr)
        for msg in failures:
            print(f"  - {msg}", file=sys.stderr)
        return 1

    print("registry_staleness: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
