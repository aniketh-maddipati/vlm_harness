import json
import os
import sys
import tempfile
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import delta_e  # noqa: E402
import parity  # noqa: E402

CRITERIA = json.load(open(os.path.join(HERE, "..", "criteria.json")))


class LookMappingTests(unittest.TestCase):
    def test_plain_sliders_copy_over(self):
        look = parity.lr_to_look({"Exposure": -1.5, "Contrast": 30, "Highlights": -40, "Sharpness": 70}, {}, (5200.0, 3.0))
        self.assertEqual((look["ev"], look["con"], look["hl"], look["shp"]), (-1.5, 30, -40, 70))
        self.assertIsNone(look["wb"], "no Temperature/Tint means as shot")

    def test_temperature_moves_apples_as_shot_by_lightrooms_mired_delta(self):
        # Lightroom: as shot 5000 K, slider 4000 K → +50 mired. Apple as shot 5400 K → 185.2 + 50 = 235.2 mired → 4252 K.
        look = parity.lr_to_look({"Temperature": 4000}, {"Temperature": 5000, "Tint": 10}, (5400.0, -2.0))
        self.assertAlmostEqual(look["wb"][0], 1e6 / (1e6 / 5400 + 50), places=3)
        self.assertAlmostEqual(look["wb"][1], -2.0, "tint stays at Apple's as shot")
        look = parity.lr_to_look({"Tint": 40}, {"Temperature": 5000, "Tint": 10}, (5400.0, -2.0))
        self.assertAlmostEqual(look["wb"][0], 5400.0)
        self.assertAlmostEqual(look["wb"][1], 28.0)
        # No Lightroom as-shot recorded: the slider is taken as absolute.
        look = parity.lr_to_look({"Temperature": 8000}, {}, (5400.0, 0.0))
        self.assertAlmostEqual(look["wb"][0], 8000.0, places=3)


