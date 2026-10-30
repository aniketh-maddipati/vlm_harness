"""Sweeps 4–13 of lr_cc_sweep.py: the preset tables, and the ingest on synthetic XMP."""
import hashlib
import json
import os
import re
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import lr_cc_sweep as sweep  # noqa: E402

# Click counts per sweep. A change here means new presets in Lightroom and orphaned exports.
COUNTS = {4: 18, 5: 65, 6: 55, 7: 14, 8: 13, 9: 7, 10: 6, 11: 11, 12: 12, 13: 4}
# sha256 of the sweep-1/2/3 preset files as main wrote them before sweeps 4–12 (already imported in Lightroom).
OLD_PRESETS = "8cc0a1f6b9a7c4f00643ed081c7302441f47d563475f4496fdbe6501e15888d5"
GRADE_COMBO_1 = {"SplitToningHighlightHue": 225, "SplitToningHighlightSaturation": 50, "ColorGradeMidtoneHue": 190,
                 "ColorGradeMidtoneSat": 30, "ColorGradeGlobalHue": 335, "ColorGradeGlobalSat": 20, "ColorGradeBlending": 70}
GRADE_COMBOS_SHA = "8c9d7b14c82684f3"   # sha256 of the whole table, first 16 hex


def segment(marker, payload):
    return b"\xff" + bytes([marker]) + (len(payload) + 2).to_bytes(2, "big") + payload


