# Agent-first grammar — research and design session

**Session id:** AG.1 · **Writes:** this document + one BUILD_LOG entry · **No code. No rulings — proposals only.**
**Authority:** `design/contract-v6.md` → `design/tokens.yaml` → `design/copy-contract.txt` → code → tests.
**Batch status:** Amendment Batch 2 IN FORCE · Batch 3 PROPOSED, NOT RATIFIED (`design/amendments/proposal-batch-3.md`) · D38 doors, not deletions.
**Tree measured:** uploaded source tree carrying `tokens.yaml` version `6.3-motion-wiring`; **no `.git` metadata present**, so no SHA can be named — see UNKNOWNS. BUILD_LOG's newest entry (2026-08-16) claims `origin/main` @ `b90fdfd`.
**Sequencing:** this session designs; it does not freeze. The grammar must not be frozen before the input-latency work lands — if a held glance lags, "momentary" does not feel momentary, and a frozen grammar would enshrine the workaround. Every proposal below names its falsifier.

---

## HEADLINE

Agent-first means the agent is one more operator of the locked grammar — it may hold glances now, may someday stage behind the same banner the hands use, and is locked out of commit by D60's hardware-release precondition — which forecloses agent-only verbs, background mutation, autonomous culling, and (under D45 as ratified) any model that does not run on this Mac.

---

## SESSION CORRECTIONS TO THE BRIEF (grep before assessing)

The brief's Part-2 list carries three mis-citations, found by grep this session. Recorded here because the rule that caught them ("never cite a contract entry unverified") is the rule this document defends.

| Brief says | Grep says |
|---|---|
| "D62 (⇧⏎ stages; ⏎ cannot commit until Return is physically released)" | That is **D60** — Return-release gate, copy sealed verbatim. **D62** is post-commit focus advance ("On staged commit (⏎), focus advances to the next row's first kept frame"). |
| "D40 / R-M.1 (X never touches the filesystem…)" | That is **D36** *(amended by R-M.1)*: "the **ONE** file-touching verb in the product is the post-export offer `Rejects to Trash · N files · size`… Mark key **X** still never touches the file system." **D40** is engineering reconciliation. |
| "D57 / A10 (taste-model gate)" | The gate is **D46** *(R-A.1 + A10)* / **D32** amendment ("GATED on taste-model proof… benchmark = each tester's own final hand edits"). **D57** is 90 px / PERSUADE. |

One reading-list item could not be read: `design/strategy/release-readiness.md` is absent from this tree (UNKNOWN below).

---

## PRIOR ART — researched, not recalled

### 1. Modal editors as automation languages

Vim macros are recorded keystrokes stored in ordinary text registers — "the contents of a macro in a register are the very same with which the Yank/Put operations interact," so a macro can be pasted, edited as text, and yanked back (fzheng.me, "Practical Vim: Registers," 2018). Recording is `q{register}…q`; replay is `@{register}` (Red Hat, "Use Vim macros to automate frequent tasks," 2025). Replay is blind and mechanical: "When executing a macro, Vim blindly repeats the sequence of canned keystrokes… by default Vim aborts the rest of the macro if a motion fails" (fzheng.me).

What that buys: **no second API exists.** The automation is auditable by inspection — paste the register and read the keys. Anything the macro does, the hand could have done, and vice versa. The abort-on-failed-motion rule is the safety valve: when context has drifted from what the recording assumed, the macro stops rather than adapting silently.

What it costs: no control flow. Emacs's ancestor documented the ceiling in 1981: keyboard macros "differ from ordinary EMACS commands, in that they are written in the EMACS command language… However, the EMACS command language is not powerful enough as a programming language to be useful for writing anything intelligent or general" (EMACS Manual for ITS Users, AI Memo 555, 1981, quoted at abochannek.github.io). Emacs therefore went the other way — Elisp as a privileged extension language: "Macros only repeat canned key sequences. Sometimes you need control flow, calculations, user interactions" (Phil Sung, "Being Productive With Emacs," MIT IAP 2009). The price of that choice is that Emacs automation is no longer inspectable as keystrokes; the automation surface became a programming surface, and what an extension does can only be known by reading its program. Mastering Emacs states the macro ceiling plainly: macros "can do pretty much everything you can do, except make human decisions about what to do next."

**Transfers:** the Lumina thesis is Vim's, upgraded — an agent pressing the grammar's keys is a macro with judgment supplying exactly the part macros lack (deciding what to do next), while keeping the part Elisp gave up (auditable-by-inspection, one language). The abort rule transfers directly: if the state an agent proposal assumed has changed (the frame was re-marked, focus moved), the proposal must lapse, never adapt silently. **Does not transfer:** macros replay invisibly at machine speed; Lumina's L2 (held is temporary) requires agent action to be visible and watched. Also load-bearing: shared Vim macros work only because normal-mode commands are stable across machines — a heavily remapped vimrc breaks every recorded macro that touches the remapped keys. A customisable grammar has no stable automation surface. This is the empirical case for the lock (D36 grammar stability; D23/D63 decision-key remap ban), confirmed.

