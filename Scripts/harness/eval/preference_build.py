#!/usr/bin/env python3
"""A01 preference study — RUN 2 presentation builder (AGENT 2 "collect").

Reads AGENT 1's run-2 manifest and emits a blind, fully side-balanced presentation set plus the
local judging page that records responses.

RUN 2 differs from run 1 in three ways that matter to this file:

  A3.2  FULL SIDE-BALANCING REPLACES THE 20% REPEAT SET. Every base pair is built once and shown
        TWICE — once with each arm on the left. There is NO separate repeat set; adding one on top
        would double-count, because every pair is already its own side-flipped duplicate.
  A3.8  57 frames (10/7/10/10/10/10); event 1's fresh pool was exhausted by run 1.
        47 frames x 3 pairs + 10 frames x 6 pairs = 201 base pairs = 402 showings.
        402 exceeds A01-STEP2-COLLECT.md §3's ~400 ceiling by 2. That ceiling was written for
        run 1's design and is superseded by A3.2; pairs are NOT sampled away to get under it.
  A3.9  THE MANIFEST SCHEMA CHANGED. Run 1's manifest.json is a flat JSON LIST of render rows;
        run 2's is a JSON OBJECT whose `renders` key holds the 181 rows. This module loads
        manifest["renders"] explicitly and asserts the row count before building anything.

Blindness (A01-STEP2-COLLECT.md §2): nothing the evaluator sees may reveal an arm — not a
filename, DOM node, tooltip, CSS class, source comment, tab title, or element ordering. Images
load by the render id AGENT 1 assigned, which is arm-opaque because the render agent shuffled slot
numbers per frame; this module verifies that no slot maps to a single arm and refuses to build if
one does. The id -> arm mapping lives only in answer-key.json, which the page never reads and the
server never serves.

Usage:
    python3 preference_build.py                       # writes into the run-2 evidence directory
    python3 preference_build.py --out DIR --seed N
    python3 preference_build.py --check-only          # re-run the verifications, write nothing
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import os
import random
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone

# ---------------------------------------------------------------------------------------------
# constants fixed by the contract

EVIDENCE = os.path.expanduser("~/LuminaEvidence/a01-preference-run2")
RUN1_EVIDENCE = os.path.expanduser("~/LuminaEvidence/a01-preference")

DEFAULT_SEED = 2026092502          # run 2. Run 1 used 20260925; a distinct seed, recorded here.
DEFAULT_PORT = 8741               # run 1 used 8731. A3/Delta 3 requires a different port.

EXPECTED_RENDERS = 181
EXPECTED_FRAMES = 57
EXPECTED_BASE_PAIRS = 201
EXPECTED_SHOWINGS = 402
EXPECTED_PER_EVENT_FRAMES = {0: 10, 1: 7, 2: 10, 3: 10, 4: 10, 5: 10}

# Canonical arm order. Used only to name a comparison and a pair_key deterministically; it never
# reaches the evaluator.
ARM_ORDER = ("asShot", "auto", "hand", "oracle")

MIN_INTERVENING = 10              # at least 10 OTHER showings between a pair's two showings
CONFOUNDED_ARM = "oracle"         # A2.5: the only arm whose white balance and tint move


# ---------------------------------------------------------------------------------------------
# manifest


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_manifest(path: str) -> dict:
    """Load run 2's manifest OBJECT. A3.9: never iterate the top level."""
    with open(path) as fh:
        raw = json.load(fh)
    if isinstance(raw, list):
        raise SystemExit(
            "manifest at %s is a flat LIST — that is run 1's schema (A3.9). This builder targets "
            "run 2's OBJECT schema. Refusing to guess." % path
        )
    if not isinstance(raw, dict):
        raise SystemExit("manifest at %s is neither list nor object" % path)
    for key in ("renders", "frames"):
        if key not in raw:
            raise SystemExit("manifest is missing required run-2 key %r (A3.9)" % key)
    renders = raw["renders"]
    frames = raw["frames"]
    if not isinstance(renders, list) or not isinstance(frames, list):
        raise SystemExit("manifest renders/frames are not lists")
    # A3.9: verify the row count you actually loaded before building anything from it.
    if len(renders) != EXPECTED_RENDERS:
        raise SystemExit(
            "loaded %d render rows, expected %d (A3.9 verification failed)"
            % (len(renders), EXPECTED_RENDERS)
        )
    if len(frames) != EXPECTED_FRAMES:
        raise SystemExit(
            "loaded %d frame rows, expected %d (A3.8)" % (len(frames), EXPECTED_FRAMES)
        )
    return raw


