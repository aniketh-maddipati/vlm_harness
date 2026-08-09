#!/usr/bin/env python3
"""Table layout contract — swim lanes, wrap-shares-lane, gap/compression geometry."""
from __future__ import annotations

import sys
from datetime import datetime, timedelta, timezone

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def pass_(message: str) -> None:
    print(f"PASS: {message}")


def lane_timestamp(date: datetime | None) -> str:
    if date is None:
        return "18:17"
    return date.strftime("%H:%M")


def responsive_page_size(two_up: bool, available_width: float) -> int:
    if two_up:
        return 2
    if available_width <= 0:
        return 3
    fits = int((available_width - 60 + 16) / (300 + 16))
    return min(max(fits, 3), 5)


def compact_visible_count(available_width: float) -> int:
    if available_width <= 0:
        return 6
    tile = 104 + 6
    return min(max(int((available_width - 60) / tile), 4), 12)


def comparison_tile_width(
    available_width: float, page_size: int, two_up: bool, gap: float = 16, mat: float = 12
) -> float:
    if available_width <= 0:
        return 480 if two_up else 336
    n = float(max(page_size, 1))
    per = (available_width - gap * (n - 1)) / n - mat * 2
    return min(max(per, 280), 720)


def comparison_compression(page_size: int, has_selection: bool, focus_boost: float = 1.22):
    n = float(max(page_size, 1))
    if not has_selection or n <= 1:
        return (1.0, 1.0)
    neighbor = (n - focus_boost) / (n - 1)
    return (focus_boost, neighbor)


class FakeGroup:
    def __init__(
        self,
        id: str,
        time_start: datetime | None = None,
        time_end: datetime | None = None,
        sibling_group_id: str | None = None,
        sibling_part_index: int | None = None,
        sibling_part_count: int | None = None,
    ):
        self.id = id
        self.time_start = time_start
        self.time_end = time_end
        self.sibling_group_id = sibling_group_id
        self.sibling_part_index = sibling_part_index
        self.sibling_part_count = sibling_part_count

    @property
    def is_sibling_continuation(self) -> bool:
        return (self.sibling_part_index or 0) > 1


def swim_lane_units(groups: list[FakeGroup]):
    units = []
    index = 0
    while index < len(groups):
        head = groups[index]
        lane_groups = [head]
        next_i = index + 1
        if head.sibling_group_id:
            while (
                next_i < len(groups)
                and groups[next_i].is_sibling_continuation
                and groups[next_i].sibling_group_id == head.sibling_group_id
            ):
                lane_groups.append(groups[next_i])
                next_i += 1
        header = None if head.is_sibling_continuation else lane_timestamp(head.time_start)
        units.append(
            {
                "id": head.sibling_group_id or head.id,
                "lane_header": header,
                "groups": lane_groups,
            }
        )
        index = next_i
    return units


def scene_break_label(prior: FakeGroup, nxt: FakeGroup) -> str | None:
    end = prior.time_end or prior.time_start
    start = nxt.time_start
    if end is None or start is None:
        return None
    minutes = int((start - end).total_seconds() / 60)
    if minutes < 1:
        return None
    return f"+ {minutes} min"


# MARK: - Geometry

if responsive_page_size(two_up=False, available_width=1200) != 3:
    fail("responsivePageSize should fit 3 tiles at 1200pt tray")
if responsive_page_size(two_up=True, available_width=1600) != 2:
    fail("responsivePageSize should be 2 in two-up mode")
if compact_visible_count(available_width=900) < 4:
    fail("compactVisibleCount should fit at least 4 tiles at 900pt")

tile_w = comparison_tile_width(available_width=1100, page_size=4, two_up=False)
if not (280 <= tile_w <= 720):
    fail(f"comparison tile width out of clamp range: {tile_w}")

focus, neighbor = comparison_compression(page_size=4, has_selection=True)
if abs(focus - 1.22) > 0.001 or neighbor >= 1.0:
    fail("comparison compression should boost focus and shrink neighbors")

pass_("Gap / wrap / compression geometry stable")

# MARK: - Swim lanes

base = datetime(2026, 8, 9, 17, 12, tzinfo=timezone.utc)
g1 = FakeGroup("a", time_start=base, time_end=base + timedelta(minutes=8), sibling_group_id="lane-1", sibling_part_index=1, sibling_part_count=2)
g2 = FakeGroup("b", time_start=base + timedelta(minutes=9), time_end=base + timedelta(minutes=16), sibling_group_id="lane-1", sibling_part_index=2, sibling_part_count=2)
units = swim_lane_units([g1, g2])
if len(units) != 1:
    fail("wrapped sibling rows must share one swim lane")
if units[0]["lane_header"] != "17:12":
    fail("lane header should carry row timestamp, not wrap page")
if len(units[0]["groups"]) != 2:
    fail("wrap shares lane — both parts in one unit")

g3 = FakeGroup("c", time_start=base + timedelta(hours=1), time_end=base + timedelta(hours=1, minutes=5))
units2 = swim_lane_units([g1, g2, g3])
if len(units2) != 2:
    fail("scene break should start a new lane unit")
break_label = scene_break_label(g2, g3)
if break_label != "+ 44 min":
    fail(f"unexpected scene break label: {break_label}")

pass_("Lane geometry and wrap-shares-lane contract holds")
print("Table layout test: all checks passed")
