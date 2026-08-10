#!/bin/bash
# Structural contract checks — .cursorrules, design tokens, birth-motion path.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
report() { echo "FAIL: $1" >&2; fail=1; }

RULES="$ROOT/.cursorrules"
TOKENS="$ROOT/DesignTokens/Tokens.swift"
STABLE="$ROOT/Lumina/Views/Components/StablePhotoView.swift"

require_in_file() {
  local file="$1" needle="$2" label="$3"
  if ! grep -qF "$needle" "$file"; then
    report "$label: missing '$needle' in $(basename "$file")"
  fi
}

[[ -f "$RULES" ]] || report "missing .cursorrules"
[[ -f "$TOKENS" ]] || report "missing DesignTokens/Tokens.swift"
[[ -f "$STABLE" ]] || report "missing StablePhotoView.swift"

if [[ -f "$RULES" ]]; then
  require_in_file "$RULES" "Banner, header, and receipt strings come from" "cursorrules A1 source"
  require_in_file "$RULES" "Develop** is the sanctioned physical word" "cursorrules Develop ruling"
  require_in_file "$RULES" "design/copy-contract.txt" "cursorrules copy contract path"
fi

if [[ -f "$TOKENS" ]]; then
  require_in_file "$TOKENS" 'Color(hex: "2E2E2C")' "selection ring token"
  require_in_file "$TOKENS" "assertDistinctSelectionAndHalo" "selection/halo distinct helper"
fi

if [[ -f "$STABLE" ]]; then
  require_in_file "$STABLE" "tableBirth" "StablePhotoView tableBirth"
  require_in_file "$STABLE" "photoBirth" "StablePhotoView photoBirth motion"
  if grep -F '.transition(.opacity)' "$STABLE" | grep -qv reduceMotion; then
    report "StablePhotoView uses banned .transition(.opacity) without reduceMotion guard"
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "contract_structure.sh: OK"