class SelectionAndAggregationTests(unittest.TestCase):
    def refs(self):
        out = [{"id": "A__base", "stem": "A", "kind": "base", "settings": {}}]
        for s, vals in (("Exposure", [-2, 2]), ("Highlights", [-50, 50]), ("Shadows", [-50, 50]), ("Vibrance", [40])):
            for v in vals:
                out.append({"id": f"A__{s}__{v}", "stem": "A", "kind": "single", "slider": s, "value": float(v), "settings": {s: v}})
        out.append({"id": "A__combo01", "stem": "A", "kind": "combo", "combo": 1, "settings": {"Exposure": 1, "Contrast": 20, "Vibrance": 10}})
        out.append({"id": "B__Exposure__1", "stem": "B", "kind": "single", "slider": "Exposure", "value": 1.0, "settings": {"Exposure": 1}, "error": "truncated"})
        return out

    def test_select_by_stage_slider_and_kind(self):
        refs = self.refs()
        self.assertEqual({r["id"] for r in parity.select(refs, stage="tone")}, {"A__base", "A__Highlights__-50", "A__Highlights__50", "A__Shadows__-50", "A__Shadows__50"})
        self.assertEqual({r["id"] for r in parity.select(refs, slider="Vibrance")}, {"A__base", "A__Vibrance__40"})
        self.assertEqual(len(parity.select(refs, kinds=("combo",))), 1)
        self.assertEqual(len(parity.select(refs)), 9, "the broken reference is skipped")

    def measured(self, ref, level):
        rng = np.random.default_rng(abs(hash(ref["id"])) % 1000)
        sample = rng.gamma(2.0, level / 2.0, size=2000)
        regs = {k: {"n": 100, "median": float(level), "p95": float(level * 2), "mean": float(level), "max": float(level * 3)} for k in ("shadows", "midtones", "highlights", "skin")}
        return {"ref": ref, "look": "", "measure": {"all": {"n": 2000, "median": float(np.median(sample)), "p95": float(np.percentile(sample, 95)),
                                                            "mean": float(sample.mean()), "max": float(sample.max())},
                                                    **regs, "byL": [level] * 10, "sample": sample, "map": np.zeros((4, 4)) + level}}

    def test_aggregate_and_report(self):
        results = []
        for r in parity.select(self.refs()):
            level = 0.8 if r["kind"] != "single" or r["slider"] != "Highlights" else 4.0
            results.append(self.measured(r, level))
        agg = parity.aggregate(results, CRITERIA)
        self.assertTrue(agg["sliders"]["Exposure"]["pass"])
        self.assertFalse(agg["sliders"]["Highlights"]["pass"])
        self.assertEqual(agg["sliders"]["Exposure"]["pairs"], 2)
        self.assertEqual(set(agg["sliders"]["Highlights"]["positions"]), {"-50.0", "50.0"})
        self.assertIn("tone", agg["stages"])
        self.assertFalse(agg["stages"]["tone"]["pass"])
        self.assertTrue(agg["stages"]["exposure"]["pass"])
        self.assertTrue(agg["sliders"]["combo"]["pass"])
        self.assertEqual(agg["worst"][0]["id"].split("__")[1], "Highlights")
        md = parity.report_md(agg, results, CRITERIA, {"label": "test", "date": "now", "rules": "r", "px": 2048, "space": "prophoto"})
        self.assertIn("| Highlights | tone |", md)
        self.assertIn("✗", md)
        self.assertIn("### Highlights by position", md)
        self.assertIn("Worst five pairs", md)

    def test_run_end_to_end_with_a_fake_renderer(self):
        """parity.run with a stand-in lumina-render (a Python script) and synthetic TIFFs: the
        Mac-only half is the binary; everything around it runs here."""
        import tifffile
        with tempfile.TemporaryDirectory() as d:
            refs_dir = os.path.join(d, "refs"); os.makedirs(refs_dir)
            golden_root = os.path.join(d, "golden"); os.makedirs(golden_root)
            ramp = np.tile(np.linspace(0.05, 0.95, 64)[None, :, None], (32, 1, 3))
            for name, gain in (("DSC00001__base.tif", 1.0), ("DSC00001__Exposure__1.tif", 2.0), ("DSC00001__Exposure__-1.tif", 0.5)):
                tifffile.imwrite(os.path.join(refs_dir, name), (np.clip(ramp * gain, 0, 1) * 65535).astype(np.uint16))
            json.dump({"Temperature": 5000, "Tint": 0}, open(os.path.join(refs_dir, "DSC00001__asshot.json"), "w"))
            open(os.path.join(golden_root, "DSC00001.ARW"), "wb").write(b"II*\0" + b"\0" * 64)
            import import_refs
            refs = import_refs.index(refs_dir)
            json.dump(refs, open(os.path.join(d, "refs.json"), "w"))
            json.dump({"version": 1, "root": golden_root, "images": [{"file": "DSC00001.ARW"}]}, open(os.path.join(d, "golden.json"), "w"))
            # A stand-in renderer: `info` prints an as-shot, `batch` writes the ramp scaled by 2^ev (an exact exposure stage).
            fake = os.path.join(d, "fake-render.py")
            with open(fake, "w") as f:
                # The interpreter running the tests (with numpy), not whatever `python3` is first on PATH.
                f.write(f"#!{sys.executable}\n" + """import json, sys, os, numpy as np, tifffile
cmd = sys.argv[1]
if cmd == 'info':
    print(json.dumps({"asShot": {"kelvin": 5400, "tint": 1}})); sys.exit(0)
jobs = json.load(open(sys.argv[2]))
ramp = np.tile(np.linspace(0.05, 0.95, 64)[None, :, None], (32, 1, 3))
for j in jobs:
    ev = float([t for t in j['look'].split() if t.startswith('ev:')][0][3:])
    os.makedirs(os.path.dirname(j['out']), exist_ok=True)
    tifffile.imwrite(j['out'], (np.clip(ramp * 2 ** ev * 1.02, 0, 1) * 65535).astype(np.uint16))
    print(json.dumps({"ok": True, "renderMs": 3, "developMs": 40, "out": j['out']}))
""")
            os.chmod(fake, 0o755)
            args = ["--refs", os.path.join(d, "refs.json"), "--golden", os.path.join(d, "golden.json"), "--render-bin", fake,
                    "--render-dir", os.path.join(d, "render"), "--evidence", os.path.join(d, "evidence"), "--report", os.path.join(d, "report"),
                    "--space", "prophoto", "--label", "t"]
            code = parity.main(args)
            self.assertEqual(code, 0)
            latest = json.load(open(os.path.join(d, "report", "latest.json")))
            summary = json.load(open(os.path.join(latest["report"], "summary.json")))
            self.assertEqual(summary["aggregate"]["sliders"]["Exposure"]["pairs"], 2)
            self.assertLess(summary["aggregate"]["sliders"]["Exposure"]["median"], 2.0, "a 2 % gain error is well inside the criterion")
            self.assertTrue(summary["aggregate"]["sliders"]["Exposure"]["pass"])
            self.assertIn("base", summary["aggregate"]["sliders"])
            self.assertTrue(os.path.exists(os.path.join(latest["report"], "report.md")))
            self.assertTrue(os.path.isdir(os.path.join(latest["evidence"], "heatmaps")))
            self.assertEqual(len(os.listdir(os.path.join(latest["evidence"], "heatmaps"))), 3)
            self.assertFalse(any(f.endswith(".png") for f in os.listdir(latest["report"])), "no photo content in the committed report")
            cache = json.load(open(os.path.join(d, "render", "asshot.json")))
            self.assertEqual(list(cache.values())[0], [5400, 1])
            # STAGE filter: only exposure's references (plus base)
            code = parity.main(args + ["--stage", "exposure", "--reuse"])
            self.assertEqual(code, 0)
            code = parity.main(args + ["--stage", "tone"])
            self.assertEqual(code, 2, "no tone references → nothing to do")


if __name__ == "__main__":
    unittest.main()
