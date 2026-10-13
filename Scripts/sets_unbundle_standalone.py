#!/usr/bin/env python3
"""Turn a designer's single-file "standalone" export back into the page files.

    python3 Scripts/sets_unbundle_standalone.py <standalone.html> --out <folder> [--like <known Sets page>]
    python3 Scripts/sets_unbundle_standalone.py --prove <standalone.html> <known Sets page>

The standalone carries the original bytes of every resource (core script, Edit page, support.js,
data, measure) base64 + gzip in a <script type="__bundler/manifest"> block, and the Sets page as a
JSON string in <script type="__bundler/template">, rewritten by the bundler. This reverses the
rewriting (rules below, each counted), writes every file under its real name into --out, and prints
each file's size and SHA-256. `--like` is a known Sets page: it names the scripts (by the order of
their src attributes) and settles the two lossy rules (which <img> tags carry a closer, and the
thumbnail line); without it those two are reported as "assumed".

`--prove` runs the reversal with the known page as --like and exits 0 only if it reproduces that
page byte for byte; otherwise it prints the first differing position with 80 characters either side.

Writes only inside --out (never into design/ or Lumina/ of this checkout); no network; standard
library only. Exit 0: done / proven. 1: the proof differs. 2: not a bundle this tool can read.
"""
import argparse, base64, binascii, gzip, hashlib, json, os, re, sys, zlib

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROTECTED = [os.path.join(REPO, "design"), os.path.join(REPO, "Lumina")]

# How the 2026-10-05 handoff's resources begin. Used only for a resource neither --like nor the
# template names; a later handoff may begin differently (then it is written as resource-<id>).
SIGNATURES = [
    (b"// Lumina core", "lumina-core-v4.js"),
    (b"// Shared pixel", "lumina-measure.js"),
    (b"// GENERATED", "support.js"),
    (b"// Lumina v4-beta page data", "lumina-v4-data.js"),
]
SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._-]{0,200}$")
THUMB = re.compile(r'<template id="__bundler_thumbnail">.*?</template>', re.S)
TAIL = "</script>\n</body>\n</html>\n"
RULES = ["script src", "html newline", "camelCase attribute", "thumbnail line", "x-dc blank line",
         "data-dc-script", "&amp; in text", "<img> closer", "last lines"]


class BundleError(Exception):
    pass


def read_bundle(text):
    """(manifest, template, ext_resources or None) from the standalone's text."""
    def block(name, required=True):
        m = re.search(r'<script type="__bundler/%s">(.*?)</script>' % re.escape(name), text, re.S)
        if not m and required:
            raise BundleError('no <script type="__bundler/%s"> block: not a standalone export' % name)
        return m.group(1) if m else None
    try:
        manifest = json.loads(block("manifest"))
    except json.JSONDecodeError as e:
        raise BundleError("the manifest is not valid JSON (%s)" % e)
    try:
        template = json.loads(block("template"))
    except json.JSONDecodeError as e:
        raise BundleError("the template is not valid JSON (%s)" % e)
    if not isinstance(template, str):
        raise BundleError("the template is not a JSON string")
    if not isinstance(manifest, dict):
        raise BundleError("the manifest is not a JSON object")
    ext = block("ext_resources", required=False)
    try:
        ext = json.loads(ext) if ext is not None else None
    except json.JSONDecodeError:
        ext = None
    return manifest, template, ext


def decode_resources(manifest, notes):
    """id → bytes. An entry marked compressed is gunzipped; one marked compressed that is not gzip
    is kept as is and noted."""
    out = {}
    for rid, entry in manifest.items():
        if not isinstance(entry, dict) or not isinstance(entry.get("data"), str):
            raise BundleError("manifest entry %s has no data" % rid)
        try:
            raw = base64.b64decode(entry["data"], validate=True)
        except (binascii.Error, ValueError):
            raise BundleError("manifest entry %s: data is not base64" % rid)
        if entry.get("compressed"):
            if raw[:2] == b"\x1f\x8b":
                try:
                    raw = gzip.decompress(raw)
                except (OSError, EOFError, zlib.error) as e:
                    raise BundleError("manifest entry %s: broken gzip (%s)" % (rid, e))
            else:
                notes.append("%s: marked compressed but not gzip, written as is" % rid)
        out[rid] = raw
    return out


