#!/usr/bin/env python3
"""Every clickable on the Skim page is a real <button>: a div or span with role="button", "tab" or "switch" (and the
time marks beside the rod) becomes <button type="button">, its closing tag too. Re-runnable, so a merge that brings
back a <div role="button"> is fixed by running it again; it changes nothing on a page that is already done.

    python3 Scripts/skim-buttons.py [--check] [page …]     default: both copies of the Skim page
"""
import os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGES = [os.path.join(ROOT, 'design', 'handoff', 'lumina-skim', 'Lumina Skim v3.dc.html'),
         os.path.join(ROOT, 'Lumina', 'Sets', 'Web', 'Lumina Skim v3.dc.html')]
TAG = re.compile(r'<(/?)([a-zA-Z][\w-]*)((?:[^>"\']|"[^"]*"|\'[^\']*\')*?)(/?)>')

def wants(name, attrs):
    if name not in ('div', 'span'): return False
    m = re.search(r'\brole="(button|tab|switch)"', attrs)
    return bool(m) or 'data-lumina="time-mark"' in attrs

def convert(src):
    end, start = src.find('</x-dc>'), src.find('</helmet>')   # the template only: not the page's style or scripts
    if end < 0: raise SystemExit('no </x-dc> in the page')
    start = max(0, start)
    head, tail, out, stack, pos, n = src[start:end], src[end:], [src[:start]], [], 0, 0
    for m in TAG.finditer(head):
        close, name, attrs, selfc = m.group(1), m.group(2), m.group(3), m.group(4)
        out.append(head[pos:m.start()]); pos = m.end(); text = m.group(0)
        if name in ('div', 'span', 'button') and not selfc:
            if close:
                if not stack or stack[-1][0] != name: raise SystemExit('unbalanced </%s> at %d' % (name, m.start()))
                was, conv = stack.pop()
                if conv: text = '</button>'
            else:
                conv = wants(name, attrs)
                if conv:
                    a = re.sub(r'\s+role="button"', '', attrs); a = re.sub(r'\s+tabIndex="0"', '', a)
                    # a div or span has a content box; a button would take the browser's border box
                    if 'box-sizing' not in a: a = a.replace(' style="', ' style="box-sizing:content-box;', 1)
                    text = '<button type="button"' + a + '>'; n += 1
                stack.append((name, conv))
        out.append(text)
    out.append(head[pos:])
    if stack: raise SystemExit('unclosed tags: %r' % stack[-3:])
    return ''.join(out) + tail, n

def main(argv):
    check = '--check' in argv; pages = [a for a in argv if not a.startswith('--')] or PAGES
    bad = 0
    for p in pages:
        src = open(p, encoding='utf-8').read(); new, n = convert(src)
        if check:
            if n: print(p, n, 'clickables are not buttons'); bad = 1
            continue
        if new != src: open(p, 'w', encoding='utf-8').write(new)
        print(p, n, 'made buttons')
    return bad

if __name__ == '__main__': sys.exit(main(sys.argv[1:]))
