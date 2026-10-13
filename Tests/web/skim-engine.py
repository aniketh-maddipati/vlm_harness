#!/usr/bin/env python3
"""The Skim web preview built and run in Safari's engine: the check CI calls "Skim in WebKit" and
"Skim in Safari".

Builds the one-file preview (Scripts/build-skim-preview.py, what lumina-skim.pages.dev serves), serves
it on 127.0.0.1 with the clips in Tests/web/fixtures/skim-clips, and runs Tests/web/skim-engine-check.js
inside the page: the same steps in either engine.

  xvfb-run -a -s "-screen 0 1600x1000x24" /usr/bin/python3 Tests/web/skim-engine.py webkitgtk
      WebKitGTK (apt: gir1.2-webkit2-4.1 python3-gi gstreamer1.0-libav gstreamer1.0-plugins-good
      gstreamer1.0-plugins-bad). A real window: WebKitGTK doesn't load media in an offscreen one.
  python3 Tests/web/skim-engine.py safari
      Safari through safaridriver (macOS; once per Mac: sudo safaridriver --enable).

Bounded: LUMINA_WEB_LIMIT seconds (default 300), then FAIL and exit 124.
"""
import functools, http.server, json, os, shutil, signal, socket, subprocess, sys, tempfile, threading, time, urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
CLIPS = os.path.join(ROOT, 'Tests/web/fixtures/skim-clips')
CHECK = os.path.join(ROOT, 'Tests/web/skim-engine-check.js')
# Page errors from the first script on, in any engine (a driver can't always inject at document start).
CATCH = ('<script>window.__errors = []; addEventListener("error", e => __errors.push(String(e.message) + (e.filename ? " @ " + e.filename + ":" + e.lineno : "")));'
         ' addEventListener("unhandledrejection", e => __errors.push("rejection: " + String(e.reason && e.reason.message || e.reason)));</script>\n'
         '<script src="skim-engine-check.js"></script>\n')


def site():
    """A temp folder with the preview (error catcher first), the check and the clips; returns (dir, clip names)."""
    d = tempfile.mkdtemp(prefix='skim-engine-')
    page = os.path.join(d, 'preview.html')
    subprocess.run([sys.executable, os.path.join(ROOT, 'Scripts/build-skim-preview.py'), page], check=True, stdout=subprocess.DEVNULL)
    html = open(page, encoding='utf-8').read()
    i = html.index('<script')
    open(page, 'w', encoding='utf-8').write(html[:i] + CATCH + html[i:])
    shutil.copy(CHECK, d)
    shutil.copytree(CLIPS, os.path.join(d, 'clips'))
    return d, sorted(os.listdir(CLIPS))


def serve(d):
    class H(http.server.SimpleHTTPRequestHandler):
        extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, '.MP4': 'video/mp4', '.mp4': 'video/mp4', '.js': 'text/javascript'}
        def log_message(self, *a): pass
    srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(H, directory=d))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, 'http://127.0.0.1:%d/preview.html' % srv.server_address[1]


def webkitgtk(url, names):
    import gi
    gi.require_version('Gtk', '3.0')
    gi.require_version('WebKit2', '4.1')
    from gi.repository import Gtk, WebKit2

    def spin(cond, secs):
        end = time.time() + secs
        while time.time() < end:
            while Gtk.events_pending():
                Gtk.main_iteration_do(False)
            if cond():
                return True
            time.sleep(0.01)
        return False
    view, win = WebKit2.WebView(), Gtk.Window()
    win.set_default_size(1440, 900)
    win.add(view)
    win.show_all()
    view.load_uri(url)
    if not spin(lambda: view.get_estimated_load_progress() >= 1, 30):
        raise RuntimeError('the page did not load')
    box = {}

    def done(v, res):
        try:
            box['v'] = json.loads(v.call_async_javascript_function_finish(res).to_string())
        except Exception as e:
            box['e'] = str(e)
    view.call_async_javascript_function('return (async () => JSON.stringify(await window.__skimEngineCheck(%s)))();' % json.dumps(names), -1, None, None, None, None, done)
    spin(lambda: box, 180)
    if 'e' in box or 'v' not in box:
        raise RuntimeError(box.get('e', 'the check did not answer within 180 s'))
    return box['v'], 'WebKitGTK %d.%d' % (WebKit2.get_major_version(), WebKit2.get_minor_version())


def safari(url, names):
    """W3C WebDriver over HTTP to safaridriver: one session, the check as an async script."""
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
    drv = subprocess.Popen(['safaridriver', '-p', str(port)])
    base = 'http://127.0.0.1:%d' % port
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))   # 127.0.0.1, never through a proxy

    def wd(method, path, body=None):
        req = urllib.request.Request(base + path, method=method, data=None if body is None else json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
        with opener.open(req, timeout=200) as r:
            return json.loads(r.read() or b'{}').get('value')
    sid = None
    try:
        for _ in range(50):
            try:
                wd('GET', '/status')
                break
            except OSError:
                time.sleep(0.2)
        sid = wd('POST', '/session', {'capabilities': {'alwaysMatch': {'browserName': 'safari'}}})['sessionId']
        wd('POST', '/session/%s/timeouts' % sid, {'script': 180000, 'pageLoad': 30000})
        wd('POST', '/session/%s/url' % sid, {'url': url})
        res = wd('POST', '/session/%s/execute/async' % sid, {
            'script': 'const done = arguments[arguments.length - 1]; window.__skimEngineCheck(arguments[0]).then(r => done(JSON.stringify(r)), e => done(JSON.stringify({steps: [[false, "the check threw: " + e]], errors: []})));',
            'args': [names]})
        version = subprocess.run(['defaults', 'read', '/Applications/Safari.app/Contents/Info', 'CFBundleShortVersionString'], capture_output=True, text=True).stdout.strip()
        return json.loads(res), 'Safari ' + version
    finally:
        if sid:
            try:
                wd('DELETE', '/session/' + sid)
            except Exception:
                pass
        drv.terminate()


def main():
    engine = (sys.argv[1:] or ['webkitgtk'])[0]
    if engine not in ('webkitgtk', 'safari'):
        sys.exit('usage: skim-engine.py webkitgtk|safari')
    limit = int(os.environ.get('LUMINA_WEB_LIMIT') or 300)
    signal.signal(signal.SIGALRM, lambda *_: (print('FAIL  skim-engine.py reached its limit of %d s and was stopped' % limit, flush=True), os._exit(124)))
    signal.alarm(limit)
    d, names = site()
    srv, url = serve(d)
    try:
        out, name = (webkitgtk if engine == 'webkitgtk' else safari)(url, names)
    finally:
        srv.shutdown()
        shutil.rmtree(d, ignore_errors=True)
    print('— Skim web preview in %s (%s)' % (name, out.get('ua', '')))
    fails = 0
    for good, what in out['steps']:
        print(('ok    ' if good else 'FAIL  ') + what)
        fails += not good
    print('%d FAIL' % fails if fails else 'all ok')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
