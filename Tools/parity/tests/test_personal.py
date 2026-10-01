"""import_lr_edits.py and parity_personal.py without photos: synthetic XMP, tiny generated images."""
import io
import json
import os
import struct
import sys
import tempfile
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import delta_e  # noqa: E402
import import_lr_edits as lr  # noqa: E402
import import_refs  # noqa: E402
import lookmath  # noqa: E402
import parity_personal as pp  # noqa: E402

CRS = 'xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"'
RDF = 'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"'


BASE = {"crs:ProcessVersion": "15.4", "crs:RawFileName": "DSC00001.ARW", "crs:CameraProfile": "Adobe Standard", "crs:Sharpness": "40",
        "crs:ColorNoiseReduction": "25", "crs:LensProfileEnable": "1", "crs:HasCrop": "False"}


def xmp(attrs="", body=""):
    """An XMP packet shaped like Lightroom's: crs values as attributes (`attrs` overrides the
    defaults above), structures as elements."""
    import re
    fields = dict(BASE)
    fields.update(dict(re.findall(r'(\S+?)="([^"]*)"', attrs)))
    attrs = " ".join(f'{k}="{v}"' for k, v in fields.items())
    return (f'<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?><x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF {RDF}>'
            f'<rdf:Description rdf:about="" {CRS} xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/" xmlns:aux="http://ns.adobe.com/exif/1.0/aux/" '
            f'xmpMM:OriginalDocumentID="ABC123" aux:Lens="Test 50mm" {attrs}>'
            f'<crs:Look><rdf:Description crs:Name="Adobe Color"/></crs:Look>'
            f'<crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 0</rdf:li><rdf:li>255, 255</rdf:li></rdf:Seq></crs:ToneCurvePV2012>'
            f'{body}</rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end="w"?>')


def jpeg_with(main, extended=None, size=(24, 16)):
    """A real JPEG (Pillow) with an APP1 XMP segment and, optionally, ExtendedXMP chunks."""
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", size, (120, 110, 100)).save(buf, "JPEG")
    data = buf.getvalue()
    segs = []
    body = b"http://ns.adobe.com/xap/1.0/\x00" + main.encode()
    segs.append(b"\xff\xe1" + struct.pack(">H", len(body) + 2) + body)
    if extended:
        blob, guid = extended.encode(), b"0123456789ABCDEF0123456789ABCDEF"
        half = len(blob) // 2
        for off, chunk in ((half, blob[half:]), (0, blob[:half])):  # out of order on purpose
            b2 = b"http://ns.adobe.com/xmp/extension/\x00" + guid + struct.pack(">II", len(blob), off) + chunk
            segs.append(b"\xff\xe1" + struct.pack(">H", len(b2) + 2) + b2)
    return data[:2] + b"".join(segs) + data[2:]


class XmpReadingTests(unittest.TestCase):
    def test_main_and_extended_packets(self):
        ext = (f'<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF {RDF}><rdf:Description rdf:about="" {CRS}>'
               '<crs:MaskGroupBasedCorrections><rdf:Seq><rdf:li><rdf:Description crs:What="Correction" crs:CorrectionAmount="1"/></rdf:li></rdf:Seq>'
               '</crs:MaskGroupBasedCorrections></rdf:Description></rdf:RDF></x:xmpmeta>')
        data = jpeg_with(xmp('crs:Exposure2012="+0.30" crs:WhiteBalance="As Shot"'), ext)
        main, extended = lr.jpeg_xmp(data)
        crs = lr.parse_crs(main, extended)
        self.assertEqual(crs["Exposure2012"], "+0.30")
        self.assertEqual(crs["RawFileName"], "DSC00001.ARW")
        self.assertEqual(crs["_OriginalDocumentID"], "ABC123")
        self.assertEqual(crs["_Lens"], "Test 50mm")
        self.assertEqual(crs["Look"], {"Name": "Adobe Color"})
        self.assertEqual(crs["ToneCurvePV2012"], ["0, 0", "255, 255"])
        self.assertEqual(len(crs["MaskGroupBasedCorrections"]), 1)
        self.assertIn("masks", lr.features(crs)[0])

    def test_not_a_jpeg(self):
        with self.assertRaises(ValueError):
            lr.jpeg_xmp(b"GIF89a")


