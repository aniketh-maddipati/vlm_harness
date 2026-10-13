#!/usr/bin/env python3
"""Audit a handoff page: user-facing wording v0.01 retires, and the demo layer the app still has to
route around. Report only — the fix belongs in the design.

Wording, earliest source first, later ones win: ADDENDUM-remove §4 (v3, in git history), the v5
GRAMMAR (reference/GRAMMAR.md), the v0.01 README ("keepers" is now "picks" everywhere; steps
Open ⌘1 · Pick ⌘2 · Edit ⌘3 · Save ⌘4; R and X remove). Verbs stay: "K keeps", "⏎ keeps",
"likely recoverable" and "row header" are current copy."""
import re, sys

WORDS = [  # (label, regex, flags)
    ("keepers → picks", r"\b[Kk]eepers?\b|\b\d+\s+keeps\b|^\s+keeps\b|^Keeps\b(?!\s+[a-z])", 0),  # nouns only
    ("Cull (step) → Pick", r"\bCull\b|⌘2\W{0,3}(to\s+)?cull\b|\bback to cull\b", 0),
    ("⌘3 Save → ⌘4 Save", r"⌘3\W{0,3}(to\s+)?[Ss]av|\b[Ss]ave\W{0,3}⌘3", 0),
    ("reject → remove", r"\b[Rr]eject(s|ed|ing)?\b", 0),
    ("finals → selects", r"\b[Ff]inals?\b", 0),
    ("out → remove", r"\bouts\b|\bout\?|\ball out\b|\bX out\b", 0),
    ("widen → back out", r"\bwiden", 0), ("accept picks → keep suggested", r"accept pick", 0),
    ("preview(ing) auto → show(ing) Auto", r"\bpreview(ing)?\b[^<]{0,20}(auto|\{\{ *[A-Za-z.]*look)", 0),
    ("likely out → not suggested", r"\blikely[- ]outs?\b", re.I),
    ("best badge → sharpest", r"^best$", 0),  # template text only: badges; "pick" is the v0.01 noun
    ("sub-row → group", r"sub-row", 0), ("scope → applies to", r"\bscope\b|edits →", 0),
    ("narrow", r"\bnarrow\b(?!\s+(window|screen|width|display)s?\b)", re.I),
    ("copy (beta reads in place)", r"\bcopy it\b|Copy & start", 0),
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

def wording_hits(ss):
    for label, rx, fl in WORDS:
        hits = [(l, t) for l, t in ss if re.search(rx, t, fl)]
        for l, t in hits[:6]:
            yield l, label, t

def main(path):
    h = open(path, encoding="utf-8").read()
    ss = list(strings(h))
    n = 0
    print("wording (ADDENDUM §4):")
    for l, label, t in wording_hits(ss):
        print(f"  L{l:<5} {label:<36} {t[:90]}"); n += 1
    print("demo layer still in the page (the app routes around it; ADDENDUM §1):")
    for label, rx in DEMO:
        c = len(re.findall(rx, h))
        if c: print(f"  {label:<22} {c}×")
    print(f"{n} wording hit(s)")

if __name__ == "__main__":
    main(sys.argv[1])
