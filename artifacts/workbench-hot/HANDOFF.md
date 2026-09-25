# Workbench / InjectionIII — branch handoff

**Branch:** `cursor/workbench-hot-reload`  
**Worktree:** `/Users/aniketh/lumina-wt/workbench-hot`  
**Base:** `99a5785` (main @ Auto WB preserve)

## Why so many “different UIs”

| Binary | Bundle ID | Hot reload |
|--------|-----------|------------|
| `Lumina.app` (any agent `*/DD/...`) | `com.lumina.app` | **No** — `.workbenchHot()` is a no-op |
| `LuminaPlayground.app` | `com.lumina.playground` | **Yes** — Inject + `LUMINA_WORKBENCH` |

Agents rebuilding under `/private/tmp/.../DD` open **different** `com.lumina.app` instances. The Playground is a separate app. Seeing “old UI” usually means an old Debug Lumina is still frontmost.

**Rule:** one Playground from `/private/tmp/lumina-playground-hot/DD/...`. Quit everything else with the smoke script before tasting.

## LuminaPlayground inspection

- Target links Inject SPM; defines `LUMINA_WORKBENCH`; `-interposable`; Copy Injection Bundle phase.
- Scheme bug fixed: `--card` / `card-clean-500` / `--surface` / `table` are **separate** argv tokens (was one string, so card never parsed).
- Default workbench on in Playground even without `--workbench`.

## Hot surfaces (this branch)

`ElasticRootView`, `ElasticTableView`, `ElasticFilmstrip`, `ElasticDevelopDrawer`, `P0RootView`, `P0OpenView`, `P0AdjustmentRail`.

## Commands

```bash
cd /Users/aniketh/lumina-wt/workbench-hot
bash Scripts/workbench_hot_smoke.sh --list
bash Scripts/workbench_hot_smoke.sh --sole-quit
bash Scripts/workbench_hot_smoke.sh          # build+launch sole Playground
```

Point InjectionIII at **this** worktree when tasting here (`lastWatched` must match).

Recorder checkout `/Users/aniketh/vlm_harness` left on `codex/recorder-cpu-reduction` (script removed from there).