def safe_id(rid):
    return re.sub(r"[^A-Za-z0-9._-]", "_", rid)[:80] or "unnamed"


def name_resources(res, template, like, notes):
    """id → (file name, how it was named). Scripts by --like's src order, an HTML resource by the
    template's <dc-import name>, the rest by SIGNATURES, else resource-<id>."""
    named = {}
    ids = [rid for rid in re.findall(r'<script\b[^>]*\bsrc="([^"]+)"', template) if rid in res]
    if like is not None:
        known = re.findall(r'<script\b[^>]*\bsrc="\./([^"]+)"', like)
        if len(known) == len(ids):
            named.update({rid: (n, "--like") for rid, n in zip(ids, known)})
        else:
            notes.append("--like has %d script sources, the template %d: scripts named from their first bytes" % (len(known), len(ids)))
    imports = re.findall(r'<dc-import\b[^>]*\bname="([^"]+)"', template)
    pages = [rid for rid, d in res.items() if rid not in named and d.lstrip()[:9].lower() == b"<!doctype"]
    if len(imports) == 1 and len(pages) == 1:
        named[pages[0]] = (imports[0] + ".dc.html", "dc-import")
    elif pages:
        notes.append("%d HTML resources for %d <dc-import> names: not matched" % (len(pages), len(imports)))
    for rid, d in res.items():
        if rid in named:
            continue
        hit = next((n for sig, n in SIGNATURES if d.startswith(sig)), None)
        if hit:
            named[rid] = (hit, "first bytes")
    used = set()
    out = {}
    for rid in res:
        n, how = named.get(rid, (None, None))
        if n is None or not SAFE_NAME.match(n) or n in used:
            if n is not None:
                notes.append("%s: name %r unusable or taken" % (rid, n))
            n, how = "resource-" + safe_id(rid), "unknown"
        used.add(n)
        out[rid] = (n, how)
    return out


def camel(m):
    w = m.group(1).split("-")
    return w[0] + "".join(x.capitalize() for x in w[1:]) + "="


def reverse(template, names, like):
    """The Sets page from the template: (text, rule counts, assumed rules)."""
    counts = {r: 0 for r in RULES}
    assumed = []
    i = template.find("class Component")
    j = template.rfind("</script>")
    if i < 0 or j < i:
        raise BundleError("the template has no page script (class Component … </script>)")
    head, js = template[:i], template[i:j]
    if template[j:] != TAIL:
        counts["last lines"] = 1
    # Script ids back to their ./names.
    for rid, (n, _) in names.items():
        head, c = re.subn(r'src="%s"' % re.escape(rid), lambda _m, n=n: 'src="./%s"' % n, head)
        counts["script src"] += c
    if "<html><head>" in head:
        head = head.replace("<html><head>", "<html>\n<head>", 1)
        counts["html newline"] = 1
    head, counts["camelCase attribute"] = re.subn(r"sc-camel-([a-z-]+)=", camel, head)
    # The bundler moves the thumbnail line to the end of the body, in place of </x-dc>, and
    # re-serialises it: back after <body>, as --like has it, else with self-closed <rect>s (assumed).
    m = re.search(r'\n(<template id="__bundler_thumbnail">[^\n]*)(?=\n<script type="text/x-dc")', head)
    if m:
        moved = m.group(1)
        head = head[:m.start()] + "\n</x-dc>" + head[m.end():]
        head, counts["x-dc blank line"] = re.subn(r'(</div>)\n\n</x-dc>\n<script type="text/x-dc"', r'\1\n</x-dc>\n<script type="text/x-dc"', head)
        src = THUMB.search(like).group(0) if like is not None and THUMB.search(like) else None
        if src is None:
            src = moved.replace("></rect>", "/>")
            assumed.append("thumbnail line")
        if "<body>\n\n<x-dc>" in head:
            head = head.replace("<body>\n\n<x-dc>", "<body>\n" + src + "\n<x-dc>", 1)
            counts["thumbnail line"] = 1
    if 'data-dc-script=""' in head:
        head = head.replace('data-dc-script=""', "data-dc-script", 1)
        counts["data-dc-script"] = 1
    k = head.rfind('<script type="text/x-dc"')
    body, tag = (head[:k], head[k:]) if k >= 0 else (head, "")
    # Entities in attribute values stay; text nodes get their & back.
    def text(mm):
        counts["&amp; in text"] += mm.group(1).count("&amp;")
        return ">" + mm.group(1).replace("&amp;", "&") + "<"
    body = re.sub(r">([^<]*)<", text, body)
    # An <img> the source closes explicitly loses its closer in the bundle: back where --like has it.
    closed = set(re.findall(r"(<img\b[^>]*>)</img>", like)) if like is not None else set()
    if like is None and re.search(r"<img\b[^>]*>(?!</img>)", body):
        assumed.append("<img> closer")
    def img(mm):
        if mm.group(1) in closed:
            counts["<img> closer"] += 1
            return mm.group(1) + "</img>"
        return mm.group(1)
    body = re.sub(r"(<img\b[^>]*>)(?!</img>)", img, body)
    return body + tag + js + TAIL, counts, assumed


