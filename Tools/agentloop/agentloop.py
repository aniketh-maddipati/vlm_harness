#!/usr/bin/env python3
"""One lead, several workers: a task split into sub-tasks, each routed to Grok, Claude or a local command.

    python3 Tools/agentloop/agentloop.py                                  # dry run of the sample task: routing + cost, no calls
    python3 Tools/agentloop/agentloop.py --plan-file my-plan.json         # dry run of your own plan
    python3 Tools/agentloop/agentloop.py --task "…" --plan                # Claude splits the task (one small call), dry run of the result
    python3 Tools/agentloop/agentloop.py --plan-file p.json --live        # run it: Grok + Claude calls, inside the caps in config.json

Dev tooling only: nothing here is app code, and the app gains no reach. Workers report back as JSON
files in ~/LuminaEvidence/agentloop/runs/<time>/ (one per sub-task, plus summary.md). Grok only reads:
tracked repo files and ci_local logs go in, a report (or, for lint-fix, a patch outside protected
paths) comes out. Claude workers run one at a time (one writer per worktree). The last step, when any
file changed, is `bash Scripts/ci_local.sh`; the loop never commits, pushes or merges.
The xAI key is read from the Keychain (service xai-api-key) at call time and never printed.
"""
import argparse, concurrent.futures, dataclasses, fnmatch, json, os, re, subprocess, sys, time, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
EVIDENCE = os.path.join(os.path.expanduser("~"), "LuminaEvidence", "agentloop")
CONFIG = json.load(open(os.path.join(HERE, "config.json")))
NO_CLAUDE = False


# ——— plans and routing

@dataclasses.dataclass
class Subtask:
    id: str
    kind: str
    title: str
    prompt: str = ""
    paths: list = dataclasses.field(default_factory=list)    # repo globs the sub-task reads or edits
    inputs: list = dataclasses.field(default_factory=list)   # extra files (ci_local logs) for Grok
    command: str = ""                                        # local workers only
    depends_on: list = dataclasses.field(default_factory=list)


@dataclasses.dataclass
class Route:
    worker: str            # grok | claude | local | refused
    why: str
    model: str = ""
    agent: str = ""
    web_search: bool = False


def protected(path, cfg=CONFIG):
    return any(fnmatch.fnmatch(path, p) for p in cfg["protected"])


def route(t, cfg=CONFIG):
    """Where a sub-task goes. The table in config.json, then the guards: Grok never gets a protected
    path (the bridge, the page, trust, signing, the look maths), an unknown kind goes to Claude, and a
    local command must start with an allowed prefix."""
    r = cfg["routes"].get(t.kind)
    if r is None:
        return Route("claude", f"unknown kind '{t.kind}': Claude decides")
    out = Route(r["worker"], r["why"], r.get("model", ""), r.get("agent", ""), r.get("web_search", False))
    if out.worker == "grok":
        hits = [p for p in t.paths if protected(p, cfg)]
        if hits:
            return Route("claude", f"protected path {hits[0]}: stays with Claude")
    if out.worker == "local":
        if not any(t.command.startswith(c) for c in cfg["local_commands"]):
            return Route("refused", f"command not in config.json local_commands: {t.command!r}")
    return out


def load_plan(path):
    raw = json.load(open(path))
    subs = [Subtask(**{k: v for k, v in s.items() if k in Subtask.__dataclass_fields__}) for s in raw["subtasks"]]
    return raw.get("task", ""), subs


PLAN_SCHEMA = {
    "type": "object", "required": ["subtasks"],
    "properties": {"subtasks": {"type": "array", "items": {
        "type": "object", "required": ["id", "kind", "title", "prompt"],
        "properties": {"id": {"type": "string"}, "kind": {"type": "string", "enum": sorted(CONFIG["routes"])},
                       "title": {"type": "string"}, "prompt": {"type": "string"},
                       "paths": {"type": "array", "items": {"type": "string"}},
                       "inputs": {"type": "array", "items": {"type": "string"}},
                       "command": {"type": "string"},
                       "depends_on": {"type": "array", "items": {"type": "string"}}}}}}}