def export(path, raw, settings, drop=(), width=None, extra=""):
    """A JPEG with an XMP packet carrying `settings` (Lightroom's attribute form) and, with `width`,
    a SOF0 marker giving that size. `drop`: keys Lightroom left out of the file."""
    crs = {k: v for k, v in {**settings, "RawFileName": raw}.items() if k not in drop}
    attrs = " ".join(f'crs:{k}="{sweep.fmt(k, v)}"' for k, v in crs.items())
    xmp = (f'<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
           f'<rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" {attrs}>{extra}</rdf:Description>'
           f'</rdf:RDF></x:xmpmeta>').encode()
    body = segment(0xE1, xmp)
    if width:
        body += segment(0xC0, b"\x08" + (width * 2 // 3).to_bytes(2, "big") + width.to_bytes(2, "big") + b"\x03")
    with open(path, "wb") as f:
        f.write(b"\xff\xd8" + body + b"\xff\xd9")


def load(path):
    with open(path) as f:
        return json.load(f)


def by_name(name):
    return next(p for p in sweep.ext_presets() if p[1] == name)


class TableTests(unittest.TestCase):
    def test_the_old_sweeps_are_unchanged(self):
        h = hashlib.sha256()
        shots = {"A": (5550, -5), "B": (4950, -4)}
        for t, g in ((sweep.presets(), sweep.GROUP), (sweep.presets2(), sweep.GROUP2), (sweep.presets3(shots), sweep.GROUP3)):
            for p in t:
                h.update(sweep.preset_xmp(*p, group=g).encode())
        self.assertEqual(h.hexdigest(), OLD_PRESETS)

    def test_counts_numbering_and_one_shared_base(self):
        ps = sweep.ext_presets()
        self.assertEqual(ps[0][:2], ("00", "Base"))
        self.assertEqual(ps[0][2], sweep.EXT_BASE)
        counts = {}
        for num, *_ in ps[1:]:
            s, n = num.split("-")
            counts[int(s)] = counts.get(int(s), 0) + 1
            self.assertEqual(int(n), counts[int(s)])
        self.assertEqual(counts, COUNTS)
        self.assertEqual(len({p[0] for p in ps}), len(ps))
        self.assertEqual([p[0] for p in sweep.ext_presets({8})], ["00"] + [f"8-{i:02d}" for i in range(1, 14)])

    def test_every_preset_is_the_base_plus_its_moves(self):
        for (sweep_n, group, name, moves), (_, pname, settings, pgroup) in zip(sweep.ext_table(), sweep.ext_presets()[1:]):
            self.assertEqual((name, group), (pname, pgroup))
            self.assertTrue(group.startswith(f"Lumina sweep {sweep_n} "))
            self.assertEqual(settings["WhiteBalance"], "As Shot")
            for k, v in sweep.EXT_BASE.items():
                self.assertEqual(settings[k], moves.get(k, v), (name, k))
            self.assertEqual(settings["LensProfileEnable"], 1 if "profile" in name else 0)

    def test_positions_are_distinct_and_none_is_the_base(self):
        pos = sweep.positions()
        sigs = [p[4] for p in pos]
        self.assertEqual(len(set(sigs)), len(sigs))
        self.assertTrue(all(sigs))

    def test_every_preset_classifies_as_itself(self):
        for i, (_, name, settings, _) in enumerate(sweep.ext_presets()[1:]):
            if "Mask" in settings:
                continue   # MaskTests: a mask lives in the XMP body
            self.assertEqual(sweep.classify({k: sweep.fmt(k, v) for k, v in settings.items()}), (("pos", i), None), name)
        self.assertEqual(sweep.classify({k: sweep.fmt(k, v) for k, v in sweep.EXT_BASE.items()}), ("base", None))

    def test_grade_combos_are_seeded_and_pinned(self):
        c = sweep.grade_combos()
        self.assertEqual(c, sweep.grade_combos())
        self.assertEqual(len(c), 10)
        self.assertEqual(c[0], GRADE_COMBO_1)
        self.assertEqual(hashlib.sha256(json.dumps(c, sort_keys=True).encode()).hexdigest()[:16], GRADE_COMBOS_SHA)
        for g in c:
            wheels = [w for w in sweep.WHEELS if w[2] in g]
            self.assertIn(len(wheels), (2, 3))
            self.assertTrue(all(w[1] in g for w in wheels))

    def test_sweep_5_has_a_group_per_hue_and_one_for_black_and_white(self):
        groups = {}
        for s, g, name, _ in sweep.ext_table():
            if s == 5:
                groups.setdefault(g, []).append(name)
        self.assertEqual(len(groups), 9)
        self.assertEqual(groups["Lumina sweep 5 HSL Red"], ["Red Hue -50", "Red Hue +50", "Red Saturation -50", "Red Saturation +50",
                                                             "Red Luminance -50", "Red Luminance +50"])
        self.assertEqual(len(groups["Lumina sweep 5 B&W"]), 17)

    def test_preset_xmp_pins_the_secondary_keys(self):
        x = sweep.preset_xmp(*by_name("Texture +25"))
        for want in ('crs:Texture="+25"', 'crs:Clarity2012="0"', 'crs:SharpenRadius="+1.0"', 'crs:ConvertToGrayscale="False"',
                     'crs:ColorGradeBlending="+50"', 'crs:GrainSize="+25"', ">Lumina sweep 4 Presence<",
                     "Lumina parity sweep: Texture +25 from the neutral base."):
            self.assertIn(want, x)
        x = sweep.preset_xmp(*by_name("Sharpness 150 radius 0.5"))
        self.assertIn('crs:SharpenRadius="+0.5"', x)
        self.assertIn('crs:Sharpness="+150"', x)

    def test_the_batch_zip_holds_every_preset_under_its_group(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(sweep.main(["presets", "--sweep", "batch", "--out", d]), 0)
            with zipfile.ZipFile(os.path.join(d, "Lumina-sweeps-4-13-presets.zip")) as zf:
                names = zf.namelist()
            self.assertEqual(len(names), 1 + sum(COUNTS.values()))
            self.assertIn("Lumina sweeps/00 Base.xmp", names)
            self.assertIn("Lumina sweep 6 Grade/6-41 Split 210-40.xmp", names)
            self.assertIn("Lumina sweep 13 Sky/13-01 Sky local exposure -1.xmp", names)
            self.assertEqual(sweep.main(["presets", "--sweep", "8", "--out", os.path.join(d, "s8")]), 0)
            self.assertEqual(len(os.listdir(os.path.join(d, "s8", "presets"))), 14)


class IngestTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ex = os.path.join(self.tmp.name, "exports")
        self.refs = os.path.join(self.tmp.name, "refs")
        os.makedirs(self.ex)

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, name, raw, preset, **kw):
        settings = by_name(preset)[2] if isinstance(preset, str) else preset
        export(os.path.join(self.ex, name), raw, settings, **kw)

    def whys(self, r):
        return {p["file"]: p["why"] for p in r["problems"]}

    def test_singles_and_multi_key_positions_get_their_names(self):
        self.put("a.jpg", "A.ARW", "Base")
        self.put("a-1.jpg", "A.ARW", "Texture +25")
        self.put("a-2.jpg", "A.ARW", "Clarity -100")
        self.put("a-3.jpg", "A.ARW", "Shadows hue 210 sat 50")
        self.put("a-4.jpg", "A.ARW", "B&W")
        self.put("a-5.jpg", "A.ARW", "B&W Blue -50")
        r = sweep.ingest(self.ex, self.refs)
        self.assertEqual(r["problems"], [])
        self.assertEqual(sorted(n for n in os.listdir(self.refs) if n.endswith(".jpg")), sorted([
            "A__base.jpg", "A__Texture__25.jpg", "A__Clarity__-100.jpg", "A__s06p06.jpg", "A__ConvertToGrayscale__1.jpg",
            "A__s05p60.jpg"]))
        side = load(os.path.join(self.refs, "A__s06p06.json"))
        self.assertEqual(side, {"sweep": 6, "preset": "6-06 Shadows hue 210 sat 50",
                                "settings": {"SplitToningShadowHue": 210, "SplitToningShadowSaturation": 50}})
        self.assertEqual(load(os.path.join(self.refs, "A__s05p60.json"))["settings"], {"ConvertToGrayscale": 1, "GrayMixerBlue": -50})

    def test_the_harness_reads_what_the_ingest_writes(self):
        import import_refs
        self.put("a.jpg", "A.ARW", "Base")
        self.put("a-1.jpg", "A.ARW", "Dehaze +50")
        self.put("a-2.jpg", "A.ARW", "Grain 50 size 75 roughness 25")
        self.assertEqual(sweep.ingest(self.ex, self.refs)["problems"], [])
        data = import_refs.index(self.refs, read_info=False)
        by_id = {e["id"]: e for e in data["refs"]}
        self.assertEqual(by_id["A__Dehaze__50"]["settings"], {"Dehaze": 50.0})
        grain = by_id["A__s12p07"]
        self.assertEqual((grain["kind"], grain["sweep"], grain["position"]), ("position", 12, 7))
        self.assertEqual(grain["settings"], {"GrainAmount": 50, "GrainSize": 75, "GrainFrequency": 25})
        self.assertEqual(data["counts"]["positions"], 1)
        self.assertEqual(data["ignored"], [])

    def test_keys_lightroom_leaves_out_or_keeps_unused_still_match(self):
        base = sweep.EXT_BASE
        # Lightroom writes no sharpening, NR, grain or vignette details while those are off, and no B&W mix in colour.
        idle = [k for k in base if k.startswith(("Sharpen", "LuminanceNoise", "Grain", "GrayMixer", "PostCropVignette")) and k != "PostCropVignetteAmount"]
        self.put("a.jpg", "A.ARW", {**base, "SplitToningShadowHue": 210, "ColorGradeBlending": 60}, drop=idle)
        self.put("a-1.jpg", "A.ARW", {**base, "Sharpness": 80}, drop=["SharpenRadius", "SharpenDetail", "SharpenEdgeMasking"])
        r = sweep.ingest(self.ex, self.refs)
        self.assertEqual(r["problems"], [])
        self.assertTrue(os.path.exists(os.path.join(self.refs, "A__base.jpg")))
        self.assertTrue(os.path.exists(os.path.join(self.refs, "A__Sharpness__80.jpg")))

    def test_a_photo_given_one_sweep_is_expected_to_have_that_sweeps_presets_only(self):
        self.put("a.jpg", "A.ARW", "Base")
        self.put("a-1.jpg", "A.ARW", "Texture +25")
        self.put("b-1.jpg", "B.ARW", "Red Hue -50")
        self.put("b-2.jpg", "B.ARW", "Base")
        self.put("b-3.jpg", "B.ARW", "Base")   # B is in two hue albums: Base twice is fine
        self.put("b-4.jpg", "B.ARW", "Orange Hue -50")
        r = sweep.ingest(self.ex, self.refs)
        self.assertEqual(r["problems"], [])
        self.assertEqual(r["groups"], {"A": ["Lumina sweep 4 Presence"], "B": ["Lumina sweep 5 HSL Orange", "Lumina sweep 5 HSL Red"]})
        self.assertEqual(len(r["missing"]["A"]), 17)
        self.assertIn("4-01 Texture -100", r["missing"]["A"])
        self.assertEqual(r["missing"]["B"][:5], ["5-02 Red Hue +50", "5-03 Red Saturation -50", "5-04 Red Saturation +50",
                                                 "5-05 Red Luminance -50", "5-06 Red Luminance +50"])
        self.assertEqual(len(r["missing"]["B"]), 10)

    def test_problems_are_named_not_guessed(self):
        b = sweep.EXT_BASE
        self.put("off.jpg", "A.ARW", {**b, "Texture": 30})
        self.put("two.jpg", "A.ARW", {**b, "Texture": 25, "Clarity2012": 25})
        self.put("wb.jpg", "A.ARW", {**b, "Texture": 25, "WhiteBalance": "Custom", "Temperature": 5000, "Tint": 0})
        self.put("crop.jpg", "A.ARW", {**by_name("Texture +50")[2], "HasCrop": "True"})
        self.put("mask.jpg", "A.ARW", "Texture -50", extra="<crs:PaintBasedCorrections><rdf:Seq><rdf:li/></rdf:Seq></crs:PaintBasedCorrections>")
        self.put("curve.jpg", "A.ARW", {**by_name("Texture +100")[2], "ToneCurveName2012": "Custom"})
        self.put("prof.jpg", "A.ARW", {**by_name("Dehaze +25")[2], "LookName": "Adobe Vivid"})
        self.put("mono.jpg", "A.ARW", {**by_name("B&W")[2], "LookName": "Adobe Monochrome"})
        r = sweep.ingest(self.ex, self.refs)
        w = self.whys(r)
        self.assertIn("Texture 30: not a position of sweeps 4–13", w["off.jpg"])
        self.assertIn("Clarity2012 25, Texture 25: not a position", w["two.jpg"])
        self.assertIn("white balance is Custom", w["wb.jpg"])
        self.assertIn("cropped", w["crop.jpg"])
        self.assertIn("PaintBasedCorrections", w["mask.jpg"])
        self.assertIn("point curve Custom", w["curve.jpg"])
        self.assertIn("profile Adobe Vivid", w["prof.jpg"])
        self.assertNotIn("mono.jpg", w)
        self.assertEqual(len(w), 7)

    def test_a_sweep_folder_takes_only_its_own_presets_at_its_own_size(self):
        self.put("a.jpg", "A.ARW", "Base", width=6000)
        self.put("a-1.jpg", "A.ARW", "Sharpness 80 radius 1", width=6000)
        self.put("a-2.jpg", "A.ARW", "Sharpness 40 radius 2", width=2048)
        self.put("a-3.jpg", "A.ARW", "Texture +25", width=6000)
        r = sweep.ingest(self.ex, self.refs, only=8)
        w = self.whys(r)
        self.assertIn("exported at 2048 px", w["a-2.jpg"])
        self.assertIn("sweep 4's, in the sweep 8 folder", w["a-3.jpg"])
        self.assertEqual(r["sweep"], 8)
        self.assertEqual(len(r["missing"]["A"]), 12)
        self.assertNotIn("base", r["missing"]["A"])
        # Not a full-size sweep: 2048 px is what the others are exported at.
        self.put("b.jpg", "B.ARW", "Base", width=2048)
        self.assertNotIn("b.jpg", self.whys(sweep.ingest(self.ex, os.path.join(self.tmp.name, "r4"), only=4)))

    def test_ingest_sweeps_does_every_folder_in_one_command(self):
        root = self.tmp.name
        for n, preset in ((4, "Texture +25"), (11, "Vignette -50 feather +100")):
            d = os.path.join(root, "exports", f"sweep{n:02d}")
            os.makedirs(d)
            export(os.path.join(d, "a.jpg"), "A.ARW", sweep.EXT_BASE)
            export(os.path.join(d, "a-1.jpg"), "A.ARW", by_name(preset)[2])
        os.makedirs(os.path.join(root, "exports", "notes"))
        self.assertEqual(sweep.main(["ingest-sweeps", root]), 1)   # the rest of each sweep is missing
        for n, ref in ((4, "A__Texture__25"), (11, "A__s11p08")):
            data = load(os.path.join(root, "refs", f"sweep{n:02d}", "refs.json"))
            self.assertIn(ref, {e["id"] for e in data["refs"]})
            self.assertEqual(load(os.path.join(root, "refs", f"sweep{n:02d}", "sweep-ingest.json"))["problems"], [])
        self.assertEqual(sweep.main(["ingest-sweeps", os.path.join(root, "nope")]), 2)


PROBE = """<crs:MaskGroupBasedCorrections><rdf:Seq><rdf:li><rdf:Description crs:What="Correction" crs:CorrectionAmount="1"
 crs:CorrectionActive="true" crs:CorrectionName="Mask 1" crs:LocalExposure="0" crs:LocalExposure2012="{ev}" crs:LocalContrast2012="{con}"
 crs:LocalCurveRefineSaturation="100"><crs:CorrectionMasks><rdf:Seq><rdf:li crs:What="Mask/Image" crs:MaskActive="true"
 crs:MaskName="Sky 1" crs:MaskBlendMode="0" crs:MaskInverted="{inv}" crs:MaskValue="1" crs:MaskVersion="1" crs:MaskSubType="{sub}"
 crs:ReferencePoint="0.500000 0.500000" crs:LocalInputDigest="77FA16632F371F5BFF2F1527BB882591" crs:ErrorReason="0"/></rdf:Seq>
 </crs:CorrectionMasks></rdf:Description></rdf:li></rdf:Seq></crs:MaskGroupBasedCorrections>"""


def probe(ev="-0.250000", sub="2", inv="false", con="0"):
    """A correction shaped like the one Lightroom saved in the owner's "Lumina mask probe" preset."""
    return PROBE.format(ev=ev, sub=sub, inv=inv, con=con)


class MaskTests(unittest.TestCase):
    def test_the_preset_writes_lightrooms_structure(self):
        x = sweep.preset_xmp(*by_name("Sky local exposure -1"))
        for want in ('crs:What="Correction"', 'crs:What="Mask/Image"', 'crs:MaskSubType="2"', 'crs:LocalExposure2012="-0.2500"',
                     'crs:LocalCurveRefineSaturation="100"', 'crs:Version="18.7"', ">Lumina sweep 13 Sky<", 'crs:Texture="0"'):
            self.assertIn(want, x)
        self.assertNotIn("LocalInputDigest", x)
        self.assertNotIn('crs:Mask="', x)
        self.assertIn('crs:MaskSubType="1"', sweep.preset_xmp(*by_name("Subject local exposure +1")))
        # What the writer writes, the reader reads back as that position.
        crs = sweep.read_xmp_text(x)
        self.assertEqual(sweep.mask_signature(crs["MaskCorrections"]), (("sky", -1.0), None))

    def test_masked_exports_become_sweep_13_refs(self):
        with tempfile.TemporaryDirectory() as d:
            ex, refs = os.path.join(d, "ex"), os.path.join(d, "refs")
            os.makedirs(ex)
            export(os.path.join(ex, "a.jpg"), "A.ARW", sweep.EXT_BASE)
            export(os.path.join(ex, "a-1.jpg"), "A.ARW", sweep.EXT_BASE, extra=probe())
            export(os.path.join(ex, "a-2.jpg"), "A.ARW", sweep.EXT_BASE, extra=probe(ev="0.25", sub="1"))
            export(os.path.join(ex, "bad1.jpg"), "B.ARW", sweep.EXT_BASE, extra=probe(sub="3"))
            export(os.path.join(ex, "bad2.jpg"), "B.ARW", sweep.EXT_BASE, extra=probe(inv="true"))
            export(os.path.join(ex, "bad3.jpg"), "B.ARW", sweep.EXT_BASE, extra=probe(con="20"))
            export(os.path.join(ex, "bad4.jpg"), "B.ARW", sweep.EXT_BASE, extra=probe(ev="-0.5"))
            export(os.path.join(ex, "bad5.jpg"), "B.ARW", {**sweep.EXT_BASE, "Texture": 25}, extra=probe())
            r = sweep.ingest(ex, refs, only=13)
            w = {p["file"]: p["why"] for p in r["problems"]}
            self.assertIn("subtype 3", w["bad1.jpg"])
            self.assertIn("inverted", w["bad2.jpg"])
            self.assertIn("LocalContrast2012 20", w["bad3.jpg"])
            self.assertIn("-2 EV: not a sweep-13 position", w["bad4.jpg"])
            self.assertIn("on top of other changes", w["bad5.jpg"])
            self.assertEqual(len(w), 5)
            self.assertEqual(load(os.path.join(refs, "A__s13p01.json")),
                             {"sweep": 13, "preset": "13-01 Sky local exposure -1", "settings": {"Mask": "sky", "LocalExposure": -1}})
            self.assertEqual(load(os.path.join(refs, "A__s13p04.json"))["settings"], {"Mask": "subject", "LocalExposure": 1})
            self.assertEqual(r["groups"], {"A": ["Lumina sweep 13 Sky", "Lumina sweep 13 Subject"]})
            self.assertEqual(r["missing"]["A"], ["13-02 Sky local exposure +1", "13-03 Subject local exposure -1"])
            # The picker's not_clean still refuses a masked base export.
            self.assertIn("local edits", sweep.not_clean(sweep.read_xmp(os.path.join(ex, "a-1.jpg"))))


if __name__ == "__main__":
    unittest.main()
