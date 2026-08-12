#!/usr/bin/env python3
"""STUB (F2): Python grammar oracle for Probe v2 assert shape — NOT the live driver.

owned-by-CP4 — Swift-on-macOS event driver + probe client are REQUIRED for
app-coupled grammar (FULL). This module is orchestration-only: schema/oracle
unit tests under FAST. It must never be reported as an app-coupled PASS.

Real transport: Lumina/Testing/ProbeV2/StateProbeV2.swift (DEBUG, loopback).
"""
from __future__ import annotations

import copy
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


def blank_state(fixture: str, seed: int, n: int = 8) -> dict[str, Any]:
    records = [{"id": f"a{i:03d}", "row": i // 4, "scene": 0, "availability": "online"} for i in range(n)]
    marks = {r["id"]: "undecided" for r in records}
    rungs = {r["id"]: "preview" for r in records}
    return {
        "schemaVersion": 2,
        "tsMs": 0,
        "generation": {"records": 1, "marks": 1, "staging": 1, "focus": 1, "layout": 1},
        "records": records,
        "marks": marks,
        "staging": {
            "active": False,
            "ring": "none",
            "scopeCount": 0,
            "excludedCount": 0,
            "bannerCount": 0,
            "headerCount": 0,
            "receiptCount": 0,
            "returnReleaseArmed": False,
            "recipeKind": None,
        },
        "focus": {"assetId": records[0]["id"], "visible": True, "armedControl": None},
        "residentRungByFrame": rungs,
        "undoDepth": 0,
        "exportKeptCount": 0,
        "chipPresent": True,
        "fixture": fixture,
        "seed": str(seed),
        "fakeClockMs": 0,
    }


@dataclass
class ProbeSimulator:
    state: dict[str, Any]
    pre_stage_snapshot: dict[str, Any] | None = None
    _return_held_after_shift: bool = False
    _gate_was_armed: bool = False
    _undo: list[dict[str, Any]] = field(default_factory=list)
    journal: list[dict[str, Any]] = field(default_factory=list)

    @classmethod
    def from_script(cls, script: dict[str, Any]) -> "ProbeSimulator":
        return cls(state=blank_state(script.get("fixture", "mixed-60"), int(script.get("seed", 0))))

    def focus_index(self) -> int:
        fid = self.state["focus"]["assetId"]
        ids = [r["id"] for r in self.state["records"]]
        return ids.index(fid) if fid in ids else 0

    def set_focus_index(self, index: int) -> None:
        ids = [r["id"] for r in self.state["records"]]
        index = max(0, min(index, len(ids) - 1))
        self.state["focus"]["assetId"] = ids[index]
        self.state["focus"]["visible"] = True
        self.state["generation"]["focus"] += 1

    def _push_undo(self) -> None:
        self._undo.append(copy.deepcopy(self.state))
        self.state["undoDepth"] = len(self._undo)

    def _bump(self, *keys: str) -> None:
        for key in keys:
            self.state["generation"][key] += 1
        self.state["tsMs"] = int(self.state.get("fakeClockMs") or 0)

    def apply_event(self, event: dict[str, Any]) -> None:
        t_ms = int(event["tMs"])
        self.state["fakeClockMs"] = t_ms
        self.state["tsMs"] = t_ms
        op = event["op"]
        if op == "wait":
            # Sugar: timeline advance is encoded in tMs (= prior tMs + ms); no separate op body.
            return
        if op == "waitProbe":
            return
        if op == "focusIndex":
            self.set_focus_index(int(event["index"]))
            return
        if op == "armControl":
            self.state["focus"]["armedControl"] = event["control"]
            self._bump("focus")
            return
        if op in {"pointerDown", "pointerUp", "pointerTap"}:
            # Pointer targets are logical ids — never coordinates.
            return
        if op in {"key", "keyDown", "keyUp"}:
            self._apply_key(op, event)
            return
        raise ValueError(f"unknown event op: {op}")

    def _apply_key(self, op: str, event: dict[str, Any]) -> None:
        key = event.get("key") or ""
        mods = set(event.get("modifiers") or [])
        if op == "keyDown" and key == "Return" and "shift" in mods:
            self._stage_row()
            self._return_held_after_shift = True
            self.state["staging"]["returnReleaseArmed"] = False
            return
        if op == "keyUp" and key == "Return":
            if self._return_held_after_shift or self.state["staging"]["active"]:
                self.state["staging"]["returnReleaseArmed"] = True
                self._gate_was_armed = True
                self._return_held_after_shift = False
            return
        if op == "keyDown" and key == "Return" and "shift" not in mods:
            # keyDown never commits — release gate + separate key/up path (D60 / D13).
            return
        if op != "key":
            return
        if key == "P":
            self._mark_toggle("keep")
        elif key == "X":
            self._mark_toggle("reject")
        elif key == "Return" and "shift" in mods:
            self._stage_row()
            self.state["staging"]["returnReleaseArmed"] = True
        elif key == "Return":
            if self.state["staging"]["active"]:
                if not self.state["staging"]["returnReleaseArmed"]:
                    return
                self._commit_stage()
            else:
                # Enter edit — no recipe mutation yet.
                self.state["focus"]["armedControl"] = None
                self._bump("focus")
        elif key == "Escape":
            self._esc()
        elif key == "Tab":
            # Arm first control as consent (D24) — no recipe write.
            if self.state["focus"].get("armedControl") is None:
                self.state["focus"]["armedControl"] = "Exposure"
                self._bump("focus")

    def _mark_toggle(self, mark: str) -> None:
        self._push_undo()
        idx = self.focus_index()
        asset = self.state["records"][idx]["id"]
        cur = self.state["marks"][asset]
        self.state["marks"][asset] = "undecided" if cur == mark else mark
        self._bump("marks")
        # Advance on set (not on clear) — same-mark-clears stays in place (D59).
        if self.state["marks"][asset] != "undecided":
            self.set_focus_index(idx + 1)

    def _stage_row(self) -> None:
        if self.pre_stage_snapshot is None:
            self.pre_stage_snapshot = copy.deepcopy(self.state)
        kept = [r["id"] for r in self.state["records"] if self.state["marks"][r["id"]] == "keep"]
        # Row scope: keep marks in focused row; if none, scope=1 on focus.
        focus_row = self.state["records"][self.focus_index()]["row"]
        scope = [rid for rid in kept if self._row_of(rid) == focus_row]
        if not scope:
            scope = [self.state["focus"]["assetId"]]
        st = self.state["staging"]
        st["active"] = True
        st["ring"] = "row"
        st["scopeCount"] = len(scope)
        st["excludedCount"] = 0
        st["bannerCount"] = st["scopeCount"]
        st["headerCount"] = st["scopeCount"]
        st["receiptCount"] = st["scopeCount"]
        st["recipeKind"] = "adapt"
        st["returnReleaseArmed"] = False
        self._bump("staging")

    def _row_of(self, asset_id: str) -> int:
        for r in self.state["records"]:
            if r["id"] == asset_id:
                return int(r["row"])
        return 0

    def _commit_stage(self) -> None:
        self._push_undo()
        st = self.state["staging"]
        st["active"] = False
        st["ring"] = "none"
        st["returnReleaseArmed"] = False
        st["recipeKind"] = None
        # Count invariant collapses to zero when idle.
        st["scopeCount"] = st["bannerCount"] = st["headerCount"] = st["receiptCount"] = 0
        self.pre_stage_snapshot = None
        self._bump("staging", "marks")

    def _esc(self) -> None:
        if self.state["staging"]["active"] and self.pre_stage_snapshot is not None:
            # Exact restore of pre-stage space (marks from before stage preserved).
            marks = copy.deepcopy(self.pre_stage_snapshot["marks"])
            focus = copy.deepcopy(self.pre_stage_snapshot["focus"])
            self.state["staging"] = copy.deepcopy(self.pre_stage_snapshot["staging"])
            self.state["marks"] = marks
            self.state["focus"] = focus
            self.pre_stage_snapshot = None
            self._bump("staging", "focus", "marks")
            return
        self.state["focus"]["armedControl"] = None
        self._bump("focus")

    def run(self, script: dict[str, Any]) -> dict[str, Any]:
        for event in script["events"]:
            self.apply_event(event)
            self.journal.append({"event": event, "state": copy.deepcopy(self.state)})
        failures = []
        for assertion in script["asserts"]:
            err = self.check_assert(assertion)
            if err:
                failures.append(err)
        return {"ok": not failures, "failures": failures, "state": self.state}

    def check_assert(self, assertion: dict[str, Any]) -> str | None:
        op = assertion["op"]
        st = self.state
        if op == "markEquals":
            idx = int(assertion["assetIndex"])
            asset = st["records"][idx]["id"]
            actual = st["marks"][asset]
            expected = assertion["mark"]
            if actual != expected:
                return f"markEquals a[{idx}] expected {expected} got {actual}"
            return None
        if op == "focusIndex":
            if self.focus_index() != int(assertion["equals"]):
                return f"focusIndex expected {assertion['equals']} got {self.focus_index()}"
            return None
        if op == "probePath":
            actual = _path_get(st, assertion["path"])
            if actual != assertion["equals"]:
                return f"probePath {assertion['path']} expected {assertion['equals']!r} got {actual!r}"
            return None
        if op == "probeEquals":
            if st != assertion["equals"]:
                return "probeEquals mismatch"
            return None
        if op == "stagingRing":
            if st["staging"]["ring"] != assertion["ring"]:
                return f"stagingRing expected {assertion['ring']} got {st['staging']['ring']}"
            return None
        if op == "returnReleaseGate":
            if assertion.get("armed") and not self._gate_was_armed:
                return "returnReleaseGate expected armed before commit"
            return None
        if op == "exactRestore":
            if st["staging"]["active"]:
                return "exactRestore failed — still staged"
            if self.pre_stage_snapshot is not None:
                return "exactRestore failed — pre-stage snapshot retained"
            return None
        if op == "countInvariant":
            s = st["staging"]
            if s["active"]:
                if not (s["bannerCount"] == s["headerCount"] == s["receiptCount"] == s["scopeCount"]):
                    return (
                        "countInvariant banner/header/receipt/scope diverge: "
                        f"{s['bannerCount']}/{s['headerCount']}/{s['receiptCount']}/{s['scopeCount']}"
                    )
            return None
        if op == "undoEntries":
            if int(st.get("undoDepth") or 0) != int(assertion["entries"]):
                return f"undoEntries expected {assertion['entries']} got {st.get('undoDepth')}"
            return None
        if op == "chipAbsenceIffFullRung":
            for asset_id, rung in st["residentRungByFrame"].items():
                chip = rung != "full" and rung != "absent"
                # chipPresent is global readiness chip; per-frame absence is rung==full/absent.
                if rung == "full" and st.get("chipPresent") and len(st["residentRungByFrame"]) == 1:
                    return f"chip present at full rung for {asset_id}"
            return None
        if op == "armedConsent":
            if st["focus"].get("armedControl") != assertion.get("control"):
                return (
                    f"armedConsent expected {assertion.get('control')} "
                    f"got {st['focus'].get('armedControl')}"
                )
            if st["staging"]["active"]:
                return "armedConsent must not imply staging"
            return None
        return f"unknown assert op {op}"


def _path_get(obj: Any, path: str) -> Any:
    cur = obj
    for part in path.split("."):
        if isinstance(cur, dict):
            cur = cur[part]
        else:
            raise KeyError(path)
    return cur


def load_script(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))
