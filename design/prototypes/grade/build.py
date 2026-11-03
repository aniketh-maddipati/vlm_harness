"""Inline local sample photos into the Grade prototype as data URIs (samples.js beside the page).

The photos stay outside the repo (default ~/LuminaEvidence/prototypes/grade/samples); the built page is
written next to them, never into the repo. Data URIs keep WebGL happy on file:// (no tainted images).

    python3 design/prototypes/grade/build.py [samples_dir] [out.html]
"""
import base64, json, os, sys

here = os.path.dirname(os.path.abspath(__file__))
samples = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/LuminaEvidence/prototypes/grade/samples")
out = os.path.expanduser(sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(samples), "grade.html"))
items = []
for name in sorted(os.listdir(samples)):
    if name.lower().endswith((".jpg", ".jpeg", ".png")):
        with open(os.path.join(samples, name), "rb") as f:
            mime = "image/png" if name.lower().endswith(".png") else "image/jpeg"
            items.append({"name": os.path.splitext(name)[0], "src": f"data:{mime};base64," + base64.b64encode(f.read()).decode()})
page = open(os.path.join(here, "index.html"), encoding="utf-8").read()
with open(out, "w", encoding="utf-8") as f:
    f.write(page)
with open(os.path.join(os.path.dirname(out), "samples.js"), "w", encoding="utf-8") as f:
    f.write("window.LUMINA_SAMPLES = " + json.dumps(items) + ";\n")
print(out, len(items), "photos")
