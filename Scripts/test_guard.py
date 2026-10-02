#!/usr/bin/env python3
"""Runs a test command so that it ends, and stops every test on this Mac.

  test_guard.py run --name NAME --limit SECONDS [--screen] [--quiet] [--sweep-under DIR]… -- COMMAND…
      COMMAND runs in its own process group with a wall-clock limit. At the limit, on Ctrl-C, on
      SIGTERM / SIGHUP and when COMMAND ends, the whole group is stopped (TERM, then KILL), every
      process started from a file under a --sweep-under DIR is stopped, and every disk image
      whose file is under one is detached. Exit: COMMAND's own, 124 at the limit, 75 if refused.
      Refused when a run of the same NAME is alive, and, with --screen, when another run holds
      the screen (the probe's window and XCUITests take the keyboard: one at a time on a Mac).
      LUMINA_LOCK_WAIT=<s> waits that long for the screen instead of refusing at once.

  test_guard.py stop [--dry-run]       (Scripts/stop_tests.sh)
      Stops everything test-related: guarded runs, probes, UI test runners, the drivers that
      start them (parents first, so nothing respawns), test builds of the app, the probe's disk
      images, listening test servers, and the tests' temp folders. Safe at any time.

  test_guard.py status
      What stop would stop, and who holds the screen.

State: ~/LuminaEvidence/.screen.lock (flock: released by the kernel when its holder dies) and
~/LuminaEvidence/.runs/<pid>.json. LUMINA_GUARD_DIR moves both.
"""
import fcntl, glob, json, os, plistlib, re, shutil, signal, subprocess, sys, tempfile, time

HOME = os.path.expanduser("~")
STATE = os.environ.get("LUMINA_GUARD_DIR") or os.path.join(HOME, "LuminaEvidence")
LOCK, RUNS = os.path.join(STATE, ".screen.lock"), os.path.join(STATE, ".runs")
HELD = "LUMINA_SCREEN_LOCK_HELD"          # set for the command: it and its children already own the screen
REFUSED, TIMED_OUT = 75, 124
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def say(text):
    print(text, file=sys.stderr, flush=True)


def real(path):
    return os.path.realpath(path)


def under(path, roots):
    path = real(path)
    return any(path == r or path.startswith(r.rstrip("/") + "/") for r in roots)


# ——— processes

def processes():
    """pid → (ppid, pgid, started, command) for every process of this user."""
    out = subprocess.run(["ps", "-xo", "pid=,ppid=,pgid=,stat=,lstart=,command="], capture_output=True, text=True).stdout
    table = {}
    for line in out.splitlines():
        m = re.match(r"\s*(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(\w+\s+\w+\s+\d+\s+[\d:]+\s+\d+)\s+(.*)", line)
        if m and not m[4].startswith("Z"):          # a zombie is over: only its parent's wait is missing
            table[int(m[1])] = (int(m[2]), int(m[3]), m[5], m[6])
    return table


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def members(pgid, table=None):
    return [p for p, v in (table or processes()).items() if v[1] == pgid]


def end(pids, grace=3.0):
    """TERM, then KILL what is left after `grace`. Returns the pids that would not die."""
    pids = [p for p in pids if p != os.getpid()]
    for p in pids:
        try: os.kill(p, signal.SIGTERM)
        except OSError: pass
    t0 = time.time()
    while time.time() - t0 < grace and any(alive(p) for p in pids):
        time.sleep(0.1)
    for p in pids:
        if alive(p):
            try: os.kill(p, signal.SIGKILL)
            except OSError: pass
    time.sleep(0.2)
    table = processes()
    return [p for p in pids if p in table]


