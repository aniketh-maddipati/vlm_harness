#!/usr/bin/env bash
# Build the one-file Skim web preview and put it on Cloudflare Pages (project "lumina-skim").
#
#   bash Scripts/deploy-skim-preview.sh          build + deploy; prints the address
#
# First time only: it runs `npx wrangler login` (opens your browser to sign in to Cloudflare) and creates
# the project. The page is static: clips are read in the viewer's browser and never uploaded.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${SKIM_PAGES_PROJECT:-lumina-skim}"
SITE="$ROOT/dist/site"

python3 "$ROOT/Scripts/build-skim-preview.py" "$SITE/index.html" >/dev/null
# Not in search results, always the newest page.
cat > "$SITE/_headers" <<'H'
/*
  X-Robots-Tag: noindex, nofollow
  Cache-Control: no-cache
  Referrer-Policy: no-referrer
H
echo "$(git -C "$ROOT" rev-parse --short HEAD) $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SITE/version.txt"

command -v npx >/dev/null || { echo "Needs Node (npx). Install it from nodejs.org or 'brew install node', then run this again." >&2; exit 1; }
npx --yes wrangler whoami >/dev/null 2>&1 || npx --yes wrangler login
npx --yes wrangler pages project list 2>/dev/null | grep -q "\b$PROJECT\b" || npx --yes wrangler pages project create "$PROJECT" --production-branch main
npx --yes wrangler pages deploy "$SITE" --project-name "$PROJECT" --branch main --commit-dirty=true
echo "Live at https://$PROJECT.pages.dev  ($(cat "$SITE/version.txt"))"
