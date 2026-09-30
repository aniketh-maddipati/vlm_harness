#!/usr/bin/env python3
"""Stands in for SetsIngest.thumb in the WebKit sandbox (webkit-server.mjs): the embedded preview
resized to cover 720 × 480 once upright (never upscaled), turned for orientation 3 / 6 / 8, saved as
a 0.9 JPEG. GdkPixbuf stands in for ImageIO. One request per stdin line, JSON {f, o, l, ori}; each
answer is an 8-byte big-endian length (0 = failed) and the JPEG bytes on stdout.
"""
import json, struct, sys
import gi
gi.require_version('GdkPixbuf', '2.0')
from gi.repository import GdkPixbuf

W, H = 720, 480
out = sys.stdout.buffer


def thumb(f, o, l, ori):
    with open(f, 'rb') as fh:
        fh.seek(o)
        data = fh.read(l)
    ld = GdkPixbuf.PixbufLoader.new_with_type('jpeg')
    ld.write(data)
    ld.close()
    pb = ld.get_pixbuf()
    w, h = pb.get_width(), pb.get_height()
    uw, uh = (h, w) if ori in (6, 8) else (w, h)
    s = min(1.0, H / uh if uh > uw else max(W / uw, H / uh))
    if s < 1:
        pb = pb.scale_simple(max(1, round(w * s)), max(1, round(h * s)), GdkPixbuf.InterpType.HYPER)
    rot = {3: GdkPixbuf.PixbufRotation.UPSIDEDOWN, 6: GdkPixbuf.PixbufRotation.CLOCKWISE, 8: GdkPixbuf.PixbufRotation.COUNTERCLOCKWISE}.get(ori)
    if rot is not None:
        pb = pb.rotate_simple(rot)
    ok, buf = pb.save_to_bufferv('jpeg', ['quality'], ['90'])
    return bytes(buf) if ok else b''


for line in sys.stdin:
    try:
        q = json.loads(line)
        b = thumb(q['f'], int(q['o']), int(q['l']), int(q.get('ori', 1)))
    except Exception:
        b = b''
    out.write(struct.pack('>Q', len(b)) + b)
    out.flush()
