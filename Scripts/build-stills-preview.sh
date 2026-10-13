#!/usr/bin/env bash
# Build the Stills web preview: the Sets page with Edit mounted inside it, as a browser runs it (the
# design's prototype: no plumbing, no native bridge), as a folder any static web server can show.
#
#   bash Scripts/build-stills-preview.sh [out-dir]     default: dist/site-stills
#
# The page files are copied unchanged, except index.html: the Sets page with two lines added. One points
# support.js at the React copies in vendor/ beside it; the other is the app's own content policy
# (SetsOffline.swift) with this site in place of lumina:, so the page can load and reach nothing but its
# own files. Babel is left out: neither page has JSX, and a page that asked for it would be refused, loudly.
# Photos are read in the viewer's browser. Builds only: it starts no server and uploads nothing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Scripts/page_files.sh"
SRC="$ROOT/design/handoff/lumina-cull"
SITE="${1:-$ROOT/dist/site-stills}"

mkdir -p "$SITE/vendor"
for f in "${PAGE_FILES[@]}"; do [[ "$f" == "$PAGE" ]] || cp "$SRC/$f" "$SITE/$f"; done
cp "$ROOT/design/handoff/vendor/"react*.js "$SITE/vendor/"
BUILD="${LUMINA_BUILD:-$(git -C "$ROOT" rev-parse --short HEAD)}"
python3 - "$SRC/$PAGE" "$SITE/index.html" "$BUILD" <<'PY'
import json, os, sys
src, out, build = sys.argv[1:4]
page = open(src, encoding='utf-8').read()
res = {'https://unpkg.com/react@18.3.1/umd/react.production.min.js': './vendor/react.production.min.js',
       'https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js': './vendor/react-dom.production.min.js'}
csp = ("default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' blob: 'unsafe-inline'; "
       "img-src 'self' blob: data:; media-src 'self' blob: data:; font-src 'self' blob: data:; connect-src 'self' blob: data:; "
       "frame-src 'none'; child-src 'none'; worker-src blob:; object-src 'none'; manifest-src 'none'; base-uri 'none'; form-action 'none'")
open(os.path.join(os.path.dirname(out), 'csp.txt'), 'w').write(csp + '\n')
head = '<meta http-equiv="Content-Security-Policy" content="%s">\n' % csp
head += '<script>window.luminaPreview = true; window.luminaBuild = %s; window.__resources = %s;</script>\n' % (json.dumps(build), json.dumps(res))
i = page.index('<script'); page = page[:i] + head + page[i:]
# Which build this is, small in the corner, so a stale tab can be told from the newest page (same hash as version.txt).
stamp = ('<div data-lumina="build" style="position:fixed;right:8px;top:2px;z-index:2147483647;font:10px/1.2 ui-monospace,Menlo,monospace;'
         'color:#9A958D;opacity:.6;pointer-events:none;user-select:none">build ' + build + '</div>\n')
j = page.rfind('</body>'); page = (page[:j] + stamp + page[j:]) if j >= 0 else page + stamp
# Whole or not at all: a browser reloading mid-build never reads half a page.
open(out + '.part', 'w', encoding='utf-8').write(page); os.replace(out + '.part', out)
PY
echo "$BUILD $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SITE/version.txt"
echo "$SITE  ($(cat "$SITE/version.txt"))"
