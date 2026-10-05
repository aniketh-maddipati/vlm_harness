#!/usr/bin/env python3
"""Unit tests for Scripts/sets_unbundle_standalone.py on a tiny synthetic bundle.
python3 Tests/probe/test_unbundle_standalone.py"""
import base64, gzip, io, json, os, re, sys, tempfile, unittest
from contextlib import redirect_stderr, redirect_stdout

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "Scripts"))
import sets_unbundle_standalone as su

THUMB = ('<template id="__bundler_thumbnail"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
         '<rect width="100" height="100" fill="#1E1D1B"/></svg></template>')

# A Sets page with one of each construct the bundler rewrites.
SOURCE = (
    '<!DOCTYPE html>\n<html>\n<head>\n<meta charset="utf-8">\n'
    '<script src="./support.js"></script>\n<script src="./lumina-core-v4.js"></script>\n'
    '</head>\n<body>\n' + THUMB + '\n<x-dc>\n'
    '<div tabIndex="0" aria-label="Fish &amp; chips" title="a &amp; b">Fish & chips · Tom & Jerry</div>\n'
    '<img src="a.png"></img>\n<img src="b.png">\n'
    '<dc-import name="Lumina Edit v99" hint-size="100%,100%"></dc-import>\n'
    '<div spellCheck="false">end</div>\n'
    '</x-dc>\n<script type="text/x-dc" data-dc-script>class Component { a(){ return 1 && 2; } }\n'
    '</script>\n</body>\n</html>\n'
)

CORE = b"// Lumina core v4\nconsole.log(1)\n"
SUPPORT = b"// GENERATED support\nwindow.x = 1\n"
EDIT = b"<!DOCTYPE html>\n<html><body>Edit</body></html>\n"
PNG = b"\x89PNG\r\n\x1a\nnot really"


def bundle_template(src):
    """What the bundler does to the page, rule by rule (the inverse of the tool)."""
    t = src.replace('src="./support.js"', 'src="id-support"').replace('src="./lumina-core-v4.js"', 'src="id-core"')
    t = t.replace("<html>\n<head>", "<html><head>", 1)
    t = re.sub(r'\b(tabIndex|spellCheck)=', lambda m: "sc-camel-" + re.sub(r"([A-Z])", lambda c: "-" + c.group(1).lower(), m.group(1)) + "=", t)
    k = t.rfind('<script type="text/x-dc"')
    body, rest = t[:k], t[k:]
    body = re.sub(r">([^<]*)<", lambda m: ">" + m.group(1).replace("&", "&amp;").replace("&amp;amp;", "&amp;") + "<", body)
    body = body.replace("</img>", "")
    body = body.replace("<body>\n" + THUMB + "\n<x-dc>", "<body>\n\n<x-dc>", 1)
    body = body.replace("</div>\n</x-dc>\n", "</div>\n\n" + THUMB.replace("/>", "></rect>") + "\n", 1)
    rest = rest.replace("data-dc-script>", 'data-dc-script="">', 1)
    rest = rest[:rest.rfind("</script>")] + "</script></body></html>"
    return body + rest


def entry(data, compressed=True):
    return {"mime": "application/octet-stream", "compressed": compressed,
            "data": base64.b64encode(gzip.compress(data) if compressed else data).decode()}


def standalone(template=None, manifest=None, template_json=None):
    manifest = manifest if manifest is not None else {
        "id-core": entry(CORE), "id-support": entry(SUPPORT), "id-edit": entry(EDIT), "id-png": entry(PNG, compressed=False)}
    # As a bundler must, so the block's </script> is the block's own: "</" written "<\/" (still JSON).
    tj = template_json if template_json is not None else json.dumps(template if template is not None else bundle_template(SOURCE)).replace("</", "<\\/")
    return ('<!DOCTYPE html><html><head></head><body>\n'
            '<script type="__bundler/manifest">' + json.dumps(manifest) + '</script>\n'
            '<script type="__bundler/ext_resources">[]</script>\n'
            '<script type="__bundler/template">' + tj + '</script>\n</body></html>\n')


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        try:
            code = su.main(list(argv))
        except SystemExit as e:
            code = e.code
    return code, out.getvalue(), err.getvalue()


class Reversal(unittest.TestCase):
    def setUp(self):
        self.page, self.files, self.counts, self.assumed, self.notes = su.unbundle(standalone(), like=SOURCE)

    def test_the_synthetic_bundle_is_reversed_byte_for_byte(self):
        self.assertEqual(self.page, SOURCE)
        self.assertEqual(self.assumed, [])

    def test_every_rule_fired(self):
        self.assertEqual(self.counts, {"script src": 2, "html newline": 1, "camelCase attribute": 2, "thumbnail line": 1,
                                       "x-dc blank line": 1, "data-dc-script": 1, "&amp; in text": 2, "<img> closer": 1,
                                       "last lines": 1})

    def test_attribute_values_keep_their_entities(self):
        self.assertIn('aria-label="Fish &amp; chips" title="a &amp; b"', self.page)
        self.assertIn(">Fish & chips · Tom & Jerry<", self.page)

    def test_resources_are_the_original_bytes_under_their_names(self):
        got = {n: (how, d) for n, how, d in self.files.values()}
        self.assertEqual(got["lumina-core-v4.js"], ("--like", CORE))
        self.assertEqual(got["support.js"], ("--like", SUPPORT))
        self.assertEqual(got["Lumina Edit v99.dc.html"], ("dc-import", EDIT))

    def test_an_unknown_resource_is_written_as_resource_id_not_dropped(self):
        got = {n: (how, d) for n, how, d in self.files.values()}
        self.assertEqual(got["resource-id-png"], ("unknown", PNG))

    def test_without_like_the_lossy_rules_are_assumed_and_names_come_from_first_bytes(self):
        page, files, counts, assumed, _ = su.unbundle(standalone())
        self.assertEqual(sorted(assumed), ["<img> closer", "thumbnail line"])
        self.assertEqual(counts["<img> closer"], 0)
        self.assertIn('<img src="a.png">\n', page)
        self.assertIn(THUMB, page, "the assumed thumbnail (self-closed rects) matches this source")
        self.assertEqual({n: how for n, how, _ in files.values()},
                         {"lumina-core-v4.js": "first bytes", "support.js": "first bytes", "Lumina Edit v99.dc.html": "dc-import",
                          "resource-id-png": "unknown"})

    def test_a_like_with_other_scripts_falls_back_to_first_bytes_with_a_note(self):
        like = SOURCE.replace('<script src="./lumina-core-v4.js"></script>\n', "")
        _, files, _, _, notes = su.unbundle(standalone(), like=like)
        self.assertIn("lumina-core-v4.js", {n for n, _, _ in files.values()})
        self.assertTrue(any("script sources" in n for n in notes), notes)

    def test_a_resource_named_with_a_path_is_never_written_as_one(self):
        man = {"../../evil": entry(b"unknown bytes"), "id-support": entry(SUPPORT)}
        _, files, _, _, _ = su.unbundle(standalone(manifest=man))
        names = {n for n, _, _ in files.values()}
        self.assertIn("resource-.._.._evil", names)
        self.assertTrue(all("/" not in n for n in names), names)


