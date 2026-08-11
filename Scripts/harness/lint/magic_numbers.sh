#!/usr/bin/env bash
# Magic-number gate: UI files must not re-literal values owned by tokens.yaml.
# Allowlisted debt: artifacts/harness/magic_number_allowlist.txt (path + literal).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

ALLOW="$ROOT/artifacts/harness/magic_number_allowlist.txt"
GEN="$ROOT/DesignTokens/HiFiTokens.generated.swift"

fail=0
report() { echo "FAIL: $1" >&2; fail=1; }

[[ -f "$GEN" ]] || { report "missing generated tokens $GEN"; exit 1; }
python3 "$ROOT/Scripts/harness/codegen/tokens_codegen.py" --check || exit 1

# High-signal chrome literals (integer pt/px from tokens).
declare -a CHECKS=(
  '252|histogram width'
  '1280|min window width'
  '800|min window height'
)

is_allowed() {
  local file="$1" lit="$2"
  [[ -f "$ALLOW" ]] || return 1
  grep -Fq "${file} ${lit}" "$ALLOW" 2>/dev/null
}

mapfile -d '' FILES < <(find Lumina/Views Lumina/Design Lumina/Shell -name '*.swift' -print0 2>/dev/null)

for item in "${CHECKS[@]}"; do
  lit="${item%%|*}"
  label="${item#*|}"
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    line="${rest#*:}"
    if [[ "$line" =~ HiFiTokens|LuminaTokens|CopyContract ]]; then
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*// ]]; then
      continue
    fi
    if is_allowed "$file" "$lit"; then
      continue
    fi
    report "raw magic $lit ($label) in $hit — use generated HiFiTokens.*"
  done < <(grep -nE "(^|[^0-9.])${lit}([^0-9.]|$)" "${FILES[@]}" 2>/dev/null || true)
done

if [[ "$fail" -ne 0 ]]; then
  echo "NOTE: allowlist format: '<path> <literal>' per line in $ALLOW" >&2
  exit 1
fi
echo "magic_numbers.sh: OK"
