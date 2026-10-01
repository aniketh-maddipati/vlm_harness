import json
import os
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import fit  # noqa: E402
import lookmath  # noqa: E402

RULES = os.path.join(os.path.dirname(__file__), "..", "..", "..", "Lumina", "Sets", "Look", "rules-v1.json")


class ObjectiveTests(unittest.TestCase):
    def setUp(self):
        with open(os.environ.get("LUMINA_RULES") or RULES) as f:
            self.rules = json.load(f)
        base = np.linspace(0.02, 0.9, 48).reshape(4, 12, 1).repeat(3, axis=2)
        look = lookmath.single("Contrast", 50)
        ref = lookmath.apply_image(base, look, {"kelvin": 5500, "tint": 0}, {**self.rules, "order": ["rawDevelop", "contrast", "outputTransform"]})
        self.pairs = [{"base_lin": base, "look": look, "as_shot": {"kelvin": 5500, "tint": 0}, "ref_lab": fit.lab_from_working(ref)}]

    def test_the_stage_scores_zero_against_its_own_output(self):
        names = ["midpoint", "slopePerUnit", "lumaMix"]
        x = [self.rules["stages"]["contrast"]["coefficients"][n] for n in names]
        f, med, p95 = fit.objective(x, names, "contrast", self.rules, self.pairs, 4.0)
        self.assertLess(f, 1e-6)
        self.assertLess(p95, 1e-6)

    def test_out_of_bounds_is_a_large_objective_in_the_same_shape(self):
        # Nelder–Mead steps outside the bounds on every multi-coefficient stage; the objective must
        # answer with the same (objective, median, p95) triple, not a bare number.
        names = ["midpoint", "slopePerUnit", "lumaMix"]
        out = fit.objective([0.46, 0.006, 1.7], names, "contrast", self.rules, self.pairs, 4.0)
        self.assertEqual(len(out), 3)
        self.assertGreater(out[0], 1e5)


if __name__ == "__main__":
    unittest.main()
