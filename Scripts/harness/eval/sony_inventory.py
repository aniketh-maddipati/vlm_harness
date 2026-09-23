#!/usr/bin/env python3
"""Private, resumable read-only ARW inventory. No images or metadata belong in git."""
import argparse
import datetime as dt
import hashlib
import html
import json
import os
from pathlib import Path
import sqlite3
import subprocess

VERSION = 1
TAGS = ['DateTimeOriginal', 'SubSecDateTimeOriginal', 'OffsetTimeOriginal', 'Model',
        'LensModel', 'SonyRawFileType', 'Compression', 'ImageWidth', 'ImageHeight',
        'ISO', 'ExposureTime', 'FNumber', 'WhiteBalance', 'ColorTemperature',
        'WB_RGGBLevels', 'Orientation']


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def private_output(path):
    path = Path(path).resolve()
    # Refuse any git worktree, not just this checkout.
    for parent in (path, *path.parents):
        if (parent / '.git').exists():
            raise ValueError('Private data output must be outside every git worktree')
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    return path


def capture_time(meta):
    value = meta.get('DateTimeOriginal', '')
    try:
        return dt.datetime.strptime(value[:19], '%Y:%m:%d %H:%M:%S')
    except (ValueError, TypeError):
        return None


def sessions(rows, gap_seconds=7200):
    """Conservative inferred sessions; unknown dates share one quarantined group.

    Exact card copies collapse before grouping. Adjacent frames never split at a
    random frame boundary. Camera clock/timezone ambiguity requires owner review.
    """
    unique = {}
    for row in rows:
        unique.setdefault(row['sha256'], row)
    ordered = sorted(unique.values(), key=lambda r: (capture_time(r['metadata']) or dt.datetime.min, r['sha256']))
    previous = None
    group = None
    result = {}
    for row in ordered:
        when = capture_time(row['metadata'])
        if when is None:
            result[row['sha256']] = 'unknown-date'
            continue
        if previous is None or (when - previous).total_seconds() > gap_seconds:
            group = 'inferred-' + row['sha256'][:12]
        result[row['sha256']] = group
        previous = when
    return result


def inventory(root, out):
    root = Path(root).resolve(strict=True)
    out = private_output(out)
    if out == root or root in out.parents:
        raise ValueError('Output must not be inside the originals folder')
    db = sqlite3.connect(out / 'inventory.sqlite')
    db.execute('CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY, size INTEGER, mtime INTEGER, sha TEXT, metadata TEXT)')
    rows = []
    hits = 0
    for path in sorted(root.rglob('*')):
        if path.suffix.lower() != '.arw' or not path.is_file() or path.is_symlink():
            continue
        stat = path.stat()
        old = db.execute('SELECT size,mtime,sha,metadata FROM files WHERE path=?', (str(path),)).fetchone()
        if old and old[:2] == (stat.st_size, stat.st_mtime_ns):
            sha, meta = old[2], json.loads(old[3])
            hits += 1
        else:
            sha = digest(path)
            response = subprocess.run(['exiftool', '-j', '-n', *['-' + t for t in TAGS], str(path)],
                                      check=True, capture_output=True, timeout=30)
            meta = json.loads(response.stdout)[0]
            meta.pop('SourceFile', None)
            if meta.get('Error'):
                raise ValueError('Unreadable RAW: ' + str(path))
            if path.stat().st_mtime_ns != stat.st_mtime_ns or path.stat().st_size != stat.st_size:
                raise ValueError('Original changed during inventory: ' + str(path))
            db.execute('INSERT OR REPLACE INTO files VALUES(?,?,?,?,?)',
                       (str(path), stat.st_size, stat.st_mtime_ns, sha, json.dumps(meta)))
            db.commit()  # each completed file survives interruption
        rows.append(dict(path=str(path), folder=str(path.parent), size=stat.st_size,
                         mtime_ns=stat.st_mtime_ns, sha256=sha, metadata=meta))
    if not rows:
        raise ValueError('No ARW files found')
    groups = sessions(rows)
    copies = {}
    for row in rows:
        copies.setdefault(row['sha256'], []).append(row['path'])
    for row in rows:
        row['session'] = groups[row['sha256']]
        row['duplicate_paths'] = copies[row['sha256']]
        row['lighting'] = 'unreviewed'
    manifest = dict(version=VERSION, root=str(root), files=rows, cache_hits=hits,
                    unique_files=len(copies), inferred_sessions=len(set(groups.values())),
                    confirmed_shoots=None, confirmed_lighting_conditions=None,
                    caveat='Time grouping is inferred; contact sheets require owner confirmation. Unknown dates are quarantined.')
    atomic_json(out / 'inventory.json', manifest)
    db.close()
    return manifest


def atomic_json(path, data):
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(data, indent=2, allow_nan=False) + '\n')
    temp.replace(path)


