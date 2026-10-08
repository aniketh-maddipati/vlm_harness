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
def du(name): return 'data:text/javascript;base64,' + base64.b64encode(open(os.path.join(VENDOR, name), 'rb').read()).decode()
for tag, name in [('<script src="./support.js"></script>', 'support.js'), ('<script src="./lumina-video-data-mvp.js"></script>', 'lumina-video-data-mvp.js')]:
    assert page.count(tag) == 1, tag
    page = page.replace(tag, '<script>\n' + js(name) + '\n</script>')
head = ('<script>window.luminaPreview = true; window.__resources = Object.assign(window.__resources || {}, {'
        '"https://unpkg.com/react@18.3.1/umd/react.production.min.js": "' + du('react.production.min.js') + '", '
        '"https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js": "' + du('react-dom.production.min.js') + '"});</script>\n')
i = page.index('<script'); page = page[:i] + head + page[i:]
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, 'w', encoding='utf-8').write(page)
print(out, len(page), 'bytes')
