"""Today's tone stage (lookmath.py, rules-v1.json as shipped) applied to Lightroom's own base export."""
import json, os
import numpy as np
from scipy.ndimage import gaussian_filter
from common import HERE, W
import lookmath as lm

RULES = json.load(open(os.path.join(HERE, '../../../Lumina/Sets/Look/rules-v1.json')))


def apply_today(base, hl, sh, rules=RULES):
    c = base.astype(np.float64)
    anchor = lm.tone_anchor(c, rules)
    y = lm.luma(c, rules)
    b = gaussian_filter(y, lm.k(rules, 'tone', 'radiusFraction', 0.03) * max(c.shape[:2]), mode='nearest')
    g = lm.tone_gain(b, anchor, hl, sh, rules)
    return lm.through_curve(c * lm.tone_detail(y, b, rules)[..., None], g[..., None], lm.tone_white(rules))
