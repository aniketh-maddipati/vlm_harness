#!/usr/bin/env python3
"""Find which annotated adaCG shot each source clip is (Trevor's HDRVS zips name clips SHGCNCT_…_Tnnn.MOV,
not choiceNNNNN). Frames from t = 0 and then every --step seconds are decoded with ffmpeg at the thumbnails' size;
each frame and each label thumbnail becomes a z-scored log-luminance image, and each frame is matched on its own
(best shot, its r, the next shot's r). A shot is found in a clip when some frame matches it with r >= --min-r and
a margin >= --min-margin over the next shot. Matching per frame, not on a mean: a still is often the clip's
opening frame and the camera moves after it, and one long take can hold several annotated shots.

    ~/LuminaEvidence/venv-parity/bin/python -I Tools/exposeval/match_clips.py \
        --pkl …/trainDemo8b.pkl.UNTRUSTED-do-not-unpickle --zip /Volumes/T7/Lumina/datasets/hdrvs-trevor/20240629.zip \
        --out ~/LuminaEvidence/exposeval/clip-map.json      (or --clips <folder> of extracted clips)

--zip reads each clip in place: the zips store their entries uncompressed, so nothing is extracted (extracting
on the T7's USB 2 link takes hours). ffmpeg's `subfile:` protocol fails on entries over 2 GiB, so each clip
becomes a sparse local file the entry's size holding only the bytes ffmpeg needs: the header, the `moov` index
(at the end in these files), and the packets of the frames decoded. A few MB per clip, deleted after.

ffmpeg only decodes (ProRes RAW needs FFmpeg 8's prores_raw). The decoded raw keeps the sensor's black level,
so each frame's 0.1st percentile is taken off before the log. Data only: nothing from the clips is run.
"""

import argparse
import json
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import adacg  # noqa: E402

SIZE = (102, 54)  # the label thumbnails


def feature(lin_rgb, black=0.0):
    """z-scored log luminance of a linear RGB image (H, W, 3), flattened."""
    a = np.clip(np.asarray(lin_rgb, dtype=np.float64) - black, 0.0, None)
    y = np.log(a @ np.array([0.2126, 0.7152, 0.0722]) + 1e-3)
    y = y - y.mean()
    return (y / (y.std() + 1e-9)).ravel()


def thumb_features(E):
    import run
    names = sorted(E)
    F = np.array([feature((run.decode_thumb(E[n]["thumb"]).astype(np.float64) / 255.0) ** 2.4) for n in names])
    return names, F


def match(frames, names, F):
    """frames: list of features (same size as F's rows). → [(name, mean r)] best first, per shot (2k, 2k + 1 pooled)."""
    with np.errstate(all="ignore"):  # numpy 2.0 on Accelerate flags finite matmuls; the values are checked below
        c = np.mean([F @ f / F.shape[1] for f in frames], axis=0)
    if not np.all(np.isfinite(c)):
        raise ValueError("non-finite correlation")
    best = {}
    for n, r in zip(names, c):
        s = adacg.shot_of(n)
        if s not in best or r > best[s][1]:
            best[s] = (n, float(r))
    return sorted(best.values(), key=lambda x: -x[1])


def decode_frame(path, t, size=SIZE):
    """One frame at t seconds, linear 16-bit RGB at `size`, through ffmpeg (no shell)."""
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", str(t), "-i", path, "-frames:v", "1",
           "-vf", "scale=%d:%d" % size, "-pix_fmt", "rgb48le", "-f", "rawvideo", "-"]
    raw = subprocess.run(cmd, check=True, capture_output=True, timeout=120).stdout
    a = np.frombuffer(raw, dtype="<u2").astype(np.float64) / 65535.0
    return a.reshape(size[1], size[0], 3)


def zip_sources(path):
    """(name, ffmpeg input) for each stored video entry of a zip, read from its local headers."""
    import struct
    import zipfile
    out = []
    with zipfile.ZipFile(path) as z, open(path, "rb") as f:
        for i in z.infolist():
            if not i.filename.lower().endswith((".mov", ".mp4", ".mxf")) or i.filename.rsplit("/", 1)[-1].startswith("._"):
                continue
            if i.compress_type != zipfile.ZIP_STORED:
                raise ValueError("%s is compressed; extract it instead" % i.filename)
            f.seek(i.header_offset)
            h = f.read(30)
            n, e = struct.unpack("<HH", h[26:30])
            start = i.header_offset + 30 + n + e
            out.append((i.filename, (path, start, i.file_size)))
    return out