### 2. The git index

The index is a two-phase ladder — stage, review, commit — that lets any tool and any hand share one working tree through one shared staging state: "Staging helps you 'check off' individual changes as you review a complex commit, and to concentrate on the stuff that has not yet passed your review" (Sitaram Chamarty, gitolite.com, "Why the index/staging area is so useful"). Lumina's ⇧⏎ → ⏎ (D14 ladder, D60 gate) arrived at the same shape independently.

Where decades of use show two-phase breaks down — same source: "You might end up committing something that is not tested exactly, because you tested with the contents of the work tree, which is not the same as the index that is being committed." The staged thing and the committed thing can diverge. Lumina already closes this: what ⏎ applies is exactly the bannered staged state, previews warm ADAPTED per frame (D14, D57 — loupe on staged strip shows the adapted preview "regardless of spike resolution"), and D19's count invariant makes banner = receipt = header. **Transfers:** one staging namespace. If an agent ever stages, it stages into the *same* state the banner shows and Esc dissolves — never a parallel proposal tray, which would be git's index-vs-worktree divergence rebuilt on purpose. **Does not transfer:** git's index is silent and forgettable; D14's staging is loudly bannered and ephemeral, which is the stronger design for an agent whose staged work must never be mistaken for committed work.

### 3. Flight envelope protection

Airbus: "In Normal and Alternate Law, the flight crew are able to manipulate the flight controls but are unable to make any input which would result in the aircraft operating outside a pre-defined set of parameters… known as 'Hard' limits"; Boeing: "The pilot is the final authority for the operation of the aeroplane" (both per Spitzer & Ferrell 2015, quoted at flightdeckfriend.com). Boeing's soft limits are tactile: "when the limit is reached, simulated opposing force is provided as feedback to the pilot, but the pilot can override the protections by pushing or pulling harder" (US Patent 8,195,346, Boeing envelope-protection filing).

Which philosophy does Lumina's contract implement? **Hard limits — but pointed at a different target.** Airbus's hard limits constrain the *pilot's* inputs. Lumina's hard limits constrain what *any actor* may do to the photographs and the record: X never touches the file system (D36); the one file-touching verb fires never automatically, never before ✓, never twice (D36/R-M.1); one held press can never stage-and-commit (D60); decision keys are never remapped (D23/D63); no network calls (D45). The envelope protects the photographs and the operator's sovereignty, not the machine's judgment over the operator's. That inversion is why hard limits are trust-building here where they are contested in the cockpit: nothing in Lumina's envelope ever refuses the operator a decision about a photograph — it refuses classes of *consequence* (file destruction, silent commit, egress) to every actor equally.

Does the operator know they chose it? Partially. `nothing leaves this Mac`, `files stay where they are`, and the D60 sentence are frozen copy rows, and A13 made the first truthful of wave builds. The D60 sentence, however, is footer-grade chrome for what this session argues is the constitution's most valuable mechanical property. No new chrome is proposed (D18 facts-only); the observation is recorded for the operator.

The fair caveat from the same literature: hard limits mislead when the system's model of the world is corrupted — AF447's crew appears to have flown inputs that only make sense "if one assumes he believed FBW was still protecting him" after the protections had degraded (airline pilot commentary, 99% Invisible, "Children of the Magenta," 2015 episode discussion). Lumina's equivalent: a gate that *claims* to be mechanical must actually be mechanical. Hence proposal P1.

### 4. Accept/reject diff models

Per-item review of machine suggestions degrades measurably. GitHub's research with Accenture found developers accepted roughly 30% of Copilot suggestions in enterprise deployment (augmentcode.com summary of GitHub/Accenture study). A 2026 study of agentic code review found "AI agent reviewers generate significantly more code suggestions than human reviewers, yet achieve lower adoption rates," with over half of unadopted suggestions factually incorrect or replaced (arXiv:2603.15911). The bias data is the sharp edge: "A survey published in late 2025 found that 96% of developers do not fully trust AI-generated code, yet only 48% consistently verify it before merging" and a GitHub RCT with 202 developers found reviewers 5% *more* likely to approve AI-assisted code (tianpan.co, "The AI Code Review Trap," 2026). Industry write-ups now name the failure "approval fatigue — where developers rubber-stamp AI suggestions without reading them" (reptile.haus, 2026).

**Prediction for per-frame review of an agent's cull:** a 500-frame shoot presented as 500 accept/reject decisions collapses into rubber-stamping within the first rows — the operator's stated distrust and actual verification diverge exactly as the code-review data shows, and the review becomes the theater of control rather than control. The grammar already contains the correct counter-shape: review at the *rung* level, not the item level — one staged set, one loud banner, one count invariant (D19), inspection by exception (walk with arrows, veto by same-mark-clears D59, one ⌘Z for the batch). Any future agent-suggestion surface must be that shape. This is also why D47's pointer marks matter for the agent era: the veto gesture is already 44 pt, always visible, and identical to the key.

