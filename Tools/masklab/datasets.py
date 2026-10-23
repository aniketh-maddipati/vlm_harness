#!/usr/bin/env python3
"""Public datasets for the mask lab: fetch, verify and record them, on the T7 only.

    python3 Tools/masklab/datasets.py list
    python3 Tools/masklab/datasets.py fetch davis2017-trainval-480p
    python3 Tools/masklab/datasets.py verify

Each set is downloaded into DATA/<name>/ (DATA = $MASKLAB_DATASETS, default
/Volumes/LuminaFactory/datasets: the APFS image kept on the T7, because exFAT stores each of
DAVIS's ~10k small files in a 128 KB block with a ._ stub beside it). The run stops when the T7 isn't
mounted. MANIFEST.json beside the sets, and a copy at /Volumes/T7/Lumina/datasets/MANIFEST.json,
records the URL, licence, size and sha256 of every archive actually fetched.

Sets whose host needs a sign-in or a Google Drive confirmation have "url": null and a "how" line:
they are fetched by hand into DATA/<name>/ and then recorded with `verify`.
"""
import argparse, hashlib, json, os, subprocess, sys, time

T7 = "/Volumes/T7/Lumina"
DATA = os.environ.get("MASKLAB_DATASETS", "/Volumes/LuminaFactory/datasets")

SETS = {
    "davis2017-trainval-480p": {
        "dir": "davis2017",
        "url": "https://data.vision.ee.ethz.ch/csergi/share/davis/DAVIS-2017-trainval-480p.zip",
        "file": "DAVIS-2017-trainval-480p.zip",
        "licence": "CC BY 4.0 (sequences owned by the DAVIS authors unless SOURCES.md says otherwise)",
        "use": "video object segmentation: 30 val sequences, every frame labelled; J&F",
        "page": "https://davischallenge.org/davis2017/code.html",
    },
    "youtube-vos-2019-valid": {
        "dir": "youtube-vos-2019", "url": None,
        "licence": "CC BY 4.0 annotations; videos under YouTube's terms",
        "use": "video object segmentation, 507 val videos, first-frame masks only (scored on the server)",
        "page": "https://youtube-vos.org/dataset/vos/",
        "how": "CodaLab sign-in, then the valid.zip Google Drive link",
    },
    "mose-valid": {
        "dir": "mose", "url": None,
        "licence": "CC BY-NC-SA 4.0",
        "use": "occlusion and crowded scenes; valid split scored on the server",
        "page": "https://henghuiding.github.io/MOSE/",
        "how": "Google Drive / OneDrive links on the page",
    },
    "lvos-val": {
        "dir": "lvos", "url": None,
        "licence": "unverified: read the page before use",
        "use": "long videos (minutes): drift and re-finding after the object leaves",
        "page": "https://lingyihongfd.github.io/lvos.github.io/",
        "how": "Google Drive links on the page",
    },
}


def need_t7():
    if not os.path.isdir(T7):
        sys.exit("datasets: the T7 isn't mounted (no /Volumes/T7/Lumina). Plug it in and run again.")
    if not os.path.isdir(DATA):
        sys.exit(f"datasets: {DATA} isn't there (attach /Volumes/T7/Lumina/factory/mac.sparsebundle).")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def manifest_path():
    return os.path.join(DATA, "MANIFEST.json")


def load():
    try:
        return json.load(open(manifest_path()))
    except FileNotFoundError:
        return {}


def save(m):
    for p in (manifest_path(), os.path.join(T7, "datasets", "MANIFEST.json")):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p + ".tmp", "w") as fh:
            json.dump(m, fh, indent=1, sort_keys=True)
        os.replace(p + ".tmp", p)


def record(m, name, path):
    s = SETS[name]
    m[name] = {k: s.get(k) for k in ("url", "licence", "use", "page")}
    m[name].update(file=os.path.relpath(path, DATA), bytes=os.path.getsize(path), sha256=sha256(path),
                   recorded=time.strftime("%Y-%m-%dT%H:%M:%S"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["list", "fetch", "verify"])
    ap.add_argument("names", nargs="*")
    a = ap.parse_args()
    if a.cmd == "list":
        m = load() if os.path.isdir(DATA) else {}
        for n, s in SETS.items():
            state = "fetched" if n in m else ("by hand: " + s["how"] if not s["url"] else "not yet")
            print(f"{n:28} {state}\n{'':28} {s['use']}")
        return
    need_t7()
    m = load()
    for n in a.names or [n for n in SETS if SETS[n]["url"]]:
        s = SETS[n]
        d = os.path.join(DATA, s["dir"])
        os.makedirs(d, exist_ok=True)
        if a.cmd == "fetch":
            if not s["url"]:
                print(f"{n}: fetch by hand ({s['how']}) into {d}, then `verify {n}`")
                continue
            path = os.path.join(d, s["file"])
            if not os.path.exists(path):
                subprocess.run(["curl", "-fL", "--retry", "3", "-o", path + ".part", s["url"]], check=True)
                os.replace(path + ".part", path)
            record(m, n, path)
        else:
            files = [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith((".zip", ".tar", ".tar.gz", ".tgz"))]
            if not files:
                print(f"{n}: no archive in {d}")
                continue
            old = m.get(n, {}).get("sha256")
            record(m, n, files[0])
            if old and old != m[n]["sha256"]:
                sys.exit(f"{n}: sha256 changed ({old} → {m[n]['sha256']})")
        print(f"{n}: {m[n]['bytes']} bytes, sha256 {m[n]['sha256']}")
    save(m)


if __name__ == "__main__":
    main()
