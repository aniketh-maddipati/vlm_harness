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


class CommandTests(unittest.TestCase):
    def test_a_missing_or_empty_exports_folder_fails_loudly(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(sweep.main(["ingest", os.path.join(d, "nope"), "--refs", os.path.join(d, "refs")]), 2)
            os.makedirs(os.path.join(d, "empty"))
            self.assertEqual(sweep.main(["ingest", os.path.join(d, "empty"), "--refs", os.path.join(d, "refs")]), 2)


if __name__ == "__main__":
    unittest.main()
