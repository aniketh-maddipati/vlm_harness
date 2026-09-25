#!/usr/bin/env python3
"""Focused pinch zoom — wiring gate plus the placement math.

The Swift type `FocusZoom` is what the photograph runs. This gate fails if that
type leaves the open photograph, if double-click stops being return, or if the
table pinch is replaced. The numeric battery is the same contract the logic
tests lock: the point under the fingers stays put.
"""
from __future__ import annotations

import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FOCUS = ROOT / "Lumina" / "Views" / "P0" / "ElasticFocusView.swift"
MONITOR = ROOT / "Lumina" / "Views" / "P0" / "FocusZoomMonitor.swift"
ZOOM = ROOT / "Lumina" / "Rendering" / "FocusZoom.swift"
SHEET = ROOT / "Lumina" / "Views" / "P0" / "ContactSheetCollection.swift"

FIT = 1.0
RUBBER_SLACK = 48.0
PAGE_THRESHOLD = 72.0
SMART_ZOOM = 2.0
FALLBACK_MAX = 6.0


def fail(message: str) -> None:
    print(f"FAIL focus_zoom: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_wiring() -> None:
    focus = FOCUS.read_text(encoding="utf-8")
    monitor = MONITOR.read_text(encoding="utf-8")
    zoom = ZOOM.read_text(encoding="utf-8")
    sheet = SHEET.read_text(encoding="utf-8")
    for needle in (
        "FocusZoomMonitor(",
        "zoom: focusZoom.zoom",
        "panOffset: focusZoom.pan",
        "session.closeInspection()",
        "onTapGesture(count: 2)",
        "focusZoom.magnify(",
        "focusZoom.rebase(",
        "FocusZoom.page(",
        "focusZoom.toggleSmart(",
    ):
        if needle not in focus:
            fail(f"ElasticFocusView missing {needle}")
    if "renderOneToOne" in focus or "developScheduler" in focus:
        fail("the pinch path calls the renderer")
    if "override func hitTest(_ point: NSPoint) -> NSView? { nil }" not in monitor:
        fail("zoom monitor takes clicks; double-click and hold-before would die")
    for needle in (".magnify", ".scrollWheel", ".smartMagnify"):
        if needle not in monitor:
            fail(f"monitor does not watch {needle}")
    if "onDensityDelta" not in sheet or "handleMagnify" not in sheet:
        fail("table density pinch was removed")
    for needle in ("func magnify(", "func page(", "func toggleSmart(", "func rebase("):
        if needle not in zoom:
            fail(f"FocusZoom missing {needle}")


class Placement:
    def __init__(self) -> None:
        self.zoom = FIT
        self.pan_x = 0.0
        self.pan_y = 0.0

    def fraction(self, x: float, y: float, box_w: float, box_h: float) -> tuple[float, float]:
        displayed_w = box_w * self.zoom
        displayed_h = box_h * self.zoom
        origin_x = (box_w - displayed_w) / 2 + self.pan_x
        origin_y = (box_h - displayed_h) / 2 + self.pan_y
        return (x - origin_x) / displayed_w, (y - origin_y) / displayed_h

    def magnify(self, delta: float, x: float, y: float, box_w: float, box_h: float, max_zoom: float, rubber: bool) -> None:
        anchor = self.fraction(x, y, box_w, box_h)
        limit = max(max_zoom, FIT)
        nxt = self.zoom * (1 + delta)
        if rubber:
            nxt = resist(nxt, FIT, limit)
        else:
            nxt = min(max(nxt, FIT), limit)
        self.zoom = nxt
        displayed_w = box_w * self.zoom
        displayed_h = box_h * self.zoom
        self.pan_x = (x - anchor[0] * displayed_w) - (box_w - displayed_w) / 2
        self.pan_y = (y - anchor[1] * displayed_h) - (box_h - displayed_h) / 2
        if rubber:
            self._resist_pan(box_w, box_h)
        else:
            self._clamp_pan(box_w, box_h)

    def settle(self, box_w: float, box_h: float, max_zoom: float) -> None:
        limit = max(max_zoom, FIT)
        self.zoom = min(max(self.zoom, FIT), limit)
        if self.zoom <= FIT + 0.001:
            self.zoom = FIT
            self.pan_x = 0.0
            self.pan_y = 0.0
        else:
            self._clamp_pan(box_w, box_h)

    def _excess(self, box_w: float, box_h: float) -> tuple[float, float]:
        return (
            max(0.0, (box_w * self.zoom - box_w) / 2),
            max(0.0, (box_h * self.zoom - box_h) / 2),
        )

    def _clamp_pan(self, box_w: float, box_h: float) -> None:
        ex, ey = self._excess(box_w, box_h)
        self.pan_x = min(max(self.pan_x, -ex), ex)
        self.pan_y = min(max(self.pan_y, -ey), ey)

    def _resist_pan(self, box_w: float, box_h: float) -> None:
        ex, ey = self._excess(box_w, box_h)
        self.pan_x = resist_edge(self.pan_x, ex)
        self.pan_y = resist_edge(self.pan_y, ey)


def rubber(over: float) -> float:
    return RUBBER_SLACK * (1 - math.exp(-over / RUBBER_SLACK))


def resist(value: float, low: float, high: float) -> float:
    if value < low:
        return low - rubber(low - value)
    if value > high:
        return high + rubber(value - high)
    return value


def resist_edge(value: float, limit: float) -> float:
    if value > limit:
        return limit + rubber(value - limit)
    if value < -limit:
        return -limit - rubber(-limit - value)
    return value


def page(dx: float, dy: float, zoom: float) -> int | None:
    if zoom > FIT + 0.001:
        return None
    if abs(dx) < PAGE_THRESHOLD or abs(dx) <= abs(dy):
        return None
    return 1 if dx < 0 else -1


def maximum(sensor_w: float, sensor_h: float, box_w: float, box_h: float, backing: float) -> float:
    backing = max(backing, 1)
    if sensor_w <= 1 or sensor_h <= 1 or box_w <= 1 or box_h <= 1:
        return FALLBACK_MAX
    return max(FIT, min(sensor_w / (box_w * backing), sensor_h / (box_h * backing)))


def battery() -> None:
    box_w, box_h = 800.0, 600.0
    finger = (600.0, 180.0)
    place = Placement()
    before = place.fraction(*finger, box_w, box_h)
    place.magnify(0.4, *finger, box_w, box_h, 4, False)
    after = place.fraction(*finger, box_w, box_h)
    if abs(after[0] - before[0]) > 1e-4 or abs(after[1] - before[1]) > 1e-4:
        fail("single pinch moved the point under the fingers")
    if place.zoom <= 1:
        fail("pinch did not zoom in")

    rng = random.Random(24)
    hold = Placement()
    anchor_at = (220.0, 410.0)
    held = hold.fraction(*anchor_at, box_w, box_h)
    for _ in range(200):
        delta = rng.uniform(-0.25, 0.35)
        hold.magnify(delta, *anchor_at, box_w, box_h, 5, False)
        got = hold.fraction(*anchor_at, box_w, box_h)
        if abs(got[0] - held[0]) > 1e-3 or abs(got[1] - held[1]) > 1e-3:
            fail(f"anchor drifted after {delta}: {got} vs {held}")
        if not math.isfinite(hold.zoom):
            fail("zoom became non-finite")
    if hold.zoom < FIT - 1e-6 or hold.zoom > 5 + 1e-6:
        fail(f"zoom left fit...1:1: {hold.zoom}")

    stretched = Placement()
    stretched.magnify(20, 400, 300, box_w, box_h, 2, True)
    if stretched.zoom >= 2 + RUBBER_SLACK:
        fail("rubber band did not cap the pinch")
    stretched.settle(box_w, box_h, 2)
    if abs(stretched.zoom - 2) > 1e-6:
        fail("settle did not return to 1:1")

    if page(-80, 10, 1) != 1 or page(80, 4, 1) != -1:
        fail("horizontal glide did not page")
    if page(-80, 10, 1.4) is not None or page(-20, 0, 1) is not None or page(40, 90, 1) is not None:
        fail("glide paged while zoomed, too short, or mostly vertical")

    cap = maximum(6000, 4000, box_w, box_h, 2)
    if abs(cap - (4000 / (600 * 2))) > 1e-6:
        fail(f"1:1 ceiling {cap}")
    if maximum(400, 300, box_w, box_h, 2) != FIT:
        fail("a small sensor was allowed to zoom past 1:1")


def main() -> int:
    require_wiring()
    battery()
    print("PASS focus_zoom")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
