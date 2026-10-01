import json
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import lr_cc_sweep as sweep  # noqa: E402

# A JPEG is only bytes to the ingest: SOI, an APP1 XMP packet, EOI is enough to carry the settings.
def fake_export(path, raw, **settings):
    crs = {**sweep.BASE, **settings, "RawFileName": raw}
    attrs = " ".join(f'crs:{k}="{sweep.fmt(k, v)}"' for k, v in crs.items())
    xmp = (f'<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
           f'<rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" {attrs}/></rdf:RDF></x:xmpmeta>').encode()
    with open(path, "wb") as f:
        f.write(b"\xff\xd8\xff\xe1" + (len(xmp) + 2).to_bytes(2, "big") + xmp + b"\xff\xd9")


class PresetTests(unittest.TestCase):
    def test_every_position_has_one_preset_in_click_order(self):
        ps = sweep.presets()
        self.assertEqual(len(ps), 2 + sum(len(v) for _, _, v in sweep.SWEEP))
        self.assertEqual([p[0] for p in ps], [f"{i:02d}" for i in range(1, len(ps) + 1)])
        self.assertEqual(ps[0][1], "Base")
        self.assertEqual(ps[1][2]["LensProfileEnable"], 1)

    def test_preset_xmp_is_lightroom_shaped_and_moves_one_slider(self):
        num, name, settings = next(p for p in sweep.presets() if p[1] == "Exposure -0.50")
        x = sweep.preset_xmp(num, name, settings)
        self.assertIn('crs:PresetType="Normal"', x)
        self.assertIn('crs:HasSettings="True"', x)
        self.assertIn('crs:Exposure2012="-0.50"', x)
        self.assertIn('crs:Contrast2012="0"', x)
        self.assertIn(">Lumina sweep<", x)
        self.assertEqual(len(re.findall(r'crs:UUID="([0-9A-F]{32})"', x)), 1)

    def test_uuids_are_stable_and_distinct(self):
        a = [re.search(r'crs:UUID="(\w+)"', sweep.preset_xmp(*p)).group(1) for p in sweep.presets()]
        b = [re.search(r'crs:UUID="(\w+)"', sweep.preset_xmp(*p)).group(1) for p in sweep.presets()]
        self.assertEqual(a, b)
        self.assertEqual(len(set(a)), len(a))


class IngestTests(unittest.TestCase):
    def test_exports_become_refs_named_from_their_xmp_not_their_file_names(self):
        with tempfile.TemporaryDirectory() as d:
            ex, refs = os.path.join(d, "exports"), os.path.join(d, "refs")
            os.makedirs(ex)
            fake_export(os.path.join(ex, "LUM00009.jpg"), "LUM00009.ARW")
            fake_export(os.path.join(ex, "LUM00009-2.jpg"), "LUM00009.ARW", LensProfileEnable=1)
            fake_export(os.path.join(ex, "LUM00009-3.jpg"), "LUM00009.ARW", Exposure2012=-0.5)
            fake_export(os.path.join(ex, "LUM00009-4.jpg"), "LUM00009.ARW", Blacks2012=25)
            r = sweep.ingest(ex, refs)
            self.assertEqual(r["refs_written"], 4)
            self.assertEqual(sorted(os.listdir(refs)), sorted([
                "LUM00009__base.jpg", "LUM00009__baseLens.jpg", "LUM00009__Exposure__-0.5.jpg",
                "LUM00009__Blacks__25.jpg", "sweep-ingest.json"]))
            self.assertEqual(r["problems"], [])
            self.assertIn("Contrast -50.0", r["missing"]["LUM00009"])
            self.assertTrue(json.load(open(os.path.join(refs, "sweep-ingest.json")))["missing"])

    def test_bad_exports_are_named_not_guessed(self):
        with tempfile.TemporaryDirectory() as d:
            ex, refs = os.path.join(d, "exports"), os.path.join(d, "refs")
            os.makedirs(ex)
            fake_export(os.path.join(ex, "two.jpg"), "A.ARW", Exposure2012=1, Contrast2012=25)
            fake_export(os.path.join(ex, "off.jpg"), "A.ARW", Exposure2012=0.7)
            fake_export(os.path.join(ex, "clar.jpg"), "A.ARW", Clarity2012=10)
            fake_export(os.path.join(ex, "dup1.jpg"), "A.ARW", Whites2012=50)
            fake_export(os.path.join(ex, "dup2.jpg"), "A.ARW", Whites2012=50)
            with open(os.path.join(ex, "nometa.jpg"), "wb") as f:
                f.write(b"\xff\xd8\xff\xd9")
            r = sweep.ingest(ex, refs)
            whys = {p["file"]: p["why"] for p in r["problems"]}
            self.assertIn("more than one slider", whys["two.jpg"])
            self.assertIn("not a sweep position", whys["off.jpg"])
            self.assertIn("Clarity2012", whys["clar.jpg"])
            self.assertIn("duplicate", whys["dup2.jpg"])
            self.assertIn("All metadata", whys["nometa.jpg"])
            self.assertEqual(r["refs_written"], 1)


