"""The page as it was before LOCAL-CHANGES 325 (⇧E on each frame's upper median), run through the page's own
JavaScript: the 322 baseline re-scored on the page path, to check it against the numpy baseline. Look as baseline."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import page_js as J  # noqa: E402

fit_look, apply_look = J.fit_look, J.apply_look
PATCHES = [('if (!v.length) return 0; let s = 0; for (const y of v) s += Math.log(y + 1e-4); return Math.exp(s / v.length); // log-mean (325)',
            'v.sort((a, b) => a - b); return v.length ? v[v.length >> 1] : 0;')]
balance = J.make_balance(PATCHES)
