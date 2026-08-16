#!/bin/bash
# Banned-word and legacy-string scan — pure grep on user-visible literals.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

fail=0
report() { echo "FAIL: $1" >&2; fail=1; }

SWIFT_FILES=()
while IFS= read -r -d '' f; do
  SWIFT_FILES+=("$f")
done < <(find Lumina -name '*.swift' \
  ! -path 'Lumina/Design/CopyContract.swift' \
  ! -path 'Lumina/Develop/Lab/*' \
  ! -path 'Lumina/Testing/*' \
  -print0)

plumbing=(
  "files stay where they are · edits in open sidecars · this shoot opens in Lightroom as-is"
  "fetching full RAW"
  "The folder you pointed at is no longer where it was."
  "Point at it again"
  "Latest-wins: ⌘E re-renders dirty frames only; the header counts what is current."
  "⌘E re-renders"
  "⌥⌘E changes the recipe."
)

is_plumbing() {
  local value="$1"
  local p
  for p in "${plumbing[@]}"; do
    [[ "$value" == *"$p"* ]] && return 0
  done
  return 1
}

extract_ui_literals() {
  local file="$1"
  awk '
    /^[[:space:]]*\/\// { next }
    {
      line = $0
      while (match(line, /(Text|Button|Label|accessibilityLabel|accessibilityHint|help)[[:space:]]*\([[:space:]]*"([^"\\]|\\.)*"/)) {
        lit = substr(line, RSTART, RLENGTH)
        sub(/^.*"/, "\"", lit)
        sub(/".*$/, "\"", lit)
        gsub(/^"/, "", lit)
        gsub(/"$/, "", lit)
        print lit
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$file"
}

check_banned_literal() {
  local file="$1" value="$2"
  local lower
  lower="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  if is_plumbing "$value"; then
    return 0
  fi
  for word in sync preset catalog smart analyze generate; do
    if [[ "$lower" =~ (^|[^a-z])${word}([^a-z]|$) ]]; then
      report "$file banned word '$word' in UI string: $value"
    fi
  done
  if [[ "$lower" == *"copy settings"* ]]; then
    report "$file banned phrase 'copy settings' in UI string: $value"
  fi
  if [[ "$lower" =~ (^|[^a-z])import([^a-z]|$) ]]; then
    report "$file banned word 'import' in UI string: $value"
  fi
  if [[ "$value" =~ [Aa]uto ]] && [[ "$value" != *Develop* ]]; then
    report "$file banned 'Auto' outside Develop context in UI string: $value"
  fi
  if [[ "$value" =~ (^|[^a-zA-Z])[Aa][Ii]([^a-zA-Z]|$) ]]; then
    report "$file banned 'AI' in UI string: $value"
  fi
}

for file in "${SWIFT_FILES[@]}"; do
  while IFS= read -r literal || [[ -n "$literal" ]]; do
    [[ -z "$literal" ]] && continue
    check_banned_literal "$file" "$literal"
  done < <(extract_ui_literals "$file")
done

legacy=(
  "Adapt treatment to"
  "Adapted treatment to"
  "undoes all of it"
  "From DSC"
)
for file in "${SWIFT_FILES[@]}"; do
  for phrase in "${legacy[@]}"; do
    if grep -qF "$phrase" "$file"; then
      report "$file contains legacy string: $phrase"
    fi
  done
done

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "banned_words.sh: OK"
