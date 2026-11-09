"""Round S2 (shift-e-logmean loop): a low-key guard on ⇧E. An upward lift from the log-mean is capped at the median's
answer + 0.5 stop (never below 0); downward moves stay free. Each frame keeps both: `sceneSl(img, c, pp)` still
returns the log-mean and writes the upper median to `pp.slm`; `evAutoMap` takes a clip's and the shoot's median of
those as 322 did. Run through the page's own JavaScript (page_js). 0.5 from the R1 judge's read of the dev shots
(Sparks 30-511 +0.94 over the median, Sparks 8396-8941 +0.43 and helped). Look as baseline."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import page_js as J  # noqa: E402

fit_look, apply_look = J.fit_look, J.apply_look
PATCHES = [
    ('  sceneSl(img, c) {', '  sceneSl(img, c, o) {'),
    ('if (!v.length) return 0; let s = 0; for (const y of v) s += Math.log(y + 1e-4); return Math.exp(s / v.length); // log-mean (325)',
     'if (!v.length) return 0; let s = 0; for (const y of v) s += Math.log(y + 1e-4); if (o) { const w = v.slice().sort((a, b) => a - b); o.slm = w[w.length >> 1]; } return Math.exp(s / v.length); // log-mean (325); o.slm: the upper median'),
    ("C.forEach(c => { const v = Object.values(c._px || {}).map(q => q && q.sl).filter(x => x > 0); if (v.length) per[c.id] = med(v); });\n"
     "    const mid = med(Object.values(per)); if (mid > 0) Object.keys(per).forEach(id => { m[id] = Math.round(Math.max(-1, Math.min(1, Math.log2(mid / per[id]))) * 100) / 100; });",
     "const pm = {}; C.forEach(c => { const q = Object.values(c._px || {}), v = q.map(p => p && p.sl).filter(x => x > 0), w = q.map(p => p && p.slm).filter(x => x > 0); if (v.length) per[c.id] = med(v); if (w.length) pm[c.id] = med(w); });\n"
     "    const mid = med(Object.values(per)), mm = med(Object.values(pm)); if (mid > 0) Object.keys(per).forEach(id => { let e = Math.log2(mid / per[id]); if (e > 0 && mm > 0 && pm[id] > 0) e = Math.min(e, Math.max(0, Math.log2(mm / pm[id]) + 0.5)); m[id] = Math.round(Math.max(-1, Math.min(1, e)) * 100) / 100; });   // a lift at most the median's + 0.5 stop"),
]
balance = J.make_balance(PATCHES)
