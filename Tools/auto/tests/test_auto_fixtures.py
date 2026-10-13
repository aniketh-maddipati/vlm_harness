"""Tests for Tools/auto/auto_fixtures.py on synthetic `lumina-render auto` lines (not fixture values)."""
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import auto_fixtures as af  # noqa: E402


def line(name, ok=True, **look):
    d = {'image': '/x/' + name, 'ok': ok, 'version': 'autodevelop-test'}
    if ok:
        d['look'] = look
    else:
        d['error'] = 'not a RAW'
    return d


class AutoFixturesTests(unittest.TestCase):
    def test_sample_stems_come_from_the_design_data(self):
        stems = af.sample_stems()
        self.assertTrue(stems and all(s.startswith('DSC') and '.' not in s for s in stems), stems[:5])
        self.assertIn('DSC06175', stems)

    def test_entries_keep_page_keys_and_finite_numbers(self):
        table, versions, failed = af.entries([line('A.ARW', ev=0.35, wb=5200, tint=3, hl=-24, sh=0, wh=0, bl=0, vib=8, junk='x'),
                                              line('B.ARW', ok=False), line('C.ARW', hl=-10), line('D.ARW', ev=True)])
        self.assertEqual(table, {'A.ARW': {'ev': 0.35, 'wb': 5200, 'tint': 3, 'hl': -24, 'sh': 0, 'wh': 0, 'bl': 0}})
        self.assertEqual(versions, {'autodevelop-test'})
        self.assertEqual([n for n, _ in failed], ['B.ARW', 'C.ARW', 'D.ARW'])

    def test_js_defines_the_global_by_name_and_stem(self):
        js = af.render_js({'DSC1.ARW': {'ev': -0.5, 'hl': -30, 'sh': 10}}, 'autodevelop-test')
        out = subprocess.run(['node', '-e', 'const window={};' + js + 'console.log(JSON.stringify([window.LuminaAutoFixtures, window.LuminaAutoFixturesVersion]))'],
                             capture_output=True, text=True)
        if out.returncode != 0 and 'not found' in out.stderr:
            self.skipTest('node not installed')
        self.assertEqual(json.loads(out.stdout), [{'DSC1.ARW': {'ev': -0.5, 'hl': -30, 'sh': 10}, 'DSC1': {'ev': -0.5, 'hl': -30, 'sh': 10}}, 'autodevelop-test'])

    def test_failures_write_nothing_unless_allowed(self):
        with tempfile.TemporaryDirectory() as d:
            src, out = os.path.join(d, 'auto.jsonl'), os.path.join(d, 'data', 'auto-fixtures.js')
            with open(src, 'w') as f:
                f.write(json.dumps(line('A.ARW', ev=0.1, hl=0, sh=0)) + '\n' + json.dumps(line('B.ARW', ok=False)) + '\n')
            with self.assertRaises(SystemExit):
                af.main(['--from-jsonl', src, '--out', out])
            self.assertFalse(os.path.exists(out))
            self.assertEqual(af.main(['--from-jsonl', src, '--out', out, '--allow-missing']), 0)
            with open(out) as f:
                self.assertIn('"A.ARW": {"ev":0.1,"hl":0,"sh":0}', f.read())

    def test_two_versions_in_one_run_are_refused(self):
        a, b = line('A.ARW', ev=0.1), line('B.ARW', ev=0.2)
        b['version'] = 'other'
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, 'auto.jsonl')
            with open(src, 'w') as f:
                f.write(json.dumps(a) + '\n' + json.dumps(b) + '\n')
            with self.assertRaises(SystemExit):
                af.main(['--from-jsonl', src, '--out', os.path.join(d, 'x.js')])

    def test_find_raws_by_stem_reports_missing(self):
        with tempfile.TemporaryDirectory() as d:
            for n in ['DSC1.ARW', 'dsc2.arw', 'DSC3.jpg']:
                open(os.path.join(d, n), 'w').close()
            found, missing = af.find_raws(d, ['DSC1', 'DSC2', 'DSC3'])
            self.assertEqual([os.path.basename(p) for p in found], ['DSC1.ARW', 'dsc2.arw'])
            self.assertEqual(missing, ['DSC3'])
            self.assertEqual(af.find_raws(os.path.join(d, 'nope'), ['DSC1']), ([], ['DSC1']))


if __name__ == '__main__':
    unittest.main()
