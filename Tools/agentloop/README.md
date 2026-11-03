# agentloop: one lead, Grok and Claude workers

Dev tooling. Nothing here ships in the app or adds reach to it (`Scripts/trust_check.py` reads only
app code, `plumbing.js`, entitlements and the workflow). Python 3 standard library only.

```bash
python3 Tools/agentloop/agentloop.py                          # dry run of sample-plan.json: routing + worst-case cost
python3 Tools/agentloop/agentloop.py --plan-file plan.json    # dry run of your plan
python3 Tools/agentloop/agentloop.py --task "…" --plan        # Claude splits the task (one headless call ≤ $0.50)
python3 Tools/agentloop/agentloop.py --plan-file plan.json --live   # run it
python3 -m unittest discover -s Tools/agentloop/tests         # routing and guards, no network
```

## How it works

1. **Lead.** A plan is a list of sub-tasks: `id`, `kind`, `title`, `prompt`, `paths` (repo globs),
   `inputs` (ci_local logs), `command` (local only), `depends_on`. A Claude Code session usually
   writes it (it is the lead), or `--plan` asks headless `claude -p` with a JSON schema.
2. **Router** (`config.json` `routes`, then guards in `route()`):

   | kind | worker | why |
   |---|---|---|
   | search, summarize, log-triage, lint-fix, doc-draft | Grok `grok-build-0.1` ($1 / $2 per M tokens, 256k) | lots of input, short answer |
   | large-read, research | Grok `grok-4.3` ($1.25 / $2.50, 1M context; research adds web / X search, $5 per 1k) | whole-area reads, current facts |
   | page-ui | Claude `--agent page-ui-editor` | design work, byte copies, headless checks |
   | canvas | Claude `--agent canvas-debugger` | native Edit canvas |
   | bridge, look-math, code-edit, release, unknown | Claude `claude -p` | the bridge, trust rules, maths, edits |
   | test-run, ci | local, through `Scripts/test_guard.py` | allowlisted commands only |

   Guards: a sub-task naming a **protected path** (`config.json` `protected`: the bridge, the page and
   its copies, the look, entitlements, `docs/release`, trust / guard / release scripts, CI) goes to
   Claude whatever its kind. Grok's context is **tracked files only**, minus protected ones, plus
   ci_local logs; nothing from `~/LuminaEvidence` otherwise, nothing untracked.
3. **Workers report back** as `~/LuminaEvidence/agentloop/runs/<time>/<id>.json`
   (`status` ok / failed / refused / skipped, `summary`, `output` file, `files_changed`, `usd`, tokens,
   seconds) and the lead writes `summary.md`. Waves follow `depends_on`; Grok sub-tasks in a wave run
   side by side (they only read), Claude and local ones one at a time (one writer per worktree). A
   sub-task whose dependency failed is skipped.
4. **Grok never writes.** A lint-fix answer is a diff, applied only when every file it touches was
   named by the sub-task and none is protected, and `git apply --check` passes.
5. **Last step:** when anything changed and the plan has no `ci` sub-task, the lead runs
   `bash Scripts/ci_local.sh`. PASS ends with "ready for pr-shepherd". The loop never commits,
   pushes or merges.

## Budget

`config.json` `budget`: Grok ≤ $0.50 per run and ≤ $10 per month (ledger
`~/LuminaEvidence/agentloop/ledger.jsonl`, from the usage each response reports), Claude ≤ $3 per run
and ≤ $1 per sub-task (`--max-budget-usd`), at most 12 sub-tasks. Each Grok call reserves its worst
case first (all input uncached, the whole 4,000-token output allowance) and is refused if that
exceeds what is left. Contexts stay under 600k characters, below xAI's 200k-token double rate.
Without `--live` nothing is called: the dry run is the default.

## The xAI key

Keychain, login keychain, service `xai-api-key`, read at call time, never printed or written:

```bash
security add-generic-password -a "$USER" -s xai-api-key -U -w
```

(`-w` last with no value prompts for it, so it stays out of shell history.) The dry run says
whether it is there without reading it.

## Headless Claude

`claude -p` needs its own login (`claude` in a terminal, `/login`). Inside the desktop app a session
whose OAuth has expired gets "Failed to authenticate"; then let the Claude Code session be the lead:
it writes the plan, runs `--live` for the Grok and local sub-tasks, and does Claude's sub-tasks
itself or through its project agents.
