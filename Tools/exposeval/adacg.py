"""Read the adaCG annotation pickle (trainDemo8b.pkl) without running anything in it.

A pickle can name any Python callable and call it on load. This one, inspected with pickletools
(protocol 4, four STACK_GLOBALs), names only numpy's array reconstruction and datetime. The
unpickler below resolves exactly those four names and refuses everything else, so a changed or
hostile file fails to load instead of running code. Run it under `python3 -I`, from outside the
data folder.

The layout (Canham, Punnappurath, Brown, "Adaptive Color Grading", arXiv 2609.21169; the HF card
of trevorcanham/hdrvs_adaCGsubset; adaCG.py `newGrade`):
    {'root': str,
     '<name>.tif': {'set':  {region: [a*, b*]},          CIELAB offsets per region (colour only)
                    'reg':  {region: [pivot, falloff]},  region threshold, encoded mean(R,G,B) in [0, 1]
                    'hist': ndarray,  linear Y histogram of the full still (bins over [0, 1], scaled by its std)
                    'thumb': ndarray (uint8 JPEG bytes, the still at 5 %),
                    'labels': [str], 'time': datetime}}
"""

import io
import pickle

REGIONS = ("darkest", "dark", "light", "lightest")

# (module, name) pairs this file is allowed to resolve, and what they become.
_ALLOWED = {
    ("numpy.core.multiarray", "_reconstruct"),
    ("numpy._core.multiarray", "_reconstruct"),
    ("numpy", "ndarray"),
    ("numpy", "dtype"),
    ("datetime", "datetime"),
}


class RefusedGlobal(pickle.UnpicklingError):
    pass


class SafeUnpickler(pickle.Unpickler):
    def find_class(self, module, name):
        if (module, name) not in _ALLOWED:
            raise RefusedGlobal("refused global %s.%s" % (module, name))
        if module == "datetime":
            import datetime
            return datetime.datetime
        import numpy as np
        if name == "_reconstruct":
            try:
                from numpy._core.multiarray import _reconstruct
            except ImportError:  # numpy < 2
                from numpy.core.multiarray import _reconstruct
            return _reconstruct
        return getattr(np, name)


def loads(data):
    return SafeUnpickler(io.BytesIO(data)).load()


def load(path):
    with open(path, "rb") as f:
        return SafeUnpickler(f).load()


def entries(db):
    """name → annotation, the 'root' key left out, names sorted."""
    return {k: db[k] for k in sorted(db) if k != "root" and isinstance(db[k], dict)}


def shot_of(name):
    """Two stills per video, numbered 2k and 2k + 1: choice86400.tif and choice86401.tif → 43200.

    Checked on the labels: consecutive (even, odd) stills share their location labels on 98 % of pairs and
    their histograms are about 4× closer (median CDF distance 7.7 vs 28.9) than (odd, even) neighbours."""
    stem = name.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    return int("".join(ch for ch in stem if ch.isdigit())) // 2


def pivots(entry):
    return [float(entry["reg"][r][0]) for r in REGIONS]


def falloffs(entry):
    return [float(entry["reg"][r][1]) for r in REGIONS]
