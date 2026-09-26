#!/usr/bin/env bash
# LuminaPlayground — build, run, and see compile errors from the terminal.
# Startup selects this project in InjectionIII; Debug builds include injection support.
#
# Usage (from repo root):
#   bash Scripts/playground.sh          # build + run (open screen)
#   bash Scripts/playground.sh photos   # build + run (test photo grid)
#   bash Scripts/playground.sh build    # compile only — prints every error
#   bash Scripts/playground.sh run      # launch last build (no compile)
#   bash Scripts/playground.sh open     # open Xcode on this project
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="${LUMINA_DERIVED_DATA:-$ROOT/.derivedData}"
APP="$DERIVED/Build/Products/Debug/LuminaPlayground.app"
BIN="$APP/Contents/MacOS/LuminaPlayground"
SCHEME="LuminaPlayground"
INJECTION="/Applications/InjectionIII.app"
EVIDENCE="${LUMINA_DEV_EVIDENCE:-$HOME/LuminaEvidence/dev-startup}"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \?//'
  echo ""
  echo "Env: LUMINA_DERIVED_DATA overrides derived data path (default: .derivedData)"
}

ensure_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "playground: needs macOS + Xcode (see AGENTS.md)" >&2
    exit 2
  fi
  if ! command -v xcodebuild >/dev/null; then
    echo "playground: xcodebuild not found — install Xcode" >&2
    exit 2
  fi
}

ensure_injection() {
  if [[ ! -d "$INJECTION" ]]; then
    echo "playground: InjectionIII not in /Applications — hot reload will not work on save."
    echo "  Install: open https://github.com/johnno1962/InjectionIII/releases/latest"
    return
  fi
  echo "playground: selecting $ROOT in InjectionIII…"
  open -a "$INJECTION" "$ROOT/Lumina.xcodeproj"
  echo "playground: save Swift view edits in this checkout to inject; rebuild for structural changes."
}

# Cursor on the leading half; the app takes the trailing half (--dev-split).
park_prompt_window() {
  bash "$ROOT/Scripts/dev_split_peer.sh" || true
}

build_playground() {
  ensure_macos
  echo "=== building $SCHEME (Debug) ==="
  echo "derived data: $DERIVED"
  set +e
  mkdir -p "$EVIDENCE"
  local log="$EVIDENCE/build-$(date +%Y%m%d-%H%M%S)-$$.log"
  echo "build log: $log"
  xcodebuild \
    -project Lumina.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED" \
    SWIFT_CONTINUE_BUILDING_AFTER_ERRORS=YES \
    build 2>&1 | tee "$log"
  code=${PIPESTATUS[0]}
  set -e

  errors="$(grep -E '\.swift:[0-9]+:[0-9]+: error:' "$log" | sort -u || true)"
  if [[ -n "$errors" ]]; then
    echo ""
    echo "=== compile errors ===" >&2
    echo "$errors" >&2
    exit 1
  fi

  if [[ $code -ne 0 ]]; then
    echo "playground: xcodebuild failed (exit $code) — open Lumina.xcodeproj and check Issue navigator (⌘5)" >&2
    exit "$code"
  fi
  if [[ ! -x "$BIN" ]]; then
    echo "playground: build succeeded but $BIN missing" >&2
    exit 1
  fi
  {
    echo "source=$ROOT"
    echo "commit=$(git rev-parse HEAD)"
    echo "branch=$(git branch --show-current)"
    echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "log=$log"
    git status --short
  } > "$DERIVED/dev-build.txt"
  echo "playground: build OK → $APP"
  cat "$DERIVED/dev-build.txt"
}

run_playground() {
  if [[ ! -x "$BIN" ]]; then
    echo "playground: no build yet — run: bash Scripts/playground.sh build" >&2
    exit 1
  fi

  # Never terminate another agent's or the user's photo session.
  if pgrep -x Lumina >/dev/null 2>&1 || pgrep -x LuminaPlayground >/dev/null 2>&1; then
    echo "playground: a Lumina session is running; quit it normally before launching the new build." >&2
    echo "new build: $APP" >&2
    return 2
  fi
  ensure_injection
  park_prompt_window

  local -a args=("$@")
  if [[ ${#args[@]} -eq 0 ]]; then
    args=(--no-workbench)
  fi
  if [[ " ${args[*]} " != *" --dev-split "* ]]; then
    args+=(--dev-split)
  fi

  echo "=== running Lumina Playground ==="
  echo "app: $APP"
  echo "args: ${args[*]}"
  open "$APP" --args "${args[@]}"
  echo ""
  echo "Look for: menu bar «Lumina Playground» + «Playground» badge top-right."
  echo "Save a Swift view edit and verify InjectionIII reports success; structural changes need a rebuild."
  echo "Inject / save errors: Xcode debug console (bottom) while app is running."
  echo "Full project errors:  bash Scripts/playground.sh build"
}

open_xcode() {
  open "$ROOT/Lumina.xcodeproj"
  echo "playground: use scheme LuminaPlayground, then ⌘R."
  echo "Issue navigator ⌘5 — all compile errors. Debug area ⌘⇧Y — inject errors on save."
}

cmd="${1:-start}"
shift || true

case "$cmd" in
  -h|--help|help)
    usage
    ;;
  build|check)
    build_playground
    ;;
  prepare-hot)
    ensure_macos
    ensure_injection
    park_prompt_window
    ;;
  run)
    run_playground "$@"
    ;;
  photos|grid|workbench)
    build_playground
    run_playground --workbench --card card-clean-500
    ;;
  open|xcode)
    open_xcode
    ;;
  start|"")
    build_playground
    run_playground --no-workbench
    ;;
  *)
    echo "playground: unknown command '$cmd'" >&2
    usage >&2
    exit 1
    ;;
esac
