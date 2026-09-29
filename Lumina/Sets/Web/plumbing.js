// Lumina app plumbing. Injected at document start into the design's page, which ships byte-identical.
// This file is the only place the app differs from the prototype: it swaps the page's browser I/O
// (BUILD-exact rule 2: openFolder / writeInto / renderJpg / download keep their names, only the
// insides change) for calls to the native bridge. Layout, styles, copy and keys are untouched.
(() => {
  // sample: keep the design's sample shoot (debug fixture data). Off in release: start empty.
  const cfg = Object.assign({ sample: true }, window.__luminaConfig || {});
  const native = (op, args) => window.webkit.messageHandlers.lumina.postMessage(Object.assign({ op }, args || {}));

  // The page only offers RAW copies when a directory picker exists (a Chrome-tab check). The Mac
  // app always has one: writeInto below picks the folder natively, so this is never called.
  if (!window.showDirectoryPicker) window.showDirectoryPicker = () => Promise.reject(new DOMException('native', 'AbortError'));

  const b64 = u8 => {
    let s = '';
    for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
    return btoa(s);
  };
  const relPath = f => (f && (f.webkitRelativePath || f.name)) || '';

  // Native ingest (the page's onDir, read by the Mac). The listing arrives first; each file then
  // gives a 256 KB head that the page's own parseHead reads, and its embedded preview, read by
  // byte range and turned upright by the Mac, which the page resizes and measures exactly as
  // before. The page keeps only a lumina:// URL for the large view (the Mac caches around the
  // cursor). Same origin, so canvases stay clean.
  class Gone extends Error {}
  const media = (kind, q) => new URL('/media/' + kind + '?' + new URLSearchParams(q).toString(), location.href).href;
  const get = async url => {
    const r = await fetch(url);
    if (r.status === 410) throw new Gone('card removed');
    if (!r.ok) throw new Error((await r.text()) || 'HTTP ' + r.status);
    return r;
  };
  const previewOf = lg => {
    try { const u = new URL(lg); return u.pathname === '/media/preview' ? Object.fromEntries(u.searchParams) : null; } catch (_) { return null; }
  };
  // Stands in for the File the page kept per photo: the same relative path, no bytes.
  const fileRef = f => ({ name: f.rel.split('/').pop(), size: f.size, webkitRelativePath: f.rel, __luminaRel: f.rel });
  let reading = null, lastRead = null;

  // Everything below leans on these page members. A design sync that renames one shows up here
  // (and in the probe's plumbing-contract scenario) instead of as a silent break.
  const REQUIRED = ['onKey', 'setState', 'setView', 'say', 'undo', 'openFolder', 'onDir', 'writeInto', 'renderJpg',
    'impStart', 'impSet', 'simCard', 'libOpen', 'build', 'cssR', 'eff', 'forget', 'saveGolden'];
  const missing = logic => REQUIRED.filter(k => typeof logic[k] !== 'function').concat(
    logic.constructor && Array.isArray(logic.constructor.SHOOTS) ? [] : ['static SHOOTS'],
    ['parseHead', 'measure'].filter(k => typeof (logic.constructor || {})[k] !== 'function').map(k => 'static ' + k));
  // The native read (below) repeats the page's onDir step for step. When a design sync changes
  // onDir, the contract check reports it here so the repeat gets reviewed; the app keeps working.
  const ONDIR = 1642218538;
  const fnv = t => { let h = 0x811c9dc5; for (let i = 0; i < t.length; i++) { h ^= t.charCodeAt(i); h = Math.imul(h, 0x01000193); } return h >>> 0; };
  const drift = logic => {
    const proto = logic && Object.getPrototypeOf(logic), h = proto && typeof proto.onDir === 'function' ? fnv(proto.onDir.toString()) : 0;
    return h === ONDIR ? [] : ['onDir changed (fnv ' + h + '): review the native read in plumbing.js'];
  };

  // Decisions saved per shoot, keyed by file path so they survive files being added.
  const BY_ID = ['marks', 'final', 'auto', 'rA', 'rO', 'caps', 'cuts', 'texts'];
  const SCALAR = ['title', 'sub', 'body', 'foot', 'lastEx', 'ex'];
  let shootId = null, lastSaved = '', cardPulledWhileReading = false;
  // Path inside the opened folder ("sub/DSC00001.ARW"): stable across reopen and new files.
  const keyOf = p => { const r = (p && p.fileObj && p.fileObj.webkitRelativePath) || ''; return r ? r.split('/').slice(1).join('/') : (p && p.file) || ''; };
  const pathOf = (logic, id) => keyOf(logic.data && logic.data.byId[id]);
  const snapshot = logic => {
    const s = logic.state, out = { v: 1, cur: pathOf(logic, s.cur) || null };
    for (const k of BY_ID) { const m = {}; for (const [id, v] of Object.entries(s[k] || {})) { const p = pathOf(logic, id); if (p) m[p] = v; } out[k] = m; }
    for (const k of SCALAR) if (s[k] !== undefined) out[k] = s[k];
    return out;
  };
  const restore = (logic, saved) => {
    const idOf = {}; for (const [id, p] of Object.entries(logic.data.byId)) idOf[keyOf(p)] = id;
    const patchState = {};
    for (const k of BY_ID) { const m = {}; for (const [p, v] of Object.entries(saved[k] || {})) if (idOf[p]) m[idOf[p]] = v; patchState[k] = m; }
    for (const k of SCALAR) if (saved[k] !== undefined) patchState[k] = saved[k];
    if (Object.keys(patchState.cuts || {}).length) logic.data = logic.build(patchState.cuts);
    const cur = saved.cur && idOf[saved.cur];
    if (cur) Object.assign(patchState, { cur, node: logic.data.sub[cur], lvl: 'photo' });
    logic.setState(patchState);
  };
  const saveLoop = () => {
    try {
      const l = current;
      if (l && l.real && shootId) {
        const json = JSON.stringify(snapshot(l));
        if (json !== lastSaved) { lastSaved = json; native('saveSession', { id: shootId, json }); }
      }
    } finally { setTimeout(saveLoop, 800); }
  };

  // The data contract the design can read (DESIGN-ASKS §contract). Absent in the browser prototype,
  // so the design falls back to its sample; present in the app with real values.
  window.lumina = Object.assign(window.lumina || {}, {
    app: true, debug: !!cfg.debug, persisted: true,
    card: null,            // { name, photos, bytes, sony } while a card is in, else null
    read: null,            // the last folder read: { name, total, read, unreadable, stopped: 'card removed' | null }
    shoots: [],            // recent real shoots: { id, t, d, cam, n, src, where }
    open: id => native('reopen', { id }),
    // Lumina's own files for the open shoot (never RAWs or .xmp): size in bytes, and remove.
    workingFiles: () => shootId ? native('workingFiles', { id: shootId }) : Promise.resolve(0),
    removeWorkingFiles: () => shootId ? native('removeShoot', { id: shootId }).then(ok => { shootId = null; lastSaved = ''; return ok; }) : Promise.resolve(false),
  });

  let sampleShoots = null;
  const loadRecents = async logic => {
    const list = await native('recents', {});
    if (sampleShoots === null) sampleShoots = cfg.sample ? (logic.constructor.SHOOTS || []).slice() : [];
    if (Array.isArray(list)) window.lumina.shoots = list;
    if (Array.isArray(list) && logic.constructor) logic.constructor.SHOOTS = list.concat(sampleShoots);
    logic.forceUpdate && logic.forceUpdate();
  };

  const patch = logic => {
    if (logic.__luminaPlumbed) return;
    logic.__luminaPlumbed = true;
    const gaps = missing(logic);
    if (gaps.length) { native('ready', { missing: gaps }); return; }

    // After a folder is read: remember the shoot and bring its decisions back.
    const afterRead = async () => {
      if (!logic.real) return;
      const first = logic.real.map(p => p.date).filter(Boolean).sort()[0] || '';
      const r = await native('shootOpened', { name: (logic.state.realInfo || {}).name, n: logic.real.length, date: first });
      shootId = r && r.id; lastSaved = '';
      if (r && r.session) { try { restore(logic, JSON.parse(r.session)); } catch (_) {} }
      lastSaved = JSON.stringify(snapshot(logic));
      loadRecents(logic);
    };

    // Opening a folder reads it natively. The steps and wording after the read are the page's own
    // onDir, unchanged; only where the bytes come from differs.
    logic.openFolder = async () => {
      if (reading) return;                                   // one read at a time
      const L = await native('openFolder', {});
      if (!L) return;                                        // cancelled
      await ingest(L);
      await afterRead();
    };
    const ingest = async L => {
      const C = logic.constructor, xmpMap = {};
      // One sidecar per RAW. On a case-sensitive disk both DSC.xmp and DSC.XMP can exist: the
      // lower-case .xmp wins (Adobe's name, and the one the page gives new sidecars), else the first
      // by name, never whichever was listed last. The other file is never read or written.
      const sidecars = (L.xmp || []).slice().sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));
      for (const x of sidecars) {
        const k = x.rel.replace(/\.[^.\/]+$/, '').toLowerCase(), had = xmpMap[k];
        if (!had || (/\.xmp$/.test(x.rel) && !/\.xmp$/.test(had.path))) xmpMap[k] = { tx: x.text, path: x.rel };
      }
      const files = (L.files || []).slice().sort((a, b) => a.rel.localeCompare(b.rel));
      if (!files.length) return logic.say('no ARW files in that folder');
      const run = reading = { name: L.name, total: files.length, done: 0, gone: false };
      const t0 = performance.now(), out = []; let done = 0, i = 0; logic._gold = [];
      logic.setState({ realLoad: { done: 0, total: files.length, t0 } });
      const one = async f => {
        const name = f.rel.split('/').pop();
        try {
          const head = new Uint8Array(await (await get(media('head', { p: f.rel }))).arrayBuffer());
          const m = C.parseHead(head, f.size) || {}; if (!m.preview) throw new Error('no preview');
          const ori = m.orient || 1, pq = { p: f.rel, o: m.preview[0], l: m.preview[1], ori };
          // The preview passes through once, as stored, for the page's own steps: turn on a canvas,
          // resize, measure. Then only its URL is kept (the Mac serves it upright for the large view).
          let blob = await (await get(media('preview', Object.assign({}, pq, { ori: 1 })))).blob();
          if (ori === 3 || ori === 6 || ori === 8) { const b0 = await createImageBitmap(blob, { imageOrientation: 'none' }), sw = ori !== 3, c = document.createElement('canvas'); c.width = sw ? b0.height : b0.width; c.height = sw ? b0.width : b0.height; const x = c.getContext('2d'); x.translate(c.width / 2, c.height / 2); x.rotate(ori === 6 ? Math.PI / 2 : ori === 8 ? -Math.PI / 2 : Math.PI); x.drawImage(b0, -b0.width / 2, -b0.height / 2); b0.close(); blob = await new Promise(res => c.toBlob(res, 'image/jpeg', 0.92)); }
          const sm = await createImageBitmap(blob, { resizeWidth: 360, resizeQuality: 'medium' }), portrait = sm.height > sm.width, me = C.measure(sm); sm.close();
          const tb = await new Promise(res => me.canvas.toBlob(res, 'image/jpeg', 0.82));
          logic._gold.push({ file: name, size: f.size, parsed: { date: m.date || null, exp: m.exp ?? null, fl: m.fl ?? null, ev: m.ev ?? null, iso: m.iso ?? null, orient: m.orient || 1, preview: m.preview } });
          const xk = f.rel.replace(/\.[^.\/]+$/, '').toLowerCase(), xo = xmpMap[xk] || null, xt = xo && xo.tx,
            xpath = xo ? xo.path : f.rel.replace(/\.[^.\/]+$/, '') + '.xmp', lrEd = LuminaCore.hasDevelop(xt);
          out.push({ fileObj: fileRef(f), xpath, xmp: xt, lrEd, portrait, orient: ori, name, path: f.rel, date: m.date || '', exp: m.exp, fl: m.fl, ev: m.ev, iso: m.iso,
            lum: me.lum, focus: me.focus, clip: me.clip, src: URL.createObjectURL(tb), lg: media('preview', pq) });
        } catch (err) {
          if (err instanceof Gone) run.gone = true;
          out.push({ name, path: f.rel, err: err.message });
        }
        done++; run.done = done;
        if (done % 8 === 0 || done === files.length) logic.setState({ realLoad: { done, total: files.length, t0 } });
      };
      await Promise.all(Array.from({ length: Math.max(1, L.workers || 4) }, async () => { while (i < files.length && !run.gone) await one(files[i++]); }));
      // Card pulled: the readers stopped. What wasn't read counts as unreadable, as the page counts it.
      for (; i < files.length; i++) out.push({ name: files[i].rel.split('/').pop(), path: files[i].rel, err: 'card removed' });
      const ok = out.filter(p => !p.err), bad = out.length - ok.length, secs = ((performance.now() - t0) / 1000).toFixed(1);
      reading = null;
      lastRead = { name: L.name, total: files.length, read: ok.length, unreadable: bad, stopped: run.gone ? 'card removed' : null, secs: +secs };
      window.lumina.read = Object.assign({}, lastRead);
      if (!ok.length) { logic.setState({ realLoad: null }); return logic.say(run.gone ? 'Card removed · re-insert to keep going' : 'couldn\'t read previews from those files'); }
      (logic.real || []).forEach(p => { URL.revokeObjectURL(p.src); if (/^blob:/.test(p.lg)) URL.revokeObjectURL(p.lg); });
      logic.real = ok; logic.data = logic.build({});
      logic.setState({ realLoad: null, realInfo: { xmpN: ok.filter(p => p.xmp).length, lrN: ok.filter(p => p.lrEd).length, n: ok.length, bad, secs, name: L.name },
        marks: {}, auto: {}, rA: {}, rO: {}, final: {}, caps: {}, cuts: {}, pending: {}, sel: {}, undo: [], cur: logic.data.order[0], node: 'm0', lvl: 'node' });
      logic.say(run.gone ? 'Card removed · ' + ok.length + ' of ' + files.length + ' read · re-insert to keep going'
        : ok.length + ' photos ready in ' + secs + ' s' + (bad ? ' · ' + bad + ' unreadable' : ''));
      logic.setView('cull');
    };

    // The page's own folder input still works (drag-in, or anything that clicks it).
    const onDir = logic.onDir.bind(logic);
    logic.onDir = async e => {
      cardPulledWhileReading = false;
      await onDir(e);
      // The page counts files lost to a pulled card as "unreadable"; say what happened, in its words.
      if (cardPulledWhileReading) logic.say('Card removed · re-insert to keep going');
      await afterRead();
    };
    // Recent shoots reopen the real folder; the design's sample entries (no id) keep the page's own step.
    // Key C simulated a card; the app has real mount notices (ADDENDUM §1).
    logic.simCard = () => {};
    loadRecents(logic);
    const libOpen = logic.libOpen.bind(logic);
    logic.libOpen = x => (x && x.id) ? native('reopen', { id: x.id }).then(ok => { if (!ok) logic.say('not available · card out or folder moved'); }) : libOpen(x);

    if (!cfg.sample) {
      // Start empty: the design's own builder with no photos, and no simulated card.
      const build = logic.build.bind(logic);
      logic.build = cuts => logic.real ? build(cuts) : LuminaCore.buildShoot([], cuts || {});
      logic.data = logic.build({});
      logic.setState({ marks: {}, final: {}, auto: {}, rA: {}, rO: {}, caps: {}, cuts: {}, pending: {}, sel: {}, undo: [],
        cur: logic.data.order[0] || null, node: (logic.data.N[0] || {}).id || null, lvl: 'node' });
      logic.constructor.SHOOTS = [];
      // The design has no empty Cull / Edit / Export yet (zero photos throws in its templates):
      // until it does, stay on Open while there's nothing to show. No new UI.
      const setView = logic.setView.bind(logic);
      logic.setView = (v, force) => (v !== 'import' && !logic.data.order.length) ? undefined : setView(v, force);
    }

    // Export: the page builds names + bytes; native picks the folder, keeps .lumina-bak, writes
    // atomically, verifies, refuses the card.
    logic.writeInto = async (files, label) => {
      const list = [];
      for (const f of files) {
        const d = f.data;
        if (d && d.__luminaJpg) list.push({ name: f.name, jpg: d.__luminaJpg });
        else if (d && d.__luminaRel) list.push({ name: f.name, src: d.__luminaRel });
        else if (typeof File !== 'undefined' && d instanceof File) list.push({ name: f.name, src: relPath(d) });
        else if (d instanceof Uint8Array) list.push({ name: f.name, b64: b64(d) });
        else if (d instanceof Blob) list.push({ name: f.name, b64: b64(new Uint8Array(await d.arrayBuffer())) });
      }
      const r = await native('writeInto', { label, files: list });
      if (r && r.say) logic.say(r.say);
      return r;
    };

    // "⏎ Cull this card": with a real card in, open its DCIM folder read-only; otherwise the page's own step.
    const impStart = logic.impStart.bind(logic);
    logic.impStart = resume => native('cullCard', {}).then(opened => { if (!opened) impStart(resume); });

    // JPEG export renders from the RAW natively. The look travels as the same CSS filter string the
    // Edit preview uses, so export = what Edit showed. Rendering happens when writeInto lands it.
    logic.renderJpg = async (id, px) => {
      const p = logic.data.byId[id];
      return { __luminaJpg: { src: relPath(p && p.fileObj), px: String(px), css: logic.cssR(logic.eff(id)) } };
    };
  };

  const findLogic = () => {
    for (const el of document.querySelectorAll('[data-screen-label], body *')) {
      const k = Object.keys(el).find(x => x.startsWith('__reactFiber$'));
      if (!k) continue;
      for (let f = el[k]; f; f = f.return) {
        const sn = f.stateNode;
        if (sn && sn.logic && typeof sn.logic.onKey === 'function' && sn.logic.state && 'view' in sn.logic.state) return sn.logic;
      }
    }
    return null;
  };

  let current = null;
  const watch = () => {
    const l = findLogic();
    if (l && l !== current) { current = l; patch(l); if (!missing(l).length) native('ready', {}); }
    setTimeout(watch, current ? 1000 : 30);
  };
  watch();
  saveLoop();

  // Previews around the cursor are read ahead into the Mac's cache (never into the page).
  let lastCur = null;
  const prefetchLoop = () => {
    try {
      const l = current;
      if (l && l.real && l.data && !reading && l.state.cur !== lastCur) {
        lastCur = l.state.cur;
        const o = l.data.order, k = o.indexOf(lastCur), items = [];
        if (k >= 0) for (const d of [1, -1, 2, 3, -2, 4, 5, 6, 0]) { const p = l.data.byId[o[k + d]], q = p && previewOf(p.lg); if (q) items.push(q); }
        if (items.length) native('prefetch', { items });
      }
    } finally { setTimeout(prefetchLoop, 120); }
  };
  prefetchLoop();

  // Native → page. Only existing page actions are used.
  window.__lumina = {
    logic: () => current || findLogic(),
    ready: () => !!(current && current.__luminaPlumbed),
    missing: () => { const l = current || findLogic(); return l ? missing(l) : ['page not found']; },
    drift: () => drift(current || findLogic()),
    shootId: () => shootId,
    card(present, info) {
      if (cfg.parity) return;              // test-only: keep the design's sample card state for pixel parity
      window.lumina.card = present ? (info || {}) : null;
      const l = window.__lumina.logic();
      if (!present && l && l.state.realLoad) cardPulledWhileReading = true;
      if (l) l.impSet({ card: !!present });
    },
    // The card went away. `stopped`: the opened folders on it, whose reads the Mac has already
    // stopped. A read in progress stops too and then says how far it got.
    cardGone(stopped) {
      if (cfg.parity) return;
      window.__lumina.card(false);
      if (reading && (stopped || []).includes(reading.name)) { reading.gone = true; return; }
      if (!cardPulledWhileReading) window.__lumina.say('Card removed · re-insert to keep going');
    },
    // Read-only state surface for the probe's invariant checker: what the page holds and what the
    // Mac is doing. JSON-safe.
    inspect() {
      const l = window.__lumina.logic(), s = l && l.state, real = (l && l.real) || [];
      const paths = real.map(p => (p.fileObj && p.fileObj.webkitRelativePath) || '');
      return {
        view: s ? s.view : null, cur: s ? s.cur : null, real: real.length, order: l && l.data ? l.data.order.length : 0,
        reading: reading && { name: reading.name, total: reading.total, done: reading.done, gone: reading.gone },
        lastRead, realLoad: s ? s.realLoad || null : null, realInfo: s ? s.realInfo || null : null,
        lgHeld: real.filter(p => !previewOf(p.lg)).length,          // large previews the page holds itself: must be 0
        zsrcOff: real.length && l.data ? Object.values(l.data.byId).filter(q => q.zsrc !== q.lg).length : 0,   // zoom must use the same preview
        srcNotBlob: real.filter(p => !/^blob:/.test(p.src || '')).length,
        dupPaths: paths.length - new Set(paths).size,
        shootId, card: window.lumina.card,
      };
    },
    nativeStats: () => native('ingestStats', {}),
    say(t) { const l = window.__lumina.logic(); if (l) l.say(t); },
    openFolder() { const l = window.__lumina.logic(); if (l) l.openFolder(); },
    undo() {
      const a = document.activeElement;
      if (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA')) return document.execCommand('undo');
      const l = window.__lumina.logic(); if (l) l.undo();
    },
  };
})();