def plan_with_claude(task):
    """The lead's split: one headless Claude call that reads AGENTS.md and returns sub-tasks (JSON schema)."""
    kinds = "\n".join(f"- {k}: {v['why']}" for k, v in CONFIG["routes"].items())
    prompt = (f"Split this Lumina task into at most {CONFIG['budget']['max_subtasks']} sub-tasks for workers. "
              f"Read AGENTS.md first. Kinds:\n{kinds}\nUse cheap read-only kinds (search, summarize, log-triage, "
              f"large-read, doc-draft, lint-fix, research) where they fit; anything that edits the page, the bridge or "
              f"trust files is page-ui / bridge / code-edit. paths are repo globs. End with a 'ci' sub-task whose "
              f"command is 'bash Scripts/ci_local.sh' when anything edits files. Do not change files.\n\nTask: {task}")
    r = subprocess.run([CONFIG["claude"]["cli"], "-p", prompt, "--output-format", "json", "--json-schema", json.dumps(PLAN_SCHEMA),
                        "--max-budget-usd", "0.50", "--permission-mode", "plan"], cwd=ROOT, capture_output=True, text=True, timeout=600)
    try:
        out = json.loads(r.stdout)
    except json.JSONDecodeError:
        out = {"is_error": True, "result": (r.stderr or r.stdout).strip()[-400:]}
    if r.returncode or out.get("is_error"):
        sys.exit(f"planning failed: {out.get('result', '')}\n"
                 "  (headless `claude -p` needs its own login: run `claude` once in a terminal and /login; "
                 "or have a Claude Code session write the plan and pass --plan-file)")
    plan = out.get("structured_output") or json.loads(out.get("result", "{}"))
    return [Subtask(**{k: v for k, v in s.items() if k in Subtask.__dataclass_fields__}) for s in plan["subtasks"]], out.get("total_cost_usd", 0)


# ——— Grok's context: tracked files only

def tracked(globs):
    files = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.split("\n")
    return [f for f in files if f and any(fnmatch.fnmatch(f, g) for g in globs) and not protected(f)]


def allowed_input(path):
    """Extra inputs Grok may read: files under the repo that git tracks, and ci_local logs."""
    p = os.path.realpath(os.path.expanduser(path))
    logs = os.path.realpath(os.path.join(os.path.expanduser("~"), "LuminaEvidence", "ci-local"))
    if p.startswith(logs + os.sep):
        return True
    rel = os.path.relpath(p, ROOT)
    return not rel.startswith("..") and rel in tracked([rel])


