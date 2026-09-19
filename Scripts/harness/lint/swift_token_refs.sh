#!/usr/bin/env bash
# Static guard: every HiFiTokens.* use in Swift must exist in generated tokens.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
exec python3 "$ROOT/Scripts/harness/lint/swift_token_refs.py" "$@"