def cwd_of(pid):
    out = subprocess.run(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"], capture_output=True, text=True).stdout
    return next((l[1:] for l in out.splitlines() if l.startswith("n")), "")


# ——— disk images

def attached_images():
    """[(image file, whole-disk device, mount points)] for every attached disk image."""
    try:
        raw = subprocess.run(["hdiutil", "info", "-plist"], capture_output=True, timeout=20).stdout
        images = plistlib.loads(raw).get("images", []) if raw else []
    except Exception:
        return []
    out = []
    for image in images:
        ents = image.get("system-entities", [])
        devs = sorted((e.get("dev-entry", "") for e in ents if e.get("dev-entry")), key=len)
        out.append((image.get("image-path", ""), devs[0] if devs else "", [e["mount-point"] for e in ents if e.get("mount-point")]))
    return out


def detach_under(roots, dry=False):
    """Force-detaches the images whose *file* is under `roots`. A volume is never chosen by its
    mount point or name: a real card or disk has no image file and cannot match."""
    done = []
    for path, dev, mounts in attached_images():
        if not path or not dev or not under(path, roots):
            continue
        if not dry:
            subprocess.run(["hdiutil", "detach", dev, "-force"], capture_output=True, timeout=30)
        done.append(f"{dev} {path}" + (f" (mounted at {', '.join(mounts)})" if mounts else ""))
    return done


# ——— runs

def run_files():
    runs = []
    for f in glob.glob(os.path.join(RUNS, "*.json")):
        try:
            runs.append((f, json.load(open(f))))
        except Exception:
            try: os.remove(f)
            except OSError: pass
    return runs


def sweep(run, table=None):
    """What a run may leave behind: its process group, processes started from under its sweep
    folders (the app a UI test launched, a probe's export worker), disk images made there."""
    table = table or processes()
    leader = table.get(run["pgid"])
    reused = leader is not None and run.get("leaderStarted") and leader[2] != run["leaderStarted"]
    group = [] if reused else members(run["pgid"], table)
    roots = [real(r) for r in run.get("sweep", [])]
    strays = [p for p, v in table.items() if roots and p not in group and any(v[3].startswith(r.rstrip("/") + "/") for r in roots)]
    left = end(group + strays) if group or strays else []
    images = detach_under(roots) if roots else []
    return len(group) + len(strays), images, left


def reap():
    """Runs whose guard died (kill -9, a closed terminal): end what they left."""
    for f, run in run_files():
        if alive(run["guard"]) and processes().get(run["guard"], ("",) * 4)[3].find("test_guard") >= 0:
            continue
        n, images, _ = sweep(run)
        if n or images:
            say(f"guard  cleaned up after '{run['name']}' (its guard pid {run['guard']} is gone): {n} processes, {len(images)} disk images")
        try: os.remove(f)
        except OSError: pass


def holder():
    try:
        return json.load(open(LOCK))
    except Exception:
        return {}


def take_screen(name, wait):
    """The screen lock, or None. flock, so a dead holder never leaves it taken."""
    fd = os.open(LOCK, os.O_RDWR | os.O_CREAT, 0o644)
    t0 = time.time()
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except OSError:
            if time.time() - t0 >= wait:
                os.close(fd)
                return None
            time.sleep(1)
    os.ftruncate(fd, 0)
    os.write(fd, json.dumps({"pid": os.getpid(), "name": name, "since": time.strftime("%H:%M:%S"), "cwd": os.getcwd()}).encode())
    return fd


def cmd_run(argv):
    if "--" not in argv:
        sys.exit(__doc__)
    opts, command = argv[:argv.index("--")], argv[argv.index("--") + 1:]
    name, limit, screen, roots, quiet = "test", 300.0, False, [], False
    i = 0
    while i < len(opts):
        o = opts[i]
        if o == "--name": name = opts[i + 1]; i += 1
        elif o == "--limit": limit = float(opts[i + 1]); i += 1
        elif o == "--sweep-under": roots.append(opts[i + 1]); i += 1
        elif o == "--screen": screen = True
        elif o == "--quiet": quiet = True
        else: sys.exit(f"test_guard: unknown option {o}")
        i += 1
    if not command or limit <= 0:
        sys.exit(__doc__)
    os.makedirs(RUNS, exist_ok=True)
    reap()
    for _, run in run_files():
        if run["name"] == name:
            say(f"REFUSED  '{name}' is already running (pid {run['guard']}, since {run['started']}, in {run['cwd']}). "
                f"One at a time; `bash Scripts/stop_tests.sh` stops it.")
            return REFUSED
    lock = None
    if screen and not os.environ.get(HELD):
        lock = take_screen(name, float(os.environ.get("LUMINA_LOCK_WAIT", "0") or 0))
        if lock is None:
            h = holder()
            say(f"REFUSED  the screen is in use by '{h.get('name', '?')}' (pid {h.get('pid', '?')}, since {h.get('since', '?')}, in {h.get('cwd', '?')}). "
                f"Screen-owning tests run one at a time; LUMINA_LOCK_WAIT=<seconds> waits, `bash Scripts/stop_tests.sh` stops it.")
            return REFUSED

    env = dict(os.environ, LUMINA_GUARDED=name, LUMINA_GUARD_LIMIT=str(int(limit)))
    if screen: env[HELD] = os.environ.get(HELD) or str(os.getpid())
    t0 = time.time()
    child = subprocess.Popen(command, env=env, start_new_session=True)
    run = {"guard": os.getpid(), "pgid": child.pid, "name": name, "started": time.strftime("%H:%M:%S"), "limit": limit,
           "cwd": os.getcwd(), "command": " ".join(command)[:400], "sweep": roots, "screen": screen,
           "leaderStarted": processes().get(child.pid, ("",) * 4)[2]}
    record = os.path.join(RUNS, f"{os.getpid()}.json")
    json.dump(run, open(record, "w"))

    stopped = []
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda s, _: stopped.append(s))
    code = None
    while code is None and not stopped and time.time() - t0 < limit:
        try:
            code = child.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            pass
    why = ""
    if code is None:
        if stopped:
            code, why = 128 + stopped[0], f"stopped by signal {stopped[0]}"
        else:
            code, why = TIMED_OUT, f"FAIL  '{name}' reached its limit of {int(limit)} s and was stopped"
    n, images, left = sweep(run)
    try: child.wait(timeout=5)
    except subprocess.TimeoutExpired: pass
    try: os.remove(record)
    except OSError: pass
    if lock is not None:
        os.ftruncate(lock, 0); os.close(lock)
    if why: say(why)
    tail = (f", {len(images)} disk images detached" if images else "") + (f", {len(left)} processes would not die: {left}" if left else "")
    if code or not quiet: say(f"guard  {name}: exit {code} in {time.time() - t0:.0f} s (limit {int(limit)} s){tail}")
    return code