def context(t, limit):
    parts, size, dropped = [], 0, []
    names = tracked(t.paths) + [i for i in t.inputs if allowed_input(i)]
    for f in names:
        try:
            text = open(os.path.join(ROOT, f) if not os.path.isabs(os.path.expanduser(f)) else os.path.expanduser(f),
                        encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        chunk = f"=== {f}\n{text}\n"
        if size + len(chunk) > limit:
            dropped.append(f)
            continue
        parts.append(chunk); size += len(chunk)
    return "".join(parts), len(parts), dropped


# ——— budget

def ledger_path():
    return os.path.join(EVIDENCE, "ledger.jsonl")


def month_spent(worker="grok"):
    month, total = time.strftime("%Y-%m"), 0.0
    try:
        for line in open(ledger_path()):
            e = json.loads(line)
            if e.get("worker") == worker and e.get("month") == month:
                total += e.get("usd", 0)
    except OSError:
        pass
    return total


def charge(worker, usd, sub_id):
    os.makedirs(EVIDENCE, exist_ok=True)
    with open(ledger_path(), "a") as fh:
        fh.write(json.dumps({"month": time.strftime("%Y-%m"), "at": time.strftime("%F %T"), "worker": worker, "usd": round(usd, 5), "id": sub_id}) + "\n")


def grok_estimate(model, in_chars, web=False):
    """Worst case for one call: every input token at the uncached rate, the whole output allowance used."""
    m = CONFIG["grok"]["models"][model]
    tin, tout = in_chars / 3.5, CONFIG["grok"]["max_output_tokens"]
    return (tin * m["in"] + tout * m["out"]) / 1e6 + (CONFIG["grok"]["web_search_per_call"] * 5 if web else 0)


class Budget:
    def __init__(self):
        b = CONFIG["budget"]
        self.left = {"grok": min(b["run_grok_usd"], b["month_grok_usd"] - month_spent("grok")), "claude": b["run_claude_usd"]}

    def reserve(self, worker, usd):
        if usd > self.left[worker]:
            return False
        self.left[worker] -= usd
        return True

    def settle(self, worker, reserved, actual):
        self.left[worker] += reserved - actual


# ——— workers

@dataclasses.dataclass
class Report:
    id: str
    worker: str
    status: str            # ok | failed | refused | skipped | handed (a Claude sub-task left to the lead session)
    summary: str = ""
    model: str = ""
    output: str = ""       # path to the full answer
    files_changed: list = dataclasses.field(default_factory=list)
    usd: float = 0.0
    tokens_in: int = 0
    tokens_out: int = 0
    seconds: float = 0.0


def keychain_has(service):
    return subprocess.run(["security", "find-generic-password", "-a", os.environ.get("USER", ""), "-s", service],
                          capture_output=True).returncode == 0


def keychain_secret(service):
    r = subprocess.run(["security", "find-generic-password", "-a", os.environ.get("USER", ""), "-s", service, "-w"],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


SYSTEM = ("You are a read-only worker for the Lumina repo (a macOS photo app). Answer the sub-task from the files given. "
          "Be terse: findings first, file:line references, no preamble. You cannot change files.")
PATCH_RULE = ("\nReturn the fix as one unified diff (paths a/<file> b/<file>, relative to the repo root) in a ```diff block, "
              "touching only the files given. No other prose than one line of summary.")


def run_grok(t, r, run_dir, budget):
    g = CONFIG["grok"]
    limit = min(g["max_input_chars"], int(g["models"][r.model]["context"] * 3.5 * 0.8))
    ctx, n, dropped = context(t, limit)
    est = grok_estimate(r.model, len(ctx) + len(t.prompt) + len(SYSTEM), r.web_search)
    if not budget.reserve("grok", est):
        return Report(t.id, "grok", "refused", f"worst case ${est:.3f} is over what is left of the Grok cap", r.model)
    key = keychain_secret(g["keychain_service"])
    if not key:
        budget.settle("grok", est, 0)
        return Report(t.id, "grok", "refused", f"no key in Keychain service {g['keychain_service']}", r.model)
    body = {"model": r.model, "max_output_tokens": g["max_output_tokens"], "input": [
        {"role": "system", "content": SYSTEM},
        {"role": "user", "content": f"Sub-task: {t.title}\n{t.prompt}{PATCH_RULE if t.kind == 'lint-fix' else ''}\n\n"
                                    f"Files ({n}{', ' + str(len(dropped)) + ' left out for size' if dropped else ''}):\n{ctx}"}]}
    if r.web_search:
        body["tools"] = [{"type": "web_search"}]
    req = urllib.request.Request(g["endpoint"], data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    del key
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=g["timeout_s"]) as resp:
            out = json.load(resp)
    except urllib.error.HTTPError as e:
        budget.settle("grok", est, 0)
        return Report(t.id, "grok", "failed", f"HTTP {e.code}: {e.read()[:300].decode(errors='replace')}", r.model)
    except (urllib.error.URLError, TimeoutError) as e:
        budget.settle("grok", est, 0)
        return Report(t.id, "grok", "failed", f"network: {e}", r.model)
    text = "\n".join(c.get("text", "") for item in out.get("output", []) if item.get("type") == "message"
                     for c in item.get("content", []) if c.get("type") in ("output_text", "text"))
    u = out.get("usage", {})
    tin, tout = u.get("input_tokens", 0), u.get("output_tokens", 0)
    cached = (u.get("input_tokens_details") or {}).get("cached_tokens", 0)
    m = g["models"][r.model]
    searches = sum(1 for item in out.get("output", []) if "search" in item.get("type", ""))
    usd = ((tin - cached) * m["in"] + cached * m["cached_in"] + tout * m["out"]) / 1e6 + searches * g["web_search_per_call"]
    budget.settle("grok", est, usd)
    charge("grok", usd, t.id)
    path = os.path.join(run_dir, f"{t.id}.md")
    open(path, "w").write(text)
    rep = Report(t.id, "grok", "ok", text.strip().split("\n")[0][:200], r.model, path, [], round(usd, 5), tin, tout, round(time.time() - t0, 1))
    if t.kind == "lint-fix":
        apply_patch(t, text, rep)
    return rep


def apply_patch(t, text, rep):
    """A Grok patch lands only when every file it touches is one the sub-task named and none is protected."""
    m = re.search(r"```diff\n(.*?)```", text, re.S)
    if not m:
        rep.status, rep.summary = "failed", "no diff in the answer"
        return
    diff = m.group(1)
    files = sorted(set(re.findall(r"^\+\+\+ b/(\S+)", diff, re.M)))
    named = set(tracked(t.paths))
    bad = [f for f in files if protected(f) or f not in named]
    if bad or not files:
        rep.status, rep.summary = "refused", f"patch touches {bad or 'nothing'}: not applied (saved in {rep.output})"
        return
    chk = subprocess.run(["git", "apply", "--check", "-"], cwd=ROOT, input=diff, text=True, capture_output=True)
    if chk.returncode:
        rep.status, rep.summary = "failed", f"patch does not apply: {chk.stderr.strip()[:200]}"
        return
    subprocess.run(["git", "apply", "-"], cwd=ROOT, input=diff, text=True, check=True)
    rep.files_changed = files


def run_claude(t, r, run_dir, budget):
    cap = min(CONFIG["claude"]["per_task_usd"], budget.left["claude"])
    if cap <= 0.05 or not budget.reserve("claude", cap):
        return Report(t.id, "claude", "refused", "Claude cap for this run is spent")
    before = changed_files()
    cmd = [CONFIG["claude"]["cli"], "-p", f"{t.title}\n\n{t.prompt}\n\nScope: {', '.join(t.paths) or 'as needed'}. "
           "Follow AGENTS.md. Do not commit, push or merge. End with one line: what changed.",
           "--output-format", "json", "--max-budget-usd", f"{cap:.2f}", "--permission-mode", "acceptEdits"]
    if r.agent:
        cmd += ["--agent", r.agent]
    t0 = time.time()
    try:
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=CONFIG["claude"]["timeout_s"])
    except subprocess.TimeoutExpired:
        budget.settle("claude", cap, cap)
        return Report(t.id, "claude", "failed", "timed out", r.agent)
    try:
        out = json.loads(p.stdout)
    except json.JSONDecodeError:
        out = {"result": p.stdout[-2000:] + p.stderr[-1000:], "is_error": True}
    usd = float(out.get("total_cost_usd") or 0)
    budget.settle("claude", cap, usd)
    path = os.path.join(run_dir, f"{t.id}.md")
    open(path, "w").write(out.get("result", ""))
    status = "failed" if p.returncode or out.get("is_error") else "ok"
    last = (out.get("result") or "").strip().split("\n")[-1][:200]
    return Report(t.id, "claude", status, last, r.agent or "claude", path, sorted(set(changed_files()) - set(before)),
                  round(usd, 4), seconds=round(time.time() - t0, 1))


def run_local(t, r, run_dir, budget):
    t0 = time.time()
    log = os.path.join(run_dir, f"{t.id}.log")
    guard = [sys.executable, os.path.join(ROOT, "Scripts/test_guard.py"), "run", "--quiet", "--name", f"agentloop {t.id}", "--limit", "2400", "--",
             "bash", "-c", t.command]
    with open(log, "w") as fh:
        rc = subprocess.run(guard if not t.command.startswith("bash Scripts/ci_local.sh") else ["bash", "-c", t.command],
                            cwd=ROOT, stdout=fh, stderr=subprocess.STDOUT).returncode
    tail = open(log).read().strip().split("\n")[-1:] or [""]
    status = {0: "ok", 75: "refused"}.get(rc, "failed")
    return Report(t.id, "local", status, f"exit {rc}: {tail[0][:200]}", "", log, seconds=round(time.time() - t0, 1))


def changed_files():
    out = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True).stdout
    return [l[3:] for l in out.split("\n") if l]