def top_atoms(read, size):
    """[(type, offset, size)] of a QuickTime file's top-level atoms; read(offset, n) → bytes."""
    import struct
    out, pos = [], 0
    while pos + 8 <= size:
        h = read(pos, 16)
        n, typ = struct.unpack(">I4s", h[:8])
        if n == 1:
            n = struct.unpack(">Q", h[8:16])[0]
        elif n == 0:
            n = size - pos
        if n < 8:
            break
        out.append((typ.decode("latin1"), pos, n))
        pos += n
    return out


def _children(buf, start, end):
    import struct
    pos = start
    while pos + 8 <= end:
        n, typ = struct.unpack(">I4s", buf[pos:pos + 8])
        hdr = 8
        if n == 1:
            n, hdr = struct.unpack(">Q", buf[pos + 8:pos + 16])[0], 16
        elif n == 0:
            n = end - pos
        if n < hdr:
            break
        yield typ.decode("latin1"), pos + hdr, pos + n
        pos += n


def video_samples(moov):
    """[(seconds, offset, size)] of the first video track's samples, from a QuickTime `moov` atom's bytes
    (moov's own 8-byte header included). Reads stts / stsc / stsz / stco|co64 only, no demuxing."""
    import struct

    def find(s, e, *path):
        for typ, a, b in _children(moov, s, e):
            if typ == path[0]:
                return (a, b) if len(path) == 1 else find(a, b, *path[1:])
        return None

    for typ, a, b in _children(moov, 8, len(moov)):
        if typ != "trak":
            continue
        mdia = find(a, b, "mdia")
        hd = mdia and find(*mdia, "hdlr")
        if not hd or moov[hd[0] + 8:hd[0] + 12] != b"vide":
            continue
        md = find(*mdia, "mdhd")
        v = moov[md[0]]
        scale = struct.unpack(">I", moov[md[0] + (20 if v == 1 else 12):][:4])[0]
        st = find(*mdia, "minf", "stbl")
        box = {t: (x, y) for t, x, y in _children(moov, *st)}

        def ints(t, skip, fmt="I"):
            x, _ = box[t]
            n = struct.unpack(">I", moov[x + 4:x + 8])[0]
            w = struct.calcsize(fmt)
            return n, x + 8 + skip, w

        x = box["stsz"][0]
        fixed, count = struct.unpack(">II", moov[x + 4:x + 12])
        sizes = [fixed] * count if fixed else list(struct.unpack(">%dI" % count, moov[x + 12:x + 12 + 4 * count]))
        if "co64" in box:
            n, p, _ = ints("co64", 0)
            chunks = struct.unpack(">%dQ" % n, moov[p:p + 8 * n])
        else:
            n, p, _ = ints("stco", 0)
            chunks = struct.unpack(">%dI" % n, moov[p:p + 4 * n])
        n, p, _ = ints("stsc", 0)
        stsc = [struct.unpack(">III", moov[p + 12 * i:p + 12 * i + 12]) for i in range(n)]
        n, p, _ = ints("stts", 0)
        stts = [struct.unpack(">II", moov[p + 8 * i:p + 8 * i + 8]) for i in range(n)]
        times, t = [], 0
        for c, d in stts:
            for _ in range(c):
                times.append(t / scale)
                t += d
        out, k = [], 0
        for ci, off in enumerate(chunks, 1):
            per = [s for f, s, _ in stsc if f <= ci][-1]
            for _ in range(per):
                if k >= count:
                    break
                out.append((times[k] if k < len(times) else 0.0, off, sizes[k]))
                off += sizes[k]
                k += 1
        return out
    return []