### 5. DAW automation lanes

In Ableton Live, machine-written parameter curves run until the human touches the control; touching it disables that parameter's automation immediately — "This will come on (meaning automation for one of the tracks is disabled) due to either manually moving an automated control or a MIDI device being used to automate a control that has automation recorded" — and automation resumes only when the human explicitly presses Re-Enable Automation (forum.ableton.com, automation-override thread; the Re-Enable button is standard product surface across Live 10–12 per Ableton ecosystem documentation).

**Transfers, and is the closest analogue to an agent editing a develop recipe:** the hand wins instantly, per-parameter, without a dialog, and the machine's authority never returns on its own. Mapped into Lumina's grammar: if an agent ever holds or stages a develop value, the operator touching that control cancels the agent's pending value for that control at the moment of touch — no confirm, no contest — and nothing the agent does re-arms itself. This is L2 and Esc semantics already; the DAW evidence says the per-parameter granularity and the explicit-re-enable are the parts that make shared control livable. **Does not transfer:** Live's override is silent and its state (which lanes are overridden) is famously easy to lose track of — the recurring forum confusion is itself evidence. Lumina's answer is D14's loud banner: shared control states are never quiet.

### 6. Autopilot handoff failures — the case against agentic culling, stated fairly

Bainbridge's "Ironies of Automation" (1983): "The more advanced a control system is, so that it can automate 99% of the routine activity, the more crucial the human contribution becomes in the remaining 1%" — while the human's skill for that 1% atrophies from disuse (quoted at qhsestandard, Medium, 2026). Warren VanderBurgh's 1997 American Airlines lecture named "children of the magenta line": pilots "so used to… managing the automation rather than actually flying the plane, that they lost their own skills to manually fly the plane" (carlhendrick.substack.com, 2026; AOPA, 2016/2023). AF447 (2009) is the canonical handoff: "the autopilot handed a perfectly good airliner back to its crew, the pilots, confused and out of practice, stalled it into the sea" (same source; AOPA 2023 concurs on the automation-interaction framing). AviatorDB's 2026 review of 150,000 records found dozens of fatal GA accidents "explicitly citing a pilot's inability to fly without automation" (generalaviationnews.com, 2026-03-22).

Applied to a photographic cull, honestly: the catastrophic-handback component does not transfer — culling is not a real-time control loop; every frame is revisitable; ⌘Z is total; the cost of taking back control is zero. What transfers fully is **skill and judgment atrophy plus its Lumina-specific twin, eval-set contamination.** D46/A10's benchmark is "each tester's own final hand edits." An operator who mostly ratifies agent suggestions stops producing hand edits; the benchmark degrades toward the agent's own prior output; the gate that was supposed to prove the model beats the photographer ends up measuring the model against itself. Bainbridge's irony, restated for this product: the better the agent culls, the less hand-cull signal exists to prove it should. This is the strongest single argument for keeping the agent off the decision keys until the gate passes — and for THE RECORD's provenance requirement if a suggestion rung is ever ratified.

---

## RULES: SURVIVES / STRENGTHENS / RE-ARGUE / CONFLICT

Every entry below was grepped in this tree this session; quoted fragments are verbatim.

### The Five Laws (v5 D8) — quoted: "Touch moves never decides · held is temporary · taps decide (work states are loud latches; navigating away = Esc) · ⇧ is more ⌥ is less · Esc puts it back ⌘Z takes it back."

- **L1 — SURVIVES, with one reading made explicit.** "Touch moves never decides" is actor-independent as written: motion by any actor never decides. An agent that could decide by moving things would be the trap named in the brief.
- **L2 — STRENGTHENS.** Held is temporary is the agent's free rung: a proposal shown as a hold costs nothing, cannot be forgotten, and release is the exit — v5 D9's own words for why a hold is "safer for a two-second peek." Everything the agent does uninvited should have this shape.
- **L3 — STRENGTHENS.** The loud latch is the reviewable unit the accept/reject evidence (Prior Art 4) demands: one staged state, one banner, one count — never per-item confirms.
- **L4 — SURVIVES unchanged.** Modifier temperaments are indifferent to who presses.
- **L5 — STRENGTHENS.** One undo namespace is the operator's veto over the agent. If agent-derived state were not Esc-able and ⌘Z-able identically, predictability of consequence — the definition of control — fails.

### D60 — Return-release gate — STRENGTHENS; the most valuable line, with one clarification needed

Quoted (contract v6, copy sealed verbatim): "After ⇧⏎ stages, ⏎ cannot commit until Return is physically released. One held press can never stage-and-commit." Provenance (v5 D11): "*Adopted from code:* the Return-release gate." Rejected list: "Timed chords; release-commits; compressing ⇧⏎+⏎ into one held press." Tests: `CommandChordTests.testHeldReturnCannotDoubleCommit` (surface-sweep, SHIPPED-logic).

