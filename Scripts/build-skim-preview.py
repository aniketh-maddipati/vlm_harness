#!/usr/bin/env python3
"""One file for Safari: the Skim page with its runtime and React inlined, in web preview mode
(window.luminaPreview: no sample cards or testing tools, says it is a preview). No network at all.

    python3 Scripts/build-skim-preview.py [out.html]     default: dist/Lumina Skim (web preview).html
"""
import base64, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'design', 'handoff', 'lumina-skim')
VENDOR = os.path.join(ROOT, 'design', 'handoff', 'vendor')
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'dist', 'Lumina Skim (web preview).html')
page = open(os.path.join(SRC, 'Lumina Skim v3.dc.html'), encoding='utf-8').read()
def js(name): return open(os.path.join(SRC, name), encoding='utf-8').read().replace('</script', '<\\/script')
for tag, name in [('<script src="./support.js"></script>', 'support.js'), ('<script src="./lumina-video-data-mvp.js"></script>', 'lumina-video-data-mvp.js')]:
    assert page.count(tag) == 1, tag
    page = page.replace(tag, '<script>\n' + js(name) + '\n</script>')
# React inline as plain scripts (Safari refuses data: script URLs from a local file); the runtime skips
# loading React when window.React and window.ReactDOM are already there.
def vjs(name): return open(os.path.join(VENDOR, name), encoding='utf-8').read().replace('</script', '<\\/script')
head = ('<script>window.luminaPreview = true;</script>\n<script>\n' + vjs('react.production.min.js') + '\n</script>\n<script>\n'
        + vjs('react-dom.production.min.js') + '\n</script>\n')
i = page.index('<script'); page = page[:i] + head + page[i:]
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, 'w', encoding='utf-8').write(page)
print(out, len(page), 'bytes')