def crs_of(attrs="", body=""):
    return lr.parse_crs(xmp(attrs, body))


class BucketTests(unittest.TestCase):
    def test_untouched_is_as_shot_even_cropped(self):
        crs = crs_of('crs:WhiteBalance="As Shot" crs:Temperature="5200" crs:Tint="+8" crs:HasCrop="True" crs:CropLeft="0.1" crs:CropTop="0" crs:CropRight="0.9" crs:CropBottom="1"')
        major, minor = lr.features(crs)
        self.assertEqual(major, [])
        self.assertEqual(minor, ["lensProfile"], "lens profile on is Lightroom's default: reported, not demoting")
        self.assertEqual(lr.changed(crs), [])
        self.assertEqual(lr.bucket(major, lr.changed(crs)), "as-shot")

    def test_basic_sliders_only(self):
        crs = crs_of('crs:Exposure2012="+0.30" crs:Contrast2012="+6" crs:Highlights2012="-66" crs:Shadows2012="+53" crs:Whites2012="+6" '
                     'crs:Blacks2012="-16" crs:Vibrance="+15" crs:Saturation="-1" crs:PostCropVignetteAmount="-8" crs:WhiteBalance="Custom" '
                     'crs:Temperature="4950" crs:Tint="+18"')
        major, _ = lr.features(crs)
        moved = lr.changed(crs)
        self.assertEqual(major, [])
        self.assertEqual(set(moved), {"Exposure", "Contrast", "Highlights", "Shadows", "Whites", "Blacks", "Vibrance", "Saturation", "PostCropVignette", "WhiteBalance"})
        self.assertEqual(lr.bucket(major, moved), "basic-only")

    def test_every_unsupported_feature_is_named(self):
        cases = {
            "texture": 'crs:Texture="+11"', "dehaze": 'crs:Dehaze="+8"', "hsl": 'crs:SaturationAdjustmentOrange="-10"',
            "colorGrading": 'crs:ColorGradeMidtoneSat="12"', "calibration": 'crs:RedHue="+5"', "grain": 'crs:GrainAmount="20"',
            "perspective": 'crs:PerspectiveVertical="-10"', "defringe": 'crs:DefringePurpleAmount="3"', "lensVignetteManual": 'crs:VignetteAmount="+20"',
            "toneCurve": 'crs:ParametricShadows="-10"', "profile": 'crs:CameraProfile="Camera Standard"',
        }
        for feature, attr in cases.items():
            with self.subTest(feature=feature):
                crs = crs_of(attr) if feature != "profile" else lr.parse_crs(xmp().replace('crs:CameraProfile="Adobe Standard"', attr))
                major, _ = lr.features(crs)
                self.assertIn(feature, major)
                self.assertEqual(lr.bucket(major, lr.changed(crs)), "unsupported-features")
        curve = '<crs:ToneCurvePV2012Red><rdf:Seq><rdf:li>0, 0</rdf:li><rdf:li>128, 150</rdf:li><rdf:li>255, 255</rdf:li></rdf:Seq></crs:ToneCurvePV2012Red>'
        self.assertIn("toneCurve", lr.features(crs_of(body=curve))[0])
        portrait = lr.parse_crs(xmp().replace('crs:Name="Adobe Color"', 'crs:Name="Adobe Portrait"'))
        self.assertIn("profile", lr.features(portrait)[0])
        denoise = ('<crs:FilterList rdf:parseType="Resource"><crs:Filters><rdf:Seq><rdf:li><rdf:Description crs:Name="Enhance" '
                   'crs:Title="$$$/CRaw/Filter/Title/Denoise=Denoise"/></rdf:li></rdf:Seq></crs:Filters></crs:FilterList>')
        self.assertIn("aiDenoise", lr.features(crs_of(body=denoise))[0])
        blur = '<crs:LensBlur crs:Version="1" crs:Active="true" crs:BlurAmount="50"/>'
        self.assertIn("lensBlur", lr.features(crs_of(body=blur))[0])
        self.assertNotIn("lensBlur", lr.features(crs_of(body=blur.replace("true", "false")))[0])

    def test_minor_features_do_not_demote(self):
        crs = crs_of('crs:ColorNoiseReduction="0" crs:SharpenDetail="40" crs:Exposure2012="+0.5"')
        major, minor = lr.features(crs)
        self.assertEqual(major, [])
        self.assertIn("colorNR", minor)
        self.assertIn("sharpenDetail", minor)
        self.assertEqual(lr.bucket(major, lr.changed(crs)), "basic-only")