def unbundle(text, like=None):
    """(page text, {id: (name, how, bytes)}, counts, assumed, notes)."""
    notes = []
    manifest, template, _ = read_bundle(text)
    res = decode_resources(manifest, notes)
    names = name_resources(res, template, like, notes)
    page, counts, assumed = reverse(template, names, like)
    return page, {rid: (names[rid][0], names[rid][1], res[rid]) for rid in res}, counts, assumed, notes


def first_difference(a, b):
    k = next((q for q, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
    return k, a[max(0, k - 80):k + 80], b[max(0, k - 80):k + 80]


def protected(path):
    real = os.path.realpath(path)
    return any(real == p or real.startswith(p + os.sep) for p in map(os.path.realpath, PROTECTED))


def read_text(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except (OSError, UnicodeDecodeError) as e:
        raise BundleError("cannot read %s (%s)" % (path, e))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("standalone", nargs="?")
    ap.add_argument("--out")
    ap.add_argument("--like")
    ap.add_argument("--page-name", help="the Sets page's file name (default: --like's, else 'Lumina Sets.dc.html')")
    ap.add_argument("--prove", nargs=2, metavar=("STANDALONE", "KNOWN"))
    a = ap.parse_args(argv)
    try:
        if a.prove:
            known = read_text(a.prove[1])
            page = unbundle(read_text(a.prove[0]), like=known)[0]
            if page.encode("utf-8") == known.encode("utf-8"):
                print("identical: %s reproduces %s byte for byte (%d bytes)" % (a.prove[0], a.prove[1], len(known.encode("utf-8"))))
                return 0
            k, got, want = first_difference(page, known)
            print("differs at character %d of %d (reversal %d)" % (k, len(known), len(page)))
            print("  reversal: %r" % got)
            print("  known:    %r" % want)
            return 1
        if not a.standalone or not a.out:
            ap.error("give <standalone.html> --out <folder>, or --prove <standalone.html> <known>")
        if protected(a.out):
            raise BundleError("--out %s is inside design/ or Lumina/: write elsewhere, then sync" % a.out)
        like = read_text(a.like) if a.like else None
        page, files, counts, assumed, notes = unbundle(read_text(a.standalone), like=like)
        page_name = a.page_name or (os.path.basename(a.like) if a.like else "Lumina Sets.dc.html")
        if page_name in {n for n, _, _ in files.values()} or not SAFE_NAME.match(page_name):
            raise BundleError("page name %r is unusable or taken by a resource" % page_name)
        os.makedirs(a.out, exist_ok=True)
        out = [(page_name, "template", page.encode("utf-8"))] + [(n, how, d) for n, how, d in files.values()]
        for n, how, d in out:
            path = os.path.join(a.out, n)
            if os.path.dirname(os.path.realpath(path)) != os.path.realpath(a.out):
                raise BundleError("refusing to write %r outside --out" % n)
            with open(path, "wb") as f:
                f.write(d)
            print("%10d  %s  %s  (%s)" % (len(d), hashlib.sha256(d).hexdigest(), n, how))
        print("rules:")
        for r in RULES:
            print("  %-20s %d%s" % (r, counts[r], "  assumed (no --like)" if r in assumed else ""))
        for n in notes:
            print("note: " + n)
        unknown = [n for n, how, _ in files.values() if how == "unknown"]
        if unknown:
            print("unknown resources (written, not dropped): " + ", ".join(unknown))
        return 0
    except BundleError as e:
        print("error: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
