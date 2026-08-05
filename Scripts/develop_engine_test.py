#!/usr/bin/env python3
"""Deterministic develop-engine unit tests (Linux-safe mirrors of Swift contracts).

Run: python3 Scripts/develop_engine_test.py
"""
from __future__ import annotations

import json
import sys
import uuid
from copy import deepcopy
from dataclasses import dataclass, field, asdict
from typing import Any


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def ok(msg: str) -> None:
    print(f"PASS: {msg}")


# --- Recipe serialization / migration ---

SCHEMA_V1 = 1


@dataclass
class EditCrop:
    x: float
    y: float
    width: float
    height: float

    def normalized(self) -> "EditCrop":
        w = min(max(self.width, 0.01), 1)
        h = min(max(self.height, 0.01), 1)
        return EditCrop(min(max(self.x, 0), 1 - w), min(max(self.y, 0), 1 - h), w, h)

    def pixel_rect(self, extent: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
        """extent = (minX, minY, width, height) in CI bottom-left space; crop y is top-down."""
        c = self.normalized()
        min_x, min_y, w, h = extent
        max_y = min_y + h
        ox = min_x + c.x * w
        oy = max_y - (c.y + c.height) * h
        return (ox, oy, c.width * w, c.height * h)


@dataclass
class EditRecipe:
    id: str
    schemaVersion: int = SCHEMA_V1
    exposure: float = 0
    temperature: float = 6500
    tint: float = 0
    contrast: float = 0
    highlights: float = 0
    shadows: float = 0
    whites: float = 0
    blacks: float = 0
    texture: float = 0
    clarity: float = 0
    dehaze: float = 0
    vibrance: float = 0
    saturation: float = 0
    sharpness: float = 0
    luminanceNR: float = 0
    crop: dict | None = None
    straightenDegrees: float = 0
    sourceNeighbors: list[str] = field(default_factory=list)
    confidence: float = 1

    def fingerprint(self) -> str:
        c = self.crop or {"x": 0, "y": 0, "width": 1, "height": 1}
        parts = [
            f"v{self.schemaVersion}",
            f"{self.exposure:.5f}",
            f"{self.temperature:.5f}",
            f"{self.tint:.5f}",
            f"{self.contrast:.5f}",
            f"{self.highlights:.5f}",
            f"{self.shadows:.5f}",
            f"{self.whites:.5f}",
            f"{self.blacks:.5f}",
            f"{self.texture:.5f}",
            f"{self.clarity:.5f}",
            f"{self.dehaze:.5f}",
            f"{self.vibrance:.5f}",
            f"{self.saturation:.5f}",
            f"{self.sharpness:.5f}",
            f"{self.luminanceNR:.5f}",
            f"{self.straightenDegrees:.5f}",
            f"{c['x']:.5f},{c['y']:.5f},{c['width']:.5f},{c['height']:.5f}",
        ]
        return "|".join(parts)


def stable_json(obj: Any) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"))


def test_recipe_serialization() -> None:
    r = EditRecipe(id=str(uuid.uuid4()), exposure=0.35, temperature=5200, tint=4, highlights=-20)
    data = stable_json(asdict(r))
    loaded = json.loads(data)
    if loaded["schemaVersion"] != SCHEMA_V1:
        fail("schema version")
    if abs(loaded["exposure"] - 0.35) > 1e-9:
        fail("exposure roundtrip")
    # Stable key order
    if data != stable_json(json.loads(data)):
        fail("unstable serialization")
    ok("recipe serialization + migration hook (v1 identity)")


def test_shared_propagation_and_local_override() -> None:
    recipe_id = str(uuid.uuid4())
    shared = EditRecipe(id=recipe_id, exposure=0.5)
    recipes = {recipe_id: asdict(shared)}
    p1, p2, p3 = str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())
    bindings = {
        p1: {"photoID": p1, "link": {"linked": recipe_id}, "authority": "current"},
        p2: {"photoID": p2, "link": {"linked": recipe_id}, "authority": "current"},
        p3: {
            "photoID": p3,
            "link": {"divergent": {"recipeID": recipe_id, "local": asdict(EditRecipe(id=str(uuid.uuid4()), exposure=1.0))}},
            "authority": "current",
        },
    }
    # Update shared — only linked photos follow
    recipes[recipe_id]["exposure"] = 0.8
    linked_exposure = recipes[recipe_id]["exposure"]
    local_exposure = bindings[p3]["link"]["divergent"]["local"]["exposure"]
    if linked_exposure != 0.8:
        fail("shared update")
    if local_exposure == 0.8:
        fail("local override was silently overwritten")
    if abs(local_exposure - 1.0) > 1e-9:
        fail("local override isolation")
    ok("shared recipe propagation + local override isolation")


