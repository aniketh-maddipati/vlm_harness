"""Routing and guards: python3 -m unittest discover -s Tools/agentloop/tests (no network, no keys)."""
import os, sys, unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import agentloop as al


class Routing(unittest.TestCase):
    def test_cheap_reads_go_to_grok(self):
        for kind in ("search", "summarize", "log-triage", "lint-fix", "doc-draft"):
            r = al.route(al.Subtask("a", kind, "t", paths=["Tests/web/*.mjs"]))
            self.assertEqual((r.worker, r.model), ("grok", "grok-build-0.1"), kind)
        self.assertEqual(al.route(al.Subtask("a", "large-read", "t")).model, "grok-4.3")
        self.assertTrue(al.route(al.Subtask("a", "research", "t")).web_search)

    def test_protected_paths_stay_with_claude(self):
        for p in ("Lumina/Sets/Core/SetsBridge.swift", "Lumina/Sets/Web/plumbing.js", "design/handoff/lumina-cull/x.html",
                  "docs/release/TRUST.md", "Config/Lumina-Sets.entitlements", "Lumina/Sets/Look/LookMath.swift", ".github/workflows/lumina.yml"):
            self.assertEqual(al.route(al.Subtask("a", "search", "t", paths=[p])).worker, "claude", p)

    def test_design_work_goes_to_its_agent(self):
        self.assertEqual(al.route(al.Subtask("a", "page-ui", "t")).agent, "page-ui-editor")
        self.assertEqual(al.route(al.Subtask("a", "canvas", "t")).agent, "canvas-debugger")
        self.assertEqual(al.route(al.Subtask("a", "made-up", "t")).worker, "claude")

    def test_local_commands_are_allowlisted(self):
        self.assertEqual(al.route(al.Subtask("a", "ci", "t", command="bash Scripts/ci_local.sh")).worker, "local")
        for c in ("rm -rf ~", "LUMINA_LONG=1 bash Scripts/probe.sh fuzz", "git push"):
            self.assertEqual(al.route(al.Subtask("a", "test-run", "t", command=c)).worker, "refused", c)

    def test_grok_context_never_holds_protected_or_untracked_files(self):
        files = al.tracked(["Lumina/Sets/*", "Tests/web/lib.mjs"])
        self.assertIn("Tests/web/lib.mjs", files)
        self.assertFalse([f for f in files if al.protected(f)])
        self.assertFalse(al.allowed_input("/etc/hosts"))
        self.assertFalse(al.allowed_input(os.path.expanduser("~/LuminaEvidence/agentloop/ledger.jsonl")))

    def test_waves_follow_dependencies(self):
        s = [al.Subtask("c", "ci", "t", depends_on=["a", "b"]), al.Subtask("a", "search", "t"), al.Subtask("b", "lint-fix", "t", depends_on=["a"])]
        self.assertEqual([[t.id for t in w] for w in al.waves(s)], [["a"], ["b"], ["c"]])

    def test_the_sample_plan_routes(self):
        _, subs = al.load_plan(os.path.join(al.HERE, "sample-plan.json"))
        got = {t.id: al.route(t).worker for t in subs}
        self.assertEqual(got, {"triage": "grok", "callers": "grok", "bridge-read": "claude", "lint": "grok",
                               "note": "grok", "label": "claude", "ci": "local"})

    def test_budget_refuses_over_cap(self):
        b = al.Budget()
        b.left["grok"] = 0.01
        self.assertFalse(b.reserve("grok", 0.02))
        self.assertTrue(b.reserve("grok", 0.005))
        b.settle("grok", 0.005, 0.001)
        self.assertAlmostEqual(b.left["grok"], 0.009)


if __name__ == "__main__":
    unittest.main()