# The table the presets in Lightroom were made from. The ingest matches exports against it, so it
# must never drift: a change here means new presets and a new round of exports.
COMBOS = [
    {"Shadows": -50, "Blacks": 25, "Exposure": -0.95},
    {"Whites": -25, "Saturation": 20, "Blacks": -25},
    {"Vibrance": 30, "Shadows": -45, "Saturation": -20},
    {"Contrast": 35, "Vibrance": 40, "Highlights": -25},
    {"Whites": -15, "Exposure": 0.45, "Contrast": 30},
    {"Highlights": 35, "Exposure": -0.4, "Saturation": -15},
    {"Highlights": 45, "Whites": -35, "Vibrance": -20},
    {"Shadows": 35, "Temperature": 4350, "Tint": 20},
    {"Blacks": -30, "Temperature": 5700, "Tint": -35},
    {"Contrast": -15, "Temperature": 5400, "Tint": -15},
]
AS_SHOT = {"Temperature": 5550, "Tint": -5}


def read(path, mode="r"):
    with open(path, mode) as f:
        return f.read()


def custom(**settings):
    """What Lightroom writes after a white-balance preset: Custom, both numbers present."""
    return {"WhiteBalance": "Custom", **{**AS_SHOT, **settings}}


class Sweep2PresetTests(unittest.TestCase):
    def test_the_combo_table_is_seeded_and_pinned(self):
        self.assertEqual(sweep.combos(), COMBOS)
        self.assertEqual(sweep.combos(), sweep.combos())

    def test_every_combo_moves_three_distinct_sliders_and_every_slider_is_covered(self):
        seen = {}
        for c in sweep.combos():
            self.assertEqual(len(c), 3)
            self.assertTrue(all(v != 0 for v in c.values()))
            self.assertEqual("Temperature" in c, "Tint" in c)   # white balance moves whole, or not at all
            for k in c:
                seen[k] = seen.get(k, 0) + 1
        self.assertEqual(seen, {**{label: 3 for label, *_ in sweep.COMBO_TONE}, "Temperature": 3, "Tint": 3})

    def test_sweep_2_is_a_short_separate_set_in_click_order(self):
        ps = sweep.presets2()
        self.assertEqual(len(ps), 1 + 4 + 4 + 10)
        self.assertEqual([p[0] for p in ps], [f"2-{i:02d}" for i in range(1, len(ps) + 1)])
        self.assertEqual(ps[0][1:], ("Base", sweep.BASE))
        names = [p[1] for p in ps]
        self.assertEqual(names[1:5], ["Temperature 3200", "Temperature 4000", "Temperature 6500", "Temperature 10000"])
        self.assertEqual(names[12:16], ["Tint -60", "Tint -20", "Tint +20", "Tint +60"])
        # A Tint preset leaves Temperature alone, so the preset before the first one resets white balance.
        self.assertEqual(ps[11][2]["WhiteBalance"], "As Shot")
        one = [re.search(r'crs:UUID="(\w+)"', sweep.preset_xmp(*p)).group(1) for p in sweep.presets()]
        two = [re.search(r'crs:UUID="(\w+)"', sweep.preset_xmp(*p, group=sweep.GROUP2)).group(1) for p in ps]
        self.assertEqual(len(set(one + two)), len(one) + len(two))

    def test_white_balance_presets_are_custom_and_set_one_number_over_the_base(self):
        ps = {p[1]: p for p in sweep.presets2()}
        x = sweep.preset_xmp(*ps["Temperature 6500"], group=sweep.GROUP2)
        self.assertIn('crs:WhiteBalance="Custom"', x)
        self.assertIn('crs:Temperature="6500"', x)
        self.assertNotIn("crs:Tint=", x)
        self.assertIn(">Lumina sweep 2<", x)
        self.assertIn(">2-04 Temperature 6500<", x)
        x = sweep.preset_xmp(*ps["Tint -20"], group=sweep.GROUP2)
        self.assertIn('crs:WhiteBalance="Custom"', x)
        self.assertIn('crs:Tint="-20"', x)
        self.assertNotIn("crs:Temperature=", x)
        for _, _, settings in ps.values():
            rest = {k: v for k, v in settings.items() if k in sweep.BASE and k not in sweep.SLIDER_KEYS and k != "WhiteBalance"}
            self.assertEqual(rest, {k: v for k, v in sweep.BASE.items() if k in rest})
            self.assertNotIn("CameraProfile", settings)
            self.assertEqual(settings["LensProfileEnable"], 0)
            self.assertEqual(settings["Sharpness"], 0)

    def test_combo_presets_carry_their_three_sliders(self):
        ps = {p[1]: p for p in sweep.presets2()}
        x = sweep.preset_xmp(*ps["Combo 01"], group=sweep.GROUP2)
        for want in ('crs:Shadows2012="-50"', 'crs:Blacks2012="+25"', 'crs:Exposure2012="-0.95"', 'crs:WhiteBalance="As Shot"',
                     'crs:Contrast2012="0"', "Exposure -0.95, Shadows -50, Blacks +25 from the neutral base"):
            self.assertIn(want, x)
        x = sweep.preset_xmp(*ps["Combo 08"], group=sweep.GROUP2)
        for want in ('crs:Shadows2012="+35"', 'crs:WhiteBalance="Custom"', 'crs:Temperature="4350"', 'crs:Tint="+20"'):
            self.assertIn(want, x)

    def test_presets_are_written_as_a_zip_under_their_own_group(self):
        import zipfile
        with tempfile.TemporaryDirectory() as d:
            files, z = sweep.write_presets(d, sweep=2)
            self.assertEqual(len(files), 19)
            self.assertEqual(os.path.basename(z), "Lumina-sweep2-presets.zip")
            with zipfile.ZipFile(z) as zf:
                names = zf.namelist()
            self.assertEqual(len(names), 19)
            self.assertTrue(all(n.startswith("Lumina sweep 2/2-") and n.endswith(".xmp") for n in names))
            again, _ = sweep.write_presets(os.path.join(d, "again"), sweep=2)
            self.assertEqual([read(f) for f in files], [read(f) for f in again])