# ——— stop

TESTS = re.compile(r"lumina-probe( |$)|Scripts/(probe|probe_remote|uitest|test)\.sh|Tests/probe/\S+\.(py|sh)|Tests/web/\S+\.(mjs|py)"
                   r"|Tests/linux-swift/run\.sh|LuminaUITests|LuminaLogicTests|LuminaKitPackageTests|LuminaPackageTests"
                   r"|xcodebuild\b.*Lumina|/xctest\b.*(Lumina|vlm_harness)|stitch-labels/label\.py|life_kill|q2drive")
BUILD = re.compile(r"(^|/)(swift-build|swift-test|swift-frontend|swiftpm-testing-helper|xctest)( |$)")
DRIVER = re.compile(r"^(\S*/)?(bash|sh|zsh|python[\d.]*|Python|node|perl|make|env|caffeinate|timeout|script|xcrun|swift|swift-run)( |$)")
TEMP = ("lumina-store-*", "lumina-fixtures", "lumina-wp2-*", "lumina-harness-*", "lumina-webkit*", "lumina-guard-*")


def repo_roots():
    """Every checkout of this repo: the main one and its worktrees."""
    out = subprocess.run(["git", "-C", ROOT, "worktree", "list", "--porcelain"], capture_output=True, text=True).stdout
    return sorted({real(l.split(" ", 1)[1]) for l in out.splitlines() if l.startswith("worktree ")} | {real(ROOT)})


def image_roots():
    evidence = os.path.join(HOME, "LuminaEvidence")
    roots = {real(evidence), real(tempfile.gettempdir()), "/private/tmp", real(STATE)} | set(repo_roots())
    if os.path.isdir(evidence):       # its folders may be links to another disk
        roots |= {real(os.path.join(evidence, n)) for n in os.listdir(evidence)}
    return sorted(roots)