The brief asks whether the physical-release requirement is real or an accident of wording. Finding: **the intent is real — it was adopted from code specifically to make one press unable to stage-and-commit — but the wording's protection against a *synthetic* actor is currently an accident.** As implemented, the gate is an event-sequence property (a key-up must intervene). A hand cannot cheat it. A process posting synthesized `NSEvent`s could post the key-up. So the gate is structural against hands and merely conventional against software, and the difference is exactly the agent-first question. If "physically" is ratified to mean *hardware* key transition — equivalently, if the agent's channel is defined as the grammar's verbs and the verb list simply contains no commit, because commit's precondition names the hardware — then the agent is structurally incapable of committing, a safety property enforced by mechanics rather than policy, and the session's judgment is that this is the most valuable line in the constitution: it draws the human-in-the-loop boundary at a key spring. Proposal P1 makes the reading explicit. Falsifier: a macOS test posting synthetic keyDown-stage / keyUp / keyDown-commit; if it commits, the gate is convention, not mechanics, and P1's implementation note is required, not optional.

### D62 — post-commit focus advance — SURVIVES

Quoted: "On staged commit (⏎), focus advances to the next row's first kept frame (skips rejects). Plain arrows still walk every frame." Actor-independent; and because only hands commit (D60), only hands ever trigger it. No agent interaction.

### D63 (with D23) — crop latch keys; decision-key remap ban — STRENGTHENS

Quoted (D23 amendment, normative home): "**`A` and `X` are BANNED from remapping in crop mode** — decision keys keep their meanings everywhere (stability promise)." General grammar stability is D36: "Rail positions and grammar do not move across versions," and D23: rail "positions never move across versions." The thesis's premise — this is only possible because the grammar is locked — **holds and is confirmed by prior art**: Vim's shared-macro ecosystem works because normal-mode is stable; a remapped grammar breaks every recording (Prior Art 1). The lock is the stable automation surface. Note of scope: D63's ban text is crop-scoped; the everywhere-lock rests on D36 + D23. The thesis should cite all three.

### D9 — holds vs latches — STRENGTHENS

Quoted: "Hold-Space = loupe (momentary; release returns) · hold-B = before · hold-⇧ = boundary reveal. Staging = a latch (no key held; loudly bannered; Esc exits)," with the resolution: "a hold is safer for a two-second peek (can't be forgotten; release is the exit), a latch is kinder for open-ended two-handed work." D9 hands the agent its two lawful rungs without amendment — and, read closely, also rules the agent *out* of latching: a latch is "kinder for open-ended **two-handed** work." Latches belong to hands; see THE GRAMMAR.

### D36 (amended R-M.1) — anti-irritant; X never touches the filesystem — STRENGTHENS

Quoted: "the **ONE** file-touching verb in the product is the post-export offer `Rejects to Trash · N files · size`. macOS Trash only; **never automatic**; **never before ✓**; **never asks twice**. Mark key **X** still never touches the file system." With an agent in the room this clause is what makes agent culling even discussable: a wrong X, by any actor at any rate, moves no file. The Trash offer itself is hands-only forever (NEVER list, item 2).

### D45 (R-9.1; A7 withdrawn A13) — zero egress — RE-ARGUE flagged; not resolved; plus one CONFLICT of artifacts

Quoted: "Diagnostics are **local-only or absent**; reveal/send **manual only** — never automatic egress. **No beta-channel exception.**" Banned patterns: "network calls (zero egress ideal)." Copy row: `nothing leaves this Mac`.

What on-device-only forecloses in agent capability: any frontier-scale hosted model; server-side taste inference; fleet learning; silent model updates as a channel for capability growth. The agent's ceiling becomes what an Apple Silicon Mac (D65 floor: Apple Silicon, macOS 14+) can run locally — and D46's bar is not "useful" but "beats each tester's own final hand edits," which is a high bar for a local model. What it preserves: the one sentence the product can say without qualification; the journal — which is the eval set — never leaves the machine; the sovereignty story that D4/D36 build the category position on. What an amendment would cost in trust: A13 was ratified *this batch cycle* to remove the last egress exception; reversing direction for agent capability within one batch of restoring R-9.1 in full would convert `nothing leaves this Mac` from a fact into marketing, and the copy row would have to be deleted or falsified. The session records both doors (Proposed Amendments P5) and resolves nothing.

**CONFLICT (artifact drift, contract wins):** `design/tokens.yaml` (version `6.3-motion-wiring`) still carries `grammar.beta_testflight_crash_reporting: accepted_beta_only_expires_at_1_0` citing A7, and `grammar.network_egress` notes "Beta TestFlight crash reporting is A7 exception only." The contract's D45 states "A7 withdrawn (A13, Batch 2)… No TestFlight crash reporting." `design/mvp-test-plan.md` §6 consent line likewise still cites "D45 / A7." Authority order resolves it — contract over tokens over plan — but the stale tokens are exactly the kind of text a *machine* reader would ingest as law. Routed as follow-up (not fixed here; this session writes no tokens).

