"""Round S3 (shift-e-logmean loop): a low-key guard on ⇧E by the log-mean's floor. `sceneSl` takes
exp(mean(log(Y + δ))) with δ 0.0018 (18 % grey / 100, about 6.6 stops under it, roughly the darkest an 8-bit frame
resolves) instead of 1e-4 (about 11 stops under): crushed blacks stop dragging a clip's key down, so large black
areas pull a clip toward a lift less. Reinhard's δ; not fitted (the R2 judge's pick). Run through the page's JS."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import page_js as J  # noqa: E402

fit_look, apply_look = J.fit_look, J.apply_look
PATCHES = [('for (const y of v) s += Math.log(y + 1e-4); return Math.exp(s / v.length); // log-mean (325)',
            'for (const y of v) s += Math.log(y + 0.0018); return Math.exp(s / v.length); // log-mean (325), floor 18 % / 100')]
balance = J.make_balance(PATCHES)