class LookMappingTests(unittest.TestCase):
    def test_sliders_map_to_the_look_string(self):
        crs = crs_of('crs:Exposure2012="+0.30" crs:Contrast2012="+6" crs:Highlights2012="-66" crs:Shadows2012="+53" crs:Whites2012="+6" '
                     'crs:Blacks2012="-16" crs:Vibrance="+15" crs:Saturation="-1" crs:Clarity2012="+13" crs:PostCropVignetteAmount="-8" '
                     'crs:LuminanceSmoothing="20" crs:WhiteBalance="As Shot" crs:Temperature="4950" crs:Tint="+18"')
        look = lr.build_look(lr.settings(crs), None, (4800.0, 15.0), None)
        self.assertEqual(look, "ev:+0.30 con:+6 hl:-66 sh:+53 wh:+6 bl:-16 vib:+15 sat:-1 clr:+13 shp:40 vig:-8 nr:20")
        self.assertEqual(lookmath.format_look(lookmath.parse_look(look)), look, "canonical, as Look.format writes it")

    def test_luminance_nr_zero_leaves_the_decoder_default(self):
        look = lr.build_look(lr.settings(crs_of()), None, (5000.0, 0.0), None)
        self.assertNotIn("nr:", look)
        self.assertEqual(look, "ev:0.00 con:0 hl:0 sh:0 wh:0 bl:0 vib:0 sat:0 clr:0 shp:40 vig:0")

    def test_white_balance_moves_apples_as_shot_by_lightrooms_delta(self):
        cal = lr.wb_calibration([((5000.0, 10.0), (5263.16, 7.0)), ((4000.0, 5.0), (4166.67, 2.0)), ((6000.0, 0.0), (6382.98, -3.0))])
        self.assertAlmostEqual(cal["mired"], 10.0, places=1)
        self.assertAlmostEqual(cal["tint"], 3.0)
        apple = (5263.16, 7.0)
        lr_shot = lr.lr_as_shot_estimate(apple, cal)
        self.assertAlmostEqual(lr_shot[0], 5000.0, delta=1.0)
        self.assertAlmostEqual(lr_shot[1], 10.0)
        s = lr.settings(crs_of('crs:WhiteBalance="Custom" crs:Temperature="4000" crs:Tint="+20"'))
        self.assertEqual((s["Temperature"], s["Tint"]), (4000.0, 20.0))
        look = lookmath.parse_look(lr.build_look(s, None, apple, lr_shot))
        # Lightroom moved +50 mired (5000 → 4000) and +10 tint: Apple's as shot moves the same.
        self.assertAlmostEqual(1e6 / look["wb"][0], 1e6 / apple[0] + 50.0, delta=0.1)
        self.assertEqual(look["wb"][1], 17.0)
        self.assertNotIn("Temperature", lr.settings(crs_of('crs:WhiteBalance="As Shot" crs:Temperature="4000"')), "As Shot = no wb key")


