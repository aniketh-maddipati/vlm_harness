import copy
import unittest

import benchmark
from controller import Candidate, agreement, lattice, rank, select


def receipt(identity, score, failures=None):
    return {"candidateID": identity, "highlightClipFraction": score, "shadowClipFraction": 0,
            "mean": 0.5, "failures": failures or [], "elapsedMS": 1}


class ControllerTests(unittest.TestCase):
    def test_candidate_zero_and_no_unsupported_controls(self):
        self.assertEqual(lattice()[0], Candidate())
        for candidate in lattice():
            self.assertNotIn("pixels", candidate.payload())
            self.assertNotIn("whites", candidate.payload())
        for candidate in (Candidate(exposure=0.3), Candidate(id="bad", exposure=float("nan")),
                          Candidate(id="bad", tint=2), Candidate(id="bad", highlights=10)):
            with self.assertRaises(ValueError):
                candidate.payload()

    def test_hard_failure_cannot_win(self):
        rows = [receipt("zero", 0.2), receipt("unsafe", 0, ["proxy_fallback"])]
        self.assertEqual(rank(rows)[0]["candidateID"], "zero")
        self.assertEqual(select(rows, rows)["status"], "abstained")

    def test_no_acceptance_from_unvalidated_clipping_score(self):
        rows = [receipt("zero", 0.2), receipt("dark", 0)]
        result = select(rows, rows, {"made_up_margin": 0.1})
        self.assertFalse(result["production_acceptance_enabled"])
        self.assertEqual(result["selected_candidate"], "zero")

    def test_rank_agreement_reversal_and_incomplete_audit(self):
        proxy = [receipt("zero", 0), receipt("a", 0.1), receipt("b", 0.2)]
        full = [receipt("zero", 0.2), receipt("a", 0.1), receipt("b", 0)]
        result = agreement(proxy, full)
        self.assertEqual(result["spearman_paired_subset"], -1)
        self.assertFalse(result["top1_retention"])
        self.assertIsNone(agreement(proxy, full[:2])["top1_retention"])
        self.assertTrue(agreement(proxy, [receipt("zero", 0, ["bad"]), *full[1:]])["proxy_winner_failed_full"])

    def test_tied_scores_have_no_defined_correlation(self):
        rows = [receipt("zero", 0), receipt("a", 0)]
        self.assertIsNone(agreement(rows, rows)["spearman_paired_subset"])

    def test_event_and_duplicate_leakage_are_rejected(self):
        scenes = [{"scene_id": str(index), "asset_ids": [str(index)], "anchors": [],
                   "split": split, "event_id": "event", "reject_reasons": []}
                  for index, split in enumerate(("development", "heldout"))]
        assets = [{"asset_id": str(index), "fingerprint": {"content_identity": "sha:same"}}
                  for index in range(2)]
        manifest = {"schema_version": 1, "assets": assets, "scenes": scenes}
        with self.assertRaisesRegex(ValueError, "Event crosses"):
            benchmark.validate(manifest)
        manifest = copy.deepcopy(manifest)
        manifest["scenes"][1]["event_id"] = "another"
        with self.assertRaisesRegex(ValueError, "Duplicate or burst"):
            benchmark.validate(manifest)


if __name__ == "__main__":
    unittest.main()
