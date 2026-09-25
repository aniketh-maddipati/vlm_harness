#!/usr/bin/env python3
"""A01 preference study — AGENT 2 ("collect").

Turns AGENT 1's render manifest into a blind, order-randomised presentation set plus a
self-contained local judging page and a loopback-only response writer.

Reads  (read-only):  <evidence>/manifest.json
Writes (to evidence): presentation.json          the ordered pair list the page reads
                      presentation-blind.json    machine-readable, arm-free, for the VLM stream
                      answer-key.json            id -> frame/arms/is_repeat/first_showing/confound
                      judge.html                 the judging page (contains NO study data)
                      build-log.json             seed, counts, construction record
                      serve_judge.py             loopback-only writer for responses-*.jsonl

BLINDNESS INVARIANTS enforced here (see A01-PREFERENCE.md §6, A01-STEP2-COLLECT.md §2):
  * judge.html embeds no pair data at all; it fetches presentation.json at runtime.
  * presentation.json and presentation-blind.json carry no arm name, no is_repeat flag, no
    recipe value, no raw path, no event id.
  * PNG basenames are AGENT 1's opaque f<NN>_a<N>.png; slot <N> is shuffled per frame and does
    not encode an arm.
  * serve_judge.py serves a strict whitelist, so answer-key.json is not reachable from the page
    even if the evaluator types its URL.
  * The arm mapping exists only in answer-key.json, which nothing the evaluator can reach reads.

This script does NOT score anything and never reads any responses file.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import os
import random
import sys
from datetime import datetime, timezone

# --- study constants (contract-fixed; do not "tune" these) -------------------------------
DEFAULT_SEED = 20260925          # recorded in build-log.json; the study is reproducible from it
REPEAT_FRACTION = 0.20           # A01-PREFERENCE.md §5
MIN_REPEAT_SEPARATION = 10       # at least this many OTHER pairs between the two showings
PAIR_CEILING = 400               # A01-STEP2-COLLECT.md §3 honesty ceiling
DEFAULT_PORT = 8731

RESPONSES = ("LEFT", "RIGHT", "TIE", "NEITHER")
EVALUATORS = ("photographer", "claude")
ORACLE_ARM = "oracle"

BLIND_KEYS = ("pair_id", "left_png", "right_png", "sequence_index")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------------------------------
# manifest -> base pairs
# ---------------------------------------------------------------------------------------

def load_manifest(evidence: str) -> dict:
    path = os.path.join(evidence, "manifest.json")
    if not os.path.exists(path):
        sys.exit("BLOCKED: %s does not exist (AGENT 1 output missing)." % path)
    with open(path) as fh:
        return json.load(fh)


def build_base_pairs(manifest: dict, evidence: str) -> list[dict]:
    """One entry per unordered arm-combination per frame. Sides are assigned later."""
    by_frame: dict[str, dict[str, dict]] = {}
    for r in manifest["renders"]:
        by_frame.setdefault(r["frame_id"], {})[r["arm"]] = r

    pairs: list[dict] = []
    for frame in sorted(manifest["frames"], key=lambda f: f["frame_id"]):
        fid = frame["frame_id"]
        renders = by_frame.get(fid, {})
        arms = sorted(renders)
        missing = sorted(set(frame["arms"]) - set(arms))
        if missing:
            sys.exit("BLOCKED: frame %s is missing rendered arms %s" % (fid, missing))
        for a, b in itertools.combinations(arms, 2):
            ra, rb = renders[a], renders[b]
            png_a = os.path.join(evidence, ra["png"])
            png_b = os.path.join(evidence, rb["png"])
            for p in (png_a, png_b):
                if not os.path.exists(p):
                    sys.exit("BLOCKED: render missing on disk: %s" % p)
            pairs.append({
                "frame_id": fid,
                "event": frame["event"],
                "arm_a": a, "arm_b": b,
                "render_a": ra["render_id"], "render_b": rb["render_id"],
                "png_a": png_a, "png_b": png_b,
                "comparison": "%s_vs_%s" % (a, b),
            })
    return pairs


# ---------------------------------------------------------------------------------------
# randomisation: sides, order, repeat set
# ---------------------------------------------------------------------------------------

def assign_sides(pairs: list[dict], rng: random.Random) -> None:
    """Independent left/right coin flip per pair (A01-STEP2-COLLECT.md §4)."""
    for p in pairs:
        if rng.random() < 0.5:
            p["left_arm"], p["right_arm"] = p["arm_a"], p["arm_b"]
            p["left_render"], p["right_render"] = p["render_a"], p["render_b"]
            p["left_png"], p["right_png"] = p["png_a"], p["png_b"]
        else:
            p["left_arm"], p["right_arm"] = p["arm_b"], p["arm_a"]
            p["left_render"], p["right_render"] = p["render_b"], p["render_a"]
            p["left_png"], p["right_png"] = p["png_b"], p["png_a"]


def build_sequence(pairs: list[dict], rng: random.Random, n_repeats: int) -> tuple[list[dict], dict]:
    """Shuffle the base pairs, pick the repeat set, and interleave flipped duplicates.

    Guarantees, verified by verify_sequence():
      * every repeat appears with left/right FLIPPED relative to its first showing
      * at least MIN_REPEAT_SEPARATION other pairs sit between the two showings
    Construction is retried with derived sub-seeds until the invariants hold; the attempt
    count is recorded so the run stays reproducible.
    """
    n_base = len(pairs)
    total = n_base + n_repeats
    # A candidate that lands in the tail of the base order can have no legal repeat slot, so
    # the ORDER is rejection-sampled. Which pairs repeat is still a uniform draw over pairs.
    tail_guard = MIN_REPEAT_SEPARATION + 1

    attempts = 0
    shuffle_attempts = 0
    while True:
        attempts += 1
        if attempts > 200:
            sys.exit("BLOCKED: could not construct a legal sequence in 200 attempts.")
        sub = random.Random(rng.getrandbits(64))

        repeat_idx = set(sub.sample(range(n_base), n_repeats))

        order = list(range(n_base))
        for _ in range(500):
            shuffle_attempts += 1
            sub.shuffle(order)
            if not any(i in repeat_idx for i in order[-tail_guard:]):
                break
        else:
            continue

        seq: list[dict] = []
        scheduled: list[tuple[int, int]] = []   # (earliest_position, base_index)
        emitted_repeats = 0
        next_base = 0
        ok = True
        for pos in range(total):
            slots_left = total - pos
            due = [s for s in scheduled if s[0] <= pos]
            must_repeat = (next_base >= n_base) or (len(scheduled) >= slots_left)
            if due and (must_repeat or sub.random() < (n_repeats - emitted_repeats) / slots_left):
                earliest, bi = due[0]
                scheduled.remove((earliest, bi))
                seq.append({"base_index": bi, "showing": 2})
                emitted_repeats += 1
            elif next_base < n_base:
                bi = order[next_base]
                next_base += 1
                seq.append({"base_index": bi, "showing": 1})
                if bi in repeat_idx:
                    scheduled.append((pos + MIN_REPEAT_SEPARATION + 1, bi))
            else:
                ok = False
                break
        if not ok or scheduled or emitted_repeats != n_repeats or len(seq) != total:
            continue

        record = {
            "construction_attempts": attempts,
            "shuffle_attempts": shuffle_attempts,
            "base_order_tail_guard": tail_guard,
            "tail_guard_note": (
                "The last %d slots of the base ORDER are constrained to non-repeated pairs so "
                "every repeat has a legal slot. The repeat SET is an unconstrained uniform "
                "sample over all %d base pairs." % (tail_guard, n_base)
            ),
        }
        return seq, record


def materialise(pairs: list[dict], seq: list[dict]) -> list[dict]:
    """Turn the sequence skeleton into concrete rows with opaque per-showing pair ids."""
    first_id: dict[int, str] = {}
    rows: list[dict] = []
    for idx, item in enumerate(seq):
        base = pairs[item["base_index"]]
        pid = "p%04d" % (idx + 1)
        flipped = item["showing"] == 2
        left_arm = base["right_arm"] if flipped else base["left_arm"]
        right_arm = base["left_arm"] if flipped else base["right_arm"]
        left_render = base["right_render"] if flipped else base["left_render"]
        right_render = base["left_render"] if flipped else base["right_render"]
        left_png = base["right_png"] if flipped else base["left_png"]
        right_png = base["left_png"] if flipped else base["right_png"]

        row = {
            "pair_id": pid,
            "sequence_index": idx,
            "base_index": item["base_index"],
            "is_repeat": flipped,
            "first_showing_id": first_id.get(item["base_index"]) if flipped else None,
            "frame_id": base["frame_id"],
            "event": base["event"],
            "comparison": base["comparison"],
            "left_arm": left_arm, "right_arm": right_arm,
            "left_render": left_render, "right_render": right_render,
            "left_png": left_png, "right_png": right_png,
        }
        if not flipped:
            first_id[item["base_index"]] = pid
        rows.append(row)
    return rows


def verify_sequence(rows: list[dict], n_base: int, n_repeats: int) -> dict:
    """Independent re-check of every invariant. Fails loudly rather than reporting a guess."""
    problems: list[str] = []
    by_id = {r["pair_id"]: r for r in rows}
    firsts = [r for r in rows if not r["is_repeat"]]
    reps = [r for r in rows if r["is_repeat"]]

    if len(firsts) != n_base:
        problems.append("first showings %d != %d" % (len(firsts), n_base))
    if len(reps) != n_repeats:
        problems.append("repeats %d != %d" % (len(reps), n_repeats))
    if len({r["base_index"] for r in firsts}) != n_base:
        problems.append("duplicate or missing base pair among first showings")
    if len(by_id) != len(rows):
        problems.append("pair_id collision")

    min_sep = None
    for r in reps:
        first = by_id.get(r["first_showing_id"])
        if first is None:
            problems.append("%s has no first showing" % r["pair_id"])
            continue
        if first["base_index"] != r["base_index"]:
            problems.append("%s points at the wrong first showing" % r["pair_id"])
        if not (first["left_render"] == r["right_render"] and first["right_render"] == r["left_render"]):
            problems.append("%s is not left/right flipped" % r["pair_id"])
        sep = r["sequence_index"] - first["sequence_index"] - 1
        min_sep = sep if min_sep is None else min(min_sep, sep)
        if sep < MIN_REPEAT_SEPARATION:
            problems.append("%s separated by only %d pairs" % (r["pair_id"], sep))

    for r in rows:
        if r["left_render"] == r["right_render"]:
            problems.append("%s shows the same render twice" % r["pair_id"])
        if r["left_arm"] == r["right_arm"]:
            problems.append("%s compares an arm with itself" % r["pair_id"])

    if problems:
        sys.exit("BLOCKED: sequence invariants violated:\n  " + "\n  ".join(problems))
    return {"min_repeat_separation_observed": min_sep}


# ---------------------------------------------------------------------------------------
# outputs
# ---------------------------------------------------------------------------------------

def write_json(path: str, data) -> None:
    with open(path, "w") as fh:
        json.dump(data, fh, indent=1, sort_keys=False)
        fh.write("\n")


def emit_presentation(rows: list[dict]) -> list[dict]:
    """What judge.html reads. No arm, no repeat flag, no event, no recipe, no raw path."""
    return [{
        "pair_id": r["pair_id"],
        "sequence_index": r["sequence_index"],
        "left_render": r["left_render"],
        "right_render": r["right_render"],
        "left_png": os.path.basename(r["left_png"]),
        "right_png": os.path.basename(r["right_png"]),
    } for r in rows]


def emit_blind(rows: list[dict]) -> list[dict]:
    """A01-AMENDMENT-1 A1.4: the VLM stream's blinding is structural. EXACTLY four keys."""
    return [{
        "pair_id": r["pair_id"],
        "left_png": r["left_png"],
        "right_png": r["right_png"],
        "sequence_index": r["sequence_index"],
    } for r in rows]


