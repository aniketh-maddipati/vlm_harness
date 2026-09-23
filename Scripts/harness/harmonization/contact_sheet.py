"""Small local evidence sheet using the existing Sony inventory's preview method."""

import argparse
import html
import io
import json
from pathlib import Path
import subprocess

from inventory import atomic_json, stat_key


def main():
    from PIL import Image, ImageDraw, ImageOps
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    if any((parent / ".git").exists() for parent in (out, *out.parents)):
        parser.error("Keep private contact sheets outside git")
    manifest = json.loads(args.manifest.read_text())
    if any(out.is_relative_to(Path(root)) for root in manifest["roots"]):
        parser.error("Keep evidence outside originals")
    out.mkdir(parents=True, exist_ok=False)
    selected, months = [], set()
    for row in manifest["assets"]:
        month = str(row["capture"]["value"])[:7]
        if row["format"] == "ARW" and row["device_family"] == "sony_a7iii" and month not in months:
            selected.append(row)
            months.add(month)
        if len(selected) == 6:
            break
    sheet = Image.new("RGB", (1200, 720), "#17191c")
    draw = ImageDraw.Draw(sheet)
    draw.text((20, 14), "Inventory examples: camera embedded previews, not app screenshots or harmonized outputs", fill="white")
    failures = []
    for index, row in enumerate(selected):
        path = Path(row["source_path"])
        before = stat_key(path)
        result = subprocess.run(["exiftool", "-b", "-PreviewImage", str(path)], capture_output=True, timeout=30)
        if not result.stdout:
            failures.append({"asset_id": row["asset_id"], "reason": "embedded_preview_missing"})
            continue
        image = Image.open(io.BytesIO(result.stdout)).convert("RGB")
        transform = {2: Image.Transpose.FLIP_LEFT_RIGHT, 3: Image.Transpose.ROTATE_180,
                     4: Image.Transpose.FLIP_TOP_BOTTOM, 5: Image.Transpose.TRANSPOSE,
                     6: Image.Transpose.ROTATE_270, 7: Image.Transpose.TRANSVERSE, 8: Image.Transpose.ROTATE_90}
        orientation = row["image"]["orientation"]
        if orientation in transform:
            image = image.transpose(transform[orientation])
        image = ImageOps.contain(image, (380, 270))
        left, top = 10 + index % 3 * 400, 50 + index // 3 * 330
        sheet.paste(image, (left, top))
        draw.text((left, top + 276), f"{row['asset_id'][:8]} | {str(row['capture']['value'])[:10]} | ISO {row['camera']['iso']}", fill="white")
        draw.text((left, top + 294), "Scene / lighting / consent: unreviewed", fill="#aab1bc")
        if before != stat_key(path):
            raise RuntimeError("Source changed during preview read")
    sheet.save(out / "inventory-examples.jpg", quality=90)
    failures.extend({"asset_id": row["asset_id"], "path": row["source_path"], "reason": row["metadata_error"]}
                    for row in manifest["assets"] if row["metadata_error"])
    failures.extend(manifest.get("discovery_errors", []))
    atomic_json(out / "failures.json", failures)
    cards = "".join("<article><pre>" + html.escape(json.dumps(item, indent=2)) + "</pre></article>" for item in failures)
    (out / "failures.html").write_text("<!doctype html><meta charset='utf-8'><title>Inventory failures</title>"
        "<style>body{background:#17191c;color:#eee;font:16px system-ui;margin:32px}article{padding:12px;border:1px solid #666;margin:12px 0}pre{white-space:pre-wrap}</style>"
        "<h1>Failure gallery — metadata and access cases</h1><p>These failures have no valid photo rendering. No replacement image is fabricated. "
        "Phone decode, color and harmonization failure images remain unmeasured.</p>" + cards)
    atomic_json(out / "selection.json", {"asset_ids": [row["asset_id"] for row in selected],
                "method": "first Sony ARW from six capture months; illustrative, not a benchmark", "preview_failures": failures})


if __name__ == "__main__":
    main()
