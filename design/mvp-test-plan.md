# Lumina MVP test plan — Amendment Batch 1 (A1, A6, A9, A10)

**Authority:** `design/contract-v6.md` (carry + A1–A10).  
**Status:** Documents only — no product code in this session.  
**Change-marks:** `[● A#]` = landed this batch.

---

## 1. Floor & fleet `[● A1]`

| Constraint | Law |
|------------|-----|
| Architecture | **Apple Silicon only** |
| OS | **macOS 14+** |
| Intel | **Never** — perf contract assumes unified memory + Metal purgeability |

### Bodies at MVP test

| # | Body | Formats | Fixture id (see `design/fixture-manifest.md`) |
|---|------|---------|-----------------------------------------------|
| 1 | Sony A7 IV | `.ARW` | `sony-a7iv` |
| 2 | Canon R6 II | `.CR3` | `canon-r6ii` |
| 3 | Nikon Z6 III | `.NEF` | `nikon-z6iii` |
| 4 | Fujifilm X-T5 | `.RAF` | `fujifilm-xt5` |
| 5 | iPhone (Pro) | ProRAW `.DNG` | `iphone-proraw` |
| 6 | iPhone (Pro) | `.HEIC` | `iphone-heic` |

`[FLAG: body list is Claude's pick; swap freely before fixtures are cut.]`

**Unsupported body:** facts-chip `body not yet supported` (frozen in `design/copy-contract.txt`); table keeps working — a D35 exercise, not a failure path (no modal).

**Fixture cost note:** Six bodies ~doubles fixture / golden / baseline work vs. the prior 3-body plan and sits on the **critical path** (see fixture-manifest).

---

## 2. Tester waves `[● A1]`

| Wave | Mix | Purpose |
|------|-----|---------|
| **Wave one** | Amateurs | Cold grammar, unaided completion, row-meaning probe, crop-key check |
| **Wave two** | Pros | Hot-loop stress at pro decision rates; vehicle for Tier 1 / Develop if gate passes |

Do not begin taste-model work before the wave-one eval set exists (`[● A10]`).

---

## 3. Success metrics — all required `[● A9]`

1. **Unaided completion** — card → exported set, having read nothing (aligns D32 success-test rewrite).
2. **Time vs. current tool** — self-reported comparison to the tester’s usual culling tool.
3. **Trust interview** — ask verbatim: *did you ever wonder whether what you saw was really sharp, really applied, or really reversible?*

Plus batch probes:

4. **Rows probe** `[● A6]` — cold: *what do you think the rows mean?* (swim-lane re-entry door).
5. **Crop-key check** `[● A2]` — validate R (free aspect) / O (flip orientation) with wave-one testers.  
   `[FLAG: R/O are Claude's pick — validate with wave-one testers.]`

---

## 4. Tier 1 proving schedule `[● A10]`

Schedules the D46 / R-A.1 gate:

1. Prove the taste model **after wave one**, not before.
2. Eval set = **consented tester shoots** (see consent line below).
3. Benchmark = each tester’s **own final hand edits**.
4. Tier 1 / **Develop** ships only when it **beats** that benchmark.
5. Target vehicle: **wave two** or **v1.1**.
6. **Do not begin** taste-model work before the eval set exists.

---

## 5. Tester script (facilitator)

### Setup

- Apple Silicon Mac, macOS 14+.
- Build under test is a **wave / beta** build (free; no license ceremony — A8).
- Card or folder from one of the six bodies; one unsupported-body sample on standby for the D35 chip check.

### Script

1. **Cold open** — hand the Mac; no tour. Observe whether the sample shoot / empty table is understood.
2. **Rows probe** `[● A6]` — before explaining grouping, ask: *what do you think the rows mean?* Record pass/fail (fail rate that alarms → swim-lane plates may re-enter as a ruled experiment only).
3. **Ingest** — card or folder; confirm table keeps working through copy; note any facts-chips.
4. **Cull** — keyboard P/X and pointer ✓/✕ (A3); confirm same-mark clears; advance matches keys.
5. **Crop check** `[● A2]` — enter crop; confirm banner `Crop · ⏎ applies · Esc cancels`; try R / O; confirm A and X are **not** remapped to crop verbs.
6. **Hold-J** `[● A4]` — hold J for clipping glance; release returns.
7. **Adapt / receipt** — stage Adapt; confirm compressed banner / receipt / provenance forms (A5); ⌘Z from receipt.
8. **Export** — complete card → exported set (**metric 1**).
9. **Time compare** — self-report vs. their current tool (**metric 2**).
10. **Trust interview** — ask the three-part question (**metric 3**).
11. **Unsupported body** (if scheduled) — confirm `body not yet supported` chip; table still works.

### Wave-two addenda

- Hot-loop stress at the tester’s pro decision rate.
- If taste-model gate has passed, Develop path; otherwise banked (D46).

---

## 6. Consent line (tester agreement) `[● A10]`

Include verbatim in the tester agreement:

> I consent to Lumina using photographs from this test session, and my final hand edits on those photographs, as an evaluation set for taste-model proving. Edits and marks from this session are used only to measure whether a future Develop proposal beats my own hand finishing — not for training without a further agreement, and not for network upload from launch builds (diagnostics: see contract D45 / A7).

---

## 7. Swim-lane re-entry door `[● A6]`

No lane plates at MVP. Watched tidy + time rail + gap language carry grouping at rest.

**Re-entry:** If wave-one testers fail the cold rows probe at a rate that alarms, lane plates may re-enter **only** as a ruled experiment (new ruling required — not silent un-shelf).

---

## 8. OPEN (test plan)

- Exact alarm threshold for the A6 rows-probe fail rate (not named by the ruling).
- Wave sizes / recruiting (not named).
- Whether HEIC-only iPhone shoots need a separate golden from ProRAW (fixture OPEN).
