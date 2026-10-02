# The test runner chat

One Claude session on the Mac owns **all** test execution: the *runner chat*. Every other session
(cloud workers, other Mac sessions) writes code and asks the runner chat for tests. Nobody else
runs xcodebuild test, swift test, the probe, or anything that launches the app.

Why: on 2026-10-01 several sessions ran long probe and UI-test jobs at once and restarted them when
they were killed. The app kept appearing, keys were typed into it, disk images mounted and ejected,
and the Mac beeped for hours. Never again.

## What the runner chat does

1. **Takes a request** from another session or the user: what to check ("Edit keeps the photo in
   the canvas when the window is resized while zoomed"), on which branch/commit.
2. **Generates** the shortest test that answers it, ad hoc:
   - prefer headless (`templates/headless.sh`, `snap.sh`): no window, no keys, no sound;
   - a UI test only when the check needs the real window: **one** XCUITest at a time (`uitest.sh`
     refuses a whole suite);
   - a new check that will be asked again becomes a **template** in `templates/` (a short shell
     script with `# about:` and `# limit:` lines) or a test in the repo, so the next request reuses it.
3. **Runs** it only through the runner: `bash Tests/runner/run.sh <template> [args]`.
4. **Reports** back: the verdict line (`PASS` / `FAIL` / `TIMEOUT in Ns`), the failing lines, the
   log path. Nothing long, no re-runs unless asked.

## Guardrails (the runner enforces the first four; the chat keeps the rest)

- **A hard limit per run**: the template's `# limit:` (never over 600 s); the whole process group is
  killed at the limit. XCUITests also get XCTest's own 60 s / 90 s per-test allowance.
- **One run at a time**: a lock in `~/LuminaEvidence/runner/lock`; a second run is refused.
- **A clean exit, always**: on pass, fail, timeout or Ctrl-C the runner calls `stop.sh`, which ends
  the test app, test runners, the probe and its drivers, and detaches the probe's disk images.
- **The kill switch**: `bash Tests/runner/stop.sh` stops everything test-related, any time;
  `--check` only lists what is running.
- **No retries, no loops**: a failure is reported, not re-run. Long jobs (the probe's fault, life,
  stress and storage scenarios, soak, load) run only when the user asks for them by name, inside the
  runner, with a limit the user agrees to.
- **No keys sent to the desktop**: no osascript / System Events keystrokes; UI tests type into the
  app only through XCUITest.
- **Nothing else running**: before a UI test, `stop.sh --check` must say "nothing running"; if the
  user is working in another app, ask first: a UI test takes the screen for up to 90 s.
- **No ports left open**: a template that starts a server binds it to port 0 / its own port and
  kills it on exit (the runner kills its process group either way).

## Asking for a test (for other sessions)

Send the runner chat: the branch or commit, what to check, and why. For example:
"`claude/lumina-gallery-redesign-ui-5a43d6-8sknjr` at `6a371ff`: does `LuminaKit` build and do the
headless tests pass?" → the runner chat runs `run.sh build` then `run.sh headless` and answers with
the two verdict lines.

## Templates

`bash Tests/runner/run.sh list` prints them. Today: `build`, `headless`, `uitest` (one test),
`snap` (offscreen screenshots), `look` (launch, screenshot, quit; sends no keys), `selftest`
(proves the limit and the cleanup work).
