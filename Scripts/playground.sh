#!/usr/bin/env bash
# Lumina Debug — build, run, and see compile errors from the terminal.
# Hot reload: InjectionIII on this repo + ⌘R once in Xcode + save Swift files.
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
APP="$DERIVED/Build/Products/Debug/Lumina.app"
BIN="$APP/Contents/MacOS/Lumina"
SCHEME="Lumina"
INJECTION="/Applications/InjectionIII.app"

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
  # Downloads copy does not match Inject's bundlePath (/Applications/…).
  pgrep -f 'Downloads/InjectionIII.app' >/dev/null 2>&1 && killall InjectionIII 2>/dev/null || true
  if ! pgrep -qf '/Applications/InjectionIII.app' >/dev/null 2>&1; then
    echo "playground: starting InjectionIII from /Applications…"
    open "$INJECTION"
    sleep 1
  fi
  echo "playground: InjectionIII → File → Open Project… → $ROOT"
  echo "playground: hot reload = Run once from Xcode (⌘R), then save files (⌘S). Watch debug console."
}

build_playground() {
  ensure_macos
  echo "=== building $SCHEME (Debug) ==="
  echo "derived data: $DERIVED"
  set +e
  log="$(mktemp)"
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
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"

  if [[ $code -ne 0 ]]; then
    echo "playground: xcodebuild failed (exit $code) — open Lumina.xcodeproj and check Issue navigator (⌘5)" >&2
    exit "$code"
  fi
  if [[ ! -x "$BIN" ]]; then
    echo "playground: build succeeded but $BIN missing" >&2
    exit 1
  fi
  echo "playground: build OK → $APP"
}

run_playground() {
  if [[ ! -x "$BIN" ]]; then
    echo "playground: no build yet — run: bash Scripts/playground.sh build" >&2
    exit 1
  fi

  # Quit other Lumina processes so the right window is obvious.
  pgrep -x Lumina >/dev/null 2>&1 && killall Lumina 2>/dev/null || true
  sleep 0.3

  local -a args=("$@")
  if [[ ${#args[@]} -eq 0 ]]; then
    args=(--no-workbench)
  fi

  echo "=== running Lumina (Debug) ==="
  echo "app: $APP"
  echo "args: ${args[*]}"
  open "$APP" --args "${args[@]}"
  echo ""
  echo "Look for: menu bar «Lumina» + «Hot» badge top-right (Debug only)."
  echo "Edit Swift → save → pixels update (~1s). Best with ⌘R from Xcode first."
}

open_xcode() {
  open "$ROOT/Lumina.xcodeproj"
  echo "playground: use scheme Lumina, then ⌘R."
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
  run)
    run_playground "$@"
    ;;
  photos|grid|workbench)
    build_playground
    ensure_injection
    run_playground --workbench --card card-clean-500
    ;;
  open|xcode)
    open_xcode
    ;;
  start|"")
    build_playground
    ensure_injection
    run_playground --no-workbench
    ;;
  *)
    echo "playground: unknown command '$cmd'" >&2
    usage >&2
    exit 1
    ;;
esac