def check_frames(manifest: dict, out_dir: str) -> dict:
    """Structural checks on the frame set. Returns facts for the build log."""
    frames = manifest["frames"]
    renders = manifest["renders"]

    per_event = Counter(f["event"] for f in frames)
    if dict(per_event) != EXPECTED_PER_EVENT_FRAMES:
        raise SystemExit(
            "per-event frame counts %s do not match A3.8's 10/7/10/10/10/10"
            % dict(sorted(per_event.items()))
        )

    # every render row must have a PNG on disk, and every frame must have exactly its arms rendered
    by_frame = defaultdict(dict)
    for row in renders:
        arm = row["arm"]
        fid = row["frame_id"]
        if arm in by_frame[fid]:
            raise SystemExit("frame %s has two renders for arm %s" % (fid, arm))
        png = os.path.join(out_dir, row["png"])
        if not os.path.isfile(png):
            raise SystemExit("render PNG missing on disk: %s" % png)
        by_frame[fid][arm] = row

    for f in frames:
        have = set(by_frame[f["frame_id"]])
        want = set(f["arms"])
        if have != want:
            raise SystemExit(
                "frame %s declares arms %s but %s were rendered"
                % (f["frame_id"], sorted(want), sorted(have))
            )

    # BLINDNESS PRECONDITION: the render id embeds a slot number, and the evaluator sees it in the
    # image URL. It is only arm-opaque if slot assignment was shuffled per frame. Verify that no
    # slot number maps to exactly one arm.
    slot_arms = defaultdict(Counter)
    for row in renders:
        slot_arms[row["slot"]][row["arm"]] += 1
    leaking = sorted(s for s, c in slot_arms.items() if len(c) == 1)
    if leaking:
        raise SystemExit(
            "slot(s) %s map to a single arm — the render filename would leak the arm. STOP."
            % leaking
        )

    return {
        "frames_loaded": len(frames),
        "renders_loaded": len(renders),
        "frames_per_event": {str(k): v for k, v in sorted(per_event.items())},
        "arms_per_frame_histogram": {
            str(k): v for k, v in sorted(Counter(len(v) for v in by_frame.values()).items())
        },
        "render_pngs_present": len(renders),
        "slot_arm_distribution": {
            str(slot): dict(sorted(c.items())) for slot, c in sorted(slot_arms.items())
        },
        "slots_mapping_to_a_single_arm": leaking,
    }, by_frame


# ---------------------------------------------------------------------------------------------
# base pairs


def arm_rank(arm: str) -> int:
    return ARM_ORDER.index(arm)


def build_base_pairs(manifest: dict, by_frame: dict) -> list:
    """One base pair per unordered arm combination per frame (A3.2). Built ONCE."""
    pairs = []
    for f in sorted(manifest["frames"], key=lambda r: r["frame_id"]):
        fid = f["frame_id"]
        arms = sorted(f["arms"], key=arm_rank)
        for a, b in itertools.combinations(arms, 2):
            pairs.append(
                {
                    "pair_key": "%s:%s_vs_%s" % (fid, a, b),
                    "frame_id": fid,
                    "event": f["event"],
                    "comparison": "%s_vs_%s" % (a, b),
                    "arm_a": a,
                    "arm_b": b,
                    "render_a": by_frame[fid][a]["render_id"],
                    "render_b": by_frame[fid][b]["render_id"],
                    "confounded": CONFOUNDED_ARM in (a, b),
                }
            )
    if len({p["pair_key"] for p in pairs}) != len(pairs):
        raise SystemExit("pair_key is not unique")
    return pairs


def expected_pair_arithmetic(manifest: dict) -> dict:
    """The 201/402 arithmetic, recomputed from the manifest rather than trusted from A3.8."""
    per_count = Counter(len(f["arms"]) for f in manifest["frames"])
    terms = []
    total = 0
    for n_arms, n_frames in sorted(per_count.items()):
        n_pairs = n_arms * (n_arms - 1) // 2
        terms.append(
            {
                "frames": n_frames,
                "arms_per_frame": n_arms,
                "pairs_per_frame": n_pairs,
                "base_pairs": n_frames * n_pairs,
            }
        )
        total += n_frames * n_pairs
    return {
        "terms": terms,
        "expression": " + ".join(
            "%d frames x %d pairs" % (t["frames"], t["pairs_per_frame"]) for t in terms
        ),
        "base_pairs": total,
        "showings": total * 2,
    }


# ---------------------------------------------------------------------------------------------
# sequence: 402 showings, every pair twice, >= 10 other showings between the two


def build_sequence(n_pairs: int, rng: random.Random, attempts: int = 400):
    """Return [(pair_index, showing_rank)] of length 2*n_pairs honouring MIN_INTERVENING.

    Every position must hold a showing (total showings == total positions), so a pair's first
    showing may not be placed later than total - 1 - (MIN_INTERVENING + 1): it would have no legal
    slot for its second. Candidates are weighted by pending showings (an unstarted pair owes two,
    a started one owes one) so the backlog drains at the right rate. Randomised, with retries.
    """
    total = 2 * n_pairs
    latest_start = total - 1 - (MIN_INTERVENING + 1)
    for attempt in range(1, attempts + 1):
        unstarted = list(range(n_pairs))
        rng.shuffle(unstarted)
        unstarted = set(unstarted)
        first_pos = {}
        pending = []               # started, awaiting the second showing
        seq = []
        ok = True
        for pos in range(total):
            eligible = [p for p in pending if pos - first_pos[p] > MIN_INTERVENING]
            startable = sorted(unstarted) if pos <= latest_start else []
            if not eligible and not startable:
                ok = False
                break
            w_start = 2 * len(startable)
            w_second = len(eligible)
            if rng.random() * (w_start + w_second) < w_start:
                p = rng.choice(startable)
                unstarted.discard(p)
                first_pos[p] = pos
                pending.append(p)
                seq.append((p, 0))
            else:
                p = rng.choice(eligible)
                pending.remove(p)
                seq.append((p, 1))
        if ok and not unstarted and not pending:
            return seq, attempt
    raise SystemExit(
        "could not build a %d-showing sequence with >= %d intervening showings in %d attempts"
        % (total, MIN_INTERVENING, attempts)
    )


