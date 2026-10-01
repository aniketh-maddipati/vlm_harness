import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import album_index  # noqa: E402
import lr_cc_sweep as sweep  # noqa: E402


# A JPEG is only bytes to the index: SOI, an APP1 XMP packet with the settings, the look and the capture date, EOI.
def fake_export(path, raw, day="2026-01-02", look="Adobe Color", crop=False, **settings):
    crs = {**sweep.BASE, **settings, "RawFileName": raw, "HasCrop": "True" if crop else "False"}
    attrs = " ".join(f'crs:{k}="{sweep.fmt(k, v)}"' for k, v in crs.items())
    xmp = (f'<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
           f'<rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" xmp:CreateDate="{day}T10:00:00" {attrs}>'
           f'<crs:Look><rdf:Description crs:Name="{look}"/></crs:Look></rdf:Description></rdf:RDF></x:xmpmeta>').encode()
    with open(path, "wb") as f:
        f.write(b"\xff\xd8\xff\xe1" + (len(xmp) + 2).to_bytes(2, "big") + xmp + b"\xff\xd9")


class AlbumIndexTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        d = self.tmp.name
        self.exports, self.raws, self.held, self.out = (os.path.join(d, n) for n in ("exports", "raws", "held", "out"))
        for p in (self.exports, self.raws, self.held):
            os.makedirs(p)
        for stem in ("A1", "A2", "A3", "A4", "B1", "H1", "H2"):
            open(os.path.join(self.raws, stem + ".ARW"), "wb").close()

    def export(self, name, raw, folder=None, **kw):
        fake_export(os.path.join(folder or self.exports, name), raw, **kw)

    def index(self, need=("base",)):
        held = album_index.held_out(self.held)
        return album_index.index([self.exports], album_index.raw_table([self.raws]), held, need)

    def test_states_come_from_the_settings_not_the_file_name(self):
        self.export("x.jpg", "A1.ARW")
        self.export("x-2.jpg", "A1.ARW", Vibrance=15)
        self.export("x-3.jpg", "A1.ARW", Shadows2012=100)
        self.export("x-4.jpg", "A1.ARW", **sweep.LENS)
        good, skipped, _ = self.index()
        self.assertEqual(sorted(good["A1.ARW"]["states"]), ["Shadows__100", "Vibrance__15", "base", "baseLens"])
        self.assertEqual(skipped, {})

    def test_other_profiles_crops_missing_raws_and_missing_base_are_left_out(self):
        self.export("a.jpg", "A1.ARW", look="Adobe Portrait")
        self.export("b.jpg", "A2.ARW", crop=True)
        self.export("c.jpg", "Z9.ARW")
        self.export("d.jpg", "A3.ARW", Vibrance=25)
        self.export("e.jpg", "A4.ARW")
        good, skipped, _ = self.index()
        self.assertEqual(list(good), ["A4.ARW"])
        self.assertIn("Adobe Portrait", skipped["A1.ARW"])
        self.assertEqual(skipped["A2.ARW"], "cropped")
        self.assertEqual(skipped["Z9.ARW"], "no RAW")
        self.assertEqual(skipped["A3.ARW"], "missing base")

    def test_the_held_out_shoot_stays_out_by_raw_and_by_day(self):
        self.export("held.jpg", "H1.ARW", folder=self.held, day="2026-05-05", Exposure2012=0.5)
        self.export("same-raw.jpg", "H1.ARW", day="2026-05-05")
        self.export("same-day.jpg", "H2.ARW", day="2026-05-05")
        self.export("other.jpg", "A1.ARW", day="2026-05-06")
        good, skipped, _ = self.index()
        self.assertEqual(list(good), ["A1.ARW"])
        self.assertEqual(skipped, {"H1.ARW": "held-out shoot", "H2.ARW": "held-out shoot"})

    def test_every_day_is_split_in_two_and_links_are_written_once(self):
        for stem, day in (("A1", "2026-01-02"), ("A2", "2026-01-02"), ("A3", "2026-01-02"), ("A4", "2026-01-02"), ("B1", "2026-02-03")):
            self.export(stem + ".jpg", stem + ".ARW", day=day)
            self.export(stem + "-2.jpg", stem + ".ARW", day=day, Saturation=25)
        good, _, _ = self.index()
        s = album_index.split(good)
        self.assertEqual(s, {"train": ["A1.ARW", "A3.ARW", "B1.ARW"], "test": ["A2.ARW", "A4.ARW"]})
        self.assertEqual(album_index.write(self.out, good), 15)
        self.assertEqual(album_index.write(self.out, good), 0)
        self.assertEqual(sorted(os.listdir(os.path.join(self.out, "base-refs")))[0], "A1__base.jpg")
        self.assertIn("A1__Saturation__25.jpg", os.listdir(os.path.join(self.out, "refs")))


if __name__ == "__main__":
    unittest.main()