def contacts(manifest, out):
    out = private_output(out)
    from PIL import Image, ImageOps
    import io
    cards = {}
    seen = set()
    visual = {}
    representatives = {}
    preview_version = out / 'preview-version.txt'
    regenerate = not preview_version.exists() or preview_version.read_text() != 'oriented-v2'

    for row in manifest['files']:
        sha = row['sha256']
        if sha in seen:
            continue
        seen.add(sha)
        preview = out / (sha + '.jpg')
        if regenerate or not preview.exists():
            result = subprocess.run(['exiftool', '-b', '-PreviewImage', row['path']],
                                    check=True, capture_output=True, timeout=30)
            if not result.stdout:
                continue
            image = Image.open(io.BytesIO(result.stdout)).convert('RGB')
            # Embedded JPEGs often omit the RAW's orientation tag.
            transform = {2: Image.FLIP_LEFT_RIGHT, 3: Image.ROTATE_180,
                         4: Image.FLIP_TOP_BOTTOM, 5: Image.TRANSPOSE,
                         6: Image.ROTATE_270, 7: Image.TRANSVERSE, 8: Image.ROTATE_90}
            orientation = row['metadata'].get('Orientation', 1)
            if orientation in transform:
                image = image.transpose(transform[orientation])
            image.thumbnail((512, 512))
            image.save(preview, quality=85)
        image = Image.open(preview).convert('RGB').resize((4, 4))
        vector = [v / 255 for rgb in image.getdata() for v in rgb]
        reps = representatives.setdefault(row['session'], [])
        distances = [sum(abs(a-b) for a,b in zip(vector, rep))/len(vector) for rep in reps]
        if not distances or min(distances) > 0.16:
            reps.append(vector)
            cluster = len(reps)-1
        else:
            cluster = distances.index(min(distances))
        visual[sha] = dict(session=row['session'], visual_group=f"{row['session']}-visual-{cluster}",
                           status='inferred from coarse embedded-preview appearance, not confirmed lighting')
        meta = row['metadata']
        label = html.escape(f"{Path(row['path']).name} · ISO {meta.get('ISO')} · {meta.get('DateTimeOriginal')}")
        cards.setdefault(row['session'], []).append(f'<figure><img loading="lazy" src="{preview.name}"><figcaption>{label}</figcaption></figure>')
    body = ''.join('<h2>' + html.escape(k) + ' (inferred)</h2><section>' + ''.join(v) + '</section>' for k, v in cards.items())
    atomic_json(out / 'visual-groups.json', visual)
    preview_version.write_text('oriented-v2')
    (out / 'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Private Sony inventory</title><style>body{font:16px system-ui;background:#222;color:#eee}section{display:flex;flex-wrap:wrap}figure{width:240px;margin:8px}img{width:240px}</style><h1>Inferred sessions — confirm before splitting</h1>' + body)


def freeze_split(manifest, assignments, out):
    """Owner-confirmed shoot mapping; entire shoots and card copies stay together."""
    sessions_present = {r['session'] for r in manifest['files']}
    if set(assignments) != sessions_present or 'unknown-date' in assignments:
        raise ValueError('Assign every inferred session and resolve unknown dates first')
    shoot_splits = {}
    for a in assignments.values():
        if a['split'] not in ('development', 'heldout') or not a.get('shoot') or not a.get('lighting'):
            raise ValueError('Each session needs shoot, lighting and development/heldout split')
        prior = shoot_splits.setdefault(a['shoot'], a['split'])
        if prior != a['split']:
            raise ValueError('A shoot cannot cross evaluation splits')
    if set(shoot_splits.values()) != {'development', 'heldout'}:
        raise ValueError('Need distinct development and untouched heldout shoots')
    payload = dict(version=VERSION, assignments=assignments,
                   files=[dict(sha256=r['sha256'], session=r['session']) for r in manifest['files']])
    payload['fingerprint'] = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
    path = private_output(out) / 'frozen-split.json'
    if path.exists() and json.loads(path.read_text()) != payload:
        raise ValueError('Frozen split exists; create a new version instead of overwriting')
    atomic_json(path, payload)
    return payload


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--raw', default=os.environ.get('LUMINA_RAW_DIR'))
    p.add_argument('--out', required=True)
    p.add_argument('--contacts', action='store_true')
    p.add_argument('--assignments', type=Path)
    args = p.parse_args()
    if not args.raw:
        p.error('--raw or LUMINA_RAW_DIR required')
    data = inventory(args.raw, args.out)
    if args.contacts:
        contacts(data, Path(args.out) / 'contacts')
    if args.assignments:
        freeze_split(data, json.loads(args.assignments.read_text()), args.out)
    print(json.dumps({k:v for k,v in data.items() if k not in ('files','root')}))

if __name__ == '__main__':
    main()