def emit_answer_key(rows: list[dict], manifest_sha: str, seed: int) -> dict:
    entries = []
    for r in rows:
        e = {
            "pair_id": r["pair_id"],
            "sequence_index": r["sequence_index"],
            "frame_id": r["frame_id"],
            "event": r["event"],
            "comparison": r["comparison"],
            "left_arm": r["left_arm"],
            "right_arm": r["right_arm"],
            "left_render": r["left_render"],
            "right_render": r["right_render"],
            "is_repeat": r["is_repeat"],
            "first_showing_id": r["first_showing_id"],
        }
        # A01-AMENDMENT-2 §A2.5, DELTA 3: oracle is the only arm whose WB/tint moves, so any
        # pair containing it is identifiable by colour cast without judging quality.
        if ORACLE_ARM in (r["left_arm"], r["right_arm"]):
            e["confounded"] = "white_balance"
        entries.append(e)
    return {
        "schema": 1,
        "generated_at": now_iso(),
        "seed": seed,
        "manifest_sha256": manifest_sha,
        "warning": "ANSWER KEY — never load this from the judging page or hand it to the VLM stream.",
        "confound_note": (
            "confounded=white_balance marks pairs containing oracle: per A01-AMENDMENT-2 §A2.5 "
            "oracle is the only arm whose temperature and tint move, so it is identifiable by "
            "colour cast alone. These pairs are retained, not dropped."
        ),
        "pairs": entries,
    }


