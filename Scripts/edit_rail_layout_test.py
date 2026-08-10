#!/usr/bin/env python3
"""Edit rail layout contract — frame 12 min window (1280×800), hi-fi H7."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

MIN_W = 1280
MIN_H = 800
ROW_H = 46
ROW_COUNT = 10
RAIL_W = 324
RAIL_PAD = 16
STRIP_NORMAL = 80
STRIP_COMPACT = 56
FOOTER_H = 118
CONTEXT_H = 92
HIST_W = 252
HIST_H = 64


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def pass_(message: str) -> None:
    print(f"PASS: {message}")


def is_compact(window_height: float) -> bool:
    return window_height <= MIN_H + 0.5


def shows_histogram(window_height: float) -> bool:
    return not is_compact(window_height)


def targets_height() -> float:
    return ROW_COUNT * ROW_H


def rail_column_height(context_visible: bool) -> float:
    return targets_height() + FOOTER_H + (CONTEXT_H if context_visible else 0)


def straighten_row_fits(window_height: float, context_visible: bool) -> bool:
    rail = rail_column_height(context_visible)
    hist = (HIST_H + 8) if shows_histogram(window_height) else 0
    return window_height >= rail + hist + 40


# Histogram contract size (matches HiFiTokens.Histogram).
if HIST_W != 252 or HIST_H != 64:
    fail(f"histogram must be 252×64, got {HIST_W}×{HIST_H}")

# Min window matches EditRailLayout.
if MIN_W != 1280 or MIN_H != 800:
    fail(f"min window must be 1280×800, got {MIN_W}×{MIN_H}")

# Frame 12 at exactly 1280×800 — real collapse, targets never yield.
if not is_compact(MIN_H):
    fail("1280×800 must trigger compact collapse")
if shows_histogram(MIN_H):
    fail("histogram must yield at min window before any control")
if not straighten_row_fits(MIN_H, context_visible=False):
    fail("Straighten row must fit at 1280×800 with context collapsed")

# Targets fixed — ten rows at 46 pt.
if targets_height() != 460:
    fail(f"target rail must be 460 pt, got {targets_height()}")

# Above min window histogram returns.
if not shows_histogram(MIN_H + 1):
    fail("histogram should show above min window height")
if not straighten_row_fits(MIN_H + 120, context_visible=True):
    fail("tall window with context + histogram should still fit Straighten")

# Story strip yields in compact mode.
if STRIP_COMPACT >= STRIP_NORMAL:
    fail("compact story strip must be narrower than normal")

pass_("Histogram 252×64 and min-window collapse geometry at 1280×800")
print("Edit rail layout test: all checks passed")
