#!/usr/bin/env python3
"""probe_mirror — four ProbeSnapshot sites must agree field-for-field (F03.2 / postmortem §7.2)."""
from __future__ import annotations

import sys

from probe_contract import (
    PROBE_MIRROR_SITES,
    compare_field_lists,
    parse_probe_initializer_fields,
    parse_struct_fields,
)


def main() -> int:
    fail = 0
    app_src = PROBE_MIRROR_SITES["app"].read_text(encoding="utf-8")
    canonical = parse_struct_fields(app_src, "ProbeSnapshot")

    ui_src = PROBE_MIRROR_SITES["ui_test"].read_text(encoding="utf-8")
    ui_fields = parse_struct_fields(ui_src, "ProbeSnapshot")
    for err in compare_field_lists(canonical, ui_fields):
        fail = 1
        print(f"FAIL: probe_mirror: ui_test side drift — {err}", file=sys.stderr)

    robot_src = PROBE_MIRROR_SITES["robot"].read_text(encoding="utf-8")
    robot_fields = parse_probe_initializer_fields(
        robot_src, "waitForProbe(timeout: timeout, where: predicate)"
    )
    robot_names = [n for n, _ in robot_fields]
    canon_names = [n for n, _ in canonical]
    if robot_names != canon_names:
        fail = 1
        missing = [n for n in canon_names if n not in robot_names]
        extra = [n for n in robot_names if n not in canon_names]
        if missing:
            print(
                f"FAIL: probe_mirror: robot side missing fields — {', '.join(missing)}",
                file=sys.stderr,
            )
        if extra:
            print(
                f"FAIL: probe_mirror: robot side extra fields — {', '.join(extra)}",
                file=sys.stderr,
            )
        if not missing and not extra:
            print(
                f"FAIL: probe_mirror: robot side field order mismatch — "
                f"expected {canon_names}, got {robot_names}",
                file=sys.stderr,
            )

    logic_src = PROBE_MIRROR_SITES["logic"].read_text(encoding="utf-8")
    logic_fields = parse_probe_initializer_fields(logic_src, "func testProbeSnapshotRoundTrips")
    logic_names = [n for n, _ in logic_fields]
    if logic_names != canon_names:
        fail = 1
        missing = [n for n in canon_names if n not in logic_names]
        extra = [n for n in logic_names if n not in canon_names]
        if missing:
            print(
                f"FAIL: probe_mirror: logic side missing fields — {', '.join(missing)}",
                file=sys.stderr,
            )
        if extra:
            print(
                f"FAIL: probe_mirror: logic side extra fields — {', '.join(extra)}",
                file=sys.stderr,
            )
        if not missing and not extra:
            print(
                f"FAIL: probe_mirror: logic side field order mismatch — "
                f"expected {canon_names}, got {logic_names}",
                file=sys.stderr,
            )

    if fail:
        return 1
    print("probe_mirror: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
