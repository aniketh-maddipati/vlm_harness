#!/usr/bin/env bash
# Banned-pattern grep — spinners, skeletons, progress bars, failure modals,
# hover handlers, timed double-taps, release-commits, cached decisions, egress.
# Egress rule is D67 (R-N.1): loopback-only model inference, one sanctioned file.
#
# Strict on live path: P0 + Design + ViewModels + Core + Services + Persistence
# + ProbeV2. Quarantined legacy shell hits are recorded in
# artifacts/harness/banned_patterns_legacy.txt and owned in HARNESS.md GAP LIST
# (must not be silent).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

fail=0
report() { echo "FAIL: $1" >&2; fail=1; }

ALLOW="$ROOT/artifacts/harness/banned_patterns_allowlist.txt"
LEGACY_OUT="$ROOT/artifacts/harness/banned_patterns_legacy.txt"

STRICT_FILES=()
while IFS= read -r -d '' f; do
  STRICT_FILES+=("$f")
done < <(
  find Lumina/Views/P0 Lumina/Design Lumina/ViewModels Lumina/Core \
    Lumina/Services Lumina/Persistence Lumina/Testing/ProbeV2 \
    -name '*.swift' -print0 2>/dev/null
)

LEGACY_FILES=()
while IFS= read -r -d '' f; do
  LEGACY_FILES+=("$f")
done < <(
  find Lumina/Views/Workspace Lumina/Views/Components Lumina/Views/CompareAndSoftViews.swift \
    Lumina/ContentView.swift Lumina/Shell \
    -name '*.swift' -print0 2>/dev/null || true
)

is_allowed() {
  local file="$1" pattern="$2"
  [[ -f "$ALLOW" ]] || return 1
  grep -Fq "${file} ${pattern}" "$ALLOW" 2>/dev/null
}

