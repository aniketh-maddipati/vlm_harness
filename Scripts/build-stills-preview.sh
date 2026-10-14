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
# A newer build on the site shows a notice with Refresh and Later, as Skim's preview does (its LOCAL-CHANGES 270, the
# same look and words): version.txt is read every 30 s and when the tab comes back to the front. Preview chrome only,
# added here and never to the design's page; it shows only over http(s), so a file:// copy never asks.
stamp += """<style>@keyframes lmStaleIn{from{opacity:0;transform:translate(-50%,-6px)}to{opacity:1;transform:translate(-50%,0)}}
@keyframes lmStaleDot{0%,100%{opacity:1}50%{opacity:.35}}
[data-lumina="stale"] button{font:inherit;border:0;margin:0;-webkit-appearance:none;appearance:none;min-height:28px;border-radius:8px;cursor:pointer}
[data-lumina="stale"] button:focus-visible{outline:2px solid #FFD27A;outline-offset:2px}
[data-lumina="stale-later"]:hover{background:rgba(239,236,230,0.1)!important}</style>
<div data-lumina="stale" role="status" hidden style="position:fixed;left:50%;top:10px;transform:translateX(-50%);z-index:2147483646;align-items:center;gap:12px;padding:8px 8px 8px 16px;border-radius:12px;background:#33312E;color:#EFECE6;box-shadow:0 8px 28px rgba(0,0,0,0.45),inset 0 0 0 1px rgba(255,210,122,0.4);font:13px/1.2 -apple-system,BlinkMacSystemFont,system-ui,sans-serif;white-space:nowrap;animation:lmStaleIn 220ms ease-out">
<span style="width:8px;height:8px;border-radius:50%;background:#FFD27A;animation:lmStaleDot 1.6s ease-in-out infinite"></span>
<span>A newer Lumina is ready</span>
<button type="button" data-lumina="stale-go" style="padding:5px 12px;background:#FFD27A;color:#1E1D1B;font-weight:800">Refresh</button>
<button type="button" data-lumina="stale-later" aria-label="Later" style="padding:5px 10px;background:transparent;color:#B8B3AB">Later</button>
</div>
<script>(function () {
  var build = window.luminaBuild, el = document.querySelector('[data-lumina="stale"]'), busy = false, shown = null, skip = null;
  if (!window.luminaPreview || !build || !el || !/^https?:$/.test(location.protocol)) return;
  // The same test as Skim's staleOf: the first word of version.txt, a commit hash, other than this page's build.
  function staleOf(t) { var v = String(t || '').trim().split(/\s+/)[0]; return v && /^[0-9a-f]{4,40}$/.test(v) && v !== build ? v : null; }
  function check() {
    if (busy) return; busy = true;
    fetch('version.txt?t=' + Date.now(), {cache: 'no-store'}).then(function (r) { return r.ok ? r.text() : ''; }).then(function (t) {
      var v = staleOf(t); if (v && v !== shown && v !== skip) { shown = v; el.style.display = 'flex'; el.hidden = false; }
    }).catch(function () {}).then(function () { busy = false; });
  }
  el.querySelector('[data-lumina="stale-go"]').onclick = function () { location.reload(); };
  // Later hides it until a newer build still.
  el.querySelector('[data-lumina="stale-later"]').onclick = function () { skip = shown; shown = null; el.hidden = true; el.style.display = ''; };
  window.luminaStaleCheck = check;
  check(); setInterval(check, 30000);
  function back() { if (!document.hidden) check(); }
  document.addEventListener('visibilitychange', back); window.addEventListener('focus', back);
})();</script>
"""
j = page.rfind('</body>'); page = (page[:j] + stamp + page[j:]) if j >= 0 else page + stamp
# Whole or not at all: a browser reloading mid-build never reads half a page.
open(out + '.part', 'w', encoding='utf-8').write(page); os.replace(out + '.part', out)
PY
echo "$BUILD $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SITE/version.txt"
echo "$SITE  ($(cat "$SITE/version.txt"))"
