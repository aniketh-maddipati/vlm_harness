#!/usr/bin/env bash
# Build the Stills web preview (Scripts/build-stills-preview.sh) and put it on Cloudflare Pages
# (project "lumina-still", beside Skim's "lumina-skim": two previews, two addresses).
#
#   bash Scripts/deploy-stills-preview.sh          build + deploy; prints the address
#   STILLS_PAGES_BRANCH=handoff bash Scripts/…     a preview beside it: https://handoff.lumina-still.pages.dev
#
# With CLOUDFLARE_API_TOKEN set (CI) it never asks to log in and never creates the project.
# First time only: it runs `npx wrangler login` (opens your browser to sign in to Cloudflare) and creates
# the project. The page is static: photos are read in the viewer's browser and never uploaded.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${STILLS_PAGES_PROJECT:-lumina-still}"
BRANCH="${STILLS_PAGES_BRANCH:-main}"
WRANGLER="${WRANGLER:-wrangler}"
SITE="$ROOT/dist/site-stills"

rm -rf "$SITE"
bash "$ROOT/Scripts/build-stills-preview.sh" "$SITE" >/dev/null
# Not in search results, always the newest page, never inside someone else's frame, and the page's
# content policy as a header too (the build writes it into index.html; frame-ancestors only works here).
cat > "$SITE/_headers" <<H
/*
  X-Robots-Tag: noindex, nofollow
  Cache-Control: no-cache
  Referrer-Policy: no-referrer
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY
  Content-Security-Policy: $(cat "$SITE/csp.txt"); frame-ancestors 'none'
H
rm "$SITE/csp.txt"

command -v npx >/dev/null || { echo "Needs Node (npx). Install it from nodejs.org or 'brew install node', then run this again." >&2; exit 1; }
if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  npx --yes "$WRANGLER" whoami >/dev/null 2>&1 || npx --yes "$WRANGLER" login
  npx --yes "$WRANGLER" pages project list 2>/dev/null | grep -qw "$PROJECT" || npx --yes "$WRANGLER" pages project create "$PROJECT" --production-branch main
fi
npx --yes "$WRANGLER" pages deploy "$SITE" --project-name "$PROJECT" --branch "$BRANCH" --commit-dirty=true
[[ "$BRANCH" == main ]] && HOST="$PROJECT" || HOST="$BRANCH.$PROJECT"
echo "Live at https://$HOST.pages.dev  ($(cat "$SITE/version.txt"))"
