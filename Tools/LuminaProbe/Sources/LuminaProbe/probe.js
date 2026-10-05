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

  // "storageWrites": false in a scenario: the page's own localStorage writes fail, as they do in
  // the app (it persists through plumbing.js instead). Screens that show the browser-only "saved"
  // label would otherwise never match their app twin.
  // v7 shows its five-step tour on a first launch, and the tour takes every key. A scenario starts
  // past it unless it asks for it ("tour": true), as a second launch does.
  if (!cfg.tour) { try { localStorage.setItem('lumina-v4-toured', '1'); } catch (_) {} }
  if (cfg.noStorageWrites) { try { Storage.prototype.setItem = function () { throw new DOMException('probe: storage writes off', 'QuotaExceededError'); }; } catch (_) {} }

  // Vendored React / Babel through support.js's own hook; page bytes stay unchanged.
  if (cfg.resources) window.__resources = Object.assign(window.__resources || {}, cfg.resources);

  // No system drags. A tile is draggable (GRAMMAR "Drop"), so a synthetic mouse drag over one makes
  // WebKit start a real drag session: macOS draws its drag image on the user's screen, writes the
  // drag pasteboard, and tracks the real pointer (not the probe's events), so the session can sit
  // open for minutes. The drag is refused before the page sees it; the page's own mouse-driven
  // drags (marquee, paint, row boundary, stack edge) are unaffected.
  window.addEventListener('dragstart', e => { e.preventDefault(); e.stopImmediatePropagation(); post('drag', { refused: (e.target && e.target.getAttribute && e.target.getAttribute('data-lumina')) || 'element' }); }, true);

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
  const tick = t => { if (frames.on) { if (frames.last) frames.gaps.push(t - frames.last); frames.last = t; } if (tiles.on) tileSample(); requestAnimationFrame(tick); };
  requestAnimationFrame(tick);

  // Cull tiles while scrolling, sampled every frame: how many on-screen tiles the layout expects,
  // how many show a loaded, fully faded-in thumbnail, and each shown thumbnail's upscale ratio
  // (image px per device px: < 1 means the thumbnail is magnified on screen).
  // Rows too: an on-screen row drawn at another height or place than the layout gives it (over 1 px)
  // is a row caught mid-animation, e.g. an element reused for the next row when the window moves.
  const tiles = { on: false, n: 0, expect: 0, blank: 0, blankFrames: 0, worst: 0, ratios: [], rows: 0, rowsOff: 0, rowFrames: 0, rowWorst: 0 };
  const cullEl = () => document.querySelector('[data-screen-label="1 Cull"]');
  const tileSample = () => {
    const l = P.logic(), el = cullEl();
    if (!l || !el || !l.layout || l.state.view !== 'cull') return;
    const L = l.layout(), top = el.scrollTop, bot = top + el.clientHeight, byId = l.data.byId;
    let expect = 0;
    for (let i = 0; i < L.cells.length; i++) {
      const y = l.cellY(i), c = L.cells[i];
      if (y == null || y + L.TH < top || y > bot) continue;
      const f = byId[c.id]; if (f && f.src && !f.nopv) expect++;
    }
    const vr = el.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    let ready = 0;
    for (const im of el.querySelectorAll('img')) {
      const r = im.getBoundingClientRect();
      if (r.bottom < vr.top || r.top > vr.bottom || r.width < 8) continue;
      if (!(im.complete && im.naturalWidth > 0 && parseFloat(getComputedStyle(im).opacity) > 0.99)) continue;
      ready++;
      const fit = getComputedStyle(im).objectFit, sx = r.width / im.naturalWidth, sy = r.height / im.naturalHeight;
      const s = fit === 'cover' ? Math.max(sx, sy) : Math.min(sx, sy);
      if (tiles.ratios.length < 20000) tiles.ratios.push(1 / (s * dpr));
    }
    const rowAt = {}; for (const r of L.rows) rowAt[r.r.id] = r;
    let rowsOff = 0;
    for (const d of el.querySelectorAll('[data-lumina="row"][data-row]')) {
      const r = d.getBoundingClientRect(), w = rowAt[d.getAttribute('data-row')];
      if (!w || r.bottom < vr.top || r.top > vr.bottom) continue;
      const off = Math.max(Math.abs(r.height - w.h), Math.abs(r.top - vr.top + top - w.y));
      tiles.rows++; if (off > 1) { rowsOff++; tiles.rowWorst = Math.max(tiles.rowWorst, off); }
    }
    tiles.rowsOff += rowsOff; if (rowsOff) tiles.rowFrames++;
    const blank = Math.max(0, expect - ready);
    tiles.n++; tiles.expect += expect; tiles.blank += blank;
    if (blank) tiles.blankFrames++;
    if (expect) tiles.worst = Math.max(tiles.worst, blank / expect);
  };

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
    // The header's working-files meter is masked in every snapshot: the page keeps its total for 1 s
    // while previews load and fades its cells over 360 ms, so the moment of the snapshot decides what
    // it shows, a different moment in each twin. Its contents are hidden for the snapshot (the pill's
    // background stays); the screens compare everything else byte for byte. Its numbers are checked
    // through state instead.
    async meterMask(on) {
      let el = document.getElementById('__probe-meter-mask');
      if (on && !el) { el = document.createElement('style'); el.id = '__probe-meter-mask'; el.textContent = '[data-lumina="cache-pill"] > * { visibility: hidden !important; }'; document.head.appendChild(el); }
      if (!on && el) el.remove();
      await new Promise(r => { let n = 0; const done = () => { if (!n++) r(); }; requestAnimationFrame(() => requestAnimationFrame(done)); setTimeout(done, 100); });
      return true;
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
    tilesStart() { Object.assign(tiles, { on: true, n: 0, expect: 0, blank: 0, blankFrames: 0, worst: 0, ratios: [], rows: 0, rowsOff: 0, rowFrames: 0, rowWorst: 0 }); },
    tilesStop() {
      tiles.on = false; const r = tiles.ratios.slice().sort((a, b) => a - b), q = p => r.length ? +r[Math.min(r.length - 1, Math.floor(p * r.length))].toFixed(3) : 0;
      return { samples: tiles.n, blankPct: tiles.expect ? +(100 * tiles.blank / tiles.expect).toFixed(2) : 0, blankFramesPct: tiles.n ? +(100 * tiles.blankFrames / tiles.n).toFixed(1) : 0,
        worstBlankPct: +(100 * tiles.worst).toFixed(1), rowsOffPct: tiles.rows ? +(100 * tiles.rowsOff / tiles.rows).toFixed(2) : 0,
        rowFramesPct: tiles.n ? +(100 * tiles.rowFrames / tiles.n).toFixed(1) : 0, rowWorstPx: Math.round(tiles.rowWorst), upscaleMin: q(0), upscaleP10: q(0.1), upscaleMedian: q(0.5), dpr: window.devicePixelRatio || 1,
        tile: (() => { const l = P.logic(); if (!l || !l.layout) return 0; return l.layout().TW; })() };
    },
    // What happens when a folder read ends: the cursor's file just before and 2 s after, and how far
    // the app scrolled by itself in those 2 s (appScroll: scrolling within 400 ms of the reader's own
    // wheel, key or scrollFrames input isn't counted). Also when the reader's input came relative to
    // the end, so a read that ended before the reader did anything reads as that, not as a pass or a
    // jump. __probe.readEnd() is null until then.
    watchReadEnd() {
      const l = P.logic(), el = cullEl(), t0 = performance.now(); window.__readEnd = null; let last = null, keysBefore = 0, keysAfter = 0, endAt = 0;
      const mark = () => { window.__probeScrollT = performance.now(); };
      addEventListener('wheel', mark, { capture: true, passive: true });
      addEventListener('keydown', () => { mark(); if (endAt) keysAfter++; else keysBefore++; }, true);
      const at = () => ({ top: Math.round(el.scrollTop), cur: ((l.data.byId[l.state.cur] || {}).path) || null });
      const f = () => {
        if (l.state.realLoad) { last = at(); requestAnimationFrame(f); return; }
        endAt = performance.now(); let app = 0, prev = el.scrollTop;
        const g = () => { const now = performance.now(), d = Math.abs(el.scrollTop - prev); prev = el.scrollTop;
          if (now - (window.__probeScrollT || 0) > 400) app += d;
          if (now - endAt < 2000) requestAnimationFrame(g);
          else { const after = at(); window.__readEnd = { before: last, after, appScroll: Math.round(app), keysBefore, keysAfter,
            endedAfterMs: Math.round(endAt - t0), photos: l.real ? l.real.length : 0,
            ok: keysBefore > 0 ? !!(last && after.cur === last.cur && app < 200) : null }; } };
        g();
      };
      f(); return true;
    },
    readEnd() { return window.__readEnd || null; },
    // Scroll Cull by `dy` CSS px per frame for `frames` frames (sandboxes without native wheel events).
    async scrollFrames(frames, dy) {
      const el = cullEl(); if (!el) return false;
      for (let i = 0; i < frames; i++) { el.scrollTop += dy; window.__probeScrollT = performance.now(); await new Promise(r => requestAnimationFrame(r)); }
      return true;
    },
  };
  window.__probe = P;
  post('boot', { href: location.href });
})();
