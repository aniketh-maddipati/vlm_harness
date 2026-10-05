#!/usr/bin/env python3
"""Unit tests for design_audit.py on small synthetic strings. python3 Tests/probe/test_design_audit.py"""
import io, os, re, sys, tempfile, unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import design_audit as da

RULES = {label: (rx, fl) for label, rx, fl in da.WORDS}

def fires(label, text):
    rx, fl = RULES[label]
    return bool(re.search(rx, text, fl))

class Rules(unittest.TestCase):
    def check(self, label, hit, miss):
        for t in hit:
            self.assertTrue(fires(label, t), f"{label} should fire on {t!r}")
        for t in miss:
            self.assertFalse(fires(label, t), f"{label} should not fire on {t!r}")

    def test_every_rule_is_tested(self):
        tested = {n[len("test_"):] for n in dir(self) if n.startswith("test_")}
        slug = lambda l: re.sub(r"\W+", "_", l).strip("_").lower()
        self.assertEqual({slug(l) for l in RULES} - tested, set())

    def test_keepers_picks(self):
        self.check("keepers → picks",
                   ["Save 88 keepers", "Keepers", "one sidecar per keeper", "12 keeps · 3 edited", " keeps · 3 edited", "Keeps · 12"],
                   ["U not used · K keeps, R removes", "→ moves · ⏎ keeps · R removes", "decisions · esc keeps them",
                    "What Lumina keeps to stay fast.", " · shutter under 2/f · keeps ", "Keeps camera times", "88 picks"])

    def test_cull_step_pick(self):
        self.check("Cull (step) → Pick",
                   ["Back to Cull", "photos are in · ⌘2 to cull", "⌘2 cull", "back to cull", "Keep some in Cull first."],
                   ["Waiting. New RAWs pop up while you cull.", "already culled in", "a photo-culling app", "Back to Pick"])

    def test_3_save_4_save(self):
        self.check("⌘3 Save → ⌘4 Save",
                   ["All rows seen · ⌘3 Save", "⌘3 to save", "Save ⌘3"],
                   ["⌘4 saves first", "⌘3 edit", "⌘3 Edit · ⌘4 Save"])

    def test_reject_remove(self):
        self.check("reject → remove",
                   ["rejected ", "Rejected", "reject all", "2 rejects marked −1"],
                   ["removed · 3", "R removes", "un-removed"])

    def test_finals_selects(self):
        self.check("finals → selects", ["no finals yet", "Final"], ["finally done", "selects only"])

    def test_out_remove(self):
        self.check("out → remove", ["3 outs", "all out", "X out", "out?"], ["about", "out of 12", "zoom out"])

    def test_widen_back_out(self):
        self.check("widen → back out", ["esc widen"], ["back out", "wide angle"])

    def test_accept_picks_keep_suggested(self):
        self.check("accept picks → keep suggested", ["R accept picks"], ["88 picks", "keep suggested"])

    def test_preview_ing_auto_show_ing_auto(self):
        self.check("preview(ing) auto → show(ing) Auto",
                   ["preview auto", "previewing auto on row"], ["show Auto", "Big-view previews", "preview missing"])

    def test_likely_out_not_suggested(self):
        self.check("likely out → not suggested",
                   ["likely out", "Likely-outs", "3 likely outs"], ["one or two channels · likely recoverable in RAW", "not suggested"])

    def test_best_badge_sharpest(self):
        self.check("best badge → sharpest", ["best"], ["pick", "Picks", "picks", "sharpest", "the best frame"])

    def test_sub_row_group(self):
        self.check("sub-row → group", ["sub-row 2"], ["click row header", "group"])

    def test_scope_applies_to(self):
        self.check("scope → applies to", ["scope: row", "edits → row"], ["applies to row", "telescope"])

    def test_narrow(self):
        self.check("narrow", ["Narrow", "⌘3 narrow", "narrow to finals"], ["on a narrow window", "narrow screens", "narrower"])

    def test_copy_beta_reads_in_place(self):
        self.check("copy (beta reads in place)", ["copy it first", "Copy & start"],
                   ["Copy the folder to your Mac first", "Phone DNG picks are copied to a Picks folder."])

PAGE = """<div>Back to Cull</div><div>K keeps, R removes</div>
<script type="text/x-dc">
say('All rows seen · ⌘3 Save'); x==='finals'; z='88 keepers · 3 edited';
</script>"""

class Output(unittest.TestCase):
    def run_main(self, page):
        with tempfile.NamedTemporaryFile("w", suffix=".dc.html", delete=False, encoding="utf-8") as f:
            f.write(page)
        out = io.StringIO()
        try:
            with redirect_stdout(out):
                da.main(f.name)
        finally:
            os.unlink(f.name)
        return out.getvalue().splitlines()

    def test_format_and_totals(self):
        lines = self.run_main(PAGE + "\nlocalStorage localStorage")
        self.assertEqual(lines[0], "wording (ADDENDUM §4):")
        hits = [l for l in lines if re.match(r"  L\d+ ", l)]
        self.assertEqual([l.split()[0] for l in hits], ["L3", "L1", "L3"])
        self.assertIn("keepers → picks", hits[0]); self.assertIn("Cull (step) → Pick", hits[1])
        self.assertIn("  localStorage           2×", lines)
        self.assertEqual(lines[-1], "3 wording hit(s)")

    def test_six_hits_per_rule_at_most(self):
        page = "".join(f"<p>Back to Cull {i}</p>\n" for i in range(9)) + '<script type="text/x-dc"></script>'
        self.assertEqual(self.run_main(page)[-1], "6 wording hit(s)")

if __name__ == "__main__":
    unittest.main(verbosity=2)
