# Lumina build-stability contract

## Required environment

- Apple Silicon Mac (`arm64`)
- macOS 14 or newer
- Xcode 16.4 or newer
- Python 3 with PyYAML
- `exiftool` for optional metadata/media integration

Linux may run FAST only. Xcode gates on Linux are
`PLATFORM-UNAVAILABLE`, never pass.

## Configuration invariant

| Target | Configuration | `DEBUG` | `LUMINA_SHIPPING_APP` | `LUMINA_WORKBENCH` | Intent |
|---|---|---:|---:|---:|---|
| `Lumina` | Debug | yes | no | no | development/test harness |
| `Lumina` | Release | no | yes | no | shipping |
| `LuminaPlayground` | Debug | yes | no | yes | development workbench |
| `LuminaPlayground` | Release | no | yes | no | shipping-like source surface |

Every app Release configuration is shipping-fenced; only Playground Debug has
workbench capability. Do not add a third compile identity to repair a local
source error.

## Canonical commands

```bash
# Static gate
python3 Scripts/harness/run.py fast

# Continue-after-errors compile ledger (app + logic/UI test bundles)
bash Scripts/compile_check.sh --derived-data DD

# Complete two-round clean gate
bash Scripts/build_stability.sh
```

`BUILD_STABILITY_DERIVED_DATA=/absolute/path` may override the isolated
DerivedData location. The script deletes that directory before each round.

## Per-edit loop

Before changing Swift:

```bash
test -z "$(git status --porcelain)"
python3 Scripts/harness/run.py fast
bash Scripts/compile_check.sh --derived-data DD
```

After each small coherent change:

1. Run the narrowest relevant compile/test.
2. Run `bash Scripts/compile_check.sh --derived-data DD`.
3. Run the relevant targeted logic tests.
4. Fix or revert every new red result before starting another change.

## Logical checkpoint

```bash
python3 Scripts/harness/run.py fast
rm -rf DD-checkpoint
xcodebuild -project Lumina.xcodeproj -scheme Lumina \
  -configuration Debug -derivedDataPath DD-checkpoint \
  -destination 'platform=macOS,arch=arm64' clean build
xcodebuild -project Lumina.xcodeproj -scheme Lumina \
  -configuration Debug -derivedDataPath DD-checkpoint \
  -destination 'platform=macOS,arch=arm64' build-for-testing
xcodebuild -project Lumina.xcodeproj -scheme Lumina \
  -configuration Debug -derivedDataPath DD-checkpoint \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:LuminaLogicTests test-without-building
```

## Before merge to main (Mac) / after land (CI)

Hosted CI runs `build-stability` on **push to `main`**, schedule, and
`workflow_dispatch` (`nightly` / `all`) — not on every PR. PR merge gates stay
`fast` + `compile-logic`.

On an Apple Silicon Mac, optionally run `bash Scripts/build_stability.sh`
before merging a large compile-surface change. It must complete two rounds with:

- FAST green
- clean Debug build
- build-for-testing
- every `LuminaLogicTests` test passing
- zero compile-ledger errors
- shipping and Playground Release builds passing
- applicable unsigned Release-integrity checks passing
- no tracked changes produced by the gates

Then run the supported pre-merge/media lanes that have their required fixtures.
Named refusing stubs, missing fixture secrets, signing credentials, and
unsupported hosts remain `BLOCKED`, `INCOMPLETE`, or
`PLATFORM-UNAVAILABLE` exactly as reported. Never reinterpret them as pass.

## Release check

The two-round gate builds Release and runs F11.1/F11.2. A shipping cut must
also run the credentialed signature, notarization, and stapling checks from
`HARNESS.md`; unavailable credentials are a blocker, not a green result.

## Failure classification

Every red result is one of:

- `PRE-EXISTING` — reproduced on the untouched base commit
- `INTRODUCED BY THIS TASK` — absent on the untouched base
- `ENVIRONMENTAL` — tool/fixture/credential failure on a supported host
- `PLATFORM BLOCKED` — required platform unavailable
- `UNKNOWN` — insufficient evidence; investigate before editing

Do not cite `BUILD_LOG.md` alone as proof of a pre-existing failure.

## Project-file and flake discipline

- Edit `project.pbxproj` only for required target/resource/build-setting work.
- Inspect every project-file diff and immediately run a clean build.
- Never regenerate the whole project for one file.
- Do not use test retries, quarantine, arbitrary sleeps, weakened assertions,
  removed target membership, or suppressed compiler diagnostics to create a
  green result.
- A no-op gate must leave `git status --porcelain` empty.

## No-new-red rule

An agent may not stack work on an unexplained compile or test failure. Reproduce
one failure, identify its owner and root cause, make the smallest fix, run the
narrow proof, compile ledger, complete logic suite, FAST, and a clean rebuild.
If a test is intermittent, investigate shared state, tasks, paths, fixtures,
and ordering; rerunning until green is not a fix.