# ——— the lead

def show_routing(task, subs, planning_usd=0.0):
    print(f"task: {task}\n" if task else "", end="")
    rows, grok_worst = [], 0.0
    for t in subs:
        r = route(t)
        est = ""
        if r.worker == "grok":
            ctx, n, dropped = context(t, CONFIG["grok"]["max_input_chars"])
            w = grok_estimate(r.model, len(ctx) + len(t.prompt), r.web_search)
            grok_worst += w
            est = f"≤ ${w:.3f} ({n} files, {len(ctx) // 1000} k chars{', ' + str(len(dropped)) + ' cut' if dropped else ''})"
        elif r.worker == "claude":
            est = f"≤ ${CONFIG['claude']['per_task_usd']:.2f} (cap)"
        target = {"grok": r.model + (" + web" if r.web_search else ""), "claude": r.agent or "claude -p"}.get(r.worker, r.worker)
        rows.append((t.id, t.kind, f"{r.worker}:{target}", est, r.why))
    w = [max(len(x[i]) for x in rows + [("id", "kind", "worker", "cost", "")]) for i in range(4)]
    print(f"{'id':<{w[0]}}  {'kind':<{w[1]}}  {'worker':<{w[2]}}  {'cost':<{w[3]}}  why")
    for row in rows:
        print(f"{row[0]:<{w[0]}}  {row[1]:<{w[1]}}  {row[2]:<{w[2]}}  {row[3]:<{w[3]}}  {row[4]}")
    b = CONFIG["budget"]
    left = b["month_grok_usd"] - month_spent("grok")
    print(f"\nGrok worst case ${grok_worst:.3f} · run cap ${b['run_grok_usd']:.2f} · month left ${left:.2f} of ${b['month_grok_usd']:.2f}"
          f" · Claude run cap ${b['run_claude_usd']:.2f}{f' · planning ${planning_usd:.3f}' if planning_usd else ''}")
    print(f"xAI key in Keychain ({CONFIG['grok']['keychain_service']}): {'yes' if keychain_has(CONFIG['grok']['keychain_service']) else 'no'}")
    order = waves(subs)
    print("order: " + " → ".join("[" + ", ".join(x.id for x in wave) + "]" for wave in order))
    if any(route(t).worker == "refused" for t in subs):
        print("REFUSED sub-tasks above will not run.")


