"""parity_personal summary.json → per slider position: frames, median of frame medians, median and mean of
frame p95s, highlights-zone mean. Usage: by_position.py <summary.json> [<summary.json> …]"""
import json, re, sys
import numpy as np

for path in sys.argv[1:]:
    d = json.load(open(path)); rows = {}
    for f in d['frames']:
        look = f.get('look', '')
        m = re.findall(r'(hl|sh):([+-]?\d+)', look)
        key = ' '.join(f'{a}:{int(b):+d}' for a, b in m if int(b) != 0) or 'other'
        rows.setdefault(key, []).append(f)
    print('==', path)
    for k in sorted(rows):
        fs = rows[k]
        med = np.median([f['all']['median'] for f in fs]); p95 = [f['all']['p95'] for f in fs]
        hi = np.mean([f['highlights']['mean'] for f in fs if f.get('highlights') and f['highlights'].get('n')])
        print(f'  {k:10s} n={len(fs):3d}  median {med:.2f}  p95 median {np.median(p95):.2f} mean {np.mean(p95):.2f}  highlights mean {hi:.2f}')