### D46 / D32 (R-A.1 + A10) — the taste-model gate — STRENGTHENS

Quoted: "GATED on taste-model proof — until the gate passes it stays **banked**… benchmark = each tester's own final hand edits… **do not begin** taste-model work before the eval set exists." With an agent present this is the master sequencing rule: *every* agent capability beyond glances is downstream of this gate, and the gate's benchmark is hand output — which makes journal provenance (THE RECORD) load-bearing. The autopilot evidence (Prior Art 6) is why the gate must not be softened: ungated agent culling degrades the very signal the gate measures.

### D35 / D36 — failure grammar and sovereignty — SURVIVES / STRENGTHENS

Quoted (D35): "The table keeps working · the broken thing wears a facts-chip · one sentence names it · one action fixes it · nothing the user did is ever lost. Never an error page or modal." An agent that fails — model missing, proposal stale, resource exhausted — is a broken thing that wears a facts-chip and changes nothing. No agent-specific failure chrome exists or is proposed; D35 already covers a failing agent because the agent holds no state that release does not revert.

### D40 — engineering reconciliation — SURVIVES, and already contains the trap's corpse

Quoted (v5): "The P0 route is the live path; legacy quarantined and retired checkpoint-by-checkpoint." The legacy shell contains a worked example of the failure the brief names: `PhotoAgentOrchestrator.autoResolveHighConfidence(in photos: inout [PhotoRecord], threshold: Double) -> [AgentAction]` — an agent-only verb that mutates records directly, at a confidence threshold, recording into its own `AgentAction` log rather than the decision journal. Two products sharing a window, in code, quarantined. D40's retirement schedule is the anti-trap already in force; agent-first design re-derives the same conclusion from the other direction.

### D57 (R-Q.1) — SURVIVES (assessed because the brief cited it)

Quoted: "hold-Space on staged strip frame → loupe on **ADAPTED** preview regardless of spike resolution." Actor-independent honesty rule: what a glance shows during staging is the truth of the staged state — which is precisely what an operator inspecting an agent's staged work will need.

---

## THE GRAMMAR

### Wired today — verified in `Lumina/Views/P0/P0KeyRoutingModifier.swift`, the self-described "Sole owner of P0 live-path NSEvent keyboard routing"

| Input | Wired behavior | Contract authority |
|---|---|---|
| P / X | keep / reject, autorepeat swallowed | D10, D59 |
| ⌘Z | undo last | L5, D40 one-⌘Z discipline |
| Esc | `P0EscLadder` | L5, D35 |
| ← → ↑ ↓ | move focus (autorepeat) | D10 travel keys |
| ⏎ (36/76) | opens inspection | D11 partial (no wholesale commit on P0) |
| b (hold, down/up) | before-glance, inspect only | D9 |
| ⇧G | enter/leave grouping | **contract-silent** — no D rules a G key; flag |
| Space (49) | `toggleSelectionOfFocused` | **contract-conflicting** — D9 rules hold-Space = loupe; persistent selection touches the D29 shelf (already recorded as W2 `SHELF-BROKEN` in `proposal-batch-3.md`) |
| = / + , - / _ | density step | **contract-silent** — D49/D30 rule pinch density steps; no +/- keys ruled; flag |

Count check against the brief: five letter keys wired (b, g, p, x, z) — confirmed — plus Esc, arrows, Return, Space as stated, **plus two unstated bindings (+/-)** and one wiring that contradicts the contract (Space). Ruled-but-unwired, per contract + surface-sweep existence matrix: 1–4/Tab arming (D24), A develop latch (D46, banked), hold-J (D42, UI absent), ⇧⏎ staging (D14, absent on P0), ⌥←→ / ⇧⌥←→ detents (D12, absent), crop latch with R/O (D23/D63, legacy only), hold-Space loupe and hold-⇧ boundary (D9).

### The full keyboard map (assembly of ruled grammar — nothing invented)

Decision: `P` `X` (decide + advance; same-mark clears; never autorepeat) · pointer ✓/✕ on the focused frame (D47: ≥44 pt, always visible, wear their keys, full parity).
Commit ladder: `⇧⏎` stage → *hardware Return release* → `⏎` commit (D60) · `Esc` spatial no · `⌘Z` temporal no · commit-but-stay = `⏎ ←` (D11).
Arming and adjustment: `1–4` / `Tab` arm (D24) · `⌥←→` fine, `⇧⌥←→` coarse, `⌥`-click reset (D12) · value-echo during adjustment only (D24).
Holds (release returns, side-effect-free): `Space` loupe · `B` before · `⇧` boundary · `J` clipping (D9, D42).
Latches (loud, Esc exits): staging (D14) · Crop with `R` free-aspect, `O` orientation inside; A/X meanings preserved (D23/D63) · Develop `A` (D46 — banked until the gate).
Export: `⌘E` · `⌥⌘E` re-enters the recipe (D44).
`?` all shortcuts (frozen footer row).