class CropTests(unittest.TestCase):
    def test_full_frame_is_no_crop(self):
        self.assertIsNone(lr.crop_upright(crs_of('crs:HasCrop="True" crs:CropLeft="1e-06" crs:CropTop="0" crs:CropRight="0.999999" crs:CropBottom="1"')))
        self.assertIsNone(lr.crop_upright(crs_of('crs:HasCrop="False" crs:CropLeft="0.2" crs:CropRight="0.8"')))

    def test_crop_lands_on_the_same_pixels_in_every_orientation(self):
        """Lightroom crops the RAW as stored, then turns it upright; Lumina develops upright, then
        crops with (x, y, w, h), y from the top. Both must cut out the same pixels."""
        rng = np.random.default_rng(3)
        stored = rng.random((60, 90))
        H, W = stored.shape
        box = dict(CropLeft=0.1, CropTop=0.2, CropRight=0.7, CropBottom=0.9)
        attrs = 'crs:HasCrop="True" ' + " ".join(f'crs:{k}="{v}"' for k, v in box.items())
        turn = {1: lambda a: a, 3: lambda a: np.rot90(a, 2), 6: lambda a: np.rot90(a, -1), 8: lambda a: np.rot90(a, 1)}
        for orientation, upright in turn.items():
            with self.subTest(orientation=orientation):
                lr_pixels = upright(stored[int(round(box["CropTop"] * H)):int(round(box["CropBottom"] * H)),
                                           int(round(box["CropLeft"] * W)):int(round(box["CropRight"] * W))])
                up = upright(stored)
                x, y, w, h, rot = lr.crop_upright(crs_of(attrs), orientation)
                uh, uw = up.shape
                lumina = up[int(round(y * uh)):int(round((y + h) * uh)), int(round(x * uw)):int(round((x + w) * uw))]
                self.assertEqual(rot, 0.0)
                np.testing.assert_array_equal(lumina, lr_pixels)

    def test_render_size_covers_the_comparison(self):
        self.assertEqual(lr.render_px(None, (6000, 4000)), 1024)
        px = lr.render_px((0.25, 0.0, 0.5, 1.0, 0.0), (6000, 4000))  # 3000 × 4000 kept: the long edge is the height
        self.assertEqual(px, 1536)
        self.assertGreaterEqual(1.0 * 4000 * px / 6000, 1024, "the crop's long edge at that develop size")
        self.assertEqual(lr.render_px((0.45, 0.45, 0.01, 0.01, 0.0), (6000, 4000)), 6000, "capped at the RAW's size")


class ImportTests(unittest.TestCase):
    def test_folder_to_refs(self):
        """Two exports of one RAW (a virtual copy), one without a RAW: the index has the edits,
        their buckets, looks and sRGB space; the lonely export is skipped."""
        with tempfile.TemporaryDirectory() as d:
            exports, raws, out = (os.path.join(d, n) for n in ("exports", "raws", "set/refs"))
            os.makedirs(exports)
            os.makedirs(raws)
            open(os.path.join(raws, "DSC00001.ARW"), "wb").write(b"not really a raw")
            open(os.path.join(exports, "DSC00001.jpg"), "wb").write(jpeg_with(xmp('crs:Exposure2012="+0.50" crs:WhiteBalance="As Shot" crs:Temperature="5000" crs:Tint="+5"')))
            open(os.path.join(exports, "DSC00001-2.jpg"), "wb").write(jpeg_with(xmp('crs:Dehaze="+10" crs:WhiteBalance="As Shot" crs:Temperature="5000" crs:Tint="+5"')))
            open(os.path.join(exports, "IMG_1.jpg"), "wb").write(jpeg_with(xmp().replace("DSC00001.ARW", "IMG_1.HEIC")))
            fake = os.path.join(d, "fake-render")
            with open(fake, "w") as f:  # `lumina-render asshot` stand-in
                f.write("#!/bin/sh\nfor a in \"$@\"; do [ \"$a\" = asshot ] && continue; "
                        "echo \"{\\\"image\\\":\\\"$a\\\",\\\"ok\\\":true,\\\"asShot\\\":{\\\"kelvin\\\":5263.16,\\\"tint\\\":3},\\\"width\\\":60,\\\"height\\\":40,\\\"orientation\\\":1}\"; done\n")
            os.chmod(fake, 0o755)
            data, refs_json = lr.run(exports, raws, out, fake)
            edits = {r["id"]: r for r in data["refs"] if r["kind"] == "edit"}
            self.assertEqual(sorted(edits), ["DSC00001__edit01", "DSC00001__edit02"])
            self.assertEqual(edits["DSC00001__edit01"]["export"], "DSC00001-2.jpg")
            self.assertEqual(edits["DSC00001__edit01"]["bucket"], "unsupported-features")
            self.assertEqual(edits["DSC00001__edit02"]["bucket"], "basic-only")
            self.assertEqual(edits["DSC00001__edit02"]["look"], "ev:+0.50 con:0 hl:0 sh:0 wh:0 bl:0 vib:0 sat:0 clr:0 shp:40 vig:0")
            self.assertEqual(edits["DSC00001__edit02"]["space"], "srgb")
            self.assertEqual(edits["DSC00001__edit02"]["settings"]["Exposure"], 0.5)
            self.assertEqual(edits["DSC00001__edit02"]["virtualCopies"], 2)
            self.assertEqual(data["counts"]["edits"], 2)
            self.assertEqual([s["export"] for s in data["skipped"]], ["IMG_1.jpg"])
            self.assertEqual(data["wbCalibration"]["n"], 2)
            self.assertAlmostEqual(data["wbCalibration"]["mired"], 1e6 / 5000 - 1e6 / 5263.16, places=3)
            self.assertTrue(os.path.exists(refs_json))
            again = import_refs.index(out)
            self.assertEqual(len(again["refs"]), 2)