def waves(subs):
    """Dependency order: each wave's sub-tasks have all their dependencies in earlier waves."""
    done, left, out = set(), list(subs), []
    while left:
        ready = [t for t in left if all(d in done for d in t.depends_on)]
        if not ready:
            sys.exit("plan has a dependency cycle or names a missing sub-task: " + ", ".join(t.id for t in left))
        out.append(ready)
        done |= {t.id for t in ready}
        left = [t for t in left if t.id not in done]
    return out


def run_live(task, subs):
    stamp = time.strftime("%Y%m%d-%H%M%S")
    run_dir = os.path.join(EVIDENCE, "runs", stamp)
    os.makedirs(run_dir, exist_ok=True)
    budget, reports, edited, start = Budget(), {}, False, set(changed_files())
    for wave in waves(subs):
        failed_deps = {t.id for t in wave if any(reports.get(d) and reports[d].status not in ("ok", "handed") for d in t.depends_on)}
        groks = [t for t in wave if route(t).worker == "grok" and t.id not in failed_deps]
        rest = [t for t in wave if t not in groks]
        # Grok only reads: its sub-tasks in a wave run side by side. Claude and local ones run one at a time.
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            for rep in pool.map(lambda t: run_grok(t, route(t), run_dir, budget), groks):
                reports[rep.id] = rep
        for t in rest:
            r = route(t)
            if t.id in failed_deps:
                rep = Report(t.id, r.worker, "skipped", "a dependency did not finish")
            elif r.worker == "claude" and NO_CLAUDE:
                rep = Report(t.id, "claude", "handed", f"for the lead session{' (' + r.agent + ')' if r.agent else ''}: {t.title}")
            elif r.worker == "claude":
                rep = run_claude(t, r, run_dir, budget)
            elif r.worker == "local":
                rep = run_local(t, r, run_dir, budget)
            else:
                rep = Report(t.id, r.worker, "refused", r.why)
            reports[rep.id] = rep
        for rep in (reports[t.id] for t in wave):
            edited |= bool(rep.files_changed)
            json.dump(dataclasses.asdict(rep), open(os.path.join(run_dir, f"{rep.id}.json"), "w"), indent=1)
            print(f"{rep.status:<8} {rep.id:<14} {rep.worker:<7} ${rep.usd:<7.4f} {rep.summary}")
    ran_ci = any(t.kind == "ci" for t in subs)
    if (edited or set(changed_files()) - start) and not ran_ci:
        t = Subtask("ci-final", "ci", "what CI would run", command="bash Scripts/ci_local.sh")
        rep = run_local(t, route(t), run_dir, budget)
        reports[rep.id] = rep
        print(f"{rep.status:<8} {rep.id:<14} local   $0       {rep.summary}")
    total = sum(r.usd for r in reports.values())
    ok = all(r.status in ("ok", "handed") for r in reports.values())
    lines = [f"# agentloop {stamp}", "", f"task: {task}", "", "| id | worker | status | $ | summary |", "|---|---|---|---|---|"]
    lines += [f"| {r.id} | {r.worker} {r.model} | {r.status} | {r.usd:.4f} | {r.summary.replace('|', '/')} |" for r in reports.values()]
    lines += ["", f"total ${total:.4f} · {'ready for pr-shepherd' if ok else 'not ready: see the rows above'}"]
    open(os.path.join(run_dir, "summary.md"), "w").write("\n".join(lines) + "\n")
    print(f"\n{'PASS' if ok else 'FAIL'}  total ${total:.4f} · {run_dir}/summary.md" + (" · next: pr-shepherd (one push)" if ok else ""))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--task", help="the task in words (with --plan, Claude splits it)")
    ap.add_argument("--plan-file", default=os.path.join(HERE, "sample-plan.json"))
    ap.add_argument("--plan", action="store_true", help="let Claude split --task (one small headless call, ≤ $0.50)")
    ap.add_argument("--live", action="store_true", help="run the workers (API calls, within config.json caps)")
    ap.add_argument("--no-claude", action="store_true", help="don't start headless Claude: its sub-tasks are handed back to the lead session")
    a = ap.parse_args()
    global NO_CLAUDE
    NO_CLAUDE = a.no_claude
    planning = 0.0
    if a.plan:
        if not a.task:
            sys.exit("--plan needs --task")
        subs, planning = plan_with_claude(a.task)
        task = a.task
    else:
        task, subs = load_plan(a.plan_file)
        task = a.task or task
    if len(subs) > CONFIG["budget"]["max_subtasks"]:
        sys.exit(f"{len(subs)} sub-tasks: over max_subtasks ({CONFIG['budget']['max_subtasks']})")
    show_routing(task, subs, planning)
    if not a.live:
        print("\nDRY RUN  no worker ran (--live runs them)")
        return 0
    print()
    return run_live(task, subs)


if __name__ == "__main__":
    sys.exit(main())
