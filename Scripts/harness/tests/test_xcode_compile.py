#!/usr/bin/env python3
"""Parser tests for the xcode_compile error collector (no xcodebuild required)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

HARNESS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HARNESS / "lint"))

import xcode_compile  # noqa: E402


SAMPLE = """
SwiftCompile normal arm64 Compiling P0EditLiveRunner.swift
/Users/me/Lumina/Develop/Lab/P0EditLiveRunner.swift:120:24: error: 'developScheduler' is inaccessible due to 'private' protection level
    session.developScheduler.presentedCIImage(for: landscape.id)
/Users/me/Lumina/Develop/Lab/P0EditLiveRunner.swift:120:24: error: 'developScheduler' is inaccessible due to 'private' protection level
/Users/me/Lumina/Views/P0/P0SinglePhotoEditor.swift:111:48: error: 'developScheduler' is inaccessible due to 'private' protection level
error: signing requires a development team
** BUILD FAILED **
"""


class ParseErrorsTests(unittest.TestCase):
    def test_dedupes_and_keeps_file_plus_bare_errors(self):
        errors = xcode_compile.parse_errors(SAMPLE)
        self.assertEqual(len(errors), 3)
        self.assertEqual(errors[0]["line"], "120")
        self.assertIn("inaccessible", errors[0]["message"])
        self.assertTrue(errors[1]["file"].endswith("P0SinglePhotoEditor.swift"))
        self.assertEqual(errors[2]["file"], "")
        self.assertIn("development team", errors[2]["message"])

    def test_clean_log_is_empty(self):
        self.assertEqual(xcode_compile.parse_errors("** BUILD SUCCEEDED **\n"), [])


if __name__ == "__main__":
    raise SystemExit(unittest.main())