def check_blindness(evidence: str, presentation: list[dict], blind: list[dict], html: str) -> dict:
    """Refuse to ship a de-blinding leak. Checks the artefacts the evaluator can reach."""
    arm_words = ["asShot", "asshot", "as_shot", "auto", "oracle", "hand", "incumbent", "neutral"]
    problems: list[str] = []

    for row in blind:
        if tuple(row.keys()) != BLIND_KEYS:
            problems.append("presentation-blind.json row %s has keys %s" % (row.get("pair_id"), list(row)))
            break

    blob = json.dumps(presentation) + json.dumps(blind)
    for w in arm_words:
        if w in blob:
            problems.append("arm word %r appears in a file the evaluator/VLM reads" % w)
    for w in ("is_repeat", "first_showing", "confounded", "recipe", "raw_path", "event",
              "frame_id", "exposure", "vibrance", "temperature", "tint"):
        if w in blob:
            problems.append("field %r leaked into a blind file" % w)

    low = html.lower()
    for w in arm_words:
        if w in low:
            problems.append("arm word %r appears in judge.html" % w)
    for w in ("is_repeat", "answer-key", "manifest.json", "repeat"):
        if w in low:
            problems.append("%r appears in judge.html" % w)

    # "No network" per §7: no outbound/external reference anywhere in the page.
    outbound = [t for t in ("http://", "https://", "//cdn", "fonts.googleapis", "@import")
                if t in low]
    if outbound:
        problems.append("judge.html contains outbound reference tokens: %s" % outbound)

    if problems:
        sys.exit("BLOCKED: blindness/no-network check failed:\n  " + "\n  ".join(problems))
    return {
        "blind_key_list": list(BLIND_KEYS),
        "arm_words_absent_from_blind_files": True,
        "arm_words_absent_from_judge_html": True,
        "judge_html_outbound_references": 0,
        "answer_key_reachable_from_page": False,
    }