class Entries(unittest.TestCase):
    def test_an_entry_that_is_not_gzip_is_kept_as_is(self):
        man = {"id-core": entry(CORE, compressed=False), "id-support": {"compressed": True, "data": base64.b64encode(SUPPORT).decode()}}
        _, files, _, _, notes = su.unbundle(standalone(manifest=man), like=SOURCE)
        got = {n: d for n, _, d in files.values()}
        self.assertEqual(got["lumina-core-v4.js"], CORE)
        self.assertEqual(got["support.js"], SUPPORT)
        self.assertTrue(any("not gzip" in n for n in notes), notes)

    def test_a_template_that_is_not_json_is_a_clear_error_exit_2(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "s.html")
            write(p, standalone(template_json='"<html><head> unterminated'))
            code, out, err = run(p, "--out", os.path.join(d, "out"))
            self.assertEqual(code, 2)
            self.assertIn("template is not valid JSON", err)
            self.assertFalse(os.path.exists(os.path.join(d, "out")), "nothing written")

    def test_not_a_bundle_and_broken_entries_exit_2(self):
        for text in ["<html>plain page</html>", standalone(manifest={"x": {"data": "!!!"}}),
                     standalone(manifest={"x": {"compressed": True, "data": base64.b64encode(b"\x1f\x8bbroken").decode()}}),
                     standalone(template="no page script here")]:
            with self.assertRaises(su.BundleError, msg=text[:60]):
                su.unbundle(text)


class Commands(unittest.TestCase):
    def test_out_writes_every_file_with_size_and_sha256_and_rule_counts(self):
        with tempfile.TemporaryDirectory() as d:
            p, like, out = os.path.join(d, "s.html"), os.path.join(d, "Lumina Sets v9.dc.html"), os.path.join(d, "out")
            write(p, standalone())
            write(like, SOURCE)
            code, text, _ = run(p, "--out", out, "--like", like)
            self.assertEqual(code, 0, text)
            self.assertEqual(sorted(os.listdir(out)), ["Lumina Edit v99.dc.html", "Lumina Sets v9.dc.html", "lumina-core-v4.js",
                                                      "resource-id-png", "support.js"])
            self.assertEqual(read(os.path.join(out, "Lumina Sets v9.dc.html")), SOURCE)
            import hashlib
            self.assertIn(hashlib.sha256(CORE).hexdigest() + "  lumina-core-v4.js", text)
            self.assertRegex(text, r"camelCase attribute\s+2")
            self.assertIn("unknown resources (written, not dropped): resource-id-png", text)

    def test_out_without_like_says_assumed(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "s.html")
            write(p, standalone())
            code, text, _ = run(p, "--out", os.path.join(d, "out"))
            self.assertEqual(code, 0)
            self.assertRegex(text, r"<img> closer\s+0  assumed \(no --like\)")
            self.assertRegex(text, r"thumbnail line\s+1  assumed \(no --like\)")
            self.assertIn("Lumina Sets.dc.html", os.listdir(os.path.join(d, "out")))

    def test_prove_both_ways(self):
        with tempfile.TemporaryDirectory() as d:
            p, known = os.path.join(d, "s.html"), os.path.join(d, "known.html")
            write(p, standalone())
            write(known, SOURCE)
            code, text, _ = run("--prove", p, known)
            self.assertEqual(code, 0, text)
            self.assertIn("identical", text)
            write(known, SOURCE.replace("Tom & Jerry", "Tom and Jerry"))
            code, text, _ = run("--prove", p, known)
            self.assertEqual(code, 1)
            self.assertIn("differs at character %d" % SOURCE.index("& Jerry"), text)
            self.assertIn("Tom & Jerry", text)
            self.assertIn("Tom and Jerry", text)

    def test_never_writes_into_design_or_lumina(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "s.html")
            write(p, standalone())
            for target in [os.path.join(su.REPO, "design", "unbundle-test"), os.path.join(su.REPO, "Lumina", "Sets", "Web")]:
                code, _, err = run(p, "--out", target)
                self.assertEqual(code, 2, target)
                self.assertIn("inside design/ or Lumina/", err)
            self.assertFalse(os.path.exists(os.path.join(su.REPO, "design", "unbundle-test")))


if __name__ == "__main__":
    unittest.main()