class Sweep2IngestTests(unittest.TestCase):
    def test_white_balance_exports_become_singles_and_the_as_shot_values_are_recorded(self):
        with tempfile.TemporaryDirectory() as d:
            ex, refs = os.path.join(d, "exports"), os.path.join(d, "refs")
            os.makedirs(ex)
            fake_export(os.path.join(ex, "A.jpg"), "A.ARW", ProcessVersion="15.4", **AS_SHOT)
            fake_export(os.path.join(ex, "A-2.jpg"), "A.ARW", **custom(Temperature=6500))
            fake_export(os.path.join(ex, "A-3.jpg"), "A.ARW", **custom(Tint=-20))
            fake_export(os.path.join(ex, "A-4.jpg"), "A.ARW", **custom(Temperature=10000))
            r = sweep.ingest(ex, refs)
            self.assertEqual(r["problems"], [])
            self.assertEqual(r["sweep"], 2)
            self.assertEqual(r["expected_per_photo"], 19)
            self.assertEqual(sorted(os.listdir(refs)), sorted([
                "A__base.jpg", "A__asshot.json", "A__Temperature__6500.jpg", "A__Temperature__10000.jpg", "A__Tint__-20.jpg",
                "sweep-ingest.json"]))
            self.assertEqual(json.loads(read(os.path.join(refs, "A__asshot.json"))),
                             {"Temperature": 5550, "Tint": -5, "processVersion": "15.4"})
            self.assertIn("Temperature 3200.0", r["missing"]["A"])
            self.assertIn("combo 1", r["missing"]["A"])
            self.assertNotIn("baseLens", r["missing"]["A"])

    def test_the_harness_reads_what_the_ingest_writes(self):
        import import_refs
        with tempfile.TemporaryDirectory() as d:
            ex, refs = os.path.join(d, "exports"), os.path.join(d, "refs")
            os.makedirs(ex)
            fake_export(os.path.join(ex, "1.jpg"), "A.ARW", **AS_SHOT)
            fake_export(os.path.join(ex, "2.jpg"), "A.ARW", **custom(Tint=60))
            fake_export(os.path.join(ex, "3.jpg"), "A.ARW", **custom(Shadows2012=35, Temperature=4350, Tint=20))
            fake_export(os.path.join(ex, "4.jpg"), "A.ARW", Whites2012=-15, Exposure2012=0.45, Contrast2012=30, **AS_SHOT)
            self.assertEqual(sweep.ingest(ex, refs)["problems"], [])
            by_id = {e["id"]: e for e in import_refs.index(refs, read_info=False)["refs"]}
            self.assertEqual(by_id["A__Tint__60"]["settings"], {"Tint": 60.0})
            self.assertEqual(by_id["A__combo08"]["settings"], {"Shadows": 35, "Temperature": 4350, "Tint": 20})
            self.assertEqual(by_id["A__combo05"]["settings"], {"Whites": -15, "Exposure": 0.45, "Contrast": 30})
            for e in by_id.values():
                self.assertEqual({k: e["asShot"][k] for k in AS_SHOT}, AS_SHOT)

    def test_combo_exports_are_matched_to_the_table_and_get_their_json(self):
        with tempfile.TemporaryDirectory() as d:
            ex, refs = os.path.join(d, "exports"), os.path.join(d, "refs")
            os.makedirs(ex)
            fake_export(os.path.join(ex, "b.jpg"), "B.ARW", **AS_SHOT)
            for n, c in enumerate(sweep.combos(), 1):
                keys = {sweep.COMBO_KEYS[k]: v for k, v in c.items()}
                fake_export(os.path.join(ex, f"b-{n}.jpg"), "B.ARW", **(custom(**keys) if "Temperature" in c else {**AS_SHOT, **keys}))
            r = sweep.ingest(ex, refs)
            self.assertEqual(r["problems"], [])
            self.assertEqual(r["refs_written"], 11)
            for n, c in enumerate(COMBOS, 1):
                self.assertTrue(os.path.exists(os.path.join(refs, f"B__combo{n:02d}.jpg")))
                side = json.loads(read(os.path.join(refs, f"B__combo{n:02d}.json")))
                self.assertEqual(side["settings"], c)
                self.assertEqual(side["asShot"], AS_SHOT)
            self.assertEqual(read(os.path.join(refs, "B__combo03.jpg"), "rb"), read(os.path.join(ex, "b-3.jpg"), "rb"))

    def test_white_balance_and_combo_mismatches_are_named_not_guessed(self):
        with tempfile.TemporaryDirectory() as d:
            ex, refs = os.path.join(d, "exports"), os.path.join(d, "refs")
            os.makedirs(ex)
            fake_export(os.path.join(ex, "base.jpg"), "A.ARW", **AS_SHOT)
            fake_export(os.path.join(ex, "carried.jpg"), "A.ARW", **custom(Temperature=6500, Tint=60))   # Tint +60 still applied
            fake_export(os.path.join(ex, "offgrid.jpg"), "A.ARW", **custom(Temperature=5000))
            fake_export(os.path.join(ex, "nearcombo.jpg"), "A.ARW", **custom(Shadows2012=35, Temperature=4350, Tint=25))
            fake_export(os.path.join(ex, "nearcombo2.jpg"), "A.ARW", Whites2012=-15, Exposure2012=0.45, Contrast2012=25, **AS_SHOT)
            fake_export(os.path.join(ex, "wbplus.jpg"), "A.ARW", **custom(Temperature=6500, Exposure2012=1))
            fake_export(os.path.join(ex, "auto.jpg"), "A.ARW", WhiteBalance="Auto", Temperature=5300, Tint=3)
            fake_export(os.path.join(ex, "lens.jpg"), "A.ARW", LensProfileEnable=1, **custom(Tint=20))
            fake_export(os.path.join(ex, "orphan.jpg"), "Z.ARW", **{**custom(Temperature=6500), "Tint": 12})   # no As Shot export of Z
            fake_export(os.path.join(ex, "dup1.jpg"), "A.ARW", **custom(Tint=20))
            fake_export(os.path.join(ex, "dup2.jpg"), "A.ARW", **custom(Tint=20))
            r = sweep.ingest(ex, refs)
            whys = {p["file"]: p["why"] for p in r["problems"]}
            self.assertIn("earlier white-balance preset was still applied", whys["carried.jpg"])
            self.assertIn("5550 / -5 as shot", whys["carried.jpg"])
            self.assertIn("not a sweep position", whys["offgrid.jpg"])
            self.assertIn("not one of the combos", whys["nearcombo.jpg"])
            self.assertIn("not one of the combos", whys["nearcombo2.jpg"])
            self.assertIn("not one of the combos", whys["wbplus.jpg"])
            self.assertIn("white balance is Auto", whys["auto.jpg"])
            self.assertIn("lens corrections", whys["lens.jpg"])
            self.assertIn("export the Base preset too", whys["orphan.jpg"])
            self.assertIn("duplicate", whys["dup2.jpg"])
            self.assertEqual(len(whys), 9)
            self.assertEqual(sorted(os.listdir(refs)), ["A__Tint__20.jpg", "A__asshot.json", "A__base.jpg", "sweep-ingest.json"])

    def test_a_position_equal_to_the_as_shot_value_is_still_that_position(self):
        with tempfile.TemporaryDirectory() as d:
            ex, refs = os.path.join(d, "exports"), os.path.join(d, "refs")
            os.makedirs(ex)
            fake_export(os.path.join(ex, "1.jpg"), "C.ARW", Temperature=4000, Tint=7)
            fake_export(os.path.join(ex, "2.jpg"), "C.ARW", WhiteBalance="Custom", Temperature=4000, Tint=7)
            r = sweep.ingest(ex, refs)
            self.assertEqual(r["problems"], [])
            self.assertTrue(os.path.exists(os.path.join(refs, "C__Temperature__4000.jpg")))

    def test_the_first_sweep_is_still_expected_when_nothing_from_the_second_is_there(self):
        with tempfile.TemporaryDirectory() as d:
            ex, refs = os.path.join(d, "exports"), os.path.join(d, "refs")
            os.makedirs(ex)
            fake_export(os.path.join(ex, "1.jpg"), "A.ARW", **AS_SHOT)
            fake_export(os.path.join(ex, "2.jpg"), "A.ARW", Exposure2012=1, **AS_SHOT)
            r = sweep.ingest(ex, refs)
            self.assertEqual((r["sweep"], r["expected_per_photo"]), (1, 30))
            self.assertEqual(sweep.ingest(ex, refs, sweep=2)["expected_per_photo"], 19)


class CommandTests(unittest.TestCase):
    def test_a_missing_or_empty_exports_folder_fails_loudly(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(sweep.main(["ingest", os.path.join(d, "nope"), "--refs", os.path.join(d, "refs")]), 2)
            os.makedirs(os.path.join(d, "empty"))
            self.assertEqual(sweep.main(["ingest", os.path.join(d, "empty"), "--refs", os.path.join(d, "refs")]), 2)

    def test_presets_sweep_2_writes_its_own_zip(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(sweep.main(["presets", "--sweep", "2", "--out", d]), 0)
            self.assertEqual(len(os.listdir(os.path.join(d, "presets"))), 19)
            self.assertTrue(os.path.exists(os.path.join(d, "Lumina-sweep2-presets.zip")))


if __name__ == "__main__":
    unittest.main()