def measure_separation(seq: list) -> dict:
    pos = defaultdict(list)
    for i, (p, _rank) in enumerate(seq):
        pos[p].append(i)
    intervening = []
    for p, ps in pos.items():
        if len(ps) != 2:
            raise SystemExit("pair index %d appears %d times, expected 2" % (p, len(ps)))
        intervening.append(ps[1] - ps[0] - 1)
    return {
        "min_intervening_showings_required": MIN_INTERVENING,
        "min_intervening_showings_observed": min(intervening),
        "median_intervening_showings": sorted(intervening)[len(intervening) // 2],
        "max_intervening_showings": max(intervening),
        "min_index_distance_observed": min(intervening) + 1,
        "pairs_below_requirement": sum(1 for v in intervening if v < MIN_INTERVENING),
    }


# ---------------------------------------------------------------------------------------------
# showings


def build_showings(base_pairs: list, seq: list, rng: random.Random) -> list:
    """Attach an orientation to each showing. order_index 0 = arm_a left; 1 = arm_b left.

    Which orientation is shown FIRST in time is randomised per pair, so order_index is not
    confounded with temporal position.
    """
    first_orientation = {i: rng.randrange(2) for i in range(len(base_pairs))}
    rows = []
    for idx, (p, rank) in enumerate(seq):
        pair = base_pairs[p]
        orientation = first_orientation[p] if rank == 0 else 1 - first_orientation[p]
        if orientation == 0:
            left_arm, right_arm = pair["arm_a"], pair["arm_b"]
            left_render, right_render = pair["render_a"], pair["render_b"]
        else:
            left_arm, right_arm = pair["arm_b"], pair["arm_a"]
            left_render, right_render = pair["render_b"], pair["render_a"]
        rows.append(
            {
                "pair_id": "p%04d" % (idx + 1),
                "sequence_index": idx,
                "pair_key": pair["pair_key"],
                "order_index": orientation,
                "showing_rank": rank,
                "frame_id": pair["frame_id"],
                "event": pair["event"],
                "comparison": pair["comparison"],
                "left_arm": left_arm,
                "right_arm": right_arm,
                "left_render": left_render,
                "right_render": right_render,
                "confounded": pair["confounded"],
            }
        )
    return rows


def verify_showings(showings: list, base_pairs: list) -> dict:
    by_key = defaultdict(list)
    for s in showings:
        by_key[s["pair_key"]].append(s)
    if len(by_key) != len(base_pairs):
        raise SystemExit("showings cover %d pair_keys, expected %d" % (len(by_key), len(base_pairs)))
    for key, rows in by_key.items():
        if len(rows) != 2:
            raise SystemExit("pair_key %s has %d showings, expected 2" % (key, len(rows)))
        a, b = rows
        if {a["order_index"], b["order_index"]} != {0, 1}:
            raise SystemExit("pair_key %s does not carry both order_index values" % key)
        if a["left_arm"] != b["right_arm"] or a["right_arm"] != b["left_arm"]:
            raise SystemExit("pair_key %s is not side-flipped between its two showings" % key)
        if a["left_render"] != b["right_render"] or a["right_render"] != b["left_render"]:
            raise SystemExit("pair_key %s renders are not side-flipped" % key)

    left_arms = Counter(s["left_arm"] for s in showings)
    right_arms = Counter(s["right_arm"] for s in showings)
    if left_arms != right_arms:
        raise SystemExit("side balance broken: left %s right %s" % (dict(left_arms), dict(right_arms)))

    # which orientation came first in time should be roughly even, and must not be constant
    first_orient = Counter(s["order_index"] for s in showings if s["showing_rank"] == 0)
    if len(first_orient) != 2:
        raise SystemExit("the first-shown orientation is constant across pairs")

    return {
        "showings": len(showings),
        "base_pairs_covered": len(by_key),
        "every_pair_shown_twice": True,
        "every_pair_side_flipped": True,
        "left_arm_counts": dict(sorted(left_arms.items())),
        "right_arm_counts": dict(sorted(right_arms.items())),
        "side_balance_exact": True,
        "first_shown_orientation_counts": {str(k): v for k, v in sorted(first_orient.items())},
    }


# ---------------------------------------------------------------------------------------------
# emitted page + writer
#
# judge.html and serve_judge.py are generated from here so the whole instrument is reproducible
# from this one owned file. Neither contains an arm name; both are scanned for one before writing.

JUDGE_HTML = r"""<!DOCTYPE html>
<meta charset="utf-8">
<title>Image Comparison</title>
<style>
  :root { --bg:#111; --fg:#eee; --dim:#888; --line:#333; --btn:#222; --btnh:#2e2e2e; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.4 -apple-system,
         BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif; }
  #bar { display:flex; align-items:center; gap:16px; padding:8px 14px;
         border-bottom:1px solid var(--line); font-variant-numeric:tabular-nums; }
  #bar .sp { flex:1; }
  #who { color:var(--dim); }
  #stage { display:flex; gap:10px; padding:10px; height:calc(100vh - 160px); }
  .cell { flex:1; display:flex; flex-direction:column; align-items:center; min-width:0; }
  .cell img { max-width:100%; max-height:100%; object-fit:contain; background:#000; }
  .tag { color:var(--dim); font-size:12px; letter-spacing:.14em; padding-top:6px; }
  #answers { display:grid; grid-template-columns:1fr 1fr 1fr 1fr; gap:10px; padding:0 10px 14px; }
  #answers button { padding:14px 8px; background:var(--btn); color:var(--fg);
                    border:1px solid var(--line); border-radius:8px; font-size:15px;
                    cursor:pointer; }
  #answers button:hover { background:var(--btnh); }
  #answers button:disabled { opacity:.4; cursor:default; }
  #answers .k { display:block; color:var(--dim); font-size:11px; margin-top:5px; }
  #panel { padding:40px; width:min(660px, 100%); margin-left:8vw; }
  #panel h1 { font-size:19px; font-weight:600; }
  #panel select, #panel button { font-size:15px; padding:8px 12px; margin-top:12px; }
  .warn { color:#e0a030; }
  .hide { display:none !important; }
</style>

<div id="panel">
  <h1>Image comparison</h1>
  <p id="intro">You will see two versions of the same photograph, side by side. Pick the one you
     would rather keep. If they are equally good, say so. If neither is acceptable, say that
     instead &mdash; those are different answers.</p>
  <p>Evaluator:
     <select id="evaluator">
       <option value="photographer">photographer</option>
       <option value="claude">claude</option>
     </select>
  </p>
  <p><button id="start">Begin</button></p>
  <p id="resume" class="hide"></p>
  <p id="err" class="warn"></p>
</div>

<div id="app" class="hide">
  <div id="bar">
    <span id="progress"></span><span class="sp"></span><span id="who"></span>
  </div>
  <div id="stage">
    <div class="cell"><img id="imgL" alt=""><span class="tag">LEFT</span></div>
    <div class="cell"><img id="imgR" alt=""><span class="tag">RIGHT</span></div>
  </div>
  <div id="answers">
    <button id="bL">LEFT is better<span class="k">1</span></button>
    <button id="bR">RIGHT is better<span class="k">2</span></button>
    <button id="bT">They are equally good<span class="k">3</span></button>
    <button id="bN">Neither is acceptable<span class="k">4</span></button>
  </div>
</div>

<div id="done" class="hide">
  <div style="padding:40px"><h1>All responses recorded.</h1>
  <p id="doneline"></p></div>
</div>

<script>
// Button order is fixed in the markup above and is never reordered at runtime.
var ORDER = ["bL", "bR", "bT", "bN"];
var CODE  = { bL: "LEFT", bR: "RIGHT", bT: "TIE", bN: "NEITHER" };

var pairs = [], answered = {}, i = 0, shownAt = 0, busy = false, evaluator = null;
var $ = function (id) { return document.getElementById(id); };

function fail(m) { $("err").textContent = m; }

function preload(n) {
  for (var k = i; k < Math.min(i + n, pairs.length); k++) {
    var a = new Image(); a.src = "renders/" + pairs[k].left_png;
    var b = new Image(); b.src = "renders/" + pairs[k].right_png;
  }
}

function show() {
  if (i >= pairs.length) {
    $("app").className = "hide"; $("done").className = "";
    $("doneline").textContent = pairs.length + " of " + pairs.length + " complete.";
    return;
  }
  var p = pairs[i];
  $("imgL").src = "renders/" + p.left_png;
  $("imgR").src = "renders/" + p.right_png;
  $("progress").textContent = (i + 1) + " of " + pairs.length;
  busy = false;
  ORDER.forEach(function (id) { $(id).disabled = false; });
  shownAt = performance.now();
  preload(3);
}

function answer(code) {
  if (busy || i >= pairs.length) { return; }
  busy = true;
  ORDER.forEach(function (id) { $(id).disabled = true; });
  var p = pairs[i];
  var rec = {
    evaluator: evaluator,
    pair_id: p.pair_id,
    sequence_index: p.sequence_index,
    response: code,
    elapsed_ms: Math.round(performance.now() - shownAt),
    answered_at: new Date().toISOString()
  };
  fetch("response", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(rec)
  }).then(function (r) {
    if (!r.ok) { throw new Error("writer returned " + r.status); }
    answered[p.pair_id] = code; i += 1; show();
  }).catch(function (e) {
    busy = false;
    ORDER.forEach(function (id) { $(id).disabled = false; });
    alert("Not saved: " + e.message + "\nYour answer was NOT recorded. Fix the writer and retry.");
  });
}

ORDER.forEach(function (id) {
  $(id).addEventListener("click", function () { answer(CODE[id]); });
});
document.addEventListener("keydown", function (e) {
  var map = { "1": "bL", "2": "bR", "3": "bT", "4": "bN" };
  if (map[e.key]) { answer(CODE[map[e.key]]); }
});

function begin() {
  evaluator = $("evaluator").value;
  $("err").textContent = "";
  Promise.all([
    fetch("presentation.json").then(function (r) { return r.json(); }),
    fetch("answered/" + evaluator).then(function (r) { return r.json(); })
  ]).then(function (res) {
    pairs = res[0];
    var seen = {};
    res[1].forEach(function (id) { seen[id] = true; });
    answered = seen;
    i = 0;
    while (i < pairs.length && seen[pairs[i].pair_id]) { i += 1; }
    $("panel").className = "hide"; $("app").className = "";
    $("who").textContent = evaluator;
    show();
  }).catch(function (e) {
    fail("Could not load. Open this page through the local writer, not as a file. (" +
         e.message + ")");
  });
}
$("start").addEventListener("click", begin);

var q = new URLSearchParams(location.search).get("evaluator");
if (q === "photographer" || q === "claude") { $("evaluator").value = q; }
fetch("presentation.json").then(function (r) { return r.json(); }).then(function (d) {
  $("resume").className = "";
  $("resume").textContent = d.length + " comparisons. You may quit at any time; reopening " +
                            "this page continues where you stopped.";
}).catch(function () {
  fail("This page needs the local writer. Start it, then open the address it prints.");
});
</script>
"""


SERVE_JUDGE_PY = r'''#!/usr/bin/env python3
"""Loopback-only response writer for the A01 RUN 2 judging page.

Serves judge.html, presentation.json and renders/*.png from this directory on 127.0.0.1 and
appends one JSON line per response to responses-<evaluator>.jsonl, fsync-ing each line.

Why a server at all: a file:// page cannot append to a path on disk, and A01-PREFERENCE.md §6
requires each response to reach disk as it is given so a quit-and-resume loses nothing.
"No network" means no OUTBOUND request: this makes none, and judge.html references no external
resource -- no CDN, no font, no analytics. Binding to loopback is not a network dependency.

Deliberately restrictive: GET is a whitelist. answer-key.json, manifest.json, build-log.json,
presentation-blind.json and every responses file are NOT reachable, and there is no directory
listing, so the evaluator cannot de-blind themselves by typing a URL.

    python3 serve_judge.py            # then open the printed http://127.0.0.1:PORT/ address
    python3 serve_judge.py --port 9000
"""

from __future__ import annotations

import argparse
import json
import os
import re
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
EVALUATORS = ("photographer", "claude")
RESPONSES = ("LEFT", "RIGHT", "TIE", "NEITHER")
PNG_RE = re.compile(r"^f\d\d_a\d\.png$")
DEFAULT_PORT = __PORT__


def responses_path(evaluator: str) -> str:
    return os.path.join(HERE, "responses-%s.jsonl" % evaluator)


def answered_ids(evaluator: str) -> list:
    """Read what already exists so the page can resume. Never truncates or rewrites."""
    path = responses_path(evaluator)
    out, seen = [], set()
    if not os.path.exists(path):
        return out
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            pid = rec.get("pair_id")
            if pid and pid not in seen:
                seen.add(pid)
                out.append(pid)
    return out


def append_response(rec: dict) -> None:
    path = responses_path(rec["evaluator"])
    with open(path, "a") as fh:          # append-only, by construction
        fh.write(json.dumps(rec, sort_keys=True) + "\n")
        fh.flush()
        os.fsync(fh.fileno())


class Handler(BaseHTTPRequestHandler):
    server_version = "a01writer"

    def _guard(self) -> bool:
        if self.client_address[0] not in ("127.0.0.1", "::1"):
            self.send_error(403, "loopback only")
            return False
        return True

    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _file(self, name: str, ctype: str) -> None:
        path = os.path.join(HERE, name)
        if not os.path.isfile(path):
            self.send_error(404)
            return
        with open(path, "rb") as fh:
            self._send(200, fh.read(), ctype)

    def do_GET(self) -> None:
        if not self._guard():
            return
        path = self.path.split("?", 1)[0]
        if path in ("/", "/judge.html"):
            self._file("judge.html", "text/html; charset=utf-8")
        elif path == "/presentation.json":
            self._file("presentation.json", "application/json")
        elif path.startswith("/answered/"):
            ev = path[len("/answered/"):]
            if ev not in EVALUATORS:
                self.send_error(404)
                return
            self._send(200, json.dumps(answered_ids(ev)).encode(), "application/json")
        elif path.startswith("/renders/"):
            name = path[len("/renders/"):]
            if not PNG_RE.match(name):          # no traversal, no arbitrary file
                self.send_error(404)
                return
            self._file(os.path.join("renders", name), "image/png")
        else:
            self.send_error(404)                # answer key et al. are not reachable

    def do_POST(self) -> None:
        if not self._guard():
            return
        if self.path.split("?", 1)[0] != "/response":
            self.send_error(404)
            return
        try:
            n = int(self.headers.get("Content-Length", "0"))
            rec = json.loads(self.rfile.read(n) or b"{}")
        except (ValueError, TypeError):
            self.send_error(400, "bad json")
            return
        if rec.get("evaluator") not in EVALUATORS:
            self.send_error(400, "bad evaluator")
            return
        if rec.get("response") not in RESPONSES:
            self.send_error(400, "bad response")
            return
        if not isinstance(rec.get("pair_id"), str):
            self.send_error(400, "bad pair_id")
            return
        rec["run"] = 2
        rec["received_at"] = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
        try:
            append_response(rec)
        except OSError as exc:
            self.send_error(500, "write failed: %s" % exc)
            return
        self._send(200, b'{"ok":true}', "application/json")

    def log_message(self, fmt, *args) -> None:
        pass


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("A01 run-2 judging page: http://127.0.0.1:%d/" % args.port)
    print("  photographer:   http://127.0.0.1:%d/?evaluator=photographer" % args.port)
    print("  claude:         http://127.0.0.1:%d/?evaluator=claude" % args.port)
    print("Responses append to responses-<evaluator>.jsonl in %s" % HERE)
    print("Ctrl-C to stop; reopening the page resumes at the first unanswered comparison.")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        srv.server_close()


if __name__ == "__main__":
    main()
'''


# ---------------------------------------------------------------------------------------------
# blindness scanning

# Arm names as whole words, plus the render-path words that would give an arm away.
ARM_WORD_RE = re.compile(
    r"\b(asshot|as[-_ ]shot|auto|autodevelop|oracle|hand|neutral|rawintent|recipe|exposure|"
    r"vibrance|saturation|highlights|shadows|contrast|temperature|tint|whites|blacks)\b",
    re.IGNORECASE,
)
# An outbound reference is an absolute scheme, a protocol-relative URL in an attribute or CSS
# url()/@import, or a subresource-integrity/crossorigin attribute (which only appear on one).
# A bare "//" is a JS comment and is not a reference.
OUTBOUND_RE = re.compile(
    r"""(?:[a-z][a-z0-9+.-]*:)?//(?=[a-z0-9])(?![a-z0-9.]*(?:127\.0\.0\.1|localhost))"""
    r"""|@import|integrity\s*=|crossorigin|\burl\(\s*['"]?//""",
    re.IGNORECASE,
)


def scan_arm_words(text: str) -> list:
    return sorted({m.group(0).lower() for m in ARM_WORD_RE.finditer(text)})


def scan_outbound(text: str) -> list:
    return sorted({m.group(0) for m in OUTBOUND_RE.finditer(text)})


def probe_server(out_dir: str, port: int, sample_png: str) -> dict:
    """Start serve_judge.py on a scratch port and confirm the whitelist.

    Run 1 verified the whitelist by planting answer-key.json and manifest.json in the served
    directory and confirming 404. Both files are already in this directory, so the probe asks for
    them directly, plus the other files a curious evaluator would try and a traversal attempt.
    """
    import subprocess
    import time
    import urllib.error
    import urllib.request

    serve = os.path.join(out_dir, "serve_judge.py")
    proc = subprocess.Popen(
        [sys.executable, serve, "--port", str(port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    base = "http://127.0.0.1:%d" % port

    def get(path: str) -> int:
        try:
            with urllib.request.urlopen(base + path, timeout=5) as resp:
                return resp.status
        except urllib.error.HTTPError as exc:
            return exc.code

    try:
        for _ in range(50):                      # wait for the listener
            try:
                get("/")
                break
            except Exception:
                time.sleep(0.1)
        expect_200 = {
            "/": 200,
            "/judge.html": 200,
            "/presentation.json": 200,
            "/answered/photographer": 200,
            "/answered/claude": 200,
            "/renders/%s" % sample_png: 200,
        }
        expect_404 = [
            "/answer-key.json",
            "/manifest.json",
            "/build-log.json",
            "/presentation-blind.json",
            "/responses-photographer.jsonl",
            "/responses-claude.jsonl",
            "/render-log.json",
            "/serve_judge.py",
            "/renders/",
            "/renders/../answer-key.json",
            "/../answer-key.json",
            "/answered/someone",
            "/",  # replaced below; placeholder removed
        ]
        expect_404 = [p for p in expect_404 if p != "/"]
        got_200 = {p: get(p) for p in expect_200}
        got_404 = {p: get(p) for p in expect_404}
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

    served_ok = all(got_200[p] == code for p, code in expect_200.items())
    blocked_ok = all(code == 404 for code in got_404.values())
    return {
        "probe_port": port,
        "served_paths": got_200,
        "all_expected_paths_served": served_ok,
        "blocked_paths": got_404,
        "all_sensitive_paths_404": blocked_ok,
        "answer_key_reachable_from_page": got_404.get("/answer-key.json") != 404,
        "manifest_reachable_from_page": got_404.get("/manifest.json") != 404,
        "directory_listing": "none — /renders/ returns %s" % got_404.get("/renders/"),
        "note": (
            "answer-key.json and manifest.json are physically present in the served directory, so "
            "a 404 for them is a whitelist result, not a missing-file result."
        ),
    }


# ---------------------------------------------------------------------------------------------
# main


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=EVIDENCE, help="run-2 evidence directory (read + write)")
    ap.add_argument("--seed", type=int, default=DEFAULT_SEED)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--check-only", action="store_true", help="verify inputs, write nothing")
    args = ap.parse_args()

    out_dir = os.path.abspath(os.path.expanduser(args.out))
    if os.path.abspath(RUN1_EVIDENCE) == out_dir:
        raise SystemExit("refusing to write into run 1's evidence directory (A3.7)")
    manifest_path = os.path.join(out_dir, "manifest.json")
    if not os.path.isfile(manifest_path):
        raise SystemExit("no manifest at %s — AGENT 1 has not run. Blocked." % manifest_path)

    manifest = load_manifest(manifest_path)
    manifest_sha = sha256_file(manifest_path)
    frame_facts, by_frame = check_frames(manifest, out_dir)

    arithmetic = expected_pair_arithmetic(manifest)
    base_pairs = build_base_pairs(manifest, by_frame)
    if len(base_pairs) != arithmetic["base_pairs"]:
        raise SystemExit("built %d base pairs, arithmetic says %d" % (len(base_pairs), arithmetic["base_pairs"]))
    if len(base_pairs) != EXPECTED_BASE_PAIRS:
        raise SystemExit(
            "built %d base pairs; A3.8 predicts %d. Report the discrepancy, do not proceed."
            % (len(base_pairs), EXPECTED_BASE_PAIRS)
        )

    rng = random.Random(args.seed)
    seq, seq_attempts = build_sequence(len(base_pairs), rng)
    if len(seq) != EXPECTED_SHOWINGS:
        raise SystemExit("sequence length %d, expected %d" % (len(seq), EXPECTED_SHOWINGS))
    sep = measure_separation(seq)
    if sep["min_intervening_showings_observed"] < MIN_INTERVENING:
        raise SystemExit("separation requirement violated: %s" % sep)

    showings = build_showings(base_pairs, seq, rng)
    showing_facts = verify_showings(showings, base_pairs)

    # ---- emitted files -----------------------------------------------------------------------
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    presentation = [
        {
            "pair_id": s["pair_id"],
            "sequence_index": s["sequence_index"],
            "left_render": s["left_render"],
            "right_render": s["right_render"],
            "left_png": s["left_render"] + ".png",
            "right_png": s["right_render"] + ".png",
        }
        for s in showings
    ]

    renders_dir = os.path.join(out_dir, "renders")
    presentation_blind = [
        {
            "pair_id": s["pair_id"],
            "left_png": os.path.join(renders_dir, s["left_render"] + ".png"),
            "right_png": os.path.join(renders_dir, s["right_render"] + ".png"),
            "sequence_index": s["sequence_index"],
        }
        for s in showings
    ]

    answer_key = {
        "schema": 2,
        "run": 2,
        "generated_at": now,
        "seed": args.seed,
        "manifest_sha256": manifest_sha,
        "warning": "ANSWER KEY — never load this from the judging page or hand it to the VLM stream.",
        "design": (
            "A3.2 full side-balancing: 201 base pairs, each shown twice with the sides flipped. "
            "There is NO separate repeat set. Link a pair's two showings by pair_key; order_index "
            "0/1 identifies which of the two orderings a showing is, and showing_rank 0/1 which "
            "came first in time."
        ),
        "confound_note": (
            "confounded=white_balance marks showings containing oracle: per A01-AMENDMENT-2 §A2.5 "
            "oracle is the only arm whose temperature and tint move, so it is identifiable by "
            "colour cast alone. These showings are retained, not dropped, and are tagged here "
            "only — never in presentation.json, presentation-blind.json or judge.html."
        ),
        "showings": [
            {
                "pair_id": s["pair_id"],
                "sequence_index": s["sequence_index"],
                "pair_key": s["pair_key"],
                "order_index": s["order_index"],
                "showing_rank": s["showing_rank"],
                "frame_id": s["frame_id"],
                "event": s["event"],
                "comparison": s["comparison"],
                "left_arm": s["left_arm"],
                "right_arm": s["right_arm"],
                "left_render": s["left_render"],
                "right_render": s["right_render"],
                **({"confounded": "white_balance"} if s["confounded"] else {}),
            }
            for s in showings
        ],
        "pairs": [
            {
                "pair_key": p["pair_key"],
                "frame_id": p["frame_id"],
                "event": p["event"],
                "comparison": p["comparison"],
                "arm_a": p["arm_a"],
                "arm_b": p["arm_b"],
                "render_a": p["render_a"],
                "render_b": p["render_b"],
                **({"confounded": "white_balance"} if p["confounded"] else {}),
            }
            for p in base_pairs
        ],
    }

    judge_html = JUDGE_HTML
    serve_py = SERVE_JUDGE_PY.replace("__PORT__", str(args.port))

    # ---- blindness checks, before anything is written -----------------------------------------
    blind_keys = sorted({k for row in presentation_blind for k in row})
    expected_blind_keys = ["left_png", "pair_id", "right_png", "sequence_index"]
    if blind_keys != expected_blind_keys:
        raise SystemExit(
            "presentation-blind.json key set is %s, must be exactly %s" % (blind_keys, expected_blind_keys)
        )
    pres_keys = sorted({k for row in presentation for k in row})

    leaks = {
        "presentation.json": scan_arm_words(json.dumps(presentation)),
        "presentation-blind.json": scan_arm_words(json.dumps(presentation_blind)),
        "judge.html": scan_arm_words(judge_html),
        "serve_judge.py": scan_arm_words(serve_py),
    }
    offenders = {k: v for k, v in leaks.items() if v}
    if offenders:
        raise SystemExit("arm-revealing words found in evaluator-visible files: %s" % offenders)

    outbound = scan_outbound(judge_html)
    if outbound:
        raise SystemExit("judge.html references something outbound: %s" % outbound)

    confounded_showings = sum(1 for s in showings if s["confounded"])
    if scan_arm_words(json.dumps(answer_key)) == []:
        raise SystemExit("answer key contains no arm names — it is supposed to")

    build_log = {
        "schema": 2,
        "run": 2,
        "agent": "AGENT 2 (collect) — run 2",
        "generated_at": now,
        "seed": args.seed,
        "rng": "python random.Random(seed); one stream, sequence then orientations",
        "manifest_path": manifest_path,
        "manifest_sha256": manifest_sha,
        "manifest_schema": "run 2 OBJECT (A3.9); loaded manifest['renders'] explicitly",
        "manifest_rows_loaded": {"renders": len(manifest["renders"]), "frames": len(manifest["frames"])},
        "manifest_row_count_asserted": EXPECTED_RENDERS,
        "design": "A3.2 full side-balancing — no separate repeat set",
        "repeat_set_added": False,
        "repeat_set_note": (
            "A3.2: the 20% repeat set is GONE. Every base pair is its own side-flipped duplicate, "
            "so no additional duplication was added; doing so would double-count. Self-agreement "
            "is computed by the scoring agent over all 201 pairs via pair_key."
        ),
        "frame_facts": frame_facts,
        "pair_arithmetic": {
            "expression": arithmetic["expression"],
            "computed_base_pairs": arithmetic["base_pairs"],
            "computed_showings": arithmetic["showings"],
            "a3_8_predicted_base_pairs": EXPECTED_BASE_PAIRS,
            "a3_8_predicted_showings": EXPECTED_SHOWINGS,
            "matches_a3_8": arithmetic["base_pairs"] == EXPECTED_BASE_PAIRS
            and arithmetic["showings"] == EXPECTED_SHOWINGS,
            "produced_base_pairs": len(base_pairs),
            "produced_showings": len(showings),
        },
        "base_pairs_by_comparison": dict(sorted(Counter(p["comparison"] for p in base_pairs).items())),
        "showings_by_comparison": dict(sorted(Counter(s["comparison"] for s in showings).items())),
        "base_pairs_by_event": {
            str(k): v for k, v in sorted(Counter(p["event"] for p in base_pairs).items())
        },
        "showings_by_event": {
            str(k): v for k, v in sorted(Counter(s["event"] for s in showings).items())
        },
        "confounded": {
            "tag": "white_balance",
            "base_pairs": sum(1 for p in base_pairs if p["confounded"]),
            "showings": confounded_showings,
            "tagged_in": ["answer-key.json"],
            "not_tagged_in": ["presentation.json", "presentation-blind.json", "judge.html"],
            "rule": "A2.5 — retained, not dropped",
        },
        "pair_ceiling_note": (
            "A01-STEP2-COLLECT.md §3's ~400 showing ceiling is exceeded by 2 (402). That ceiling "
            "was written for run 1's design and is superseded by A3.2. No pairs were sampled away."
        ),
        "secondary_sampling_applied": False,
        "sequence_construction": {
            "method": (
                "randomised greedy over 402 positions; candidates weighted by pending showings "
                "(unstarted pair = 2, started pair = 1); a pair may not start after position "
                "%d because its second showing would have no legal slot" % (EXPECTED_SHOWINGS - 12)
            ),
            "attempts_used": seq_attempts,
            **sep,
        },
        "side_balancing": showing_facts,
        "port": args.port,
        "run1_port": 8731,
        "evaluators": ["photographer", "claude"],
        "identical_instrument": (
            "A1.3 — one seed, one sequence, one side assignment, shared by both streams. Nothing "
            "is randomised per evaluator."
        ),
        "response_store": {
            "photographer": "responses-photographer.jsonl",
            "claude": "responses-claude.jsonl",
            "pooled_file": None,
            "note": "A1.1: never pooled. Append-only JSONL, fsync-ed per response by serve_judge.py.",
        },
        "response_choices": ["LEFT", "RIGHT", "TIE", "NEITHER"],
        "blindness_checks": {
            "presentation_blind_key_list": blind_keys,
            "presentation_key_list": pres_keys,
            "arm_words_in_evaluator_visible_files": leaks,
            "judge_html_outbound_references": outbound,
            "slots_mapping_to_a_single_arm": frame_facts["slots_mapping_to_a_single_arm"],
            "render_id_opacity": (
                "render ids are f<NN>_a<slot>; slot was shuffled per frame by AGENT 1, and every "
                "slot carries more than one arm across the frame set, so the id does not name an "
                "arm. The id -> arm mapping exists only in answer-key.json."
            ),
            "server_whitelist": ["/", "/judge.html", "/presentation.json", "/answered/<evaluator>", "/renders/<f\\d\\d_a\\d>.png"],
            "http_probe": None,      # filled in below by the live whitelist probe
        },
        "caveats": [
            "Both showings of a pair are the same two photographs with the sides swapped, so an "
            "evaluator can in principle recognise a pair they have already seen. That is inherent "
            "to A3.2's side-balancing, is what makes self-agreement measurable, and applies "
            "identically to both streams.",
            "presentation-blind.json carries absolute PNG paths whose filenames embed the frame "
            "id. Frame identity is not arm identity, and the photograph itself reveals the frame; "
            "no filename names an arm.",
            "Event-5 frames have four renders and events 0-4 have three, so the number of distinct "
            "renders for a frame indicates whether oracle is present for that frame. It does not "
            "indicate WHICH render is oracle.",
        ],
    }

    if args.check_only:
        print(json.dumps({"check_only": True, "build_log_preview": build_log}, indent=1))
        return 0

    def write(name: str, text: str, mode: int = 0o644) -> None:
        path = os.path.join(out_dir, name)
        with open(path, "w") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(path, mode)

    write("presentation.json", json.dumps(presentation, indent=1) + "\n")
    write("presentation-blind.json", json.dumps(presentation_blind, indent=1) + "\n")
    write("answer-key.json", json.dumps(answer_key, indent=1) + "\n")
    write("judge.html", judge_html)
    write("serve_judge.py", serve_py, 0o755)

    # Live whitelist probe: prove answer-key.json and manifest.json are not reachable.
    probe = probe_server(out_dir, args.port, presentation[0]["left_png"])
    build_log["blindness_checks"]["http_probe"] = probe
    if probe["answer_key_reachable_from_page"] or probe["manifest_reachable_from_page"]:
        raise SystemExit("BLINDNESS FAILURE: the page can reach the answer key or manifest. %s" % probe)
    if not probe["all_sensitive_paths_404"] or not probe["all_expected_paths_served"]:
        raise SystemExit("server whitelist probe did not behave as required: %s" % probe)

    write("build-log.json", json.dumps(build_log, indent=1) + "\n")

    print(json.dumps(
        {
            "base_pairs": len(base_pairs),
            "showings": len(showings),
            "seed": args.seed,
            "port": args.port,
            "min_intervening_showings_observed": sep["min_intervening_showings_observed"],
            "confounded_showings": confounded_showings,
            "presentation_blind_keys": blind_keys,
            "out_dir": out_dir,
        },
        indent=1,
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
