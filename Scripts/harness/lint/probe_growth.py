#!/usr/bin/env python3
"""probe_growth — P0 surface/route changes require matching probe type updates (F03.1)."""
from __future__ import annotations

import sys

from probe_contract import (
    added_route_cases,
    git_diff_name_only,
    p0_view_surfaces_changed,
    probe_types_changed,
)


def main() -> int:
    changed = git_diff_name_only()
    surfaces = p0_view_surfaces_changed(changed)
    routes = added_route_cases()
    probe_ok = probe_types_changed(changed)

    failures: list[str] = []
    if surfaces and not probe_ok:
        for surface in surfaces:
            failures.append(
                f"probe_growth: P0 surface `{surface}` changed without matching probe type update "
                f"(expected diff in Lumina/Testing/UITestStateProbe.swift and/or "
                f"LuminaUITests/Support/ProbeSnapshot.swift)"
            )
    if routes and not probe_ok:
        for route in routes:
            failures.append(
                f"probe_growth: route case `.{route}` added without matching probe type update "
                f"(extend ProbeSnapshot route + uiTestSnapshot mapping)"
            )

    if failures:
        for msg in failures:
            print(f"FAIL: {msg}", file=sys.stderr)
        return 1

    print("probe_growth: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
