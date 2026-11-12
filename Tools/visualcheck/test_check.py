#!/usr/bin/env python3
"""check.py without a model: synthetic images, a mocked LM Studio reply.

    ~/LuminaEvidence/venv-parity/bin/python -m pytest Tools/visualcheck -q
    ~/LuminaEvidence/venv-parity/bin/python Tools/visualcheck/test_check.py   (no pytest)
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check as C  # noqa: E402


def scene(w=640, h=427, seed=0):
    """A photo-like test image: smooth gradients, a few edges, mild noise, 0..1 sRGB."""
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:h, 0:w] / max(w, h)
    rgb = np.stack([0.25 + 0.5 * x, 0.3 + 0.4 * y, 0.55 - 0.3 * x * y], -1)
    rgb[h // 3: h // 2, w // 5: w // 2] = [0.8, 0.55, 0.4]          # a skin-ish block
    rgb[::23] *= 0.85                                                # texture
    rgb[:, ::31] *= 0.9
    rgb += rng.normal(0, 0.004, rgb.shape)
    return np.clip(rgb, 0, 1)


def save(rgb, path):
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)).save(path)
    return str(path)


def fake_post(seen, reason="B is greener"):
    calls = []

    def post(url, body, timeout=180):
        calls.append((url, body))
        content = json.dumps({"visible_difference": seen, "reason": reason})
        return {"choices": [{"message": {"content": content}}]}
    post.calls = calls
    return post


class Pairs(unittest.TestCase):
    def test_suffix_dir(self):
        with tempfile.TemporaryDirectory() as d:
            a = scene()
            for n in ("X-before.png", "X-after.png", "Y_canvas.png", "Y_export.png", "lonely.png"):
                save(a, Path(d) / n)
            pairs = {p.name: p for p in C.load_pairs(d)}
            self.assertEqual(set(pairs), {"X", "Y"})
            self.assertTrue(pairs["X"].a.endswith("X-before.png"))
            self.assertEqual((pairs["Y"].label_a, pairs["Y"].label_b), ("canvas", "export"))

    def test_subdirs_and_list(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "before").mkdir()
            (Path(d) / "after").mkdir()
            save(scene(), Path(d) / "before" / "p1.png")
            save(scene(), Path(d) / "after" / "p1.png")
            self.assertEqual([p.name for p in C.load_pairs(d)], ["p1"])
            lst = Path(d) / "pairs.txt"
            lst.write_text("# a comment\nbefore/p1.png after/p1.png named\n\n")
            [p] = C.load_pairs(lst)
            self.assertEqual(p.name, "named")
            self.assertTrue(Path(p.a).is_file())


class Numbers(unittest.TestCase):
    def setUp(self):
        self.a = scene()

    def flags(self, b):
        _, n = C.measure(self.a, b)
        return n, C.numbers_reasons(n)

    def test_identical_is_quiet(self):
        n, r = self.flags(self.a.copy())
        self.assertEqual(r, [])
        self.assertLess(n["p95"], 0.01)

    def test_exposure_is_brighter(self):
        lin = C.DE.decode_srgb(self.a) * 2 ** 0.3
        n, r = self.flags(C.DE.encode_srgb(lin))
        self.assertTrue(r and "brighter" in r[0], r)

    def test_green_tint(self):
        lin = C.DE.decode_srgb(self.a) * np.array([0.96, 1.05, 0.96])
        n, r = self.flags(C.DE.encode_srgb(lin))
        self.assertTrue(r and "greener" in r[0], r)

    def test_global_blur_is_softer(self):
        im = Image.fromarray((self.a * 255).astype(np.uint8))
        from PIL import ImageFilter
        b = np.asarray(im.filter(ImageFilter.GaussianBlur(1.5)), dtype=np.float64) / 255
        n, r = self.flags(b)
        self.assertTrue(any("softer" in x for x in r), r)

    def test_seam_found_on_its_line(self):
        b = self.a.copy()
        b[:, 320:] = C.DE.encode_srgb(C.DE.decode_srgb(b[:, 320:]) * 1.05)
        n, r = self.flags(b)
        self.assertGreaterEqual(n["seam"], C.THRESHOLDS["seam"])
        kind, i, _ = n["seam_at"]
        self.assertEqual(kind, "column")
        self.assertLessEqual(abs(i - 320), 2)

    def test_small_noise_is_quiet(self):
        rng = np.random.default_rng(1)
        n, r = self.flags(np.clip(self.a + rng.normal(0, 0.003, self.a.shape), 0, 1))
        self.assertEqual(r, [])


class Model(unittest.TestCase):
    def test_refuses_non_loopback(self):
        for url in ("http://api.example.com/v1/chat/completions", "http://192.168.1.5:1234/v1",
                    "https://10.0.0.1/v1"):
            with self.assertRaises(SystemExit):
                C.require_loopback(url)
        for url in ("http://127.0.0.1:1234/v1", "http://localhost:1234/v1", "http://[::1]:1234/v1"):
            C.require_loopback(url)

    def test_request_shape(self):
        a = scene()
        body = C.build_request(a, a)
        content = body["messages"][0]["content"]
        imgs = [c for c in content if c["type"] == "image_url"]
        self.assertEqual(len(imgs), 2)
        self.assertTrue(imgs[0]["image_url"]["url"].startswith("data:image/jpeg;base64,"))
        self.assertEqual(body["response_format"]["type"], "json_schema")
        self.assertEqual(body["temperature"], 0)

    def test_parse_fenced_reply(self):
        resp = {"choices": [{"message": {"content":
                '```json\n{"visible_difference": true, "reason": "shadows crushed"}\n```'}}]}
        self.assertEqual(C.parse_reply(resp), (True, "shadows crushed"))

    def test_model_never_sees_a_remote_url(self):
        post = fake_post(True)
        with self.assertRaises(SystemExit):
            C.ask_model(scene(), scene(), url="http://example.com/v1", post=post)
        self.assertEqual(post.calls, [])


class Run(unittest.TestCase):
    def test_end_to_end_flagged_first(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            pairs = d / "pairs"
            pairs.mkdir()
            a = scene()
            save(a, pairs / "same-before.png")
            save(a, pairs / "same-after.png")
            save(a, pairs / "warm-before.png")
            save(C.DE.encode_srgb(C.DE.decode_srgb(a) * np.array([1.06, 1, 0.92])), pairs / "warm-after.png")
            out = d / "out"
            out.mkdir()
            post = fake_post(False, "no visible difference")
            results = [C.check_pair(p, out, True, post=post) for p in C.load_pairs(pairs)]
            self.assertEqual(len(post.calls), 2)
            page = C.write_report(results, out, {"run": "t", "model": "mock", "pairs": str(pairs)})
            rep = json.loads((out / "report.json").read_text())
            self.assertEqual(rep["results"][0]["name"], "warm")
            self.assertEqual(rep["results"][0]["by"], ["numbers"])
            self.assertFalse(rep["results"][1]["flagged"])
            self.assertIn("warm", page.read_text())
            self.assertTrue((out / rep["results"][0]["heatmap"]).is_file())
            self.assertIn("| warm |", (out / "report.md").read_text())

    def test_model_error_keeps_numbers(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            a = scene()
            pa, pb = save(a, d / "x-a.png"), save(a, d / "x-b.png")

            def broken(url, body, timeout=180):
                raise ConnectionRefusedError("LM Studio not running")
            r = C.check_pair(C.Pair("x", pa, pb), d, True, post=broken)
            self.assertIn("ConnectionRefusedError", r.error)
            self.assertFalse(r.flagged)

    def test_out_inside_repo_refused(self):
        repo = Path(C.__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(SystemExit):
                C.main(["--pairs", d, "--out", str(repo / "Tools" / "visualcheck" / "out"), "--no-model"])


if __name__ == "__main__":
    unittest.main()