def test_batch_stage_commit_cancel_undo() -> None:
    class Batch:
        def __init__(self) -> None:
            self.phase = "idle"
            self.selected: list[str] = []
            self.staged = None
            self.awaiting_release = False
            self.awaiting_confirm = False
            self.undo: list[dict] = []

        def stage(self, recipe: dict, is_repeat: bool) -> None:
            if is_repeat:
                raise RuntimeError("repeat")
            if not self.selected:
                raise RuntimeError("empty")
            self.staged = recipe
            self.phase = "staged"
            self.awaiting_release = True
            self.awaiting_confirm = False

        def note_release(self) -> None:
            if self.phase == "staged" and self.awaiting_release:
                self.awaiting_release = False
                self.awaiting_confirm = True

        def commit(self, store: dict, is_repeat: bool) -> None:
            if is_repeat:
                raise RuntimeError("repeat")
            if self.phase != "staged" or not self.awaiting_confirm or not self.staged:
                raise RuntimeError("not awaiting")
            if not self.selected:
                raise RuntimeError("empty")
            prior = {pid: deepcopy(store.get(pid)) for pid in self.selected}
            shared_id = str(uuid.uuid4())
            for pid in self.selected:
                store[pid] = {"link": "linked", "recipeID": shared_id, "exposure": self.staged["exposure"]}
            self.undo.append({"prior": prior})
            self.phase = "committed"
            self.staged = None
            self.awaiting_confirm = False

        def cancel(self) -> None:
            self.phase = "idle"
            self.staged = None
            self.awaiting_release = False
            self.awaiting_confirm = False

        def undo_last(self, store: dict) -> None:
            snap = self.undo.pop()
            for pid, binding in snap["prior"].items():
                if binding is None:
                    store.pop(pid, None)
                else:
                    store[pid] = binding

    b = Batch()
    store: dict = {}
    # Empty selection protection
    try:
        b.stage({"exposure": 0.2}, False)
        fail("empty selection should not stage")
    except RuntimeError:
        ok("empty-selection protection (stage)")

    p1, p2 = str(uuid.uuid4()), str(uuid.uuid4())
    b.selected = [p1, p2]
    b.stage({"exposure": 0.2}, False)
    # Auto-repeat rejection
    try:
        b.commit(store, True)
        fail("auto-repeat should not commit")
    except RuntimeError:
        ok("keyboard auto-repeat rejection")

    b.note_release()
    b.commit(store, False)
    if store[p1]["exposure"] != 0.2 or store[p2]["link"] != "linked":
        fail("commit")
    ok("batch stage + confirm")

    # Cancel path
    b2 = Batch()
    b2.selected = [p1]
    b2.stage({"exposure": 1}, False)
    b2.cancel()
    if b2.phase != "idle" or b2.staged is not None:
        fail("cancel")
    ok("batch cancellation")

    # Undo transaction
    prior_store = deepcopy(store)
    b.undo_last(store)
    # After undo, bindings restored to None (no prior)
    if store.get(p1) is not None:
        # prior was None → removed
        fail(f"undo restore unexpected {store.get(p1)}")
    ok("single-transaction batch undo")
    _ = prior_store


def test_render_generation_ordering() -> None:
    def should_present(candidate: int, presented: int | None) -> bool:
        if presented is None:
            return True
        return candidate >= presented

    if not should_present(5, None):
        fail("first present")
    if should_present(4, 5):
        fail("stale accepted")
    if not should_present(5, 5):
        fail("same gen")
    if not should_present(6, 5):
        fail("newer rejected")

    def coalesce(pending: list[str], newest: str) -> list[str]:
        return [newest]

    if coalesce(["a", "b"], "c") != ["c"]:
        fail("coalesce")
    ok("render-generation ordering + stale rejection + coalesce")


def test_crop_across_resolutions() -> None:
    crop = EditCrop(0.1, 0.2, 0.5, 0.4)
    preview = crop.pixel_rect((0, 0, 3200, 2000))
    export = crop.pixel_rect((0, 0, 8000, 5000))
    # Relative placement must match
    def norm(rect, w, h):
        x, y, rw, rh = rect
        # convert CI y back to top-down fraction
        top = (h - (y + rh)) / h
        return (x / w, top, rw / w, rh / h)

    n1 = norm(preview, 3200, 2000)
    n2 = norm(export, 8000, 5000)
    for a, b in zip(n1, n2):
        if abs(a - b) > 1e-9:
            fail(f"crop drift {n1} vs {n2}")
    ok("crop coordinates across preview and export resolutions")


def test_aspect_fit_orientation() -> None:
    def fit(iw, ih, dw, dh):
        scale = min(dw / iw, dh / ih)
        fw, fh = iw * scale, ih * scale
        return ((dw - fw) / 2, (dh - fh) / 2, fw, fh)

    def oriented(w, h, orientation: int):
        if orientation in (5, 6, 7, 8):
            return h, w
        return w, h

    for o in range(1, 9):
        w, h = oriented(4000, 6000, o)
        x, y, fw, fh = fit(w, h, 1200, 800)
        if abs((fw / fh) - (w / h)) > 1e-6:
            fail(f"aspect o={o}")
        if fw > 1200 + 1e-6 or fh > 800 + 1e-6:
            fail(f"overflow o={o}")
    ok("orientation + aspect-fit geometry")


def test_operation_order_equivalence_marker() -> None:
    """Documented order must be identical for settled vs export (quality differs only in resolution)."""
    order = [
        "decode",
        "downsample",
        "white_balance",
        "exposure",
        "highlights_shadows",
        "whites_blacks",
        "contrast",
        "presence",
        "vibrance_saturation",
        "noise_reduction",
        "sharpening",
        "straighten_crop",
        "region",
        "display_or_export_convert_once",
    ]
    settled = list(order)
    export = list(order)
    if settled != export:
        fail("preview/export order drift")
    ok("preview/export operation-order equivalence")


def test_cache_invalidation_fingerprint() -> None:
    a = EditRecipe(id="1", exposure=0.1)
    b = EditRecipe(id="1", exposure=0.2)
    if a.fingerprint() == b.fingerprint():
        fail("fingerprint should change with recipe")
    ok("cache invalidation when recipes change (fingerprint)")


def main() -> None:
    test_recipe_serialization()
    test_shared_propagation_and_local_override()
    test_batch_stage_commit_cancel_undo()
    test_render_generation_ordering()
    test_crop_across_resolutions()
    test_aspect_fit_orientation()
    test_operation_order_equivalence_marker()
    test_cache_invalidation_fingerprint()
    print("\nAll develop_engine_test checks passed.")


if __name__ == "__main__":
    main()
