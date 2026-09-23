"""Small immutable private review cache, not a model decision authority.

Keys cover RAW content, pipeline, complete recipe, and explicit model revision.
Only observations and <=512 KB rendered previews are stored. This avoids re-copying
review assets; inference caching is deliberately not enabled before profiling it.
"""
import hashlib
import json
from pathlib import Path
from sony_inventory import atomic_json, private_output
from technical_review import key


class ReviewCache:
    def __init__(self, folder):
        self.folder = private_output(folder)
        self.hits = 0
        self.misses = 0

    def identity(self, raw_sha, pipeline, recipe, model_revision):
        if not raw_sha or not pipeline or not model_revision:
            raise ValueError('Complete cache provenance required')
        return key(raw_sha, pipeline, recipe, model_revision)

    def get(self, identity):
        if len(identity) != 64 or any(c not in '0123456789abcdef' for c in identity):
            raise ValueError('Invalid cache identity')
        path = self.folder / (identity + '.json')
        if not path.exists():
            self.misses += 1
            return None
        row = json.loads(path.read_text())
        pixels = (self.folder / (identity + '.jpg')).read_bytes()
        if hashlib.sha256(pixels).hexdigest() != row['preview_sha']:
            raise ValueError('Corrupt immutable cache entry')
        self.hits += 1
        return row['observation'], pixels

    def put(self, identity, observation, pixels):
        if len(pixels) > 512_000 or not pixels.startswith(b'\xff\xd8'):
            raise ValueError('Only small JPEG render candidates are cached')
        old = self.get(identity)
        if old:
            if old != (observation, pixels):
                raise ValueError('Immutable cache collision; pipeline or model revision must change')
            return
        path = self.folder / (identity + '.jpg')
        temp = path.with_suffix('.tmp')
        temp.write_bytes(pixels)
        temp.replace(path)
        atomic_json(self.folder / (identity + '.json'), dict(observation=observation,
                    preview_sha=hashlib.sha256(pixels).hexdigest()))


def cache_run(metrics_path, inventory_path, out, model_revision):
    """Cache completed rendered candidates; never recycle a timed-out inference."""
    metrics_path = Path(metrics_path)
    metrics = json.loads(metrics_path.read_text())
    rows = json.loads(Path(inventory_path).read_text())['files']
    raws = {}
    for row in rows:
        raws.setdefault(Path(row['path']).name, set()).add(row['sha256'])
    pipeline = metrics['decoder'] + ':' + metrics.get('controller', 'development')
    cache = ReviewCache(out)
    for index, frame in enumerate(metrics['frames']):
        if len(raws.get(frame['raw'], set())) != 1:
            raise ValueError('Ambiguous RAW identity')
        raw_sha = next(iter(raws[frame['raw']]))
        for arm in ('neutral', 'auto', 'policy', 'technical'):
            entry = frame['arms'].get(arm)
            if not entry:
                continue
            identity = cache.identity(raw_sha, pipeline, entry['recipe'], model_revision + ':' + arm)
            observation = {k:entry[k] for k in ('action','hypothesis','reason','rawReply') if k in entry}
            pixels = (metrics_path.parent/'images'/f'frame-{index}-{arm}.jpg').read_bytes()
            cache.put(identity, observation, pixels)
    return dict(hits=cache.hits, misses=cache.misses, purpose='private review reuse, not inference acceleration')