# --- judge.html --------------------------------------------------------------------------
# No study data lives in this file. It fetches its pair list from the loopback writer.
# No arm name, no repeat marker, no comment mentioning either. No external resource.
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
    <button id="bT">Equally good<span class="k">3</span></button>
    <button id="bN">Neither is acceptable<span class="k">4</span></button>
  </div>
</div>

<div id="done" class="hide">
  <div id="panel2" style="padding:40px"><h1>All responses recorded.</h1>
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

SERVE_PY = r'''#!/usr/bin/env python3
"""Loopback-only response writer for the A01 judging page.

Serves judge.html, presentation.json and renders/*.png from this directory on 127.0.0.1 and
appends one JSON line per response to responses-<evaluator>.jsonl, fsync-ing each line.

Why a server at all: a file:// page cannot append to a path on disk, and A01-PREFERENCE.md §6
requires each response to reach disk as it is given so a quit-and-resume loses nothing.
"No network" means no OUTBOUND request: this makes none, and judge.html references no external
resource. Binding to loopback is not a network dependency.

Deliberately restrictive: GET is a whitelist. answer-key.json, manifest.json, build-log.json
and every responses file are NOT reachable, and there is no directory listing, so the evaluator
cannot de-blind themselves by typing a URL.

    python3 serve_judge.py            # then open the printed http://127.0.0.1:PORT/ address
    python3 serve_judge.py --port 9000
'''
SERVE_PY += r'''"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
EVALUATORS = ("photographer", "claude")
RESPONSES = ("LEFT", "RIGHT", "TIE", "NEITHER")
PNG_RE = re.compile(r"^f\d\d_a\d\.png$")


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
    ap.add_argument("--port", type=int, default=__PORT__)
    args = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("A01 judging page: http://127.0.0.1:%d/" % args.port)
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


def main() -> None:
    ap = argparse.ArgumentParser(description="Build the A01 blind presentation set.")
    ap.add_argument("--evidence", default=os.path.expanduser("~/LuminaEvidence/a01-preference"))
    ap.add_argument("--seed", type=int, default=DEFAULT_SEED)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = ap.parse_args()

    evidence = os.path.abspath(os.path.expanduser(args.evidence))
    manifest = load_manifest(evidence)
    manifest_sha = sha256_file(os.path.join(evidence, "manifest.json"))

    pairs = build_base_pairs(manifest, evidence)
    n_base = len(pairs)

    # Expected: 50 frames x 3 arms (3 pairs) + 10 frames x 4 arms (6 pairs) = 210.
    expected = sum(len(f["arms"]) * (len(f["arms"]) - 1) // 2 for f in manifest["frames"])
    if n_base != expected:
        sys.exit("BLOCKED: built %d base pairs, manifest implies %d." % (n_base, expected))
    n_repeats = int(round(n_base * REPEAT_FRACTION))
    if n_base + n_repeats > PAIR_CEILING:
        sys.exit("BLOCKED: %d pairs exceeds the %d ceiling; secondary sampling would be "
                 "required. Stop and report." % (n_base + n_repeats, PAIR_CEILING))

    rng = random.Random(args.seed)
    assign_sides(pairs, rng)
    seq, construction = build_sequence(pairs, rng, n_repeats)
    rows = materialise(pairs, seq)
    checks = verify_sequence(rows, n_base, n_repeats)

    presentation = emit_presentation(rows)
    blind = emit_blind(rows)
    answer_key = emit_answer_key(rows, manifest_sha, args.seed)
    html = JUDGE_HTML
    blind_report = check_blindness(evidence, presentation, blind, html)

    write_json(os.path.join(evidence, "presentation.json"), presentation)
    write_json(os.path.join(evidence, "presentation-blind.json"), blind)
    write_json(os.path.join(evidence, "answer-key.json"), answer_key)
    with open(os.path.join(evidence, "judge.html"), "w") as fh:
        fh.write(html)
    serve = SERVE_PY.replace("__PORT__", str(args.port))
    serve_path = os.path.join(evidence, "serve_judge.py")
    with open(serve_path, "w") as fh:
        fh.write(serve)
    os.chmod(serve_path, 0o755)

    # counts for the build log
    by_comparison: dict[str, int] = {}
    by_event: dict[str, int] = {}
    for r in rows:
        if r["is_repeat"]:
            continue
        by_comparison[r["comparison"]] = by_comparison.get(r["comparison"], 0) + 1
        by_event[str(r["event"])] = by_event.get(str(r["event"]), 0) + 1
    confounded = sum(1 for r in rows if ORACLE_ARM in (r["left_arm"], r["right_arm"]))

    build_log = {
        "schema": 1,
        "agent": "AGENT 2 (collect)",
        "generated_at": now_iso(),
        "seed": args.seed,
        "rng": "python random.Random(seed); sub-streams derived via getrandbits(64)",
        "manifest_sha256": manifest_sha,
        "base_pairs": n_base,
        "expected_base_pairs": expected,
        "repeat_pairs": n_repeats,
        "repeat_fraction": REPEAT_FRACTION,
        "total_showings": len(rows),
        "pair_ceiling": PAIR_CEILING,
        "secondary_sampling_applied": False,
        "secondary_sampling_reason": (
            "%d total showings is under the %d ceiling, so all secondary pairs are retained; "
            "no sampling was needed." % (len(rows), PAIR_CEILING)
        ),
        "base_pairs_by_comparison": dict(sorted(by_comparison.items())),
        "base_pairs_by_event": dict(sorted(by_event.items())),
        "confounded_showings_white_balance": confounded,
        "min_repeat_separation_required": MIN_REPEAT_SEPARATION,
        "sequence_construction": construction,
        "verification": checks,
        "blindness_checks": blind_report,
        "evaluators": list(EVALUATORS),
        "response_store": {
            "photographer": "responses-photographer.jsonl",
            "claude": "responses-claude.jsonl",
            "pooled_file": None,
            "note": ("A01-AMENDMENT-1 A1.1: never pooled. Append-only JSONL, one line per "
                     "response, fsync-ed by serve_judge.py as each answer is given."),
        },
        "responses_choices": list(RESPONSES),
        "how_to_run": [
            "python3 %s" % serve_path,
            "open http://127.0.0.1:%d/?evaluator=photographer" % args.port,
        ],
        "caveats": [
            "The repeat set is detectable by either evaluator from the photograph itself: a "
            "repeat shows the same two renders with sides swapped. That is inherent to an "
            "intra-rater reliability probe and applies identically to both streams.",
            "A01-AMENDMENT-2 A2.5: %d showings contain oracle and are tagged "
            "confounded=white_balance in the answer key only." % confounded,
        ],
    }
    write_json(os.path.join(evidence, "build-log.json"), build_log)

    print("base pairs        %d (expected %d)" % (n_base, expected))
    print("repeats           %d" % n_repeats)
    print("total showings    %d" % len(rows))
    print("seed              %d" % args.seed)
    print("blind key list    %s" % list(BLIND_KEYS))
    print("min separation    %d (required >= %d)"
          % (checks["min_repeat_separation_observed"], MIN_REPEAT_SEPARATION))
    print("confounded        %d showings contain oracle" % confounded)
    print("serve             python3 %s" % serve_path)


if __name__ == "__main__":
    main()