Keyboard scales because the map above spends ~20 of ~100 keys and stays derivable from four modifier temperaments and two hold/latch classes — the v5 D8 rationale ("~25 memorized mappings became derivable physics") verified in the assembled map.

### Trackpad — deliberately small, already ruled (D30, quoted)

"Two-finger glide (momentum-free, snaps to rows) · pinch = the ONE context-dependent gesture (density on the table, zoom when focused — both 'lean in'; deliberate, named) · double-click = expand/return redundancy · force-press = optional loupe redundancy only," with swipe-commits, three-finger gestures, rotate, and pressure-only routes rejected. Each gesture earns its place by mapping to a real-table sentence: glide = walking the table; pinch = leaning in; double-click = the pointer path's expand; force-press = pressing down to look closer, and only ever as redundancy. Four gestures for perhaps 25 distinguishable ones, with no legend on glass — the vocabulary is small because a gesture the hand cannot guess from the table metaphor fails D8's evaluation tool. Nothing on the trackpad decides (L1 + D30's "no decisions"). The agent, having no hands, takes nothing from this surface; no gesture needs an agent rung.

### Two hands in parallel — collisions found and dispositions

1. **Decide-while-armed.** Left hand arms a control (1–4/Tab); right hand presses P/X; D62 advance would move focus out from under the armed state. Disposition: L3's parenthetical already resolves it — "navigating away = Esc" — advance clears arming, nothing written. A reading of existing law, not a new rule. Falsifier: a tester who arms, decides, and expects the armed state to follow focus.
2. **⇧-overload.** Hold-⇧ is a boundary glance (D9) *and* a modifier in ⇧⏎ / ⇧⌥←→. Pressing ⇧ en route to ⇧⏎ flashes the boundary reveal. Disposition: benign by construction — glances are read-only, so the overload can never mis-decide; v5 already handled the persistence edge ("zones outlive ⇧ only while a drag lives"). Forbid nothing.
3. **Hold-J while traveling.** Clipping glance held across arrow travel. Lawful and intended — D42's "anytime." No ambiguity.
4. **Hold-B while dragging a slider.** The sanctioned D9 case (latched-B was rejected precisely to make this the hold). No collision.
5. **Space.** Contract Space (hold = loupe) vs wired Space (selection toggle) collide on the same key. Not a two-hand ambiguity but a code-vs-law conflict; code loses (authority order). Routed as follow-up with the W2 selection findings.

### Where the agent enters — rung per verb

The commitment ladder for any actor: **HELD** (proposes; reverts on release; costs nothing) → **LATCHED** (stages; operator applies or cancels) → **COMMITTED** (persists).

| Verb | Agent rung | Reasoning |
|---|---|---|
| Glances (Space/B/⇧/J) | **HELD — permitted now.** | Side-effect-free by law; the agent as *spotter*: it may hold clipping on the frame it doubts, before, boundary — showing the operator why, never what to do. Release reverts; L2's shape exactly. |
| Focus travel | **HELD-adjacent — only as part of presenting a glance, and Esc restores prior focus.** | Focus is the operator's frame of attention; an agent that walks focus uninvited steals the loop. Esc-puts-it-back applies to attention too. |
| P / X / pointer ✓✕ | **NONE today.** | These verbs commit on tap (journaled, D10). The grammar has no proposed-cull rung, so an agent cull would be COMMITTED — indefensible against Prior Art 6 (atrophy + eval contamination) and premature against D46 (banked until the gate). See "Completeness as capability." |
| Develop adjustments / Adapt staging (⇧⏎) | **NONE today; LATCHED is the designed future rung (P3), gated on D46/A10.** | The D14 ladder is already the correct reviewable shape (Prior Art 2, 4); Tier 1 is banked; nothing enters before the gate passes. If it ever does: DAW rule applies — operator touch on a control instantly cancels the agent's pending value for that control (Prior Art 5). |
| ⏎ commit | **NEVER.** | D60's hardware-release precondition (with P1). Nothing is defended at COMMITTED; the table contains no COMMITTED placements to defend against the autopilot evidence — which is the finding. |
| Esc / ⌘Z against operator state | **NEVER.** | The undo namespace is the operator's veto; an agent that undoes the hand rewrites decisions. (Releasing its *own* held glance is release, not Esc.) |
| Crop / Develop latch entry | **NEVER.** | D9: latches are for open-ended two-handed work — they belong to hands; an agent latching steals the mode. Principle, from D9's own rationale. |
| Export ⌘E / ⌥⌘E / Trash offer | **NEVER.** | D34/D36/R-M.1; the one file-touching verb is hands-only or the sovereignty story ends. |

### Completeness as capability — what the agent cannot say, and whether each gap closes

1. **"I think this frame is soft / clipped / the better twin."** Expressible today — as a held glance plus D41's consequence-chip class (`sharpness not final` is the sealed exemplar; additional chips remain OPEN question 2). **Boundary to keep as the entire near-term surface.**
2. **"I propose rejecting these 40 frames."** Not expressible: no staged-cull rung exists. **Gap — but one to close only via ruling, after the gate, as P3**, because the alternative (agent presses X) is the trap. Until then the inexpressibility *is* the safety property.
3. **"I adjusted the recipe toward your usual finish."** Not expressible on P0 (D14 absent on live path; Tier 1 banked). **Gap already owned by CP7 + D46's gate; nothing new needed here.**
4. **"I did this while you were away."** Never expressible. **Boundary, permanent** — the copy row `grouping happens in front of you, in visible motion` generalizes: agent work happens in front of you or not at all.
5. **"Trust me, committed."** Never expressible (D60). **Boundary, permanent, and the thesis's proof.**

---

## THE RECORD

Verified in `Lumina/Persistence/ShootDecisionJournal.swift`: append-only JSONL at `.lumina/decisions.journal.jsonl` beside the shoot ("never under Application Support"); record fields are `id, sequence (monotonic), recordedAt, kind (cull.commit | edit.commit), commandID, assetID, cullBefore, cullAfter, finalOrderAfter, editBefore/AfterFingerprint, editAfterRecipe`; error cases include `historyRewriteAttempt` and `stagingNotJournaled` — "Staging is intentionally absent (D13)." **No actor or provenance field exists.**

Three determinations:

**1. Must agent records be distinguishable from hand records?** Under today's design the question dissolves cleanly: the journal records only commits; the agent can never commit (D60); therefore every record is hand-originated *by construction* and the journal is pure operator signal. This purity is an unadvertised consequence of `stagingNotJournaled` + D60 and should be named as a property, not an accident. It breaks the moment a suggestion rung exists: an operator who ⏎-accepts an agent-staged set produces a commit that is formally theirs but evidentially weaker — the 96%-distrust/48%-verify gap (Prior Art 4) says ratification is not authorship. Both failure directions: *without* provenance, D46's benchmark ("each tester's own final hand edits") silently absorbs agent output and the taste model trains on its own suggestions — the corpus cannot separate the operator's taste from the agent's, which is the quiet failure the brief predicts; *with* provenance recorded wrongly (e.g., marking the whole commit "agent"), the operator's genuine veto-and-adjust work is discounted. The correct shape is P2: a `proposedBy` (or equivalent) field on the commit record, reserved now, added only when a suggestion rung is ratified, distinguishing *hand-originated* from *hand-ratified-agent-proposed* — the decision is always the hand's; the proposal's origin is what the eval set must know.

**2. Must ⌘Z undo an agent action identically?** Yes, and today it does trivially — agent actions (glances) create no undoable state, and any future agent-staged set commits through the same `P0Command` path ("canonical state discipline + P0Command (one ⌘Z / gesture)" — checkpoint sequence, D40 carry) and therefore undoes as one ⌘Z like any hand-staged batch (D15's "one ⌘Z for the batch"). A second undo namespace would be an agent-only verb; forbidden by the thesis and by L5.

**3. What must a stranger reconstruct a year later?** From the journal alone: for every asset, the ordered sequence of committed decisions, each with before/after, timestamp, and command identity; the final order after each cull commit; the committed recipe after each edit — and, once P2 exists, whether each commit originated at the hand or was a hand's ratification of an agent proposal. What the stranger must *never* be able to reconstruct, because it was never written: staged states that dissolved (D13), agent proposals that were released or Esc-ed. The journal is the record of decisions, not of suggestions — suggestions that mattered became hand-ratified commits with provenance; suggestions that did not leave no residue. That asymmetry is deliberate and should survive any amendment.

---

## WHAT THE AGENT MAY NEVER DO

1. **Commit a decision.** D60 (hardware Return release; P1 makes the mechanism explicit) + L3. **Principle** — the human-in-the-loop boundary is mechanical, not policy.
2. **Touch the filesystem.** D36/R-M.1: X never touches files; the one file-touching verb (post-export Trash offer) is never automatic and hands-only; export writes are D34's receipts of hand decisions. **Principle.**
3. **Egress.** D45 as ratified: no network calls; the journal/eval set never leaves the Mac. **Principle at current law** (P5 records the re-argument without resolving it).
4. **Act while the operator is not watching.** Derived from L2 (an unwatched hold is meaningless — nobody is glancing), D6/copy `grouping happens in front of you, in visible motion`, and the D40-quarantined `autoResolveHighConfidence` counter-example. **Principle.**
5. **Alter a committed decision.** Journal is append-only (`historyRewriteAttempt` is an error); ⌘Z/Esc against operator state is the operator's veto, never the agent's verb. **Principle.**
6. **Train on its own output.** D46/A10: benchmark is the tester's own hand edits; consent line: "not for training without a further agreement"; P2's provenance field is the enforcement surface. **Principle.**
7. **Latch a work state (Crop, Develop).** D9's rationale — latches serve open-ended two-handed work. **Caution**, not principle: a loud, Esc-able agent latch is imaginable without breaking sovereignty, but nothing argues for it and mode-theft argues against.
8. **Press decision keys at all (today).** **Caution**, not principle — it is item 1 in disguise while cull verbs commit on tap; if P3 is ever ratified, this item converts into "may stage, never commit," and item 1 continues to carry the weight.

Six principles, two cautions. The list is long because the grammar's verbs are few and consequential; per the brief's test, that reads as the design being right, not timid.

---

## UNKNOWNS

- `design/strategy/release-readiness.md` — named in the session's reading list; **absent from this tree**. Unread; any dependency on it is unassessed.
- **Current SHA** — the uploaded tree carries no `.git`; counts and quotes are verified against the tree as-received (tokens `6.3-motion-wiring`; BUILD_LOG newest entry claims `origin/main` @ `b90fdfd`, 2026-08-16). Re-verify on a real checkout before ratifying anything here.
- **Whether synthesized `NSEvent`s satisfy the D60 gate as implemented** — requires a macOS host; `CommandChordTests` prove the held-press case, not the synthetic-release case. This is P1's falsifier.
- **On-device model capability vs the D46 benchmark** — unknowable before the A10 eval set exists; "do not begin taste-model work before the eval set exists" applies.
- **Input latency of held glances on the live path** — UNMEASURED on this host; the sequencing warning stands: no grammar freeze before it lands.

---

## CONFLICTS

- **CONFLICT — tokens/test-plan vs contract (artifact drift).** `tokens.yaml` `grammar.beta_testflight_crash_reporting` (cites A7) and `grammar.network_egress` note, and `mvp-test-plan.md` §6 "D45 / A7", all contradict D45 as amended by A13 ("A7 withdrawn… No TestFlight crash reporting"). Contract wins by authority order. Routed: token + plan text cleanup, next tokens session (P4).
- **CONFLICT — code vs contract (already partially on record).** Live Space = persistent selection toggle vs D9 hold-Space loupe and the D29 shelf; W2's `SHELF-BROKEN` finding in `proposal-batch-3.md` covers the selection half; the Space-key half is added here. Code loses; routed to the ITEM 2 disposition the operator already owns.
- **No conflict found between agent-first design and any ratified D/R entry.** The thesis survives because the ratified grammar already confines an agent to glances; the flagged tensions are artifacts and wiring, not law.

---

## PROPOSED AMENDMENTS (proposals with cost — never decisions)

- **P1 — D60 clarification: "physically released" means a hardware key transition; synthesized events do not satisfy the gate.** Equivalently: the agent's channel is the grammar's verb set, which contains stage but no commit. Cost: one contract sentence, one macOS test. Falsifier: the synthetic-event test above. Risk to hands: none.
- **P2 — Reserve a journal provenance field (`proposedBy: hand | agent`) on commit records, schema-versioned, added only if/when a suggestion rung is ratified.** Cost: schema version bump then; nothing now; journal stays operator-pure until then. Falsifier: an eval-set audit that cannot separate hand-originated from hand-ratified commits after a suggestion rung ships — if P2 is in place, that audit succeeds by construction.
- **P3 — The single future door for agent culling: a staged-suggestion rung reusing the D14 ladder** (halo-class proposal on frames → ⇧⏎-shaped stage → hand ⏎ / Esc; one banner, one count per D19; operator touch cancels per-item per the DAW rule) — **gated behind D46/A10 exactly as Tier 1 is, and sequenced after input-latency work.** Cost: one new latch on the hot loop; banner load; real risk of the rubber-stamp failure. Falsifiers: wave testers' accept-without-inspection rate (if staged sets are ⏎-ed faster than frames can be seen, the rung has become theater) and disagreement rate between staged suggestions and subsequent hand re-marks.
- **P4 — Token and test-plan A7-reference cleanup to match A13.** Cost: trivial edit session. Falsifier: `grep A7 design/tokens.yaml design/mvp-test-plan.md` returning only withdrawal notes.
- **P5 — D45 doors, recorded not chosen.** (a) Hold zero egress; accept the on-device capability ceiling as the agent's ceiling — cost: agent capability bounded by local silicon, possibly below the D46 bar indefinitely. (b) An explicit, operator-invoked, per-action egress consent ceremony — cost: `nothing leaves this Mac` dies as an unqualified sentence one batch after A13 made it whole, plus new chrome the anti-irritant clauses resist. The session recommends neither; it notes only that (b)'s trust cost is front-loaded and unrecoverable, while (a)'s capability cost is revisitable in any future batch.

---

*This document proposes and routes. It rules nothing, wires nothing, and freezes nothing.*
