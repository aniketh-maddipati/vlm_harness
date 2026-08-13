#!/usr/bin/env bash
# Magic-number gate: UI files must not re-literal values owned by tokens.yaml.
# Literals derived at runtime from DesignTokens/HiFiTokens.generated.swift.
# Allowlisted debt: artifacts/harness/magic_number_allowlist.txt (path + literal).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
exec python3 "$ROOT/Scripts/harness/lint/magic_numbers.py" "$@"
