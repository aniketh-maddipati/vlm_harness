#!/usr/bin/env python3
"""Find which annotated adaCG shot each source clip is (Trevor's HDRVS zips name clips SHGCNCT_…_Tnnn.MOV,
not choiceNNNNN). A few frames per clip are decoded with ffmpeg at the thumbnails' size; each frame and each
label thumbnail becomes a z-scored log-luminance image; the clip's shot is the best mean correlation.

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


class SparseClip:
    """A local sparse copy of one stored zip entry, filled on demand."""

    def __init__(self, src, workdir):
        self.zip, self.start, self.size = src
        self.zf = open(self.zip, "rb")
        self.path = os.path.join(workdir, "clip-%d.mov" % self.start)
        with open(self.path, "wb") as f:
            f.truncate(self.size)
        self.fill(0, min(self.size, 1 << 16))
        for typ, off, n in top_atoms(self.read, self.size):
            if typ in ("moov", "ftyp", "wide", "free"):
                self.fill(off, n)

    def read(self, off, n):
        self.zf.seek(self.start + off)
        return self.zf.read(n)

    def fill(self, off, n):
        with open(self.path, "r+b") as f:
            f.seek(off)
            f.write(self.read(off, n))

    def packets(self):
        """[(pts_time, pos, size)] of the first video stream, from the index alone."""
        out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                              "packet=pts_time,pos,size", "-of", "csv=p=0", self.path],
                             check=True, capture_output=True, timeout=300, text=True).stdout
        rows = []
        for line in out.splitlines():
            t, size, pos = (line.split(",") + ["", "", ""])[:3]
            try:
                rows.append((float(t), int(pos), int(size)))
            except ValueError:
                continue
        return rows

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


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--pkl", required=True)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--clips", help="a folder of clips")
    src.add_argument("--zip", help="a zip whose clips are stored uncompressed")
    ap.add_argument("--out", required=True)
    ap.add_argument("--frames", type=int, default=3)
    a = ap.parse_args(argv)
    E = adacg.entries(adacg.load(a.pkl))
    names, F = thumb_features(E)
    out = []
    import tempfile
    work = tempfile.mkdtemp(prefix="exposeval-clips-")
    for f, p in (zip_sources(a.zip) if a.zip else folder_sources(a.clips)):
        feats = []
        if a.zip:
            sc = SparseClip(p, work)
            try:
                pk = sc.packets()
                d = pk[-1][0] if pk else 0.0
                for i in range(a.frames):
                    t, pos, size = pk[int(len(pk) * (i + 0.5) / a.frames)]
                    sc.fill(pos, size)
                    fr = decode_frame(sc.path, t)
                    feats.append(feature(fr, black=float(np.percentile(fr, 0.1))))
            finally:
                sc.close()
        else:
            d = duration(p)
            for i in range(a.frames):
                fr = decode_frame(p, d * (i + 0.5) / a.frames)
                feats.append(feature(fr, black=float(np.percentile(fr, 0.1))))
        ranked = match(feats, names, F)
        row = {"clip": f, "seconds": round(d, 2), "still": ranked[0][0], "r": round(ranked[0][1], 3),
               "runner_up": ranked[1][0], "runner_up_r": round(ranked[1][1], 3)}
        out.append(row)
        print("%-32s %-18s r %.3f   next %-18s r %.3f" % (f, row["still"], row["r"], row["runner_up"], row["runner_up_r"]))
    try:
        os.rmdir(work)
    except OSError:
        pass
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w") as fh:
        json.dump(out, fh, indent=1)


if __name__ == "__main__":
    main()
