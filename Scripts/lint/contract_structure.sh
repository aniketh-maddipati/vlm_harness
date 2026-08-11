#!/bin/bash
# Structural contract checks — .cursorrules, design tokens, birth-motion path.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail=0
report() { echo "FAIL: $1" >&2; fail=1; }

RULES="$ROOT/.cursorrules"
TOKENS="$ROOT/DesignTokens/HiFiTokens.generated.swift"
TOKENS_YAML="$ROOT/design/tokens.yaml"
STABLE="$ROOT/Lumina/Views/Components/StablePhotoView.swift"

require_in_file() {
  local file="$1" needle="$2" label="$3"
  if ! grep -qF "$needle" "$file"; then
    report "$label: missing '$needle' in $(basename "$file")"
  fi
}

[[ -f "$RULES" ]] || report "missing .cursorrules"
[[ -f "$TOKENS_YAML" ]] || report "missing design/tokens.yaml"
[[ -f "$TOKENS" ]] || report "missing DesignTokens/HiFiTokens.generated.swift (run tokens_codegen.py)"
[[ -f "$STABLE" ]] || report "missing StablePhotoView.swift"

if [[ -f "$RULES" ]]; then
  require_in_file "$RULES" "Banner, header, and receipt strings come from" "cursorrules A1 source"
  require_in_file "$RULES" "Develop** is the sanctioned physical word" "cursorrules Develop ruling"
  require_in_file "$RULES" "design/copy-contract.txt" "cursorrules copy contract path"
fi

if [[ -f "$TOKENS" ]]; then
  require_in_file "$TOKENS" 'selectionColor: String = "2E2E2C"' "selection ring token"
  require_in_file "$TOKENS" "assertDistinctSelectionAndHalo" "selection/halo distinct helper"
  require_in_file "$TOKENS" "tokens-hash:" "codegen tokens-hash stamp"
fi
# Keep generated file fresh vs yaml (CP0).
python3 "$ROOT/Scripts/harness/codegen/tokens_codegen.py" --check || report "HiFiTokens.generated.swift stale vs tokens.yaml"

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
