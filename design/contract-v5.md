# Lumina — Product Decision Record

A context block for any new session, collaborator, or tool. Each entry: the decision, why,
what was rejected, and how it evolved. This is the *reasoning* companion to the v5 contract —
the contract states rules; this records why they are what they are, so debates don't repeat.

---

## 1 · Identity & thesis

**D1. The interface is a table with photographs on it.**
One persistent surface; photographs are objects with weight; buttons only name what hands do.
Two surfaces total (Open, Table) — no modules, modes, or routes.
*Rejected:* Lightroom-style module walls (Library/Develop split is the #1 structural
complaint about LR); the earlier three-stage Workbench/Canvas/Proof shell (three stages =
three mental places; the code's own layout report showed proportion-morphing complexity).
*Why:* spatial memory is the pro's native index; one surface makes it possible.

**D2. Agentic-quiet: the AI is embodied in the table's behavior, never addressed.**
No chat, sparkle icons, confidence numbers, "AI" vocabulary, or approval dialogs. The
agent's work is simply the state of the table; corrections are physical (drag), never
conversational.
*Rejected:* AI tab, "Let Lumina decide" flows, per-suggestion confirm dialogs, confidence
percentages, explanation text.
*Why:* users should think "it understood what I was doing," not "I ran an AI feature."
Verifying an AI's *judgment* is slower than deciding yourself (the Aftershoot complaint);
verifying an AI's *arrangement* is a glance. Hence the deepest split:

**D3. Lumina arranges but never judges.** Grouping, adapted previews, baseline develop =
yes. Auto-culling, picks, ratings, verdicts = never in v1.
*Rejected:* tier assignment (~10% keep) that exists in the legacy code — banned;
blur/face-score-driven verdicts — banned; "auto-flag the blurry ones" — refused even as a
wish-list item (a facts-chip on shutter speed is the only contract-legal future form).
*Why:* keep/reject is pure taste, the product's philosophical spine, and the trust-killer
in every AI culler is a rejected favorite.

**D4. Positioning: "Edit the set, not every photograph."**
Plus three contrasts: shows real RAW not the camera's JPEG lie · arranges but never judges ·
files never leave, never upload, never lock in.
*Rejected:* "AI-powered Lightroom alternative" (generic; invites feature-parity war).

## 2 · The workflow inversion

**D5. The row is the unit of work; the loop is edit-then-cull-within-row.**
Pick the best frame in a row → edit it → the row answers with adapted previews → commit →
cull the row's *treated* frames → next row.
*Rejected:* whole-shoot flat culling first (LR culture; made sense when per-frame editing
was expensive — the radiating edit makes group-editing nearly free, so comparing treated
candidates beats squinting at flat RAW haze).
*Why:* rows also give a hundred small completions instead of one endless stream (Photo
Mechanic's frame-400 fatigue), and scope=row later halved the ML surface (D33).

**D6. Chronological landing → one watched tidy pass.**
The shoot lands in capture order, then visibly reorganizes into rows in front of the user.
Chronology is ground truth: tidying adds hierarchy to time, never scrambles it (L→R in a
row, top→bottom across rows).
*Rejected:* pre-grouped landing ("the model decided" — reads as an AI stunt; watched tidying
reads as "someone straightened the desk"); any reordering by quality score.
*Why:* watching the grouping happen is where trust comes from — you saw where everything
came from. The time rail (monospaced timestamps at row starts) is the entire "explanation";
no cluster labels, no confidence.

**D7. Spacing is quantized language — two values in MVP.**
3 px = burst (one moment) · ~20 px = same scene, distinct attempt · dashed rule + elapsed
time = new scene. Rows are left-aligned, ragged right, NEVER justified; long rows wrap like
sentences (indented continuation, no timestamp).
*History:* began as continuous spacing-as-confidence → rejected (humans can't read 18 vs
26 px; decays as culling removes frames) → quantized to three values with "the seam" (one
wide gap per row = the model's one doubt; "a row may hold at most one doubt") → the seam
SHELVED at MVP (a display hypothesis nobody validated; drag-correction covers all fixes).
*Rejected:* justified rows (gaps must measure exactly or the language dies); "+N" stack
badges; collapsing bursts (oversized bursts compress at the periphery instead, quantized
steps, everything stays visible).

## 3 · The physical laws (the grammar's constitution)

**D8. Five laws replace the rulebook.** Touch moves never decides · held is temporary ·
taps decide (work states are loud latches; navigating away = Esc) · ⇧ is more ⌥ is less ·
Esc puts it back ⌘Z takes it back. Companions: effort matches frequency; every interaction
needs a real-table sentence; latency is the first speed feature.
*Why:* ~25 memorized mappings became derivable physics; a pro should *guess* the grammar
and be right. The real-table test ("glide = walking the table, ⏎ = the stamp") became the
evaluation tool for every future idea.

**D9. Glances are holds; work states are latches.**
Hold-Space = loupe (momentary; release returns) · hold-B = before · hold-⇧ = boundary
reveal. Staging = a latch (no key held; loudly bannered; Esc exits).
*History:* my original ⇧-held staging chord → the design tool latched *everything*
(including the loupe) → resolved with this principle: a hold is safer for a two-second peek
(can't be forgotten; release is the exit), a latch is kinder for open-ended two-handed work.
*Rejected:* tap/hold Space duality (temporal ambiguity — the app must wait to know intent;
GPT's critique accepted); Space-toggles-loupe (forgettable mode over your photograph);
latched B (you'd adjust a slider while looking at the un-edited image); the G-key boundary
mode (a new key + a forgettable mode; replaced by ⇧-glance + drag-persistence: zones
outlive ⇧ only while a drag lives).

**D10. Culling keys: P/X decide AND advance; no Hold/Maybe; no chord on the hot loop.**
Same-mark-clears (adopted from code): re-pressing the mark on a marked frame clears to
unreviewed in place. Reconsider = P then ←. Decision keys never autorepeat.
*History:* S/X/M (original brief) → P/X, Hold banned (v3) → design tool made auto-advance
opt-in via ⇧P/⇧X ("matches pro muscle memory") → **fact-checked and rejected**: no major
tool advances via per-keystroke modifier (LR = Caps Lock mode; C1 = settings toggle); every
fast configuration converges on decision-advances-as-one-stroke; a modifier on 400
decisions/hour violates "no long modifier holds" — the modifier belongs on the rare case →
later ⇧P/⇧X *row-wide* decisions invented (⇧=more, finally lawful) → SHELVED at MVP
(unvalidated).
*Rejected:* star ratings and color labels (asked for constantly, abandoned in practice —
binary is pre-cognitive); single-toggle culling keys (undecided frames must stay findable).

**D11. The ⏎ doctrine.** ⏎ = yes-and-onward on the current scope; the one visible primary
names it and wears the key. A second ⏎ is always safe (rhythm, never a timed gesture);
⇧⏎ ⏎ is a phrase not a chord. Esc = spatial no; ⌘Z = temporal no; commit-but-stay = ⏎ ←.
*Rejected:* timed double-tap ⏎ (delays the most-pressed key); ⇧⏎ as "opposite/backward"
(⇧⏎ = the row is load-bearing; ⇧Tab keeps its macOS reversal meaning).
*Adopted from code:* the Return-release gate — after ⇧⏎ stages, ⏎ cannot commit until
Return is physically released; one held press can never stage-and-commit.

**D12. Modifier temperaments: ⇧ enlarges/coarsens, ⌥ refines.** ⌥-drag fine, ⌥←→ fine
detents, ⌥-click reset, ⇧⌥←→ coarse. Precision is GAIN, never finer motor control —
nothing ever asks for a more careful hand.
*Rejected:* ⇧-drag = fine (GPT and one design pass both proposed it; contradicts "⇧ is
more" and LR's own ⇧ = bigger increments).

## 4 · The hero interaction (propagation)

**D13. Release never commits — anywhere, in any form.** Only ⏎/⇧⏎/the one visible primary
commit. Every staged state is loudly bannered and fully reversible.
*History:* an early GPT doc specced "release over the commit zone to apply" — identified as
the single most dangerous contradiction and banned in bold. The physics obeys the grammar.

**D14. Propose → stage → commit, with the halo as the proposal.**
Editing the reference lifts a quiet halo on its row; previews warm to show the edit ALREADY
ADAPTED per frame (each RAW independently rendered). Unasked, ignorable, fades ~6 s, never
asks twice. ⇧⏎ stages; ⏎ commits (committable the frame staging appears — no settle
delay); Esc dissolves.
*Rejected:* the draggable "influence edge" (precision target; both its jobs covered by
coarser gestures); flick-out to exclude (drag already means "move between rows" —
outcome-flexibility violation); gather-drag as required path (kept as override, then
SHELVED at MVP); mandatory review beat before commit.

**D15. Exceptions: click-toggle; `Edited` protection with visible override.**
During staging the whole photograph is the toggle target (documented overload of click,
legal only in the bannered state). Individually edited frames start excluded, chip always
visible; clicking one IN is allowed (deliberate inclusion always wins — protection is a
default, never a lock), wears chip + halo together, and its prior edit folds into the same
single ⌘Z.

**D16. Adapt, never copy.** Product language is "Adapt treatment to N," never "sync/copy
settings"; each recipient gets a different numeric adjustment sharing the same visual
intention. This is the differentiation from LR Sync in four words, and it appears in the
banner verbatim.

**D17. Scope = the row, full stop (MVP).**
*History:* originally "compatible frames" cross-row detection → cut at MVP: it required a
second ML model; the row was the unit of work anyway. The code's free-selection batch
(max 3, leader-based) is re-scoped to the row.
*Socket:* the halo grammar renders cross-row whenever the model exists.

**D18. The four exposures + facts-only chips.** Every intelligent action makes legible:
Proposal (halo) · Scope (count) · Preview (adapted frames) · Provenance ("From DSC06785").
Chips state facts only — `Edited`, `4 photographs`, `proxy — settling` — never reasons,
percentages, or "AI"; any chip containing a "because" is banned.
*History:* "no explanations" softened after GPT pushback — but with the bright line above
so it can't erode in either direction.

**D19. Count invariant + clickable receipt.** Banner = receipt = header count, no path
diverges (a design pass drifted 3→4 once; now contract law). The receipt naming ⌘Z is
itself clickable as the undo.

## 5 · Fidelity & truth

**D20. The fidelity contract.** Embedded JPEG → proxy → full RAW; a quiet chip names any
rung below full truth; the chip disappearing IS the guarantee; 120 ms crossfades in the
same rectangle; softness is the loading state; latest-wins; no spinners/skeletons/bars
anywhere; native aspect always.
*Why:* Photo Mechanic's deepest flaw is the JPEG lie (culling on the camera's baked
contrast); FastRawViewer exists because of it. Honesty is the brand.

**D21. Truth-at-a-glance law: the file's facts are one held key or one glance away, never
a panel.** Loupe opens centered on the AF point (EXIF fact — FastRawViewer's killer
feature, zero new UI) · clipping overlays appear only WHILE adjusting a tone control
(momentary; deletes LR's forgettable J-toggle) · one small RAW-honest histogram above the
rail · mono EXIF line under the focused frame on the table.

**D22. Sharpness is judged only in the loupe or at 1:1.** Pinch-zoom keeps the chip honest
but is not the verdict instrument.

## 6 · The edit rail

**D23. Ten controls, four fixed sections, always visible, forever.**
Light (Exposure, Contrast, Highlights, Shadows) · Color (Temp, Tint, Vibrance, Saturation)
· Detail (Detail) · Crop (Straighten). No accordion, dropdown, or scroll; fits 800 pt;
positions never move across versions (the stability promise — LR's collapsing panels
destroy positional muscle memory).
*History:* 12 controls → the 13-inch wireframe *itself* clipped the last row → cut to 10
(dropped Blacks; merged Texture/Sharpening). The persistence schema stays richer (~15
fields + retouch, for XMP fidelity and imported sidecars) — schema rich, rail narrow.

**D24. Arming: the rail is a map, not a target.** Tap 1–4/Tab arms (2 pt charcoal ring);
armed answers scroll and ⌥←→ from ANYWHERE; value echoes at the pointer; unmodified scroll
over unarmed rows does nothing (the ring is consent — kills drift-edits).
*Why:* Capture One's Speed Edit proved aim-free adjustment; arming is its latched
descendant. Hold-keycap momentary aim was specced on probation, then SHELVED.
*Rejected:* customizable keybindings in v1 (the defaults ARE the fast configuration;
remapping = grammar drift).

**D25. Detents in photographic units; slider anatomy fixed.** ⅓ ev, 100 K, 5 units, 0.5°;
scroll/⌥←→ move by detents, pointer drag stays continuous. 50 pt rows, full-row target,
thumb 16→18→22 as cosmetic handshake, center-tick default with magnetic snap, muted =
untouched / dark = changed (the rail IS the edit summary — no history panel). Haptics
(4 events) specced, then SHELVED; detents remain visible.

## 7 · Focus, motion, selection

**D26. Focused edit = hero + elastic strip + rail; no ghost table.** ⏎ expands in place;
the row persists beneath (distant frames compress, never removed); Esc restores the exact
prior arrangement — the strip + exact restore carry "same table."
*History:* I leaned toward a ghost-table sliver; the design pass drew it gone; accepted
(the sliver was sentimentality).

**D27. Motion/fade law: photographs never fade — chrome does.** Photographs travel, dim in
place (~45–50%, recognizable), or soften toward sharp. Chrome fades (in 120 ms in place,
out 250 ms; the halo's 600 ms fade is the one slow fade — its slowness is the message).
Lift: grab 90 ms with 1.5–2° tilt ("in hand" legibility), carry 1:1 zero lag, place/return
200 ms one spring ≤2% overshoot. Fast runs → 90 ms. Reduced motion keeps dims and
crossfades (information), skips tilt/shadow. Duration never carries meaning.

**D28. Elasticity: elastic in motion, exact at rest, anchored at the focus.** Springs
travel between quantized states, never hold in-betweens; the focused/held/edited photograph
never moves as a side effect (periphery pays, distant-first); one gesture → one motion →
one spring → dead stop; sole exception = the watched tidy.

**D29. Selection: standard Mac grammar; hold-to-select banned.** Click / ⌘-click /
⇧-click / rubber-band on empty gray (surface disambiguates — drag on a photo moves it).
Fully specced, then SHELVED with two-up at MVP (existed mostly to feed two-up; the table's
adjacency + loupe is the v1 comparison).
*History:* two-up was argued in via pro compare behavior (LR's C view), specced (equal
size, both wear capture-time chips, X resolves, winner returns WITH you), then shelved by
the certainty knife. Four-up/survey permanently out.

**D30. Trackpad: full map, no decisions.** Two-finger glide (momentum-free, snaps to
rows) · pinch = the ONE context-dependent gesture (density on the table, zoom when focused
— both "lean in"; deliberate, named) · double-click = expand/return redundancy ·
force-press = optional loupe redundancy only.
*Rejected:* swipe-commits, three-finger gestures, rotate (Straighten is a slider),
pressure-only routes, unmodified scroll editing, gestures invisible until release.

## 8 · Ingestion, develop, export

**D31. Card-in IS the import; direct to table.** DCIM volume mounts → embedded JPEGs
stream → the shoot is landing when the user arrives; checksummed copy during early culling;
"safe to eject when the ✓ lands" is a hard guarantee. The Open surface greets only when
nothing is new. Point-at-folder-once is the second path.
*History:* the two-step hero card ("Open on the table ⏎") was deleted as a toll booth.
Folder WATCHING was specced (privacy line: "watches one folder, nothing leaves this Mac"),
then SHELVED. *Rejected:* any import dialog, destination picker up front, progress bar
(the sharpening thumbnail strip is the only ingestion display).

**D32. Three tiers of automatic help; Tier 0 ships.**
Tier 0 = every photograph lands at a competent camera-matched baseline; sliders read ZERO
there (zero = the honest starting point, not the sensor dump — a flat gray landing is a
*regression* from the camera's own back-screen JPEG). No chip, no undo entry.
Tier 1 = per-shoot suggested treatment via the halo grammar, written in the ten sliders
(the amateur→pro ramp: the AI's taste is always inspectable slider positions), `Suggested`
chip, A/⇧A/⌘A-A ladder (A = focused frame, live, one ⌘Z; ⇧A = row, staged; solo-A
applies live — taxing the common case to prevent a reversible typo is the wrong trade).
**Entire Tier 1 + A-ladder SHELVED at MVP** (an amateur bet on an unproven taste model;
Tier 0 delivers most of the value at zero model risk; re-enters through shipping halo
grammar). Tier 2 = the user's edit radiating (ships). Authority: hand > suggestion >
baseline, each one ⌘Z apart. Halo-pressure rule: at most one suggestion halo speaks at
rest. *Rejected:* ⌘A as auto (sacred select-all); a house look (camera-matched, not
Instagram-slop).

**D33. Learning = within-shoot memory only.** Corrected boundaries stay corrected;
exclusions persist. No silent cross-shoot model changes ("a tool with consistent reflexes,
not moods"). Cross-shoot learning returns only in an explicit, inspectable form.

**D34. Export = receipts, not a task.** ⌘E, ONE remembered recipe (size/format/naming, set
inline on first export), capture order. XMP sidecars continuously current → "this shoot
opens in Lightroom as-is" (the safety net that makes every MVP cut safe). Speculative
pre-render specced ("the fastest export already happened"), then SHELVED (invisible
optimization; honest header count at launch). Ordering UI (order-by-placing, numbers only
there, X-in-Ordering as the second pass) fully designed, then SHELVED — capture-order
export + LR handoff serve sequencers; FinalSetOrder data model stays.

## 9 · Trust, failure, absence

**D35. The failure-mode law.** The table keeps working · the broken thing wears a
facts-chip · one sentence names it · one action fixes it · nothing the user did is ever
lost. Never an error page or modal. (Canon list in the contract; data-safety cases —
eject, offline, disk full, quit-anywhere — were declared non-deferrable at every scope
cut.) Missing originals never delete catalog rows (adopted from the code's data layer).

**D36. Anti-irritant clauses (contractual absences).** Opens silently <1 s, asks nothing —
no tours, coach marks, update dialogs, rate-us, sign-in, ever (the key-wearing buttons and
footer hints ARE the onboarding). No catalog: files stay put, edits in open XMP beside
them, deleting Lumina loses nothing; X never touches the file system. Rail positions and
grammar do not move across versions.
*Why:* the category's hate list is ceremony, opacity, and broken speed promises — the
product's three commitments map onto it one-to-one.

**D37. Visual language.** Warm-white shell, neutral middle-gray table (#8D8C8A family — so
exposure judgment stays honest), warm charcoal text, photographs are the only color. Rings:
focus 3 pt charcoal · halo 1.5 pt warm-white · armed 2 pt charcoal — charcoal = the user,
white = the table speaking. Marks are shapes (✓ ✕), never color alone. One dark primary per
surface, state-based (Export is dark ONLY when exporting is the next sensible act), wearing
its key, Cancel to its left. Nothing under 44 pt; nothing hover-only. 4 pt grid; three type
sizes (11 chip · 13 UI · mono values).
*History:* porcelain-white table (original brief) → middle gray (v3, exposure honesty);
the codebase's dark-table palette (#141312) and green/red/blue accents are convergence
work, not a decision.

## 10 · Scope philosophy

**D38. The MVP knife: keep what is CERTAIN (loop-critical or evidence-backed by observed
pro behavior); shelve what was invented in design and never validated — each cut recorded
with its re-entry socket (doors, not deletions).** The shelf: Tier 1 + A-ladder · ⇧P/⇧X ·
multi-select + two-up · gather-drag · cross-row compatibility · the seam · Ordering UI ·
haptics · hold-keycap aim · folder watching · speculative pre-render.
*Why:* nothing in v1 should ride on our cleverness being right; the hero move was always
in the certain column, so the signature demo survives every cut.

**D39. Efficiency doctrine: delete the moments where the app waits for a human to confirm
what they already decided by being there.** Card inserted = wants the table · focus
arrived = wants sharpness (focused frame's RAW outranks the pipeline) · resume on first
undecided frame · last mark = light the exit ("Culled to 10 · Export ⌘E") · staging is
committable the frame it appears. Prediction of the obvious, applied to navigation.

**D40. Engineering reconciliation (code ↔ contract).** The P0 route is the live path;
the legacy shell (Workbench/Canvas/Proof, S/X/M, tiers, taste-index, audit piles, set
rail) is quarantined and retired checkpoint-by-checkpoint — salvage EmbeddingService +
burst grouping (the one model job) and ExifToolService. The Lab-gated develop engine
(unified preview ≡ export graph, latest-wins gate, fidelity labels) integrates into P0,
never the legacy shell; interactive grading of camera JPEGs must never return. Canonical
state discipline (ShootRecord/AssetRecord/EditRecipe/AssetIdentity; P0Command undo stack;
one ⌘Z entry per gesture) governs all new work; the XCUITest harness invariants (leaf-only
accessibility IDs, deterministic fixtures, state probe) ship with every new surface;
BUILD_LOG.md gets one entry per session.

## Open questions (the complete list)

1. **The 90 px question** — does the adapted preview persuade at strip width with real
photographs? (Hi-fi frames 7–8–9; fallbacks: brighter halo ring or slight recipient
growth within normal elasticity.)
2. Keycap tap-to-arm feel in practice.
3. Semantic rows + time rail + two-gap vocabulary inside NSCollectionView virtualization —
design and engineering answer together.

## The success test

A photographer finishes a real shoot — card to exported set — faster than in Lightroom, on
day one, having read nothing. Thirty seconds of watching: "they're just moving photographs
around on a table, and the app keeps up." No one ever wonders whether what they see is
really sharp, really applied, or really reversible.
