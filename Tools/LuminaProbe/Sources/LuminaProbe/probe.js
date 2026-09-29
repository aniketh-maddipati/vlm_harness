// Injected at document start by lumina-probe. Test-only: never ships in the app.
(() => {
  const cfg = window.__probeConfig || {};
  const post = (kind, payload) => {
    try { window.webkit.messageHandlers.probe.postMessage({ kind, payload }); } catch (_) {}
  };

  // Fixed clock: wall time starts at cfg.clockBase and advances in real time, so
  // "last export HH:MM" and every Date.now() gap in the page keep their meaning.
  if (cfg.clockBase) {
    const RealDate = Date, t0 = RealDate.now(), base = cfg.clockBase;
    const now = () => base + (RealDate.now() - t0);
    class ProbeDate extends RealDate {
      constructor(...a) { if (a.length === 0) super(now()); else super(...a); }
      static now() { return now(); }
    }
    window.Date = ProbeDate;
  }

  // Vendored React / Babel through support.js's own hook; page bytes stay unchanged.
  if (cfg.resources) window.__resources = Object.assign(window.__resources || {}, cfg.resources);

  // Errors and console. Anything at error level fails the run.
  const fmt = a => a.map(x => {
    if (x instanceof Error) return x.name + ': ' + x.message + (x.stack ? '\n' + x.stack : '');
    if (typeof x === 'object') { try { return JSON.stringify(x); } catch (_) { return String(x); } }
    return String(x);
  }).join(' ');
  for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
    const orig = console[level].bind(console);
    console[level] = (...a) => { post('console', { level, text: fmt(a) }); orig(...a); };
  }
  window.addEventListener('error', e => post('pageerror', { text: (e.error && e.error.stack) || e.message, src: e.filename, line: e.lineno }));
  window.addEventListener('unhandledrejection', e => post('pageerror', { text: 'unhandled rejection: ' + fmt([e.reason]) }));

  // Frame pacing: every rAF gap is recorded while a window is open.
  const frames = { on: false, gaps: [], last: 0 };
  const tick = t => { if (frames.on) { if (frames.last) frames.gaps.push(t - frames.last); frames.last = t; } requestAnimationFrame(tick); };
  requestAnimationFrame(tick);

  const fiberKey = el => Object.keys(el).find(k => k.startsWith('__reactFiber$'));
  const P = {
    // The DC host whose logic is the page's Component (has onKey + state.view).
    host() {
      const roots = document.querySelectorAll('[data-screen-label], body *');
      for (const el of roots) {
        const k = fiberKey(el); if (!k) continue;
        for (let f = el[k]; f; f = f.return) {
          const sn = f.stateNode;
          if (sn && sn.logic && typeof sn.logic.onKey === 'function' && sn.logic.state && 'view' in sn.logic.state) return sn;
        }
      }
      return null;
    },
    logic() { const h = P.host(); return h && h.logic; },
    ready() { const l = P.logic(); return !!(l && l.data && document.querySelector('[data-screen-label]') && (!window.__lumina || (window.__lumina.ready && window.__lumina.ready()))); },
    // JSON-safe copy of the page state: functions, DOM nodes and refs dropped.
    state() {
      const h = P.host(); if (!h) return null;
      const l = h.logic, seen = new WeakSet();
      const clean = JSON.parse(JSON.stringify(l.state, (k, v) => {
        if (typeof v === 'function') return undefined;
        if (v && typeof v === 'object') {
          if (v.nodeType || v instanceof Blob || ('current' in v && Object.keys(v).length === 1)) return undefined;
          if (seen.has(v)) return undefined; seen.add(v);
        }
        return v;
      }));
      return { state: clean, hostError: h.state && h.state.__err || null, order: l.data ? l.data.order.length : 0, real: !!l.real };
    },
    // Rects to ignore in pixel diffs: every <img> and every element painting a url() background.
    masks() {
      const out = [];
      for (const el of document.querySelectorAll('*')) {
        const isImg = el.tagName === 'IMG' || el.tagName === 'CANVAS' || el.tagName === 'VIDEO';
        const bg = !isImg && getComputedStyle(el).backgroundImage;
        if (!isImg && !(bg && bg.includes('url('))) continue;
        const r = el.getBoundingClientRect();
        if (r.width < 1 || r.height < 1) continue;
        out.push({ x: r.left, y: r.top, w: r.width, h: r.height });
      }
      return out;
    },
    rect(sel) { const el = document.querySelector(sel); if (!el) return null; const r = el.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; },
    // Invariants that must hold after every action. A violation is a bug even if nothing crashed.
    invariants() {
      const v = [], h = P.host();
      if (!h) return ['page host missing'];
      if (h.state && h.state.__err) v.push('render error: ' + h.state.__err);
      const l = h.logic, s = l.state, d = l.data;
      if (!d) return v.concat('no data');
      const views = ['import', 'cull', 'edit', 'narrow', 'write', 'export'];
      if (!views.includes(s.view)) v.push('unknown view ' + s.view);
      if (s.cur != null && !d.byId[s.cur]) v.push('cur not in shoot: ' + s.cur);
      for (const map of ['marks', 'final', 'auto', 'rA', 'rO', 'sel']) {
        for (const id of Object.keys(s[map] || {})) if (!d.byId[id]) { v.push(map + ' has unknown id ' + id); break; }
      }
      for (const [id, m] of Object.entries(s.marks || {})) if (m !== 'keep' && m !== 'out' && m !== null) { v.push('bad mark ' + id + '=' + m); break; }
      if (!Array.isArray(s.undo)) v.push('undo is not a list');
      if (d.order.length !== new Set(d.order).size) v.push('duplicate ids in order');
      if (window.__lumina && window.__lumina.inspect) return P.appInvariants(v);
      return v;
    },
    // App mode: the page's state surface (__lumina.inspect) and the Mac's reader must agree.
    async appInvariants(v) {
      const i = window.__lumina.inspect();
      if (i.real) {
        if (i.lgHeld) v.push(i.lgHeld + ' large previews held by the page (must be lumina:// URLs)');
        if (i.zsrcOff) v.push(i.zsrcOff + ' photos zoom a different image than their large view');
        if (i.srcNotBlob) v.push(i.srcNotBlob + ' grid thumbnails not held by the page');
        if (i.dupPaths) v.push(i.dupPaths + ' photos share a file path');
        if (i.order !== i.real) v.push('shoot has ' + i.order + ' photos but ' + i.real + ' were read');
      }
      if (i.reading) {
        const r = i.reading;
        if (r.done < 0 || r.done > r.total) v.push('read progress ' + r.done + ' / ' + r.total);
        if (i.realLoad && i.realLoad.total !== r.total) v.push('page shows ' + i.realLoad.total + ' to read, the listing has ' + r.total);
      }
      const lr = i.lastRead, info = i.realInfo;
      if (!i.reading && lr && info && info.name === lr.name && lr.read) {
        if (info.n !== lr.read) v.push('page says ' + info.n + ' photos, the read kept ' + lr.read);
        if (info.n + info.bad !== lr.total) v.push(info.n + ' read + ' + info.bad + ' unreadable ≠ ' + lr.total + ' listed');
        if (lr.stopped && !lr.read) v.push('stopped read left photos behind');
      }
      if (lr && window.lumina.read && window.lumina.read.total !== lr.total) v.push('lumina.read disagrees with the last read');
      const n = await window.__lumina.nativeStats();
      if (n) {
        if (n.opensAfterGone) v.push(n.opensAfterGone + ' files opened after their card was pulled');
        if (n.maxInFlight > n.workers + 2) v.push(n.maxInFlight + ' reads at once (limit ' + n.workers + ' + 2 prefetch)');
        if (n.largestRead > (16 << 20)) v.push('a ' + (n.largestRead >> 20) + ' MB read: ingest must never read a whole RAW');
        if (!i.reading && i.card === null && i.lastRead && n.gone.length === 0 && i.lastRead.stopped) v.push('read stopped for a pulled card, but the reader never marked it gone');
      }
      return v;
    },
    framesStart() { frames.on = true; frames.gaps = []; frames.last = 0; },
    framesStop() {
      frames.on = false; const g = frames.gaps.slice().sort((a, b) => a - b);
      const pct = p => g.length ? g[Math.min(g.length - 1, Math.floor(p * g.length))] : 0;
      return { frames: g.length, p50: pct(0.5), p95: pct(0.95), p99: pct(0.99), max: g.length ? g[g.length - 1] : 0, over33: g.filter(x => x > 33.4).length };
    },
  };
  window.__probe = P;
  post('boot', { href: location.href });
})();
