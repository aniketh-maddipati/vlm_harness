#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import service as golden


class GoldenServiceTests(unittest.TestCase):
    def test_propose_approve_compare_never_autobless(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = Path(tmp)
            with mock.patch.object(golden, "STORE", store), mock.patch.object(
                golden, "tokens_hash", return_value="abc123"
            ):
                payload = {"chrome": {"histogram_width": 252}, "mask": ["photograph"]}
                proposed = golden.propose("chrome_table", payload)
                self.assertTrue(proposed.is_file())
                # Compare before approve must fail.
                self.assertFalse(golden.compare("chrome_table", payload)["ok"])
                approved = golden.approve("chrome_table")
                self.assertTrue(approved.is_file())
                self.assertTrue(golden.compare("chrome_table", payload)["ok"])
                self.assertFalse(golden.compare("chrome_table", {"chrome": {}})["ok"])

    def test_token_change_invalidates(self):
        with tempfile.TemporaryDirectory() as tmp:
            store = Path(tmp)
            with mock.patch.object(golden, "STORE", store):
                with mock.patch.object(golden, "tokens_hash", return_value="hash_old"):
                    golden.propose("ring", {"w": 1.5})
                    golden.approve("ring")
                names = golden.invalidate_for_tokens_change("hash_old", "hash_new")
                self.assertEqual(names, ["ring"])
                stale = store / "hash_new" / "ring" / "STALE_TOKENS.md"
                self.assertTrue(stale.is_file())
                # New hash has no approved golden.
                with mock.patch.object(golden, "tokens_hash", return_value="hash_new"):
                    self.assertFalse(golden.compare("ring", {"w": 1.5})["ok"])


if __name__ == "__main__":
    raise SystemExit(unittest.main())
