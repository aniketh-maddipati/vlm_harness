import argparse
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import inventory


class InventoryTests(unittest.TestCase):
    def test_privacy_and_unknown_hdr(self):
        metadata, gps = inventory.sanitize({"GPS:GPSLatitude": 38.1, "GPS:GPSLongitude": -120,
                                           "EXIF:Model": "iPhone 15 Pro", "EXIF:SerialNumber": "private",
                                           "File:FileType": "DNG", "Apple:HDRGainMapVersion": 1})
        self.assertTrue(gps)
        self.assertFalse(any("GPS" in key or "Serial" in key for key in metadata))
        row = inventory.normalize(Path("/source/a.dng"), [5, 6, 7, 8, 9], metadata, gps)
        self.assertEqual(row["color"]["proraw_status"], "candidate_requires_decoder_verification")
        self.assertEqual(row["decode_status"], "UNMEASURED")
        self.assertEqual(row["color"]["gain_map_status"], "UNVERIFIED")

    def test_discovery_excludes_symlinks_appledouble_and_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "photo.JPG").write_bytes(b"image")
            (root / "._photo.JPG").write_bytes(b"resource")
            (root / "link.jpg").symlink_to(root / "photo.JPG")
            (root / "cache").write_bytes(b"\xff\xd8\xffabc")
            (root / "evidence").mkdir()
            (root / "evidence" / "output.jpg").write_bytes(b"output")
            found = list(inventory.discover([root, root], [root / "evidence"], True))
            self.assertEqual({path.name for path in found}, {"photo.JPG", "cache"})

    def test_identity_reuse_requires_unchanged_stat(self):
        previous = {"bytes": 10, "mtime": 20, "contentIdentity": "probe:abc"}
        row = inventory.normalize(Path("/a"), [10, 20_000_000_000, 0, 0, 0], {}, False, previous)
        self.assertEqual(row["fingerprint"]["content_identity"], "probe:abc")
        changed = inventory.normalize(Path("/a"), [11, 20_000_000_000, 0, 0, 0], {}, False, previous)
        self.assertIsNone(changed["fingerprint"]["content_identity"])

    def test_library_previews_are_not_originals(self):
        row = inventory.normalize(Path("/Pictures/Photos.photoslibrary/resources/derivatives/a.jpg"),
                                  [1, 2, 3, 4, 5], {"FileType": "JPEG"}, False)
        self.assertEqual(row["classification"], "cache_derivative")
        self.assertEqual(row["source_role"], "library_derivative")

    def test_permission_gap_is_reported_without_claiming_scan_complete(self):
        errors = []
        def denied(root, followlinks, onerror):
            onerror(PermissionError(1, "Operation not permitted", str(root)))
            return iter(())
        with patch.object(inventory.os, "walk", side_effect=denied):
            self.assertEqual(list(inventory.discover([Path("/denied")], [], errors=errors)), [])
        self.assertEqual(errors[0]["status"], "unavailable_not_scanned")

    def test_clock_groups_are_candidates_never_scene_labels(self):
        rows = [inventory.normalize(Path("/" + model), [1, 2, 3, 4, 5],
                {"Model": model, "FileType": "JPEG", "DateTimeOriginal": "2026:09:01 12:05:00"}, False)
                for model in ("iPhone 15", "ILCE-7M3")]
        group = inventory.candidates(rows)[0]
        self.assertTrue(group["cross_device_candidate"])
        self.assertFalse(group["scene_verified"])

    def test_resume_invalidates_changed_file_and_never_writes_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            root.mkdir()
            photo = root / "photo.jpg"
            photo.write_bytes(b"original")
            before = inventory.stat_key(photo)
            args = argparse.Namespace(root=[root], out=Path(directory) / "out", exclude=[], reuse_raw=[],
                                      extensionless=False, exiftool="fake", batch_size=2)
            def extract(paths, executable):
                return {str(path): {"SourceFile": str(path), "FileType": "JPEG"} for path in paths}
            with patch.object(inventory.subprocess, "check_output", return_value="13.0"), \
                    patch.object(inventory.platform, "platform", return_value="test-host"), \
                    patch.object(inventory, "extract", side_effect=extract) as extractor, contextlib.redirect_stdout(io.StringIO()):
                inventory.run(args)
                inventory.run(args)
                self.assertEqual(extractor.call_count, 1)
                self.assertEqual(inventory.stat_key(photo), before)
                self.assertEqual(json.loads((args.out / "manifest.json").read_text())["cache_hits"], 1)
                photo.write_bytes(b"changed")
                inventory.run(args)
                self.assertEqual(extractor.call_count, 2)

    def test_source_change_during_extraction_is_not_cached(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            root.mkdir()
            photo = root / "photo.jpg"
            photo.write_bytes(b"original")
            args = argparse.Namespace(root=[root], out=Path(directory) / "out", exclude=[], reuse_raw=[],
                                      extensionless=False, exiftool="fake", batch_size=2)
            def mutate(paths, executable):
                photo.write_bytes(b"external change")
                return {}
            with patch.object(inventory.subprocess, "check_output", return_value="13.0"), \
                    patch.object(inventory, "extract", side_effect=mutate):
                with self.assertRaisesRegex(RuntimeError, "Source changed"):
                    inventory.run(args)


if __name__ == "__main__":
    unittest.main()
