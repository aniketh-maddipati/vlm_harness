#!/usr/bin/env python3
"""Python mirror of Lumina/Core/CullGrammarMachine.swift for FAST parity (F02.5).

Foundation-only semantics: marks, focus, staging ring, arming, undo depth, holds.
Asset ids match ProbeSimulator blank_state (a000…). Must stay aligned with Swift.
"""
from __future__ import annotations

import copy
from dataclasses import dataclass
from typing import Any

from grammar_probe import extract_grammar
from simulator import blank_state

RAIL_CONTROLS = ["Exposure", "Contrast", "Highlights", "Shadows"]
DEFAULT_ARMED = "Exposure"


@dataclass
class GrammarMachine:
    state: dict[str, Any]
    pre_stage_snapshot: dict[str, Any] | None = None
    return_held_after_shift: bool = False

    @classmethod
    def from_script(cls, script: dict[str, Any], n: int = 8) -> GrammarMachine:
        return cls(state=blank_state(script.get("fixture", "mixed-60"), int(script.get("seed", 0)), n=n))

    @property
    def asset_ids(self) -> list[str]:
        return [r["id"] for r in self.state["records"]]

    @property
    def columns_per_row(self) -> int:
        return 4

    def focus_index(self) -> int:
        fid = self.state["focus"]["assetId"]
        ids = self.asset_ids
        return ids.index(fid) if fid in ids else 0

    def set_focus_index(self, index: int) -> None:
        ids = self.asset_ids
        if not ids:
            return
        index = max(0, min(index, len(ids) - 1))
        self.state["focus"]["assetId"] = ids[index]
        self.state["focus"]["visible"] = True

    def _sync_value_echo(self) -> None:
        armed = self.state["focus"].get("armedControl")
        adjusting = bool(self.state.get("adjusting"))
        self.state["valueEchoPresent"] = bool(armed and adjusting)

    def apply_script_event(self, event: dict[str, Any]) -> None:
        op = event["op"]
        if op == "focusIndex":
            self.set_focus_index(int(event["index"]))
            return
        if op == "armControl":
            self.state["focus"]["armedControl"] = event["control"]
            self._sync_value_echo()
            return
        if op in {"holdBegin", "holdEnd"}:
            self._apply_hold(op, event.get("key") or "")
            return
        if op == "adjustBegin":
            self.state["adjusting"] = True
            self._sync_value_echo()
            return
        if op == "adjustEnd":
            self.state["adjusting"] = False
            self._sync_value_echo()
            return
        if op in {"pointerDown", "pointerUp", "pointerTap", "wait", "waitProbe"}:
            return
        if op in {"key", "keyDown", "keyUp"}:
            self._apply_key(op, event)
            return
        raise ValueError(f"unknown event op: {op}")

    def _apply_hold(self, op: str, key: str) -> None:
        holds: set[str] = set(self.state.setdefault("activeHolds", []))
        if op == "holdBegin":
            holds.add(key)
        else:
            holds.discard(key)
        self.state["activeHolds"] = sorted(holds)

    def _apply_key(self, op: str, event: dict[str, Any]) -> None:
        key = event.get("key") or ""
        mods = set(event.get("modifiers") or [])
        if op == "keyDown" and key == "Return" and "shift" in mods:
            self._stage_row()
            self.return_held_after_shift = True
            self.state["staging"]["returnReleaseArmed"] = False
            return
        if op == "keyUp" and key == "Return":
            if self.return_held_after_shift or self.state["staging"]["active"]:
                self.state["staging"]["returnReleaseArmed"] = True
                self.return_held_after_shift = False
            return
        if op == "keyDown" and key == "Return" and "shift" not in mods:
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
                self.state["focus"]["armedControl"] = None
                self._sync_value_echo()
        elif key == "Escape":
            self._esc()
        elif key == "Tab":
            if self.state["focus"].get("armedControl") is None:
                self.state["focus"]["armedControl"] = DEFAULT_ARMED
                self._sync_value_echo()
        elif key in {"1", "2", "3", "4"}:
            idx = int(key) - 1
            if 0 <= idx < len(RAIL_CONTROLS):
                self.state["focus"]["armedControl"] = RAIL_CONTROLS[idx]
                self._sync_value_echo()

    def _mark_toggle(self, mark: str) -> None:
        idx = self.focus_index()
        asset = self.asset_ids[idx]
        before = self.state["marks"][asset]
        after = "undecided" if before == mark else mark
        if before == after:
            return
        self._push_undo()
        self.state["marks"][asset] = after
        if after != "undecided":
            self.set_focus_index(idx + 1)

    def _row_of_index(self, index: int) -> int:
        return index // self.columns_per_row

    def _row_of_id(self, asset_id: str) -> int:
        for i, rid in enumerate(self.asset_ids):
            if rid == asset_id:
                return self._row_of_index(i)
        return 0

    def _stage_row(self) -> None:
        if self.pre_stage_snapshot is None:
            self.pre_stage_snapshot = copy.deepcopy(self.state)
        focus_row = self._row_of_index(self.focus_index())
        kept = [r["id"] for r in self.state["records"] if self.state["marks"][r["id"]] == "keep"]
        scope = [rid for rid in kept if self._row_of_id(rid) == focus_row]
        if not scope:
            scope = [self.state["focus"]["assetId"]]
        count = len(scope)
        st = self.state["staging"]
        st.update(
            {
                "active": True,
                "ring": "row",
                "scopeCount": count,
                "excludedCount": 0,
                "bannerCount": count,
                "headerCount": count,
                "receiptCount": count,
                "recipeKind": "adapt",
                "returnReleaseArmed": False,
            }
        )

    def _commit_stage(self) -> None:
        self._push_undo()
        st = self.state["staging"]
        st.update(
            {
                "active": False,
                "ring": "none",
                "returnReleaseArmed": False,
                "recipeKind": None,
                "scopeCount": 0,
                "bannerCount": 0,
                "headerCount": 0,
                "receiptCount": 0,
            }
        )
        self.pre_stage_snapshot = None

    def _esc(self) -> None:
        if self.state["staging"]["active"] and self.pre_stage_snapshot is not None:
            snap = self.pre_stage_snapshot
            self.state["marks"] = copy.deepcopy(snap["marks"])
            self.state["focus"] = copy.deepcopy(snap["focus"])
            self.state["staging"] = copy.deepcopy(snap["staging"])
            self.pre_stage_snapshot = None
            return
        self.state["focus"]["armedControl"] = None
        self._sync_value_echo()

    def _push_undo(self) -> None:
        stack = self.state.setdefault("_undo_stack", [])
        stack.append(
            {
                "marks": copy.deepcopy(self.state["marks"]),
                "focus": copy.deepcopy(self.state["focus"]),
                "staging": copy.deepcopy(self.state["staging"]),
                "armedControl": self.state["focus"].get("armedControl"),
            }
        )
        if len(stack) > 64:
            del stack[: len(stack) - 64]
        self.state["undoDepth"] = len(stack)

    def apply_undo(self) -> None:
        stack = self.state.get("_undo_stack") or []
        if not stack:
            return
        snap = stack.pop()
        self.state["marks"] = snap["marks"]
        self.state["focus"] = snap["focus"]
        self.state["staging"] = snap["staging"]
        self.state["undoDepth"] = len(stack)
        if not self.state["staging"]["active"]:
            self.pre_stage_snapshot = None

    def grammar_snapshot(self) -> dict[str, Any]:
        return extract_grammar(self.state)

    def replay_script(self, script: dict[str, Any]) -> None:
        for event in script["events"]:
            self.apply_script_event(event)


def run_script_machine(script: dict[str, Any]) -> dict[str, Any]:
    machine = GrammarMachine.from_script(script)
    machine.replay_script(script)
    return machine.grammar_snapshot()
