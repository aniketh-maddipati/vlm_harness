#!/usr/bin/env python3
"""WebKit sandbox for the Mac-only checks, runnable on Linux.

Runs the real v5 page in WebKitGTK (the WebKit engine and JavaScriptCore, as in WKWebView, minus
Cocoa) with plumbing.js injected at document start and a real `lumina` script-message handler with
replies, the same channel WKWebView uses. The handler forwards each message to
Tests/web/webkit-server.mjs, which answers as SetsBridge does (a Node stand-in; the Swift itself is
not exercised here). Suites:

  contract   app-plumbing-contract.json's expressions, and ONDIR under JavaScriptCore
  selftest   the design's ?selftest (25 checks + timing)
  flow       open a folder, read, keep, save sidecars into the folder, .lumina-bak, reopen, card, access
  screens    screens-1440 / 1920: prototype vs app parity mode, every snapshot and state dump compared

  xvfb-run -a -s "-screen 0 2000x1300x24" /usr/bin/python3.12 Tests/web/webkit.py [suite …] [--out DIR]

Needs: gir1.2-webkit2-4.1 python3-gi python3-gi-cairo xvfb (apt), node + playwright (for the fixtures).
"""
import json, os, subprocess, sys, time, urllib.request
import gi
gi.require_version('Gtk', '3.0')
gi.require_version('WebKit2', '4.1')
gi.require_version('JavaScriptCore', '4.1')
from gi.repository import Gtk, GLib, WebKit2, JavaScriptCore
import cairo

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
WEB = os.path.join(ROOT, 'Lumina/Sets/Web')
SCEN = os.path.join(ROOT, 'Tests/probe/scenarios')
PAGE = 'Lumina Sets v5.dc.html'
PORT = int(os.environ.get('LUMINA_WEBKIT_PORT', '8765'))
ORIGIN = f'http://127.0.0.1:{PORT}'
args = sys.argv[1:]
OUT = args[args.index('--out') + 1] if '--out' in args else os.path.join(os.environ.get('LUMINA_HARNESS_TMP', '/tmp'), 'lumina-webkit')
suites = [a for i, a in enumerate(args) if not a.startswith('--') and (i == 0 or args[i - 1] != '--out')] or ['contract', 'selftest', 'flow', 'screens']
os.makedirs(OUT, exist_ok=True)
FAILS = []


def ok(cond, what, got=None):
    if not cond:
        FAILS.append(what)
    print(('ok   ' if cond else 'FAIL ') + what + ('' if cond or got is None else '  got ' + json.dumps(got)[:400]), flush=True)


