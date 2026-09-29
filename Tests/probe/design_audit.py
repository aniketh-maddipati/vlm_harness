#!/usr/bin/env python3
"""Audit a handoff page: user-facing wording the ADDENDUM §4 table retires, and the demo layer the
app still has to route around. Report only — the fix belongs in the design."""
import re, sys

WORDS = [  # (label, regex) — ADDENDUM §4
    ("keeps → keepers", r"\b[Kk]eeps\b"), ("finals → selects", r"\b[Ff]inals?\b"), ("out → reject", r"\bouts\b|\bout\?|\ball out\b|\bX out\b"),
    ("widen → back out", r"\bwiden"), ("accept picks → keep suggested", r"accept pick"),
    ("preview(ing) auto → show(ing) Auto", r"\bpreview(ing)?\b[^<]{0,20}(auto|\{\{ *[A-Za-z.]*look)"), ("likely out → not suggested", r"likely"),
    ("pick / best badge → sharpest", r"^(picks?|best)$"),     # template text only: badges ("sub-row / row header", r"sub-row|row header"), ("scope → applies to", r"\bscope\b|edits →"),
    ("narrow", r"narrow"), ("copy (beta reads in place)", r"\bcopy it\b|Copy & start"),
]
DEMO = [  # markers of the prototype-only layer (ADDENDUM §1)
    ("zip", r"\.zip\b|\bUnzip\b"), ("Chrome / own tab", r"Chrome|own tab|this tab"), ("prototype chip", r"prototype ·"),
    ("key C", r"code==='KeyC'"), ("X→E Proxy", r"new Proxy\("), ("localStorage", r"localStorage"),
    ("1616 px JPEG note", r"1616 px preview"), ("impStartOld", r"impStartOld"), ("sample card", r"721 photos · 11\.3 GB|Sony α7 III card"),
]

def strings(h):
    cut = h.index('<script type="text/x-dc"')
    for m in re.finditer(r">([^<>{}]*[A-Za-z][^<>]*)<", h[:cut]):
        yield h.count("\n", 0, m.start()) + 1, m.group(1).strip()
    for m in re.finditer(r"(['\"])((?:(?!\1).){2,}?)\1", h[cut:]):
        t = m.group(2)
        if re.search(r"=>|\(\{|&&|\|\||;\s*\w+\(|:\{\}", t):
            continue                                         # code, not copy
        if " " in t or "·" in t:                         # one-word literals are identifiers (ex.what==='finals')
            yield h.count("\n", 0, m.start() + cut) + 1, t

def main(path):
    h = open(path, encoding="utf-8").read()
    ss = list(strings(h))
    n = 0
    print("wording (ADDENDUM §4):")
    for label, rx in WORDS:
        hits = [(l, t) for l, t in ss if re.search(rx, t, re.I if label == "narrow" else 0)]
        for l, t in hits[:6]:
            print(f"  L{l:<5} {label:<36} {t[:90]}"); n += 1
    print("demo layer still in the page (the app routes around it; ADDENDUM §1):")
    for label, rx in DEMO:
        c = len(re.findall(rx, h))
        if c: print(f"  {label:<22} {c}×")
    print(f"{n} wording hit(s)")

if __name__ == "__main__":
    main(sys.argv[1])
