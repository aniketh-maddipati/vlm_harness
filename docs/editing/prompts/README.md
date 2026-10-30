# Edit feature prompts: one agent loop each

Each file is a complete prompt for one agent session: feature, UI, hands-on gesture, data, done-when.
They all run the shared loop in `LOOP.md`: measure → maths in three copies → tests → page UI →
checks → measure → show the owner → repeat (≤ 5 rounds) → PR, never merged unasked.

Background: `../RAPIDRAW-PARITY.md` (gaps, "better" scores), `../COLOUR-GRADING.md`,
`../LEARNED-LOOKS.md`.

To start one: open a session in this repo with "Run `docs/editing/prompts/<file>`."

## Order

| Wave | Prompts | Why |
|---|---|---|
| 0 | `00` parity baseline · `00b` Lightroom sweeps | numbers to start from; one owner Lightroom session covers every fit |
| 1 (no sweep needed) | `07` WB pad · `09` NR (needs the ISO ladder) · `10` lens · `13` grain · `14` masks panel · `19` presets/LUTs · `20` compare/clipping · `21` export | independent native areas |
| 2 (after the sweeps return) | `01` highlights · `02` clarity/texture/vibrance · `03` dehaze · `04` HSL/B&W · `06` curves · `08` sharpening · `12` vignette corners | fits |
| 3 | `05` colour grading (after 04) · `11` transform (after 10) · `15` drawn masks · `16` range/depth (after 14) · `22` repeat edits (after 14) | build on wave 1–2 |
| 4 | `05b` grading agent · `17` locals in masks · `18` heal/clone/remove · `23` learned looks | build on wave 3 |

The owner's main goal is repeating edits accurately (`22`), plus hands-on control. `14` → `22` is the
shortest path to it, and can run ahead of the fits.

## Running several at once

- Every look feature touches the same files: `LookMath.swift`, `LookKernels.swift`, `lookmath.py`,
  `LookString.swift`, `rules-v1.json`, the Edit page.
- Parallel sessions in their own worktrees are fine, but **merge one at a time**, and rebase the next
  on main after each merge. Two fits must never run on the same stage at once.
- Screen-owning checks (`probe.sh edit`, `screens`) take the screen lock: one at a time across all
  sessions.
- Stops that need the owner:
  - Lightroom data (`00b`, ISO ladder)
  - fitting on their own edits (`05b`, `22`, `23`)
  - model files (`16` depth, `18` LaMa)
  - shared key names (`05`)
  - stroke storage size (`15`)

## Keys reserved across prompts

Taken today: A C H N Q R S T V W X Y Z.

| Key | Prompt | Use |
|---|---|---|
| J | 18 | heal |
| K | 20 | clipping overlay |
| B | 20 | split view |
| U | 11 | upright |
| O | 14 | mask overlay |
| L | 23 | outcome tiles |
| F | 11 | flip, in Crop |
