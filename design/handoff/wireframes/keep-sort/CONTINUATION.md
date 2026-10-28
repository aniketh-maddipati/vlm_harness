# Continuation — keep-sort wireframes + strategy handoff

**Worktree:** `/Users/aniketh/vlm_harness/.claude/worktrees/keep-input-dock-chron`  
**Branch:** `design/keep-input-dock-chron` @ `23023d20`  
**Paste prompt for a new chat:** [`CONTINUATION-PROMPT.md`](CONTINUATION-PROMPT.md)  
**Plan (implemented):** [`PLAN-input-dock-chron.md`](PLAN-input-dock-chron.md)

Main checkout often has the same HTML dirties without PLAN/CONTINUATION — prefer this worktree or copy these markdown files over.

---

## Locked (do not re-litigate)

- No Cards & volumes / `sd*` chip strip under Drop
- Files not Phone; Rec.709 default for Log; no “matches FCP” / ΔE in shipping UI
- Do not pop `stash@{0}` SetsPrecompute unless owner asks
- Page is the product (`AGENTS.md`); wireframes live only under `design/handoff/wireframes/keep-sort/`

---

## Wireframe done on this branch

- Click-to-enable sensed cards → always-present **Input dock**
- Drop / AirDrop / Android → dock tiles; **Sort now** multi-vol `sessionStorage` handoff
- Sort: **union chron axis**, Ready N/M (not a gate), unread→develop, inbound append demo
- README + MODEL-EVAL lock-ins
- Prior rename: export ship helpers → `openExport` / `closeExport` (not ship)

### Run

```bash
cd /Users/aniketh/vlm_harness/.claude/worktrees/keep-input-dock-chron
python3 design/handoff/wireframes/keep-sort/hotserve.py --port 8788
# → http://127.0.0.1:8788/import-wf.html
# Sort: http://127.0.0.1:8788/keep-wf.html
```

### Files

| File | Role |
|---|---|
| `import-wf.html` | Sensed rail → dock → Drop / inbound |
| `keep-wf.html` | Union chron Sort, Kept dock, Export |
| `README.md` | Lock-ins + flow |
| `MODEL-EVAL.md` | Rec.709 / claim hygiene |
| `hotserve.py` | Local static server |
| `archive/` | Older experiments (incl. named-scene MVP archive — not the live path) |

### Wireframe next (if iterating UX)

Polish Input dock, inbound demo, Sort fold-bar, chron/preprocess copy — stay in these wireframes. Do not promote to `lumina-cull` / Skim / app Web unless owner asks.

---

## Strategy locked (same thread; for product/MVP chats)

- **SPC** = South Park Commons; **SFP** = Solo Founders Program (not product names).
- **Engine:** media graph — identity · chron · display-ready · decide/place → serialize. Sources / destinations / archetypes / AI = adapters. Hard prep (stitch/fix/audio/Edit) = bound node ops.
- **VC vision:** offline creative OS before the NLE; wedge = dump → Keep → package (Rec.709-ready + FCPXML and/or stills XMP).
- **Exist → compete → win:** package beats Finder+card → whole night job beats step tools → default home before editor.
- **Compete filter:** graph-native · trust (offline/card-safe) · incumbent hole · dogfood/reuse. Refuse: captions/CRM/CapCut-core/cloud-required/“any workflow” chat.
- **Dogfood:** recreate features is cheap; one graph is scarce. Escape log ranks modules. Monogram = job + selection bind modules.
- **Related demand not shipped:** verify dual-copy, proxies/CFR, phone HDR→Rec.709, stringout/browse (Kyno gap) — adopt only on the graph.
- **Tight MVP spine (generic, no named betas):** multi-vol chron + display-ready + Keep + Place off card + one package that opens (FCPXML and/or XMP). Clock-shift / chapter stacks only if a real shooter won’t switch without them.
- Research: `research_notes/Creator multi device problems/`.

---

## New chat — pick a lane

1. **Wireframes:** polish Import/Sort per PLAN; spot-check in browser.  
2. **Strategy / MVP:** continue exist·compete·win and 30-day dogfood — use `CONTINUATION-PROMPT.md`.  
3. **App:** only if owner says promote keep-sort into Skim/Sets — then follow `AGENTS.md` (edit handoff pages, sync, checks).
