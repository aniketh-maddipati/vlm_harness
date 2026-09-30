// Lumina app plumbing. Injected at document start into the design's page, which ships byte-identical.
// This file is the only place the app differs from the prototype: it swaps the page's browser I/O
// (openFolder / onDir / writeInto keep their names, only the insides change) for calls to the native
// bridge, and provides `window.lumina`, the page's data contract. Layout, styles, copy and keys are
// untouched: plumbing supplies behaviour and data, never UI.
(() => {
  const cfg = Object.assign({}, window.__luminaConfig || {});
  const native = (op, args) => window.webkit.messageHandlers.lumina.postMessage(Object.assign({ op }, args || {}));

  // Settings (MENUS.md): stored per user by the Mac (UserDefaults). The page reads 'lumina-prefs' from
  // localStorage when it starts and hands every change to lumina.setPrefs. The web view's storage is
  // not persistent, so seed it before the page's constructor runs.
  if (cfg.prefs && typeof cfg.prefs === 'object') { try { localStorage.setItem('lumina-prefs', JSON.stringify(cfg.prefs)); } catch (_) {} }

  const b64 = u8 => {
    let s = '';
    for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
    return btoa(s);
  };

  // Native ingest (the page's onDir + readOne, read by the Mac). The listing arrives first; each ARW
  // then gives a 256 KB head that LuminaCore.parseHead reads, and its embedded preview, read by byte
  // range, which the page's own steps turn, resize and measure exactly as in the prototype. The page
  // keeps only a lumina:// URL for the large view (the Mac caches around the cursor). Same origin,
  // so canvases stay clean.
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
  // Grid thumbnail made by the Mac (/media/thumb, SetsIngest.thumb: covers 720 × 480, never upscaled,
  // JPEG 0.9, off the page's thread). The in-page fallback is gridThumb, below.
  const nativeTile = pq => get(media('thumb', pq)).then(r => r.blob()).catch(() => null);
  // Stands in for the File the page keeps per photo: the same name and relative path, no bytes.
  const fileRef = rel => ({ name: rel.split('/').pop(), webkitRelativePath: rel, __luminaRel: rel });
  let reading = null, lastRead = null;

  // Everything below leans on these page members. A design sync that renames one shows up here (and
  // in the probe's plumbing-contract scenario) instead of as a silent break.
  const REQUIRED = ['onKey', 'setState', 'setView', 'say', 'undo', 'openFolder', 'onDir', 'readOne', 'intake', 'notesFor',
    'writeInto', 'runExport', 'impStart', 'impSet', 'libOpen', 'build', 'forget', 'kept', 'undec', 'land', 'xmpFor', 'reveal'];
  const GLOBALS = { 'LuminaCore.parseHead': () => window.LuminaCore && LuminaCore.parseHead, 'LuminaCore.measure': () => window.LuminaCore && LuminaCore.measure,
    'LuminaCore.hasDevelop': () => window.LuminaCore && LuminaCore.hasDevelop, 'LuminaCore.buildShoot': () => window.LuminaCore && LuminaCore.buildShoot,
    'LuminaV4.fmt.base': () => window.LuminaV4 && LuminaV4.fmt && LuminaV4.fmt.base };
  // Set by the page when it mounts (MENUS.md, SAFETY.md 3 and 5).
  const HOOKS = ['luminaCommand', 'luminaCardGone', 'luminaAccess', 'luminaState'];
  const missing = logic => REQUIRED.filter(k => typeof logic[k] !== 'function').concat(
    logic.constructor && Array.isArray(logic.constructor.SHOOTS) ? [] : ['static SHOOTS'],
    logic.constructor && typeof logic.constructor.clean === 'function' ? [] : ['static clean'],
    Object.keys(GLOBALS).filter(k => typeof GLOBALS[k]() !== 'function'),
    HOOKS.filter(k => typeof window[k] !== 'function').map(k => 'window.' + k));
  // The native read (below) repeats the page's onDir and readOne step for step. When a design sync
  // changes either, the contract check reports it so the repeat gets reviewed; the app keeps working.
  const ONDIR = 3373286225;
  const fnv = t => { let h = 0x811c9dc5; for (let i = 0; i < t.length; i++) { h ^= t.charCodeAt(i); h = Math.imul(h, 0x01000193); } return h >>> 0; };
  const readHash = logic => {
    const proto = logic && Object.getPrototypeOf(logic);
    return proto && typeof proto.onDir === 'function' && typeof proto.readOne === 'function' ? fnv(proto.onDir.toString() + '\n' + proto.readOne.toString()) : 0;
  };
  const drift = logic => { const h = readHash(logic); return h === ONDIR ? [] : ['onDir/readOne changed (fnv ' + h + '): review the native read in plumbing.js'] };

  // Decisions saved per shoot (SAFETY.md 2), keyed by file path so they survive files being added.
  // Rows seen are keyed by row id; the stack regions for Z by stack. `saved` is the keeper list of
  // the last successful Save, so Quit knows whether keepers are unsaved. The Edit step's look
  // strings (roadmap "Rendering contract") live here too: `look` per photo, by path, and `rowLook`
  // per row, by row id like `seen`. Never in XMP: the sidecars the page builds carry ratings only.
  const BY_ID = ['marks', 'flags', 'stars', 'cuts', 'look'];
  const SCALAR = ['seen', 'tsz', 'regions', 'lastEx', 'rowLook'];
  let shootId = null, lastSaved = '', base = null, savedKeepers = null, cardPulledWhileReading = false, readMoved = false;
  // Last scroll in the page (any scroller), for pacing the grid's refresh while a folder is read.
  let scrollT = 0;
  document.addEventListener('scroll', () => { scrollT = performance.now(); }, { capture: true, passive: true });
  // Path inside the opened folder ("sub/DSC00001.ARW"): stable across reopen and new files.
  const keyOf = p => { const r = (p && p.fileObj && p.fileObj.webkitRelativePath) || (p && p.path) || ''; return r ? r.split('/').slice(1).join('/') : (p && p.file) || ''; };
  const pathOf = (logic, id) => keyOf(logic.data && logic.data.byId[id]);
  const keepersOf = logic => logic.kept().map(id => pathOf(logic, id)).sort().join('\n');
  const snapshot = logic => {
    const s = logic.state, out = { v: 2, cur: pathOf(logic, s.cur) || null, saved: savedKeepers };
    const here = new Set(Object.values(logic.data.byId).map(keyOf));
    for (const k of BY_ID) {
      // Decisions for files not read this time (card pulled mid-read, file moved away) are kept.
      const m = {}; for (const [p, v] of Object.entries((base && base[k]) || {})) if (!here.has(p)) m[p] = v;
      for (const [id, v] of Object.entries(s[k] || {})) { const p = pathOf(logic, id); if (p) m[p] = v; }
      out[k] = m;
    }
    for (const k of SCALAR) if (s[k] !== undefined) out[k] = s[k];
    return out;
  };
  // For the Open screen's recent cards: the same numbers the prototype's persist() keeps.
  const summary = logic => ({ n: logic.data.order.length, dec: logic.data.order.filter(id => !logic.undec(id)).length,
    kp: logic.kept().length, last: LuminaV4.fmt.base((logic.data.byId[logic.state.cur] || {}).file) || '' });
  // `live`: the reader moved or decided while the folder was being read. Those decisions win over
  // the saved ones and the cursor stays where it is (nothing jumps when the read ends).
  const restore = (logic, saved, live) => {
    base = saved; savedKeepers = typeof saved.saved === 'string' ? saved.saved : null;
    const idOf = {}; for (const [id, p] of Object.entries(logic.data.byId)) idOf[keyOf(p)] = id;
    const st = {};
    for (const k of BY_ID) { const m = {}; for (const [p, v] of Object.entries(saved[k] || {})) if (idOf[p]) m[idOf[p]] = v; st[k] = live ? Object.assign(m, logic.state[k] || {}) : m; }
    st.marks = logic.constructor.clean(st.marks);
    for (const k of SCALAR) if (saved[k] !== undefined) st[k] = saved[k];
    if (Object.keys(st.cuts || {}).length) logic.data = logic.build(st.cuts);
    const cur = saved.cur && idOf[saved.cur];
    if (cur && logic.data.byId[cur] && !live) st.cur = cur;
    logic.setState(st);
  };
  const saveNow = () => {
    const l = current;
    if (!(l && l.real && shootId && !reading && !l.state.realLoad)) return;
    const json = JSON.stringify(snapshot(l));
    if (json !== lastSaved) { lastSaved = json; base = JSON.parse(json); native('saveSession', { id: shootId, json, summary: summary(l) }); }
  };
  // Every 2 s and on every view change (SAFETY.md 2).
  let lastView = null;
  const saveLoop = () => {
    try { saveNow(); } finally { setTimeout(saveLoop, 2000); }
  };
  const viewLoop = () => {
    try {
      const l = current, v = l && l.state.view;
      if (v !== lastView) {
        lastView = v; saveNow();
        // Save shows "Remove Lumina's working files (size)" once it knows the size; in the app the
        // page only asks after a save. Give it the size when Save opens.
        if (v === 'export' && typeof l.exSet === 'function') {
          if (cfg.parity) { if (typeof l.cacheBytes === 'function') l.exSet({ wf: l.cacheBytes() }); }
          else if (shootId) window.lumina.workingFiles().then(b => { if (current === l && l.state.view === 'export') l.exSet({ wf: b }); }).catch(() => {});
        }
      }
    } finally { setTimeout(viewLoop, 150); }
  };

  // The data contract the design reads. Absent in the browser prototype; present in the app.
  window.lumina = Object.assign(window.lumina || {}, {
    app: true, debug: !!cfg.debug, persisted: true,
    card: null,            // { name, photos, bytes, sony, path, model, range } while a card is in, else null
    readingCard: false,    // the open shoot is on a mounted card or removable volume: Save stays off (SAFETY.md 4)
    willPromptAccess: false, // the Mac's folder picker grants access itself: no pre-prompt sheet
    read: null,            // the last folder read: { name, total, read, unreadable, stopped: 'card removed' | null }
    shoots: [],            // recent shoots for the Open screen: { id, d, n, dec, kp, last, where }
    open: id => native('reopen', { id }),
    reveal: path => native('reveal', { path: String(path || '') }),
    // Lumina's own files for the open shoot (never RAWs or .xmp): size in bytes, and remove.
    workingFiles: () => shootId ? native('workingFiles', { id: shootId }) : Promise.resolve(0),
    removeWorkingFiles: () => shootId ? native('removeShoot', { id: shootId }).then(ok => { shootId = null; lastSaved = ''; base = null; return ok; }) : Promise.resolve(false),
    setPrefs: prefs => native('setPrefs', { prefs }),
    // Permissions (SAFETY.md 5).
    openSettings: what => native('openSettings', { what: what || 'files' }),
    checkAccess: () => native('checkAccess', {}),
    reopen: () => native('reopenDenied', {}),
  });

  const loadRecents = async logic => {
    const list = await native('recents', {});
    if (!Array.isArray(list)) return;
    window.lumina.shoots = list;
    logic.constructor.SHOOTS = cfg.parity ? list.concat((window.LuminaV4 && LuminaV4.SHOOTS) || []) : list;
    logic.forceUpdate && logic.forceUpdate();
  };

  const patch = logic => {
    if (logic.__luminaPlumbed) return;
    logic.__luminaPlumbed = true;
    const gaps = missing(logic);
    if (gaps.length) { native('ready', { missing: gaps }); return; }

    // After a folder is read: remember the shoot and bring its decisions back.
    const afterRead = async () => {
      if (!logic.real || !logic.real.length) return;
      const info = logic.state.realInfo || {};
      const first = logic.real.map(p => p.date).filter(Boolean).sort()[0] || '';
      const r = await native('shootOpened', { name: info.name, n: logic.real.length, date: first });
      shootId = r && r.id; lastSaved = ''; base = null; savedKeepers = null;
      if (r && r.session) { try { restore(logic, JSON.parse(r.session), readMoved); } catch (_) {} }
      // Decisions made while the folder was read aren't in the session yet: the next save sends them.
      lastSaved = readMoved ? '' : JSON.stringify(snapshot(logic));
      loadRecents(logic);
    };

    // Opening a folder reads it natively. The steps and wording are the page's own onDir; only
    // where the bytes come from differs.
    const openFolder0 = logic.openFolder.bind(logic);
    logic.openFolder = async force => {
      if (!force && window.lumina.willPromptAccess) {
        let skip = false; try { skip = localStorage.getItem('lumina-v4-pre-ok') === '1'; } catch (_) {}
        if (!skip) return openFolder0(false);                // the page's own sheet; it calls back with force
      }
      if (reading) return;                                   // one read at a time
      const L = await native('openFolder', {});
      if (!L) return;                                        // cancelled
      if (L.denied != null) { window.luminaAccess(true, L.denied); return; }
      window.luminaAccess(false);
      window.luminaCardGone(false);
      window.lumina.readingCard = !!L.onCard;
      await ingest(L);
      await afterRead();
    };

    // One ARW, as the page's readOne reads it, from the Mac's reader.
    const readOne = async (f, xmpMap) => {
      const rel = f.rel, name = rel.split('/').pop();
      const head = new Uint8Array(await (await get(media('head', { p: rel }))).arrayBuffer());
      const m = LuminaCore.parseHead(head, f.size); if (!m) throw new Error('unreadable');
      let blob = null, pq = null, nt = null;
      if (m.preview) {
        const [po, pl] = m.preview;
        if (po + pl <= f.size) {
          pq = { p: rel, o: po, l: pl, ori: m.orient || 1 };
          // As stored (ori 1): the page's own canvas turns it, below.
          blob = await (await get(media('preview', Object.assign({}, pq, { ori: 1 })))).blob();
          nt = nativeTile(pq);                               // made by the Mac while the page measures
        }
      }
      const xk = rel.replace(/\.[^.\/]+$/, '').toLowerCase(), xo = xmpMap[xk] || null, xpath = xo ? xo.path : rel.replace(/\.[^.\/]+$/, '') + '.xmp';
      const baseP = { model: m.model || null, fnum: m.fnum || null, w: m.w || null, h: m.h || null, bytes: f.size, lens: m.lens || null, serial: m.serial || null,
        program: m.program ?? null, wb: m.wb ?? null, flash: m.flash ?? null, seqImage: m.seqImage ?? null, seqLength: m.seqLength ?? null, releaseMode2: m.releaseMode2 ?? null,
        fileObj: fileRef(rel), xpath, xmp: xo && xo.tx, lrEd: LuminaCore.hasDevelop(xo && xo.tx), name, path: rel, date: m.date || '', exp: m.exp, fl: m.fl, ev: m.ev, iso: m.iso };
      let me = null, portrait = false, tb = null;
      try {
        if (!blob) throw 0;
        const ori = m.orient || 1;
        if (ori === 3 || ori === 6 || ori === 8) { const b0 = await createImageBitmap(blob, { imageOrientation: 'none' }), sw = ori !== 3, c = document.createElement('canvas'); c.width = sw ? b0.height : b0.width; c.height = sw ? b0.width : b0.height; const x = c.getContext('2d'); x.translate(c.width / 2, c.height / 2); x.rotate(ori === 6 ? Math.PI / 2 : ori === 8 ? -Math.PI / 2 : Math.PI); x.drawImage(b0, -b0.width / 2, -b0.height / 2); b0.close(); blob = await new Promise(res => c.toBlob(res, 'image/jpeg', 0.92)); }
        const sm = await createImageBitmap(blob, { resizeWidth: 360, resizeQuality: 'medium' }); portrait = sm.height > sm.width; me = LuminaCore.measure(sm); sm.close();
        // Measures above come from the page's exact 360 px bitmap. The tile shows a sharper picture:
        // the Mac's, else one made in a worker, else the page's own.
        tb = (nt && await nt) || await gridThumb(blob) || await new Promise(res => me.canvas.toBlob(res, 'image/jpeg', 0.82));
      } catch (_) { me = null; }
      logic._gold.push({ file: name, size: f.size, parsed: Object.assign(Object.fromEntries(Object.entries(m).filter(([k]) => !/^_/.test(k))), { dhash: me ? me.dhash : null }) });
      if (!me) return Object.assign(baseP, { nopv: true, portrait: false, lum: null, focus: 0, clip: 0, dhash: null, src: '', lg: '' });
      // The large view gets the Mac's upright preview by URL: never held by the page.
      return Object.assign(baseP, { portrait, dhash: me.dhash, lum: me.lum, focus: me.focus, clip: me.clip, src: URL.createObjectURL(tb), lg: media('preview', pq) });
    };

    // Grid thumbnails (data, not UI). The page makes them 360 px wide at JPEG 0.82 for its own measure
    // step; its largest tile is 216 CSS px × up to 1.5 (ADDENDUM-1 §4), so on a Retina screen a 360 px
    // thumbnail is stretched ~1.8× and its JPEG blocks show. The tile's picture is made at the largest
    // tile's device width instead (never below 360), at 0.9.
    const THUMB_W = Math.min(720, Math.max(360, Math.ceil(216 * 1.5 * Math.max(1, window.devicePixelRatio || 1))));
    // Made off the page's thread (Web Workers with OffscreenCanvas), so reading a folder doesn't wait on
    // it; in-page when workers can't (older WebKit).
    const thumbPool = (() => {
      if (typeof Worker !== 'function' || typeof OffscreenCanvas !== 'function') return null;
      try {
        const src = 'onmessage = async e => { const { id, blob, w } = e.data; try { const bm = await createImageBitmap(blob, { resizeWidth: w, resizeQuality: "high" });' +
          ' const c = new OffscreenCanvas(bm.width, bm.height); c.getContext("2d").drawImage(bm, 0, 0); bm.close();' +
          ' postMessage({ id, blob: await c.convertToBlob({ type: "image/jpeg", quality: 0.9 }) }); } catch (_) { postMessage({ id, blob: null }); } };';
        const url = URL.createObjectURL(new Blob([src], { type: 'text/javascript' }));
        const ws = Array.from({ length: 2 }, () => new Worker(url)), wait = new Map(); let n = 0;
        ws.forEach(w => { w.onmessage = e => { const f = wait.get(e.data.id); wait.delete(e.data.id); f && f(e.data.blob); }; });
        return blob => new Promise(res => { const id = ++n; wait.set(id, res); ws[id % ws.length].postMessage({ id, blob, w: THUMB_W }); });
      } catch (_) { return null; }
    })();
    const gridThumb = async blob => {
      try {
        if (thumbPool) return await thumbPool(blob);
        const bm = await createImageBitmap(blob, { resizeWidth: THUMB_W, resizeQuality: 'high' });
        const c = document.createElement('canvas'); c.width = bm.width; c.height = bm.height; c.getContext('2d').drawImage(bm, 0, 0); bm.close();
        return await new Promise(res => c.toBlob(res, 'image/jpeg', 0.9));
      } catch (_) { return null; }
    };

    // The page's onDir, step for step, over the native listing.
    const ingest = async L => {
      const xmpMap = {};
      // One sidecar per RAW. On a case-sensitive disk both DSC.xmp and DSC.XMP can exist: the lower-case
      // .xmp wins (Adobe's name, and the one the page gives new sidecars), else the first by name.
      const sidecars = (L.xmp || []).slice().sort((a, b) => (a.rel < b.rel ? -1 : a.rel > b.rel ? 1 : 0));
      for (const x of sidecars) {
        const k = x.rel.replace(/\.[^.\/]+$/, '').toLowerCase(), had = xmpMap[k];
        if (!had || (/\.xmp$/.test(x.rel) && !/\.xmp$/.test(had.path))) xmpMap[k] = { tx: x.text, path: x.rel };
      }
      const arws = (L.files || []).map(f => Object.assign(fileRef(f.rel), { size: f.size }));
      const allF = arws.concat((L.xmp || []).map(x => fileRef(x.rel)), (L.others || []).map(fileRef));
      const files = (L.files || []).slice().sort((a, b) => a.rel.localeCompare(b.rel));
      logic._intake = logic.intake(allF, arws);
      if (!files.length) {
        const I = logic._intake, parts = [...Object.entries(I.raw).map(([e, n]) => n + ' ' + e.toUpperCase()), I.jp + I.ja ? (I.jp + I.ja) + ' JPEG / HEIF' : '', I.vid ? I.vid + ' videos' : ''].filter(Boolean);
        const msg = 'no ARW found' + (parts.length ? ' · ' + parts.join(' · ') + ' · only Sony ARW is supported' : ' · 0 photos');
        logic.setState({ openNote: msg }); return logic.say(msg);
      }
      (logic.real || []).forEach(p => { p.src && URL.revokeObjectURL(p.src); /^blob:/.test(p.lg || '') && URL.revokeObjectURL(p.lg); });
      const run = reading = { name: L.name, total: files.length, done: 0, gone: false };
      const t0 = performance.now(), res = new Array(files.length); let done = 0, i = 0, pre = 0, shown = false, lastB = 0, firstCur = null;
      readMoved = false;
      logic._gold = []; logic._failed = []; logic.real = [];
      logic.setState({ realLoad: { done: 0, total: files.length, t0 }, realInfo: null, sel: {}, marks: {}, seen: {}, flags: {}, stars: {}, cuts: {}, undo: [], open: null, undec: false, pend: null });
      // Rows appear as the contiguous prefix grows: every 400 ms, as in the page; every 1.5 s while
      // the reader is scrolling, so the grid isn't rebuilt under a moving scroll (plumbing's pacing).
      const grow = force => {
        while (pre < files.length && res[pre] !== undefined) pre++;
        const now = performance.now(); if (!force && (pre < 48 || now - lastB < (now - scrollT < 300 ? 1500 : 400))) return; lastB = now;
        logic.real = res.slice(0, pre).filter(p => p && !p.err); if (!logic.real.length) return; logic.data = logic.build(logic.state.cuts || {}); logic._lk = null;
        if (!shown) { shown = true; firstCur = logic.data.order[0]; logic.setState({ cur: firstCur }); logic.setView('cull', true); } else logic.forceUpdate();
      };
      const one = async (f, k) => {
        try { res[k] = await readOne(f, xmpMap); }
        catch (err) { if (err instanceof Gone) run.gone = true; res[k] = { err: true }; logic._failed.push({ name: f.rel.split('/').pop(), reason: err instanceof Gone ? 'card removed' : 'unreadable' }); }
        done++; run.done = done;
        if (done % 8 === 0 || done === files.length) logic.setState({ realLoad: { done, total: files.length, t0 } });
        grow(false);
      };
      await Promise.all(Array.from({ length: Math.max(1, L.workers || 4) }, async () => { while (i < files.length && !run.gone) { const k = i++; await one(files[k], k); } }));
      // Card pulled: the readers stopped. What wasn't read counts as unreadable, as the page counts it.
      for (; i < files.length; i++) { res[i] = { err: true }; logic._failed.push({ name: files[i].rel.split('/').pop(), reason: 'card removed' }); }
      const ok = res.filter(p => p && !p.err);
      reading = null;
      lastRead = { name: L.name, total: files.length, read: ok.length, unreadable: files.length - ok.length, stopped: run.gone ? 'card removed' : null, secs: +((performance.now() - t0) / 1000).toFixed(1) };
      window.lumina.read = Object.assign({}, lastRead);
      if (!ok.length) { logic.real = null; logic.data = logic.build({}); logic.setState({ realLoad: null }); return logic.say(run.gone ? 'Card removed · re-insert to keep going' : '0 photos · ' + files.length + ' unreadable'); }
      // The page ends a read on the first photo and scrolls to it (land). When the reader has already
      // moved (cursor, keeps, or scrolled), plumbing keeps them where they are instead: same photo,
      // same scroll, no fly-back across the shoot. Design ask 8 asks the page for the same.
      const sc = logic.scrollRef && logic.scrollRef.current, was = logic.state.cur, wasKey = shown && was && logic.data.byId[was] ? keyOf(logic.data.byId[was]) : null;
      readMoved = shown && (was !== firstCur || Object.keys(logic.state.marks || {}).length > 0 || !!(sc && sc.scrollTop > 40));
      logic.real = ok; logic.data = logic.build({});
      let stay = null;
      if (readMoved && wasKey) for (const [id, p] of Object.entries(logic.data.byId)) if (keyOf(p) === wasKey) { stay = id; break; }
      const G = Object.values(logic.data.G), first = ok.map(p => p.date).filter(Boolean).sort()[0] || '';
      const info = { name: L.name, n: ok.length, rows: logic.data.R.length, stacks: G.filter(g => g.kind !== 'single').length, bad: logic._failed.length, secs: lastRead.secs.toFixed(1), date: first.slice(0, 10).replace(/:/g, '-') };
      logic.setState({ realLoad: null, realInfo: info, openNote: null, notes: logic.notesFor(), notesOn: true, cur: stay || logic.data.order[0] });
      logic._landT = Date.now(); logic.setView('cull', true); if (!stay) setTimeout(() => logic.land(), 0);
      if (run.gone) logic.say('Card removed · ' + ok.length + ' of ' + files.length + ' read · re-insert to keep going');
    };

    // The page's own folder input still works (drag-in, or anything that clicks it): WebKit hands it
    // Files and the page reads them itself.
    const onDir = logic.onDir.bind(logic);
    logic.onDir = async e => {
      cardPulledWhileReading = false; readMoved = false;
      window.lumina.readingCard = false;
      await onDir(e);
      if (cardPulledWhileReading) logic.say('Card removed · re-insert to keep going');
      await afterRead();
    };

    // Sidecars (SAFETY.md 1): written by the Mac INTO the shoot folder, next to each RAW. Atomic,
    // .lumina-bak first, read back and compared; refused on a card. Per-file errors come back as
    // { name, reason } for the page's result list.
    logic.writeInto = async (files, label) => {
      if (label !== 'xmp') return null;
      const info = logic.state.realInfo || {};
      const list = [];
      for (const f of files) {
        const d = f.data;
        if (d instanceof Uint8Array) list.push({ name: f.name, b64: b64(d) });
        else if (d instanceof Blob) list.push({ name: f.name, b64: b64(new Uint8Array(await d.arrayBuffer())) });
        else if (typeof d === 'string') list.push({ name: f.name, b64: b64(new TextEncoder().encode(d)) });
      }
      const r = await native('writeSidecars', { root: info.name || '', files: list });
      if (r && !(r.errors || []).length && (r.n || 0) > 0) savedKeepers = keepersOf(logic);
      if (r) setTimeout(saveNow, 0);
      return r;
    };

    // "Cull This Card": the card's DCIM folder, read in place.
    const impStart = logic.impStart.bind(logic);
    logic.impStart = () => native('cullCard', {}).then(opened => { if (!opened) impStart(); });

    // Recent shoots reopen the real folder (with a security-scoped bookmark).
    logic.libOpen = x => (x && x.id) ? native('reopen', { id: x.id }).then(ok => { if (!ok) logic.say('not available · ' + (x.where || 'card out or folder moved')); }) : undefined;
    // Key C simulated a card in the prototype; the app has real mount notices.
    if (typeof logic.simCard === 'function') logic.simCard = () => {};

    if (cfg.parity) parity(logic);
    loadRecents(logic);
  };

  // Test-only (probe screens-*-app): show the design's sample shoot and sample card, so the app's
  // screens can be compared pixel for pixel with the prototype's.
  const parity = logic => {
    logic.useSample = () => true;
    logic.data = logic.build({});
    const d = logic.data, P = d.order.map(id => d.byId[id]), t = P.map(p => p.date10 + ' ' + p.sec.slice(0, 5)).sort();
    window.lumina.card = P.length ? { name: 'SONY-A7M4', photos: P.length, bytes: P.reduce((a, p) => a + (p.bytes || 0), 0), sony: true, path: '/Volumes/Untitled',
      model: [...new Set(P.map(p => p.model).filter(Boolean))].join(' + '), range: t[0] + ' → ' + t[t.length - 1].slice(11) } : null;
    logic.constructor.SHOOTS = (window.LuminaV4 && LuminaV4.SHOOTS) || [];
    logic.setState({ cur: d.order[0] || null, imp: Object.assign({}, logic.state.imp, { card: true }) });
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
  viewLoop();


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

  // Grid thumbnails ahead of a scroll are decoded before the page mounts their rows (it renders
  // ±700 px around the viewport), so a fast scroll finds them ready. WebKit shares a decoded image
  // between elements with the same URL; the Images here only hold it (at most WARM_MAX × 720 × 480
  // × 4 bytes, ~165 MB). Two viewports ahead, 700 px behind.
  const warm = new Map();                       // tile blob URL → decoding Image, oldest first
  const WARM_MAX = 120;
  let warmReal = null, warmTop = null, warmRaf = 0, warmOn = cfg.warmAhead !== false;
  const warmAhead = () => {
    warmRaf = 0;
    if (!warmOn) return;
    const l = current, el = document.querySelector('[data-screen-label="1 Cull"]');
    if (!l || !l.real || !el || typeof l.layout !== 'function' || l.state.view !== 'cull') return;
    if (warmReal !== l._gold) { warm.clear(); warmReal = l._gold; }      // a new read (its thumbnails are new URLs)
    const top = el.scrollTop, dir = warmTop == null || top >= warmTop ? 1 : -1, span = el.clientHeight * 2 + 700;
    warmTop = top;
    const lo = dir > 0 ? top - 700 : top - span, hi = dir > 0 ? top + el.clientHeight + span : top + el.clientHeight + 700;
    const L = l.layout(), byId = l.data.byId, want = [];
    for (const r of L.rows) {
      if (r.y + r.h < lo || r.y > hi) continue;
      for (const c of r.cells) { const p = byId[c.id]; if (p && p.src) want.push({ src: p.src, d: Math.abs(r.y - top) }); }
    }
    want.sort((a, b) => a.d - b.d);
    for (const { src } of want) {
      const im = warm.get(src);
      if (im) { warm.delete(src); warm.set(src, im); continue; }
      const n = new Image(); n.decoding = 'async'; n.src = src; if (n.decode) n.decode().catch(() => {});
      warm.set(src, n);
    }
    while (warm.size > WARM_MAX) warm.delete(warm.keys().next().value);
  };
  document.addEventListener('scroll', () => { if (!warmRaf) warmRaf = requestAnimationFrame(warmAhead); }, { capture: true, passive: true });

  // Native → page. Only the page's own actions and hooks are used.
  window.__lumina = {
    logic: () => current || findLogic(),
    ready: () => !!(current && current.__luminaPlumbed && !missing(current).length),
    missing: () => { const l = current || findLogic(); return l ? missing(l) : ['page not found']; },
    drift: () => drift(current || findLogic()),
    readHash: () => readHash(current || findLogic()),
    shootId: () => shootId,
    card(present, info) {
      if (cfg.parity) return;              // test-only: keep the sample card for pixel parity
      window.lumina.card = present ? (info || {}) : null;
      const l = window.__lumina.logic();
      if (!present && l && l.state.realLoad) cardPulledWhileReading = true;
      if (l) { l.impSet({ card: !!present }); l.forceUpdate && l.forceUpdate(); }
    },
    // The card went away (SAFETY.md 3). `stopped`: the opened folders on it, whose reads the Mac has
    // already stopped; `ours`: the open shoot is on it. State is kept.
    cardGone(stopped, ours) {
      if (cfg.parity) return;
      window.__lumina.card(false);
      if (reading && (stopped || []).includes(reading.name)) reading.gone = true;
      if (ours || (stopped || []).length) window.luminaCardGone(true);
    },
    // The card with the open shoot is back. A read that the pull cut short is read again (the
    // session keeps every decision).
    cardBack() {
      if (cfg.parity) return;
      window.luminaCardGone(false);
      if (lastRead && lastRead.stopped) native('reopenCurrent', {});
    },
    access(denied, what) { window.luminaAccess(!!denied, what || ''); },
    command(name) { return typeof window.luminaCommand === 'function' ? window.luminaCommand(name) : false; },
    // View ▸ Zoom 100%: Z is a hold key in the page; the menu toggles it through the page's gesture hook.
    zoom() { const l = window.__lumina.logic(); if (l && typeof window.luminaGesture === 'function') window.luminaGesture('hold', { key: 'z', down: !l.state.zoom }); },
    // Quit asks when there are keepers not yet saved (MENUS.md): their count, or 0.
    unsaved() {
      const l = window.__lumina.logic();
      if (!l || !l.real || !l.real.length) return 0;
      const k = l.kept().length;
      return k && keepersOf(l) !== savedKeepers ? k : 0;
    },
    closeShoot() {
      const l = window.__lumina.logic(); if (!l) return;
      saveNow();
      shootId = null; lastSaved = ''; base = null; savedKeepers = null; lastRead = null;
      window.lumina.readingCard = false; window.lumina.read = null;
      window.luminaCardGone(false);
      l.forget();
      loadRecents(l);
    },
    removeWorkingFiles() {
      const l = window.__lumina.logic();
      return window.lumina.removeWorkingFiles().then(ok => { if (ok && l) { l.forget(); loadRecents(l); } return ok; });
    },
    recents() { const l = window.__lumina.logic(); if (l) loadRecents(l); },
    // Read-only state surface for the probe's invariant checker: what the page holds and what the
    // Mac is doing. JSON-safe.
    inspect() {
      const l = window.__lumina.logic(), s = l && l.state, real = (l && l.real) || [];
      const withPv = real.filter(p => !p.nopv), paths = real.map(p => p.path || '');
      return {
        view: s ? s.view : null, cur: s ? s.cur : null, real: real.length, order: l && l.data ? l.data.order.length : 0,
        reading: reading && { name: reading.name, total: reading.total, done: reading.done, gone: reading.gone },
        lastRead, realLoad: s ? s.realLoad || null : null, realInfo: s ? s.realInfo || null : null,
        lgHeld: withPv.filter(p => !previewOf(p.lg)).length,          // large previews the page holds itself: must be 0
        zsrcOff: real.length && l.data ? Object.values(l.data.byId).filter(q => q.zsrc !== q.lg).length : 0,   // zoom must use the same preview
        srcNotBlob: withPv.filter(p => !/^blob:/.test(p.src || '')).length,
        dupPaths: paths.length - new Set(paths).size,
        shootId, card: window.lumina.card, readingCard: window.lumina.readingCard,
      };
    },
    nativeStats: () => native('ingestStats', {}),
    // Probe A/B: decode thumbnails ahead of a scroll or not. Returns how many are held.
    warmAhead(on) { if (on != null) { warmOn = !!on; if (!warmOn) warm.clear(); } return warm.size; },
    say(t) { const l = window.__lumina.logic(); if (l) l.say(t); },
    openFolder() { const l = window.__lumina.logic(); if (l) l.openFolder(true); },
    undo() {
      const a = document.activeElement;
      if (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA')) return document.execCommand('undo');
      const l = window.__lumina.logic(); if (l) l.undo();
    },
  };
})();