class SparseClip:
    """A local sparse copy of one stored zip entry, filled on demand."""

    def __init__(self, src, workdir):
        self.zip, self.start, self.size = src
        self.zf = open(self.zip, "rb")
        self.path = os.path.join(workdir, "clip-%d.mov" % self.start)
        with open(self.path, "wb") as f:
            f.truncate(self.size)
        self.fill(0, min(self.size, 1 << 16))
        self.moov = b""
        for typ, off, n in top_atoms(self.read, self.size):
            if typ in ("moov", "ftyp", "wide", "free"):
                self.fill(off, n)
            if typ == "moov":
                self.moov = self.read(off, n)

    def read(self, off, n):
        self.zf.seek(self.start + off)
        return self.zf.read(n)

    def fill(self, off, n):
        with open(self.path, "r+b") as f:
            f.seek(off)
            f.write(self.read(off, n))

    def packets(self):
        """[(seconds, pos, size)] of the first video track, from the moov's sample table. (ffprobe's packet list
        on the sparse copy stops after one packet, so every frame asked for was the first.)"""
        return video_samples(self.moov)

    def close(self):
        self.zf.close()
        try:
            os.remove(self.path)
        except OSError:
            pass


def folder_sources(path):
    return [(f, os.path.join(path, f)) for f in sorted(os.listdir(path))
            if not f.startswith("._") and f.lower().endswith((".mov", ".mp4", ".mxf"))]


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         check=True, capture_output=True, timeout=60, text=True).stdout.strip()
    return float(out)


def found(frames, min_r=0.8, min_margin=0.15):
    """frames: [{t, still, r, next_r}] → [{shot, stills, best_r, margin, t}] for shots some frame matches clearly."""
    out = {}
    for fr in frames:
        if fr["r"] < min_r or fr["r"] - fr["next_r"] < min_margin:
            continue
        s = adacg.shot_of(fr["still"])
        o = out.setdefault(s, {"shot": s, "stills": set(), "best_r": 0.0, "margin": 0.0, "t": []})
        o["stills"].add(fr["still"])
        o["t"].append(fr["t"])
        if fr["r"] > o["best_r"]:
            o["best_r"], o["margin"] = fr["r"], round(fr["r"] - fr["next_r"], 3)
    return [dict(o, stills=sorted(o["stills"])) for o in sorted(out.values(), key=lambda o: o["t"][0])]


def frame_times(times, step):
    """Indices of `times` at 0, step, 2·step, … (the first frame at or after each)."""
    out, want = [], 0.0
    for i, t in enumerate(times):
        if t >= want - 1e-9:
            out.append(i)
            want = t + step
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--pkl", required=True)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--clips", help="a folder of clips")
    src.add_argument("--zip", help="a zip whose clips are stored uncompressed")
    ap.add_argument("--out", required=True)
    ap.add_argument("--step", type=float, default=1.0, help="seconds between frames")
    ap.add_argument("--min-r", type=float, default=0.8)
    ap.add_argument("--min-margin", type=float, default=0.15)
    a = ap.parse_args(argv)
    E = adacg.entries(adacg.load(a.pkl))
    names, F = thumb_features(E)
    out = []
    import tempfile
    work = tempfile.mkdtemp(prefix="exposeval-clips-")

    def one(fr, t):
        r = match([feature(fr, black=float(np.percentile(fr, 0.1)))], names, F)
        return {"t": round(t, 2), "still": r[0][0], "r": round(r[0][1], 3), "next_r": round(r[1][1], 3)}

    for f, p in (zip_sources(a.zip) if a.zip else folder_sources(a.clips)):
        frames = []
        if a.zip:
            sc = SparseClip(p, work)
            try:
                pk = sc.packets()
                d = pk[-1][0] if pk else 0.0
                for i in frame_times([x[0] for x in pk], a.step):
                    t, pos, size = pk[i]
                    sc.fill(pos, size)
                    frames.append(one(decode_frame(sc.path, t), t))
            finally:
                sc.close()
        else:
            d = duration(p)
            for t in np.arange(0.0, d, a.step):
                frames.append(one(decode_frame(p, float(t)), float(t)))
        shots = found(frames, a.min_r, a.min_margin)
        out.append({"clip": f, "seconds": round(d, 2), "shots": shots, "frames": frames})
        print("%-30s %5.1fs  %s" % (f, d, "  ".join("%s r %.2f (+%.2f) @%.1fs" % (
            "/".join(x[6:-4] for x in o["stills"]), o["best_r"], o["margin"], o["t"][0]) for o in shots) or "no shot"))
    try:
        os.rmdir(work)
    except OSError:
        pass
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w") as fh:
        json.dump(out, fh, indent=1)


if __name__ == "__main__":
    main()
