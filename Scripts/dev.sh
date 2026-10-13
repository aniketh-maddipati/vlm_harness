#!/usr/bin/env bash
# The dev app: one "Lumina Dev" that follows the code, for trying a change or a branch in seconds.
# Not what ships and not /Applications/Lumina.app (that is Scripts/install_app.sh, a clean Release build).
#
#   bash Scripts/dev.sh                 build this checkout (incremental Debug) and show it
#   bash Scripts/dev.sh --watch         the same, then again on every change under Lumina/ until Ctrl-C
#   bash Scripts/dev.sh <branch>        build that branch: from its worktree when it has one (uncommitted
#                                       work included), otherwise from a checkout the script keeps
#   bash Scripts/dev.sh <path>          build the checkout at <path>
#   bash Scripts/dev.sh --quit          quit the dev app
#   (--watch goes with a branch or a path too; a second dev.sh while one runs is refused, exit 75)
#
# What a build changed decides what happens to the running app:
#   only the page files or plumbing.js (Lumina/Sets/Web)  the page reloads in place (SetsHotReload, LUMINA_HOT=1)
#   anything else (Swift, rules-v1.json, the project)     the app is relaunched
# Either way the most recent shoot is opened again.
#
# The dev app has its own bundle id (com.lumina.app.dev), so its sandbox container, sessions and
# folder grants are its own: it never reads or writes the real app's sessions. It is a Debug build:
# Edit latency and anything the sandbox or the release settings decide are measured on the Release
# app or the probe, not here. One build folder for every checkout: ~/Library/Caches/com.lumina.dev.
#
# A second dev app beside this one (Scripts/dev-skim.sh) sets LUMINA_DEV_ID, LUMINA_DEV_NAME and
# LUMINA_DEV_CACHE: its own bundle id, name, build folder and lock, so the two never touch. LUMINA_PAGE
# is passed to the app it launches.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ID="${LUMINA_DEV_ID:-com.lumina.app.dev}"
NAME="${LUMINA_DEV_NAME:-Lumina Dev}"
CACHE="${LUMINA_DEV_CACHE:-$HOME/Library/Caches/com.lumina.dev}"
APP_ENV=(--env LUMINA_HOT=1); [[ -n "${LUMINA_PAGE:-}" ]] && APP_ENV+=(--env "LUMINA_PAGE=$LUMINA_PAGE")
DD="$CACHE/DD"
APP="$DD/Build/Products/Debug/Lumina.app"
BIN="$APP/Contents/MacOS/Lumina"
INPUTS=(Lumina Config Lumina.xcodeproj)

WATCH=0; QUIT=0; WHAT=""
for a in "$@"; do
  case "$a" in
    --watch) WATCH=1 ;;
    --quit) QUIT=1 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "dev.sh: unknown option $a" >&2; exit 2 ;;
    *) WHAT="$a" ;;
  esac
done

running() { pgrep -f "^$BIN" >/dev/null 2>&1; }
quit_app() {
  running || return 0
  pkill -f "^$BIN" 2>/dev/null || true
  for _ in $(seq 1 50); do running || return 0; sleep 0.1; done
  pkill -9 -f "^$BIN" 2>/dev/null || true
}
if [[ $QUIT == 1 ]]; then quit_app; echo "dev app quit"; exit 0; fi

# One dev.sh at a time: there is one dev app and one build folder, and two would relaunch over each other.
mkdir -p "$CACHE"
LOCK="$CACHE/dev.lock"
if ! (set -o noclobber; echo "$$ $ROOT $*" > "$LOCK") 2>/dev/null; then
  read -r HOLDER REST < "$LOCK" || true
  if [[ "$HOLDER" =~ ^[0-9]+$ ]] && kill -0 "$HOLDER" 2>/dev/null && ps -p "$HOLDER" -o command= | grep -q 'dev\.sh'; then
    echo "dev.sh: another dev.sh is running (pid $HOLDER: $REST). Stop it first (Ctrl-C there, or kill $HOLDER)." >&2; exit 75
  fi
  echo "$$ $ROOT $*" > "$LOCK"          # its holder is gone
fi
trap '[[ "$(cut -d" " -f1 "$LOCK" 2>/dev/null)" == "$$" ]] && rm -f "$LOCK"' EXIT
trap 'exit 130' INT TERM