class MeasureTests(unittest.TestCase):
    def scene(self, h=96, w=144, seed=0, block=8):
        rng = np.random.default_rng(seed)
        img = np.repeat(np.repeat(rng.random((h // block, w // block, 3)), block, 0), block, 1)
        return 0.15 + 0.7 * img

    def test_median3_matches_scipy(self):
        try:
            from scipy.ndimage import median_filter
        except ImportError:
            self.skipTest("scipy not installed")
        x = np.random.default_rng(1).random((37, 53, 3))
        x[::5] = 0.5
        want = np.stack([median_filter(x[..., c], size=3, mode="nearest") for c in range(3)], -1)
        np.testing.assert_array_equal(delta_e.median3(x), want)

    def test_identical_images(self):
        img = self.scene()
        m, de, sample = pp.measure_images(img, img.copy(), "srgb")
        self.assertEqual(m["all"]["max"], 0.0)
        self.assertEqual((m["shift"]["dy"], m["shift"]["dx"]), (0, 0))
        self.assertEqual(sample.size, 4000)

    def test_shift_and_vignette_are_seen(self):
        img = self.scene()
        moved = np.roll(img, (0, 3), axis=(0, 1))
        m, _, _ = pp.measure_images(img, moved, "srgb")
        self.assertEqual((m["shift"]["dy"], m["shift"]["dx"]), (0, -3))
        h, w = img.shape[:2]
        yy, xx = np.mgrid[0:h, 0:w]
        r = np.hypot((yy - (h - 1) / 2) / (h / 2), (xx - (w - 1) / 2) / (w / 2)) / np.sqrt(2)
        dark_corners = img * (1 - 0.5 * r ** 2)[..., None]
        m, _, _ = pp.measure_images(img, dark_corners, "srgb")
        self.assertLess(m["dLborder"], -5)
        self.assertLess(m["dLradial"][4], m["dLradial"][0])
        self.assertLess(m["dL"], 0)

    def test_measure_job_resizes_and_checks_aspect(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as d:
            img = self.scene(192, 288, block=48)
            ref, ren = os.path.join(d, "ref.png"), os.path.join(d, "ren.tif")
            Image.fromarray((img * 255).round().astype(np.uint8)).save(ref)
            import tifffile
            half = pp.resize_to(img, (144, 96))
            tifffile.imwrite(ren, (half * 65535).round().astype(np.uint16))
            res = pp.measure_job({"id": "x", "ref": ref, "render": ren, "comparePx": 96, "space": "srgb", "refCache": os.path.join(d, "cache")})
            self.assertTrue(res["ok"], res.get("error"))
            self.assertEqual(res["measure"]["size"], [96, 64])
            self.assertLess(res["measure"]["all"]["median"], 0.5)
            again = pp.measure_job({"id": "x", "ref": ref, "render": ren, "comparePx": 96, "space": "srgb", "refCache": os.path.join(d, "cache")})
            self.assertAlmostEqual(again["measure"]["all"]["median"], res["measure"]["all"]["median"], places=3)
            tifffile.imwrite(ren, (np.ones((50, 50, 3)) * 30000).astype(np.uint16))
            bad = pp.measure_job({"id": "x", "ref": ref, "render": ren, "comparePx": 96, "space": "srgb"})
            self.assertFalse(bad["ok"])
            self.assertIn("aspect", bad["error"])


class AggregateTests(unittest.TestCase):
    def test_ablation_looks(self):
        abl = dict(pp.ablation_looks("ev:+0.50 wb:5000/+3 con:+10 hl:0 sh:0 wh:0 bl:0 vib:0 sat:0 clr:0 shp:40 vig:0 crop:0.1000,0.0000,0.8000,1.0000"))
        self.assertEqual(sorted(abl), ["con", "ev", "none", "shp", "wb"])
        self.assertTrue(abl["ev"].startswith("ev:0.00 wb:5000/+3 con:+10"))
        self.assertEqual(abl["none"], "ev:0.00 con:0 hl:0 sh:0 wh:0 bl:0 vib:0 sat:0 clr:0 shp:0 vig:0 crop:0.1000,0.0000,0.8000,1.0000")
        self.assertEqual(pp.ablation_looks("ev:0.00 con:0 hl:0 sh:0 wh:0 bl:0 vib:0 sat:0 clr:0 shp:0 vig:0"), [])

    def test_buckets_sliders_and_ablation(self):
        rng = np.random.default_rng(0)

        def frame(i, bucket, ev, de, dl, features=()):
            m = {"all": {"median": de, "p95": de * 2}, "dL": dl, "da": 0.0, "db": 0.0, "dC": 0.0, "dLborder": -1.0,
                 "dLradial": [0.0, 0.0, -1.0, -2.0, -3.0], "byL": [de] * 10, "shift": {"dy": 0, "dx": 0, "peak": 0.9}}
            for reg in ("shadows", "midtones", "highlights", "skin", "centre", "border"):
                m[reg] = {"n": 10, "median": de}
            ref = {"id": f"F{i}", "bucket": bucket, "features": list(features), "lens": "L",
                   "settings": {"Exposure": ev, "Sharpness": 40.0}, "lrAsShot": None, "look": f"ev:{ev:+.2f}"}
            return {"ref": ref, "measure": m, "sample": rng.normal(de, 0.1, 50)}
        frames = [frame(i, "as-shot", 0.0, 2.0, 0.0) for i in range(3)]
        frames += [frame(10 + i, "basic-only", 0.2 * (i + 1), 3.0 + i, -i) for i in range(6)]
        frames += [frame(20, "unsupported-features", 0.5, 6.0, -2.0, ["dehaze"])]
        abl = {f"F{10 + i}": {"ev": {"id": f"F{10 + i}", "measure": {"all": {"median": 4.0 + i}, "dL": -i - 1.0, "dC": 0.0}}} for i in range(6)}
        agg = pp.aggregate(frames, abl)
        self.assertEqual(agg["buckets"]["as-shot"]["n"], 3)
        self.assertAlmostEqual(agg["buckets"]["as-shot"]["frameMedian"], 2.0)
        self.assertEqual(agg["features"]["dehaze"]["n"], 1)
        ev = agg["sliders"]["Exposure"]
        self.assertEqual(ev["active"], 7, "the edited frames (basic-only + unsupported), not the as-shot ones")
        self.assertLess(ev["dLperUnit"], 0)
        self.assertEqual(ev["ablation"]["n"], 6)
        self.assertAlmostEqual(ev["ablation"]["medianDelta"], -1.0)
        self.assertEqual(ev["ablation"]["helps"], 1.0)
        self.assertAlmostEqual(ev["ablation"]["stageDL"], 1.0)
        self.assertEqual(ev["ablation"]["matchedN"], 2)  # |ΔL*| < 2: the frames with dl 0 and -1
        self.assertEqual(agg["sliders"]["Sharpness"]["active"], 0, "Lightroom's default 40 isn't a move")
        md = pp.report_md(agg, frames, {"label": "t", "date": "d", "rules": "r", "raws": 1, "comparePx": 1024}, {"total": 1.0}, None)
        self.assertIn("| as-shot | 3 |", md)


if __name__ == "__main__":
    unittest.main()