scan_files() {
  local mode="$1"; shift
  local pattern="$1"; shift
  local message="$1"; shift
  local -a files=("$@")
  [[ ${#files[@]} -eq 0 ]] && return 0
  local hits
  hits="$(grep -nE "$pattern" "${files[@]}" 2>/dev/null || true)"
  [[ -z "$hits" ]] && return 0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ :[[:space:]]*// ]]; then
      continue
    fi
    file="${line%%:*}"
    if is_allowed "$file" "$pattern"; then
      continue
    fi
    if [[ "$mode" == "strict" ]]; then
      report "$message :: $line"
    else
      echo "$message :: $line" >> "$LEGACY_OUT"
    fi
  done <<< "$hits"
}

: > "$LEGACY_OUT"

PATTERNS=(
  'ProgressView\s*\(|spinner/ProgressView in product path'
  'Skeleton|skeletonView|redacted\(reason:\s*\.placeholder\)|skeleton/placeholder shimmer'
  'ProgressViewStyle|LinearProgress|CircularProgress|progress bar chrome'
  'NSAlert\s*\(|\.alert\s*\(|modal/alert (failure-path ban)'
  'onHover\s*\(|\.onHover|hover handler (D48)'
  'doubleTap|timedDouble|double_tap|timed double-tap'
  'releaseCommit|commitOnRelease|onReleaseCommit|release-commit'
  'URLSession\.shared|network egress from app (D67: loopback-only, one sanctioned file)'
  'cachedDecision|localStorage|cached decisions smell'
)

# PATTERNS above is a descriptive index only — it is never iterated.
# The executable scans are the scan_pair calls below; keep the two in step.
# PATTERNS stored as pattern|message — split carefully
scan_pair() {
  local mode="$1"
  local pattern="$2"
  local message="$3"
  shift 3
  scan_files "$mode" "$pattern" "$message" "$@"
}

scan_pair strict 'ProgressView\s*\(' 'spinner/ProgressView in product path' "${STRICT_FILES[@]}"
scan_pair strict 'Skeleton|skeletonView|redacted\(reason:\s*\.placeholder\)' 'skeleton/placeholder shimmer' "${STRICT_FILES[@]}"
scan_pair strict 'NSAlert\s*\(|\.alert\s*\(' 'modal/alert (failure-path ban)' "${STRICT_FILES[@]}"
scan_pair strict 'onHover\s*\(|\.onHover' 'hover handler (D48)' "${STRICT_FILES[@]}"
scan_pair strict 'doubleTap|timedDouble|double_tap' 'timed double-tap' "${STRICT_FILES[@]}"
scan_pair strict 'releaseCommit|commitOnRelease|onReleaseCommit' 'release-commit' "${STRICT_FILES[@]}"
# --- D67 (R-N.1): model inference is loopback-only --------------------------
# The socket lives in exactly one sanctioned file. Everywhere else in the strict
# tree URLSession.shared stays banned outright, exactly as before this ruling.
SANCTIONED_NET_FILE="Lumina/Services/ModelClient.swift"
if [[ ! -f "$SANCTIONED_NET_FILE" ]]; then
  report "D67 sanctioned net file missing: $SANCTIONED_NET_FILE (update this lint if it moved)"
fi

NET_SCAN_FILES=()
for f in "${STRICT_FILES[@]}"; do
  [[ "$f" == "$SANCTIONED_NET_FILE" ]] || NET_SCAN_FILES+=("$f")
done
scan_pair strict 'URLSession\.shared' "network egress from app (D67: only $SANCTIONED_NET_FILE)" "${NET_SCAN_FILES[@]}"

# D67 bans the destination, not only the transport: a URL built for any
# non-loopback host fails across the whole strict tree, sanctioned file included.
# Scoped to URL(string:) construction because XMP/RDF namespace URIs
# (XMPDevelopParser, LightroomHandoffService) are identifiers that are never
# fetched. Runtime overrides cannot be seen here — Swift enforces those.
scan_non_loopback_url_literals() {
  local -a files=("$@")
  [[ ${#files[@]} -eq 0 ]] && return 0
  local hits
  hits="$(grep -HnE 'URL\(string:.*https?://' "${files[@]}" 2>/dev/null || true)"
  [[ -z "$hits" ]] && return 0
  local line content urls url
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Strip the grep "file:line:" prefix before testing for a comment. The
    # generic scan_files filter cannot be reused here: its ":[[:space:]]*//"
    # test matches the "://" inside every URL, which would skip every hit.
    content="${line#*:}"
    content="${content#*:}"
    [[ "$content" =~ ^[[:space:]]*// ]] && continue
    urls="$(grep -oE 'https?://[^"]*' <<< "$content" || true)"
    while IFS= read -r url; do
      [[ -z "$url" ]] && continue
      if [[ ! "$url" =~ ^https?://(127\.0\.0\.1|localhost|\[::1\])([:/]|$) ]]; then
        report "non-loopback URL literal (D67) :: $line"
        break
      fi
    done <<< "$urls"
  done <<< "$hits"
}
scan_non_loopback_url_literals "${STRICT_FILES[@]}"
scan_pair strict 'cachedDecision|localStorage' 'cached decisions smell' "${STRICT_FILES[@]}"

scan_pair strict 'func selectClick\b|onSelectClick' 'pointer-to-selection wiring (Law 1 / D29 shelf)' "${STRICT_FILES[@]}"
scan_pair strict 'toggleSelectionOfFocused' 'Space/pointer selection toggle (D9 loupe; D29 shelf)' "${STRICT_FILES[@]}"

# Legacy / quarantined shell — record, do not fail FAST (owned in HARNESS.md).
scan_pair legacy 'ProgressView\s*\(' 'spinner/ProgressView in product path' "${LEGACY_FILES[@]}"
scan_pair legacy 'onHover\s*\(|\.onHover' 'hover handler (D48)' "${LEGACY_FILES[@]}"
scan_pair legacy 'NSAlert\s*\(|\.alert\s*\(' 'modal/alert (failure-path ban)' "${LEGACY_FILES[@]}"

if [[ -s "$LEGACY_OUT" ]]; then
  echo "NOTE: legacy banned-pattern hits recorded → $LEGACY_OUT (owned gaps; see HARNESS.md)"
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "banned_patterns.sh: OK"