# Where the source is.
SRC="$ROOT"
if [[ -n "$WHAT" ]]; then
  if [[ -d "$WHAT" && -d "$WHAT/Lumina.xcodeproj" ]]; then
    SRC="$(cd "$WHAT" && pwd)"
  else
    git -C "$ROOT" rev-parse --verify --quiet "$WHAT^{commit}" >/dev/null || { echo "dev.sh: no branch, commit or checkout named $WHAT" >&2; exit 2; }
    SRC="$(git -C "$ROOT" worktree list --porcelain | awk -v b="refs/heads/$WHAT" '/^worktree /{w=substr($0,10)} $1=="branch" && $2==b {print w; exit}')"
    if [[ -z "$SRC" ]]; then
      # No worktree has it checked out: the script's own checkout, moved to that commit. The same
      # path every time, so hopping between branches rebuilds only what differs.
      SRC="$CACHE/src"
      [[ -d "$SRC/Lumina.xcodeproj" ]] || { mkdir -p "$CACHE"; git -C "$ROOT" worktree prune; git -C "$ROOT" worktree add -q --detach "$SRC" "$WHAT"; }
      git -C "$SRC" checkout -q --detach "$WHAT"
    fi
  fi
fi
[[ -d "$SRC/Lumina.xcodeproj" ]] || { echo "dev.sh: no checkout at $SRC (a worktree that was removed? git worktree prune)" >&2; exit 2; }
mkdir -p "$CACHE"
STAMP="$CACHE/built.stamp"

# Everything a build reads except the page files: when this changes the app must be relaunched.
native_hash() {
  (cd "$SRC" && git ls-files -z -co --exclude-standard -- "${INPUTS[@]}" | grep -zv '^Lumina/Sets/Web/' | sort -zu \
    | xargs -0 shasum 2>/dev/null | shasum | cut -d' ' -f1)
}
web_hash() { (cd "$SRC/Lumina/Sets/Web" && find . -type f -not -name '.*' -print0 | sort -z | xargs -0 shasum | shasum | cut -d' ' -f1); }

build() {
  touch "$STAMP"
  local t0=$SECONDS
  xcodebuild -project "$SRC/Lumina.xcodeproj" -scheme Lumina -configuration Debug -derivedDataPath "$DD" \
    -destination 'platform=macOS,arch=arm64' PRODUCT_BUNDLE_IDENTIFIER="$ID" INFOPLIST_KEY_CFBundleDisplayName="$NAME" \
    build -quiet > "$CACHE/build.log" 2>&1 \
    || { grep -E '(error|failed)\b' "$CACHE/build.log" | sort -u | head -30; echo "  full log: $CACHE/build.log"; return 1; }
  local native web; native="$(native_hash)"; web="$(web_hash)"
  local name; name="$(git -C "$SRC" rev-parse --abbrev-ref HEAD)"; [[ "$name" == HEAD && -n "$WHAT" ]] && name="$WHAT"
  local what="$name $(git -C "$SRC" rev-parse --short HEAD)"
  # A checkout from before SetsHotReload has nothing watching the page files: relaunch it every time.
  [[ -f "$SRC/Lumina/Sets/SetsHotReload.swift" ]] || native="no-hot-reload $RANDOM"
  if running && [[ "$(cat "$CACHE/running" 2>/dev/null)" == "$native" ]]; then
    if [[ "$(cat "$CACHE/running.web" 2>/dev/null)" == "$web" ]]; then echo "✓ $what · $((SECONDS - t0)) s · nothing changed"
    else echo "✓ $what · $((SECONDS - t0)) s · page reloaded"; fi
  else
    local front=(); running && front=(-g)          # a relaunch stays behind the editor
    quit_app
    open -n ${front[@]+"${front[@]}"} "$APP" "${APP_ENV[@]}"
    echo "$native" > "$CACHE/running"
    echo "✓ $what · $((SECONDS - t0)) s · app $([[ ${#front[@]} == 0 ]] && echo launched || echo relaunched)"
  fi
  echo "$web" > "$CACHE/running.web"
}

echo "→ $SRC"
if [[ $WATCH == 0 ]]; then build; exit; fi

build || echo "✗ build failed; waiting for a change"
echo "watching ${INPUTS[*]} · Ctrl-C to stop (the app stays open)"
while sleep 1; do
  [[ -n "$(cd "$SRC" && find "${INPUTS[@]}" -type f -newer "$STAMP" -not -name '.*' -not -path '*/xcuserdata/*' 2>/dev/null | head -1)" ]] || continue
  build || echo "✗ build failed; waiting for a change"
done