def post(path, obj):
    req = urllib.request.Request(ORIGIN + path, data=json.dumps(obj).encode(), headers={'content-type': 'application/json'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode()


def ctl(op, **a):
    return json.loads(post('/ctl', dict(a, op=op)))


def spin(cond, timeout=30.0):
    t0 = time.time()
    while not cond():
        if time.time() - t0 > timeout:
            return False
        Gtk.main_iteration_do(False)
        time.sleep(0.002)
    return True


def wait(ms):
    t0 = time.time()
    while (time.time() - t0) * 1000 < ms:
        Gtk.main_iteration_do(False)
        time.sleep(0.002)


_FILTER = {}


def offline_filter():
    """The app's own content rule (SetsWebView.make: `^https?://` blocked), compiled by WebKit's content
    blocker, so the page gets no network here either. The page's sample photos (picsum.photos in
    lumina-v4-data.js) fail to load in both modes, as in the app."""
    if 'f' not in _FILTER:
        # Content-rule regexes have no lookahead: block every http(s) host with a letter in it, which
        # leaves only this sandbox's own server (127.0.0.1) reachable.
        rules = '[{"trigger":{"url-filter":"^https?://[^/:]*[a-z]"},"action":{"type":"block"}}]'
        store = WebKit2.UserContentFilterStore.new(os.path.join(OUT, 'filters'))
        store.save('lumina-offline', GLib.Bytes.new(rules.encode()), None, lambda st, r: _FILTER.setdefault('f', st.save_finish(r)))
        spin(lambda: 'f' in _FILTER, 30)
    return _FILTER['f']


class Page:
    """One offscreen WebKitGTK view. app=True: plumbing.js + the lumina message handler."""

    def __init__(self, app, size=(1440, 900), query='', clock=None, parity=False, storage_writes=True):
        ucm = WebKit2.UserContentManager()
        add = lambda src: ucm.add_script(WebKit2.UserScript.new(src, WebKit2.UserContentInjectedFrames.TOP_FRAME, WebKit2.UserScriptInjectionTime.START, None, None))
        if clock:
            base = int(time.mktime(time.strptime(clock, '%Y-%m-%dT%H:%M:%S')) * 1000)
            add('(() => { const R = Date, t0 = R.now(), b = %d; const now = () => b + (R.now() - t0); class D extends R { constructor(...a) { if (a.length === 0) super(now()); else super(...a); } static now() { return now(); } } window.Date = D; })();' % base)
        if not storage_writes:
            add("Storage.prototype.setItem = function () { throw new DOMException('storage writes off', 'QuotaExceededError'); };")
        add('window.__resources = Object.assign(window.__resources || {}, %s);' % json.dumps(ctl('resources')))
        add('window.__errors = []; addEventListener("error", e => __errors.push(String(e.message) + (e.filename ? " @ " + e.filename + ":" + e.lineno : ""))); addEventListener("unhandledrejection", e => __errors.push("rejection: " + String(e.reason && e.reason.message || e.reason) + " " + String(e.reason && e.reason.stack || "").split("\\n").slice(0, 3).join(" | ")));')
        if app:
            ucm.register_script_message_handler_with_reply('lumina', None)
            ucm.connect('script-message-with-reply-received::lumina', self._native)
            add('window.__luminaConfig = %s;' % json.dumps({'debug': False, 'prefs': {'rating': 3, 'adv': True, 'tsz': 1, 'enter': True}, 'parity': parity}))
            add(open(os.path.join(WEB, 'plumbing.js'), encoding='utf-8').read())
            # bridge.open(url) on the Mac evaluates __lumina.openFolder(); here the page picks it up.
            add("setInterval(() => { if (!window.__lumina) return; fetch('/ctl', {method: 'POST', body: JSON.stringify({op: 'takeKick'})}).then(r => r.json()).then(k => { if (k) __lumina.openFolder(); }); }, 150);")
        ucm.add_filter(offline_filter())
        self.view = WebKit2.WebView.new_with_user_content_manager(ucm)
        s = self.view.get_settings()
        s.set_enable_developer_extras(True)
        s.set_enable_write_console_messages_to_stdout(False)
        self.win = Gtk.OffscreenWindow()
        self.win.set_default_size(*size)
        self.view.set_size_request(*size)
        self.win.add(self.view)
        self.win.show_all()
        self.loaded = False
        self.view.connect('load-changed', lambda v, e: setattr(self, 'loaded', self.loaded or e == WebKit2.LoadEvent.FINISHED))
        self.view.load_uri(ORIGIN + '/' + urllib.request.quote(PAGE) + ('?' + query if query else ''))
        if not spin(lambda: self.loaded, 30):
            raise RuntimeError('page did not load')

    def _native(self, ucm, msg, reply):
        try:
            text = post('/native', json.loads(msg.to_json(0)))
            reply.return_value(JavaScriptCore.Value.new_from_json(msg.get_context(), text))
        except Exception as e:     # a bridge error reaches the page as a rejected promise, as in WKWebView
            reply.return_error_message(str(e))
        return True

    def js(self, body, timeout=60.0):
        """Runs `body` as an async function in the page and returns its JSON-safe result."""
        box = {}
        src = 'return (async () => { const __r = await (async () => { %s })(); return JSON.stringify(__r === undefined ? null : __r); })();' % body

        def done(view, res):
            try:
                v = view.call_async_javascript_function_finish(res)
                box['v'] = json.loads(v.to_string())
            except Exception as e:
                box['e'] = str(e)
        self.view.call_async_javascript_function(src, -1, None, None, None, None, done)
        if not spin(lambda: box, timeout):
            raise RuntimeError('js timed out: ' + body[:80])
        if 'e' in box:
            raise RuntimeError(box['e'])
        return box['v']

    def snap(self, path):
        box = {}
        self.view.get_snapshot(WebKit2.SnapshotRegion.VISIBLE, WebKit2.SnapshotOptions.NONE, None,
                               lambda v, r: box.setdefault('s', v.get_snapshot_finish(r)))
        spin(lambda: 's' in box, 30)
        s = box['s']
        s.write_to_png(path)
        img = cairo.ImageSurface(cairo.FORMAT_ARGB32, s.get_width(), s.get_height())
        c = cairo.Context(img); c.set_source_surface(s, 0, 0); c.paint(); img.flush()
        return (img.get_width(), img.get_height(), bytes(img.get_data()))

    def close(self):
        self.win.destroy()
        wait(50)


LOGIC = """(() => { for (const el of document.querySelectorAll('[data-screen-label], body *')) { const k = Object.keys(el).find(x => x.startsWith('__reactFiber$')); if (!k) continue;
  for (let f = el[k]; f; f = f.return) { const sn = f.stateNode; if (sn && sn.logic && typeof sn.logic.onKey === 'function' && sn.logic.state && 'view' in sn.logic.state) return sn.logic; } } return null; })"""
HELPERS = """
window.__probe = window.__probe || { logic: %s };
window.K = (key, o = {}) => { const code = o.code || ({' ': 'Space', '?': 'Slash', ',': 'Comma', '-': 'Minus', '=': 'Equal'}[key] || (/^[a-z]$/i.test(key) ? 'Key' + key.toUpperCase() : /^[0-9]$/.test(key) ? 'Digit' + key : key));
  const ev = t => dispatchEvent(new KeyboardEvent(t, { key, code, bubbles: true, cancelable: true, shiftKey: !!o.shift || key === '?', metaKey: !!o.cmd, altKey: !!o.alt }));
  if (o.up !== false && o.down !== false) { ev('keydown'); ev('keyup'); } else if (o.down !== false) ev('keydown'); else ev('keyup'); };
window.W = ms => new Promise(r => setTimeout(r, ms));
window.C = (op, a = {}) => fetch('/ctl', { method: 'POST', body: JSON.stringify(Object.assign({ op }, a)) }).then(r => r.json());
window.until = async (f, ms = 20000) => { const t0 = Date.now(); while (!f()) { if (Date.now() - t0 > ms) return false; await W(40); } return true; };
""" % LOGIC


def ready(p, app):
    cond = 'window.__lumina && __lumina.logic() && __lumina.logic().__luminaPlumbed' if app else "document.querySelector('[data-screen-label]') && window.luminaState"
    t0 = time.time()
    while time.time() - t0 < 30:
        if p.js('return !!(%s)' % cond):
            p.js(HELPERS + 'return true')
            return True
        wait(100)
    return False


# ——— suites

def contract():
    ctl('reset')
    p = Page(app=True)
    ok(ready(p, True), 'contract: page ready with plumbing (WebKitGTK %d.%d)' % (WebKit2.get_major_version(), WebKit2.get_minor_version()))
    spec = json.load(open(os.path.join(SCEN, 'app-plumbing-contract.json')))
    for st in [s for s in spec['steps'] if s['do'] == 'expect']:
        try:
            got = p.js(st['js'])
        except Exception as e:
            got = 'threw ' + str(e)
        ok((json.dumps(got) == json.dumps(st['equals'])) if 'equals' in st else bool(got), 'contract: ' + st['js'][:80], got)
    h = p.js('return __lumina.readHash()')
    print('     ONDIR under JavaScriptCore: %s' % h)
    ok(p.js('return window.__errors') == [], 'contract: no page errors', p.js('return window.__errors'))
    rm = ctl('state')['readyMsg']
    ok(rm is not None and not rm.get('missing'), 'contract: native told ready with nothing missing', rm)
    p.close()


def selftest():
    p = Page(app=False, query='selftest')
    ok(spin(lambda: p.js('return Array.isArray(window.luminaTestResults)'), 240), 'selftest: finished')
    rows = p.js('return window.luminaTestResults') or []
    for r in rows:
        if not r['ok'] or r['n'].startswith('perf'):
            print(('     ' if r['ok'] else 'FAIL ') + r['n'] + ' · ' + r['d'])
    # Behaviour checks gate; the two timing checks are reported only: ADDENDUM-1 §6 measures timing
    # in the real app, and a virtual display without GPU is no measure of it.
    bad = [r['n'] for r in rows if not r['ok'] and not r['n'].startswith('perf')]
    beh = [r for r in rows if not r['n'].startswith('perf')]
    ok(len(rows) >= 25 and not bad, 'selftest: %d / %d behaviour checks pass in WebKit' % (len(beh) - len(bad), len(beh)), bad)
    p.close()


FLOW = r"""
const L = () => __lumina.logic(), out = [], t = (n, c, g) => out.push({ n, ok: !!c, got: c ? undefined : g });
const shoot = await C('shoot', { name: '2026-09-01', others: ['DSC01001.JPG', 'X.CR3', 'clip.MP4'],
  sidecars: { 'DSC01002.xmp': '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="2"/></rdf:RDF></x:xmpmeta>' } });
t('start: empty Open, no sample', L().state.view === 'import' && L().data.order.length === 0, L().state.view);
const nr = await C('folder', { name: 'NoRaw', files: ['A.CR3', 'B.CR3', 'C.JPG', 'D.MP4'] });
await C('pick', { path: nr }); __lumina.openFolder(); await until(() => L().state.openNote, 5000);
t('no ARW: the page\'s note from the native listing', L().state.openNote === 'no ARW found · 2 CR3 · 1 JPEG / HEIF · 1 videos · only Sony ARW is supported', L().state.openNote);
await C('pick', { path: shoot }); __lumina.openFolder();
await until(() => L().real && L().real.length && !L().state.realLoad && L().state.realInfo, 30000);
const ri = L().state.realInfo || {};
t('read: 12 photos in Cull', L().state.view === 'cull' && ri.n === 12 && ri.bad === 0, ri);
const notes = (L().state.notes || []).map(x => x.t).join(' | ');
t('read: import notes', /1 CR3/.test(notes) && /1 video skipped/.test(notes) && /1 already rated/.test(notes), notes);
const ins = __lumina.inspect(); t('read: previews by URL, thumbs as blobs', !ins.lgHeld && !ins.srcNotBlob && !ins.dupPaths && !ins.zsrcOff, ins);
const p7 = Object.values(L().data.byId).find(p => (p.file || p.name) === 'DSC01007.ARW');
t('read: orientation 6 is portrait in WebKit', p7 && p7.portrait === true, p7 && p7.portrait);
t('read: measures from the WebKit canvas', L().real.every(p => p.nopv || (p.focus > 0 && p.lum > 0 && p.dhash)), L().real.map(p => [p.focus, p.lum, p.dhash]).slice(0, 3));
K('p'); await W(120); K('ArrowDown'); await W(150); K('p'); await W(150);
const kept = L().kept().length; t('cull: P keeps (2)', kept === 2, L().state.marks);
await W(2300);
let st = await C('state'); const sid = __lumina.shootId(), saved = st.sessions[sid] && JSON.parse(st.sessions[sid]);
t('session: saved by path within 2 s', saved && Object.keys(saved.marks).length === 2 && Object.keys(saved.marks).every(k => /^(sub\/)?DSC0\d+\.ARW$/.test(k)), saved && saved.marks);
t('quit: 2 unsaved keepers', __lumina.unsaved() === 2, __lumina.unsaved());
__lumina.command('stepSave'); await W(950);
t('save: ⌘3 via luminaCommand', L().state.view === 'export', L().state.view);
__lumina.command('save'); await until(() => L().state.ex && L().state.ex.result, 8000);
const res = L().state.ex.result || {};
t('save: "2 saved"', res.t === '2 saved' && !res.bad, res);
const ls = await C('ls', { path: shoot }); const xmps = ls.filter(f => /\.xmp$/.test(f));
t('save: sidecars written into the folder', Object.keys(saved.marks).every(k => ls.includes(k.split('/').pop().replace(/\.ARW$/, '.xmp'))), ls);
const x1 = await C('read', { path: shoot + '/' + Object.keys(saved.marks)[0].replace(/\.ARW$/, '.xmp') });
t('save: rated 3★', /Rating="3"|<xmp:Rating>3</.test(x1 || ''), (x1 || '').slice(0, 200));
t('save: working-files row size known on Save', L().state.ex.wf != null, L().state.ex.wf);
t('quit: nothing unsaved after Save', __lumina.unsaved() === 0, __lumina.unsaved());
__lumina.command('finder'); await W(100); st = await C('state');
t('save: ⌘R reveals', st.revealed.length === 1, st.revealed);
__lumina.closeShoot(); await W(300);
t('close shoot: back to Open with the recent card', L().state.view === 'import' && L().recents().length === 1 && L().recents()[0].kp === 2, L().recents());
L().libOpen(L().recents()[0]);
await until(() => L().real && L().real.length && !L().state.realLoad && L().kept().length === 2, 20000);
t('reopen: 2 keepers restored, nothing unsaved', L().kept().length === 2 && __lumina.unsaved() === 0, [L().kept().length, __lumina.unsaved()]);
K('ArrowDown'); await W(150); K('ArrowDown'); await W(150); K('p'); await W(150);
__lumina.command('stepSave'); await W(950); __lumina.command('save');
await until(() => L().state.ex && L().state.ex.result, 8000);
const ls2 = await C('ls', { path: shoot });
t('save again: .lumina-bak next to replaced sidecars', ls2.filter(f => /\.xmp\.lumina-bak$/.test(f)).length >= 2, ls2.filter(f => /lumina-bak/.test(f)));
__lumina.command('stepCull'); await W(400);
await C('gone', { name: '2026-09-01', on: true }); __lumina.cardGone(['2026-09-01'], true); await W(150);
t('card: luminaCardGone(true) shows the banner state', L().state.gone === true, L().state.gone);
await C('gone', { name: '2026-09-01', on: false }); __lumina.cardBack(); await W(150);
t('card: luminaCardGone(false) on remount', L().state.gone === false, L().state.gone);
window.lumina.card = { name: 'Untitled', photos: 12 }; window.lumina.readingCard = true;
t('card: readingCard → page onCard()', L().onCard() === true); window.lumina.card = null; window.lumina.readingCard = false;
const lk = await C('folder', { name: 'Locked', files: [] }); await C('deny', { path: lk }); await C('pick', { path: lk }); __lumina.openFolder(); await W(300);
t('access: denied → luminaAccess banner', L().state.acc && L().state.acc.what === 'Locked', L().state.acc);
await C('deny', {}); await L().accRetry(); await W(300);
t('access: checkAccess → cleared', !L().state.acc, L().state.acc);
__lumina.command('stepCull'); await W(400);
__lumina.zoom(); await W(100); t('menu: Zoom 100% toggles on', L().state.zoom === true && L().state.large === true, [L().state.zoom, L().state.large]);
__lumina.zoom(); await W(100); t('menu: Zoom 100% toggles off', L().state.zoom === false, L().state.zoom);
t('no page errors', window.__errors.length === 0, window.__errors);
return out;
"""


def flow():
    ctl('reset')
    p = Page(app=True)
    ok(ready(p, True), 'flow: page ready')
    for r in p.js(FLOW, timeout=180):
        ok(r['ok'], 'flow: ' + r['n'], r.get('got'))
    p.close()


STATE = """const l = __probe.logic(), seen = new WeakSet();
return { state: JSON.parse(JSON.stringify(l.state, (k, v) => { if (typeof v === 'function') return undefined;
  if (v && typeof v === 'object') { if (v.nodeType || v instanceof Blob || ('current' in v && Object.keys(v).length === 1)) return undefined; if (seen.has(v)) return undefined; seen.add(v); } return v; })),
  order: l.data ? l.data.order.length : 0, real: !!l.real };"""


def run_screens(spec, app, d):
    os.makedirs(d, exist_ok=True)
    ctl('reset')
    p = Page(app=app, size=tuple(spec['size']), clock=spec.get('clock'), parity=app, storage_writes=spec.get('storageWrites', True))
    if not ready(p, app):
        raise RuntimeError('screens: page not ready')
    snaps, states, fails = {}, {}, []
    for i, s in enumerate(spec['steps']):
        try:
            if s['do'] == 'wait': wait(s.get('ms', 100))
            elif s['do'] == 'key':
                for _ in range(s.get('times', 1)): p.js('K(%s, %s)' % (json.dumps(s['k']), json.dumps({'cmd': s.get('cmd'), 'alt': s.get('alt'), 'shift': s.get('shift')})))
                wait(s.get('settleMs', 60))
            elif s['do'] == 'hold':
                p.js('K(%s, {up: false})' % json.dumps(s['k'])); wait(s.get('ms', 400))
                if s.get('snap'): snaps[s['snap']] = p.snap(os.path.join(d, s['snap'] + '.png'))
                p.js('K(%s, {down: false})' % json.dumps(s['k'])); wait(60)
            elif s['do'] == 'snap': snaps[s['name']] = p.snap(os.path.join(d, s['name'] + '.png'))
            elif s['do'] == 'state':
                states[s['name']] = p.js(STATE)
                json.dump(states[s['name']], open(os.path.join(d, s['name'] + '.state.json'), 'w'), indent=1)
            elif s['do'] == 'js': p.js(s['src'])
            elif s['do'] == 'expect':
                got = p.js(s['js'])
                if ('equals' in s and json.dumps(got) != json.dumps(s['equals'])) or ('equals' not in s and not got):
                    fails.append('step %d expect %s → %s' % (i, s['js'], json.dumps(got)))
            else: fails.append('step %d: %s not supported' % (i, s['do']))
        except Exception as e:
            fails.append('step %d %s: %s' % (i, s['do'], e))
    errs = p.js('return window.__errors')
    fails += ['page error: ' + e for e in errs]
    p.close()
    return snaps, states, fails


def screens():
    for name in ('screens-1440', 'screens-1920'):
        spec = json.load(open(os.path.join(SCEN, name + '.json')))
        a = run_screens(spec, False, os.path.join(OUT, name))
        b = run_screens(spec, True, os.path.join(OUT, name + '-app'))
        for m, r in (('design', a), ('app', b)):
            for f in r[2]:
                ok(False, '%s (%s) %s' % (name, m, f))
        for k, (w, h, px) in a[0].items():
            o = b[0].get(k)
            if not o:
                ok(False, '%s/%s.png missing in app' % (name, k)); continue
            if o[2] == px:
                ok(True, '%s/%s.png identical' % (name, k)); continue
            n = sum(1 for i in range(0, min(len(px), len(o[2])), 4) if px[i:i + 3] != o[2][i:i + 3])
            ok(False, '%s/%s.png differs' % (name, k), '%d px' % n)
        for k, v in a[1].items():
            same = json.dumps(v) == json.dumps(b[1].get(k))
            keys = [] if same else [x for x in set(v['state']) | set((b[1].get(k) or {}).get('state', {})) if json.dumps(v['state'].get(x)) != json.dumps((b[1].get(k) or {}).get('state', {}).get(x))]
            ok(same, '%s/%s.state.json identical' % (name, k), keys)


if __name__ == '__main__':
    server = subprocess.Popen(['node', os.path.join(ROOT, 'Tests/web/webkit-server.mjs'), str(PORT), os.path.join(OUT, 'work')], stdout=subprocess.PIPE, text=True)
    line = server.stdout.readline()
    if not line.startswith('ready'):
        sys.exit('server failed: ' + line)
    try:
        for s in suites:
            print('— ' + s, flush=True)
            {'contract': contract, 'selftest': selftest, 'flow': flow, 'screens': screens}[s]()
    finally:
        server.terminate()
    print(('%d FAIL' % len(FAILS)) if FAILS else 'all ok', '· evidence in', OUT)
    sys.exit(1 if FAILS else 0)