def find():
    table, me = processes(), os.getpid()
    mine = set()
    p = me
    while p in table:
        mine.add(p); p = table[p][0]
    roots = repo_roots()
    targets = {}
    for pid, (ppid, pgid, _, cmd) in table.items():
        if pid in mine: continue
        if "test_guard.py run" in cmd: targets[pid] = "guard"
        elif TESTS.search(cmd): targets[pid] = "test"
        elif re.search(r"/Lumina\.app/Contents/MacOS/Lumina( |$)", cmd) and not cmd.startswith(("/Applications/", HOME + "/Applications/")):
            targets[pid] = "test build of the app"
        elif BUILD.search(cmd) and under(cwd_of(pid) or "/nowhere", roots): targets[pid] = "build in a checkout"
    for _, run in run_files():
        for pid in members(run["pgid"], table):
            if pid not in mine: targets.setdefault(pid, f"in guarded run '{run['name']}'")
    # The scripts that started them: stopped first, so a loop cannot start the next one.
    drivers = {}
    for pid in list(targets):
        p = table[pid][0]
        while p in table and p not in mine and p not in targets and p > 1:
            cmd = table[p][3]
            interactive = cmd.startswith("-") or re.fullmatch(r"(\S*/)?(bash|sh|zsh)( -\w*[il]\w*)*", cmd)
            if not DRIVER.match(cmd) or interactive: break
            drivers[p] = cmd
            p = table[p][0]
    servers = {}
    out = subprocess.run(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"], capture_output=True, text=True).stdout
    pid = None
    for line in out.splitlines():
        if line.startswith("p"): pid = int(line[1:])
        elif line.startswith("n") and pid in table and pid not in mine:
            cmd = table[pid][3]
            if re.search(r"(^|/)(python[\d.]*|Python|node)( |$)", cmd.split(" ")[0] + " ") and \
               (re.search(r"LuminaEvidence|vlm_harness|Tests/web", cmd) or under(cwd_of(pid) or "/nowhere", roots + [real(os.path.join(HOME, "LuminaEvidence"))])):
                servers[pid] = line[1:]
    sessions = [(pid, cwd_of(pid)) for pid, v in table.items() if re.search(r"(^|/)claude( |$)", v[3]) and pid not in mine]
    sessions = [(p, c) for p, c in sessions if c and under(c, roots) and table[p][0] not in dict(sessions)]
    return table, targets, drivers, servers, sessions


def temp_dirs():
    return [d for pat in TEMP for base in {tempfile.gettempdir(), "/private/tmp"} for d in glob.glob(os.path.join(base, pat))]


def cmd_stop(argv, status=False):
    dry = status or "--dry-run" in argv
    table, targets, drivers, servers, sessions = find()
    short = lambda pid: f"{pid:>6}  {table[pid][3][:150]}"
    if drivers:
        say("drivers (the scripts that start the tests):"); [say("  " + short(p)) for p in sorted(drivers)]
    if targets:
        say("tests:"); [say(f"  {short(p)}   [{targets[p]}]") for p in sorted(targets)]
    if servers:
        say("listening test servers:"); [say(f"  {short(p)}   [{servers[p]}]") for p in sorted(servers)]
    images = detach_under(image_roots(), dry=True)
    if images:
        say("the probe's disk images:"); [say("  " + i) for i in images]
    temps = temp_dirs()
    if temps:
        say("temp folders:"); [say("  " + t) for t in temps]
    h = holder()
    if h and alive(h.get("pid", 0)):
        say(f"screen: held by '{h.get('name')}' (pid {h.get('pid')}, since {h.get('since')})")
    if sessions:
        say("Claude sessions open in a checkout (they can start tests again; close the ones you don't want):")
        for pid, cwd in sessions: say(f"  {pid:>6}  {cwd}")
    nothing = not (drivers or targets or servers or images)
    if dry:
        say("nothing test-related is running" if nothing else "(dry run: nothing stopped)")
        return 0 if nothing else 1
    # Drivers are frozen first: a loop that restarts its probe gets no chance to.
    for p in drivers:
        try: os.kill(p, signal.SIGSTOP)
        except OSError: pass
    guards = [p for p, k in targets.items() if k == "guard"]
    end(guards, grace=8)                       # a guard stops and sweeps its own run
    end([p for p in targets if p not in guards] + list(servers))
    for p in drivers:
        try: os.kill(p, signal.SIGKILL)
        except OSError: pass
    for _, run in run_files():
        sweep(run)
    for f, _ in run_files():
        try: os.remove(f)
        except OSError: pass
    detached = detach_under(image_roots())
    for t in temps:
        if not os.path.ismount(t) and not any(os.path.ismount(os.path.join(dp, d)) for dp, dn, _ in os.walk(t) for d in dn):
            shutil.rmtree(t, ignore_errors=True)
    time.sleep(0.5)
    _, targets2, drivers2, servers2, _ = find()
    left_images = detach_under(image_roots(), dry=True)
    say(f"stopped {len(drivers)} drivers, {len(targets)} test processes, {len(servers)} servers; detached {len(detached)} disk images; removed {len(temps)} temp folders")
    if targets2 or drivers2 or servers2 or left_images:
        say(f"STILL THERE: {sorted(list(targets2) + list(drivers2) + list(servers2))} {left_images}")
        return 1
    say("nothing test-related is left")
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["run"]: sys.exit(cmd_run(args[1:]))
    if args[:1] == ["stop"]: sys.exit(cmd_stop(args[1:]))
    if args[:1] == ["status"]: sys.exit(cmd_stop(args[1:], status=True))
    sys.exit(__doc__)
