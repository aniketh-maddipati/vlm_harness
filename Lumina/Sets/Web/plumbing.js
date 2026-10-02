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
  // encodeURIComponent, not URLSearchParams (which writes a space as '+'): a space is %20 and a real
  // '+' is %2B, so a folder named "Shoot 2026" reads (SetsSchemeHandler.query; previewOf below reads it back).
  const query = q => Object.keys(q).filter(k => q[k] != null).map(k => encodeURIComponent(k) + '=' + encodeURIComponent(q[k])).join('&');
  const media = (kind, q) => new URL('/media/' + kind + '?' + query(q), location.href).href;
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
  // Where each photo's embedded preview is, by path, as the native read found it: what the Mac
  // measures for lumina.near. Photos the page read by itself (a dragged-in folder) have none.
  const previewAt = new Map();

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
  // (The Edit canvas API, `window.lumina.edit`, is further down; `edit` is hoisted for the loops above.)
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
  // Session writes debounce at 500 ms after the last Edit change (addendum §6): a slider drag
  // never writes mid-drag; the look lands half a second after the thumb stops.
  const SAVE_DEBOUNCE = 500;
  let lastChange = 0, saveTimer = 0;
  const saveNow = () => {
    const l = current;
    if (!(l && l.real && shootId && !reading && !l.state.realLoad)) return;
    if (performance.now() - lastChange < SAVE_DEBOUNCE) { scheduleSave(); return; }
    const json = JSON.stringify(snapshot(l));
    if (json !== lastSaved) { lastSaved = json; base = JSON.parse(json); native('saveSession', { id: shootId, json, summary: summary(l) }); }
  };
  const scheduleSave = () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => { saveTimer = 0; saveNow(); }, Math.max(1, SAVE_DEBOUNCE - (performance.now() - lastChange) + 1));
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
        // The Edit canvas overlay shows only while Edit is the active step.
        if (v !== 'edit' && edit.state().visible && !edit.state().force) edit.layout(null, false);
        if (v === 'edit') edit.pollRect();
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
    cardPending: null,     // { name, path, uuid, photos: null, sony: null, known: false }: a card the Mac will let Lumina read only
                           // once it is picked (App Sandbox, first time for this card); impStart() asks for it (DESIGN-ASKS Prompt 9)
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
    // How alike two photos are, for stacking retakes (DESIGN-ASKS Prompt 2 C): 0 is the same image,
    // about 1 is unrelated, measured by the Mac on the embedded previews (never a RAW decode). Takes
    // two photo paths; resolves once both are measured, to null when either can't be. Two photos
    // are one picture at or under nearLimit, which is the Mac's because it belongs to its measure
    // (null when the Mac has no threshold for its measure: keep the page's own rule then).
    near: (a, b) => {
      const A = previewAt.get(String(a)), B = previewAt.get(String(b));
      if (!A || !B || window.lumina.nearLimit == null) return Promise.resolve(null);
      return native('near', { a: A, b: B }).then(d => (typeof d === 'number' && isFinite(d) ? d : null), () => null);
    },
    nearLimit: typeof cfg.nearLimit === 'number' ? cfg.nearLimit : null,
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
      // One RAW per body: the Mac measures each body's decoder map once (RAW 9 §1) for the shoot header.
      const bodies = {}; for (const p of logic.real) { const m = p.model || '?', k = keyOf(p); if (m && k && !bodies[m]) bodies[m] = (info.name || '') + '/' + k; }
      const r = await native('shootOpened', { name: info.name, n: logic.real.length, date: first, bodies });
      shootId = r && r.id; lastSaved = ''; base = null; savedKeepers = null;
      edit.header(r && r.header);
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
      // The read below starts from empty decisions and brings them back from the session: write
      // the open shoot's now, or what was decided since the last 2 s autosave is lost (a card
      // re-inserted right after a keep, the same folder opened again).
      saveNow();
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
          previewAt.set(rel, pq);
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
        // The page's 360 px measuring bitmap: the same two calls as the page (turn upright, then
        // createImageBitmap at 360, 'medium'), made in a worker when there is one. In the page they
        // decode the whole embedded JPEG on its main thread, which is what a read waits on; the
        // bitmap comes back by transfer and the measures run here on the same pixels.
        const made = measurePool ? await measurePool(blob, ori) : null;
        let sm = made && made.sm;
        if (sm) { if (made.blob) blob = made.blob; }
        else {
          if (ori === 3 || ori === 6 || ori === 8) { const b0 = await createImageBitmap(blob, { imageOrientation: 'none' }), sw = ori !== 3, c = document.createElement('canvas'); c.width = sw ? b0.height : b0.width; c.height = sw ? b0.width : b0.height; const x = c.getContext('2d'); x.translate(c.width / 2, c.height / 2); x.rotate(ori === 6 ? Math.PI / 2 : ori === 8 ? -Math.PI / 2 : Math.PI); x.drawImage(b0, -b0.width / 2, -b0.height / 2); b0.close(); blob = await new Promise(res => c.toBlob(res, 'image/jpeg', 0.92)); }
          sm = await createImageBitmap(blob, { resizeWidth: 360, resizeQuality: 'medium' });
        }
        portrait = sm.height > sm.width; me = LuminaCore.measure(sm); sm.close();
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
    // The measuring bitmap, off the page's thread (see readOne). The worker runs the page's own
    // steps: an orientation of 3 / 6 / 8 is turned on a canvas and re-encoded at 0.92 exactly as the
    // page does, then createImageBitmap(…, { resizeWidth: 360, resizeQuality: 'medium' }). It answers
    // { sm, blob } (blob: the turned JPEG, when it turned one), or { sm: null } and the page does it.
    // `measureWorker: false` in the app config keeps everything on the page (the probe compares the two).
    const measurePool = (() => {
      if (cfg.measureWorker === false || typeof Worker !== 'function' || typeof OffscreenCanvas !== 'function') return null;
      try {
        const src = 'onmessage = async e => { const { id, blob, ori } = e.data; try { let b = blob;' +
          ' if (ori === 3 || ori === 6 || ori === 8) { const b0 = await createImageBitmap(blob, { imageOrientation: "none" }), sw = ori !== 3,' +
          ' c = new OffscreenCanvas(sw ? b0.height : b0.width, sw ? b0.width : b0.height), x = c.getContext("2d");' +
          ' x.translate(c.width / 2, c.height / 2); x.rotate(ori === 6 ? Math.PI / 2 : ori === 8 ? -Math.PI / 2 : Math.PI);' +
          ' x.drawImage(b0, -b0.width / 2, -b0.height / 2); b0.close(); b = await c.convertToBlob({ type: "image/jpeg", quality: 0.92 }); }' +
          ' const sm = await createImageBitmap(b, { resizeWidth: 360, resizeQuality: "medium" });' +
          ' postMessage({ id, sm, blob: b === blob ? null : b }, [sm]); } catch (_) { postMessage({ id, sm: null, blob: null }); } };';
        const url = URL.createObjectURL(new Blob([src], { type: 'text/javascript' }));
        const size = Math.max(2, Math.min(4, (navigator.hardwareConcurrency || 4) - 2));
        const ws = Array.from({ length: size }, () => new Worker(url)), wait = new Map(); let n = 0;
        ws.forEach(w => { w.onmessage = e => { const f = wait.get(e.data.id); wait.delete(e.data.id); f && f(e.data); }; w.onerror = () => {}; });
        return (blob, ori) => new Promise(res => { const id = ++n; wait.set(id, res); ws[id % ws.length].postMessage({ id, blob, ori }); });
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
      previewAt.clear();
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
      const info = logic.state.realInfo || {};
      if (label === 'jpeg') {
        // The Edit step's JPEGs (Prompt 1 §7): {name, look: {src, look, px}} rendered natively through
        // LookPipeline with the decoder the shoot pins for that body; the result names the decoder.
        const byPath = {}; for (const p of Object.values((logic.data && logic.data.byId) || {})) if (p.path) byPath[p.path] = p;
        const list = files.filter(f => f && f.look && f.look.src).map(f => ({ name: f.name, look: { src: f.look.src, look: f.look.look || '', px: f.look.px == null ? null : f.look.px, model: (byPath[f.look.src] || {}).model || null } }));
        return native('writeInto', { label: 'jpeg', files: list });
      }
      if (label !== 'xmp') return null;
      // The page merged each rating into the sidecar text it holds from the open (xmpFor on p.xmp),
      // which can be hours old: Lightroom may have written the file since. So the Mac reads every
      // sidecar again now (text + base: the SHA-256 of those bytes, or "none"). Where the text differs
      // from the page's, the photo gets the text on disk and the page's own xmpFor merges again. The
      // base goes with the write: a file that is no longer its base (written in the instant between)
      // is left as it is and comes back "changed on disk"; nothing is retried silently (SAFETY.md 6),
      // the next Save reads again. The text from the open is never written over a newer file.
      const root = info.name || '', enc = new TextEncoder(), byId = (logic.data && logic.data.byId) || {}, owner = {}, now = {};
      // A file's photo, by the name the page's runExport gave the file (xpath without the folder's name).
      for (const [id, p] of Object.entries(byId)) { const q = (p.xpath || (p.file || '').replace(/\.[^.]+$/, '') + '.xmp').split('/'); owner[q.length > 1 ? q.slice(1).join('/') : q[0]] = id; }
      for (const s of (await native('readSidecars', { root, files: files.map(f => f.name) })) || []) now[s.name] = s;
      const list = [];
      for (const f of files) {
        const s = now[f.name], id = owner[f.name], p = id != null ? byId[id] : null, it = { name: f.name };
        let d = f.data;
        if (p && s && s.base != null) {
          const tx = s.text == null ? null : s.text;
          if ((p.xmp || null) !== (tx || null)) { p.xmp = tx; p.lrEd = LuminaCore.hasDevelop(tx); d = logic.xmpFor(id); }
          it.base = s.base;
        } else if (p) it.base = 'unread';                    // couldn't be read now: no file matches this, the write says why
        // (No photo for the name: nothing the page merged from. Sent as it is, unchecked.)
        const u = d instanceof Uint8Array ? d : d instanceof Blob ? new Uint8Array(await d.arrayBuffer()) : typeof d === 'string' ? enc.encode(d) : null;
        if (u) { it.b64 = b64(u); list.push(it); }
      }
      const r = await native('writeSidecars', { root, files: list });
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

  // ——— The Edit canvas (roadmap addendum, RAW 9). Behaviour and data only: the page draws the
  // filmstrip, sliders and facts; the Mac draws the pixels, either natively (an MTKView over the
  // page's canvas rect: `canvas: native`) or, without Metal, through lumina://render images the
  // page shows in its own <img> (`canvas: image`). The page's contract is DESIGN-ASKS Prompt 1 §3:
  //   window.lumina.preview(rel, look, px, seq) → a lumina://render URL (image path) or null (native)
  //   window.lumina.canvasRect({x, y, w, h, dpr} | null)   on Edit open, layout, resize, scroll, zoom
  //   window.lumina.drag('start' | 'end')                  a slider's pointer-down / release
  //   window.lumina.roi({x, y, w, h} | null)               the visible region at 100 % (also refines it with RAW 9)
  // and the hooks the app calls (optional; no-ops when absent):
  //   window.luminaPresented(seq)                          the request is on screen (native path)
  //   window.luminaHistogram({seq, r, g, b, clipHi, clipLo})   256 bins, rest renders only
  //   window.luminaFacts({canvas, raw9, decoder, note})    the facts line's app part
  //   window.luminaEditStats(stats)                        the addendum: stats.facts.source 'raw9-region' for the flag words
  //   window.luminaEditImage(url, seq, tier)               image path helper: the URL of the newest render that loaded (the probe's)
  // `lumina.edit.*` below is the superset the probe and the harness drive; the page needs only the four calls above.
  const hook = (name, ...a) => { try { return typeof window[name] === 'function' ? window[name](...a) : undefined; } catch (_) { return undefined; } };
  // The page's monotonic clock (ms). The Mac measures its offset to its own clock from the message
  // transit times, so a look event and the frame that shows it are timed on one base.
  const pageNow = () => performance.now();
  const dpr = () => Math.max(1, window.devicePixelRatio || 1);
  // Encoded with encodeURIComponent (`query`, as media URLs), not URLSearchParams: the latter writes a
  // space as '+', and a look's sign ('ev:+0.30') must stay a '+'. Each path segment on its own.
  const renderURL = (rel, q) => (location.protocol === 'lumina:' ? 'lumina://render/' : location.origin + '/render/') + rel.split('/').map(encodeURIComponent).join('/') + '?' + query(q);
  const ed = { rel: null, look: '', model: null, rect: null, visible: false, dragging: false, path: 'image', native: null, header: null, factsText: '', roi: null, loupe: false, seq: 0, decoder: null, rectTimer: 0, preview: null };
  // The image path's latest-wins renderer (addendum §7): one fetch in flight, the newest look
  // waits, a quarter-size render while dragging, the full one at rest (drag end, key, 120 ms idle).
  const img = { pending: null, inFlight: false, shown: 0, tier: null, url: null, fetches: 0, superseded: 0, restTimer: 0, last: null };
  // The embedded JPEG's byte range (o, l, ori) rides along so the Mac can stand it in when the RAW can't be developed.
  const withPreview = q => { const p = ed.preview; if (p && +p.l > 0) { q.o = p.o; q.l = p.l; q.ori = p.ori || 1; } return q; };
  const imgSubmit = (tier, key) => {
    if (!ed.rel || !ed.rect) return;
    ed.seq++;
    img.pending = { look: ed.look, seq: ed.seq, tier, key: !!key };
    clearTimeout(img.restTimer); img.restTimer = 0;
    if (tier === 'small') img.restTimer = setTimeout(() => { if (ed.rel && img.tier !== 'base') imgSubmit('base'); }, 120);
    imgRender();
  };
  // Loaded through an <img>, not fetch(): lumina://render is another host than the page's
  // lumina://app, so a fetch would need CORS; an image load doesn't, and it decodes off the main
  // thread. A superseded request (409) fails the load and counts as superseded.
  const imgRender = async () => {
    if (img.inFlight || !img.pending || !ed.rel || !ed.rect) return;
    const p = img.pending; img.pending = null; img.inFlight = true; img.fetches++;
    const px = Math.max(64, Math.round(Math.max(ed.rect.w, ed.rect.h) * dpr()));
    const q = { look: p.look, px, seq: p.seq, tier: p.tier }; if (ed.decoder != null) q.decoder = ed.decoder;
    const url = renderURL(ed.rel, withPreview(q));
    const ok = await new Promise(res => { const im = new Image(); im.decoding = 'async'; im.onload = () => res(true); im.onerror = () => res(false); im.src = url; });
    if (!ok) img.superseded++;
    else if (p.seq > img.shown) { img.url = url; img.shown = p.seq; img.tier = p.tier; img.last = p; hook('luminaEditImage', url, p.seq, p.tier); }
    img.inFlight = false;
    if (img.pending) imgRender();
  };
  // The app's part of the facts line (Prompt 1 §3): `canvas: native · raw 9: yes` + a note.
  const factsNote = () => {
    const h = ed.header || {}, notes = [];
    if (h.offerUpdate) notes.push('decoder ' + h.decoder + ' pinned · update shoot');
    if (ed.native) { const n = ed.native.replace(/^canvas: (native|image)( · )?/, '').replace(/^(raw \d+|image file|from the embedded JPEG)( · )?/, ''); if (n) notes.push(n); }
    return notes.length ? notes.join(' · ') : null;
  };
  const factsObj = () => { const h = ed.header || {}; return { canvas: ed.path, raw9: !!h.raw9, decoder: h.decoder != null ? String(h.decoder) : null, note: factsNote() }; };
  const factsText = () => {
    const h = ed.header || {}, f = factsObj(), parts = ['canvas: ' + f.canvas];
    if (h.raw9Present != null) parts.push('raw 9: ' + (f.raw9 ? 'yes' : 'no'));
    if (f.note) parts.push(f.note);
    return parts.join(' · ');
  };
  // `force`: on entering Edit the page has just mounted its hooks, so tell it even if nothing changed.
  const pushFacts = force => { const t = factsText(); if (force || t !== ed.factsText) { ed.factsText = t; const f = factsObj(); hook('luminaFacts', f); hook('luminaEditFacts', t, Object.assign(f, edit.facts())); } };
  const photoAt = (l, rel) => { for (const [id, p] of Object.entries(l.data.byId)) if ((l.state.realInfo && l.state.realInfo.name || '') + '/' + keyOf(p) === rel || p.path === rel) return [id, p]; return [null, null]; };
  const edit = {
    // Entering Edit for a photo (its path, "<folder>/DSC.ARW"): the Mac builds its bases now and its
    // neighbours' in the background. `look` is the photo's look string.
    async enter(rel, look) {
      const l = current; if (!l || !l.data) return null;
      const [id, p] = photoAt(l, rel); if (!p) return null;
      const o = l.data.order, k = o.indexOf(id), nb = d => { const q = l.data.byId[o[k + d]]; return q ? [q.path, previewOf(q.lg)] : [null, null]; };
      const [prev, prevPreview] = nb(-1), [next, nextPreview] = nb(1);
      ed.rel = rel; ed.model = p.model || null; ed.look = look || (l.state.look || {})[id] || ''; ed.loupe = false; ed.roi = null; ed.preview = previewOf(p.lg);
      img.shown = 0; img.tier = null; img.pending = null; ed.seq = 0;
      const r = await native('canvasEnter', { rel, look: ed.look, model: ed.model, preview: previewOf(p.lg), prev, prevPreview, next, nextPreview });
      if (r && typeof r === 'object') { ed.header = Object.assign({}, ed.header || {}, r); ed.path = r.canvas || 'image'; ed.decoder = r.decoderCanvas != null ? r.decoderCanvas : null; }
      pushFacts(true);
      if (ed.path === 'image') imgSubmit('base', true);
      return edit.facts();
    },
    leave() { ed.rel = null; ed.loupe = false; clearTimeout(img.restTimer); img.pending = null; native('canvasLeave', {}); edit.layout(null, false); },
    // The canvas rect in CSS px from the page's top-left, on layout and resize; `visible` = Edit shows.
    // {force: true} (the probe) keeps the canvas up whatever the page's view is.
    layout(rect, visible, o) {
      ed.force = !!(o && o.force) && !!visible;
      ed.rect = rect && rect.w > 0 && rect.h > 0 ? { x: rect.x, y: rect.y, w: rect.w, h: rect.h } : null; ed.visible = !!visible && !!ed.rect;
      native('canvasLayout', Object.assign({ visible: ed.visible, dpr: dpr() }, ed.rect || { x: 0, y: 0, w: 0, h: 0 })).then(r => { if (r && r.path) { ed.path = r.path; pushFacts(); } }).catch(() => {});
      if (ed.path === 'image' && ed.visible && ed.rel && !img.shown) imgSubmit('base', true);
    },
    // A slider value, as often as the slider emits. {drag: true} while the thumb is held, {key: true}
    // for a keystroke, roi: the visible region {x, y, w, h} in fractions of the frame when zoomed.
    look(look, o) {
      o = o || {};
      ed.look = look; lastChange = performance.now(); scheduleSave();
      if (o.roi !== undefined) ed.roi = o.roi;
      if (!ed.rel) return 0;
      if (ed.path === 'native') { const seq = o.seq != null ? o.seq : ++ed.seq; ed.seq = Math.max(ed.seq, seq); native('canvasLook', { look, drag: !!o.drag && !o.key, key: !!o.key, roi: ed.roi, t: pageNow(), seq }).catch(() => {}); return seq; }
      imgSubmit(o.drag && !o.key ? 'small' : 'base', o.key); return ed.seq;
    },
    // Prompt 1 §3: the page's one preview call. Native path: the look goes to the canvas and null
    // comes back (the app presents; luminaPresented(seq) follows). Image path: the URL to show,
    // quarter-size while a slider drags, full otherwise; superseded requests answer 409.
    preview(rel, look, px, seq) {
      if (!rel) return null;
      if (ed.rel !== rel) edit.enter(rel, look || '');
      ed.look = look || ''; lastChange = performance.now(); scheduleSave();
      if (ed.path === 'native') { if (ed.rect) edit.look(ed.look, { drag: ed.dragging, seq }); return null; }
      const q = { look: ed.look, px: Math.max(64, Math.round(px || (ed.rect ? Math.max(ed.rect.w, ed.rect.h) * dpr() : 1024))), seq: seq != null ? seq : ++ed.seq, tier: ed.dragging ? 'small' : 'base' };
      if (ed.decoder != null) q.decoder = ed.decoder;
      ed.seq = Math.max(ed.seq, q.seq);
      return renderURL(rel, withPreview(q));
    },
    canvasRect(r) { edit.layout(r, !!r); },
    drag(what) { if (what === 'start') edit.dragStart(); else edit.dragEnd(); },
    // The visible region at 100 %: small renders show only it, and the Mac refines it with RAW 9.
    roi(r) { ed.roi = r || null; edit.loupe(!!r, r || undefined); },
    dragStart() { ed.dragging = true; lastChange = performance.now(); if (ed.rel) native('canvasDrag', { start: true }); },
    dragEnd() { ed.dragging = false; lastChange = performance.now(); scheduleSave(); if (!ed.rel) return; native('canvasDrag', { start: false }); if (ed.path === 'image') { clearTimeout(img.restTimer); imgSubmit('base'); } },
    // 100 % with G held: RAW 9 on the visible region (RAW 9 §2).
    loupe(on, roi) { ed.loupe = !!on; if (roi) ed.roi = roi; if (ed.rel) native('canvasLoupe', { on: !!on, roi: ed.roi }); },
    // The facts line's inputs: the canvas path, raw 9 yes/no, the pin, the offer (+ Prompt 1's {canvas, raw9, decoder, note}).
    facts() { return Object.assign({ text: factsText(), rel: ed.rel }, ed.header || {}, factsObj()); },
    // The Mac's numbers (the probe reads them): latency, dropped frames, bases resident, tiles, …
    stats(reset) { return native('canvasStats', { reset: !!reset }); },
    // The facts line's offer: pin the shoot to the newest decoder (RAW 9 §7).
    updateDecoder() { return native('decoderUpdate', {}).then(h => { edit.header(h); return edit.facts(); }); },
    header(h) { if (h && typeof h === 'object') { ed.header = Object.assign({}, ed.header || {}, h); if (h.canvas) ed.path = h.canvas; } pushFacts(); },
    // The page reports its rect itself (layout), or exposes luminaEditRect(): polled while Edit shows.
    pollRect() {
      clearTimeout(ed.rectTimer);
      const l = current; if (!l || l.state.view !== 'edit' || typeof window.luminaEditRect !== 'function') return;
      const r = window.luminaEditRect();
      const same = ed.rect && r && ed.rect.x === r.x && ed.rect.y === r.y && ed.rect.w === r.w && ed.rect.h === r.h;
      if (!same || !ed.visible) edit.layout(r, !!r);
      ed.rectTimer = setTimeout(edit.pollRect, 250);
    },
    get image() { return img.url; },
    state() { return { rel: ed.rel, look: ed.look, path: ed.path, rect: ed.rect, visible: ed.visible, force: !!ed.force, dragging: ed.dragging, seq: ed.seq, loupe: ed.loupe, roi: ed.roi,
      image: { shown: img.shown, tier: img.tier, fetches: img.fetches, superseded: img.superseded, inFlight: img.inFlight, pending: !!img.pending, url: img.url }, facts: ed.factsText, header: ed.header }; },
  };
  window.lumina.edit = edit;
  // Prompt 1 §3's four calls, on window.lumina itself.
  window.lumina.preview = edit.preview;
  window.lumina.canvasRect = edit.canvasRect;
  window.lumina.drag = edit.drag;
  window.lumina.roi = edit.roi;
  window.addEventListener('resize', () => { if (ed.visible || (current && current.state.view === 'edit')) edit.pollRect(); });

  watch();
  saveLoop();
  viewLoop();

  // Native → page. Only the page's own actions and hooks are used.
  window.__lumina = {
    // The Edit canvas talking back: the facts line, rest-render stats, presented frames, the shoot header.
    editFacts(text) { ed.native = text || ''; pushFacts(); },
    editStats(stats) {
      if (stats && stats.histogram) hook('luminaHistogram', { seq: stats.seq, r: stats.histogram.r, g: stats.histogram.g, b: stats.histogram.b, clipHi: stats.clipHi, clipLo: stats.clipLo });
      hook('luminaEditStats', stats);
    },
    editPresented(seq) { hook('luminaPresented', seq); },
    editHeader(h) { edit.header(h); },
    edit: () => edit.state(),
    logic: () => current || findLogic(),
    ready: () => !!(current && current.__luminaPlumbed && !missing(current).length),
    missing: () => { const l = current || findLogic(); return l ? missing(l) : ['page not found']; },
    drift: () => drift(current || findLogic()),
    readHash: () => readHash(current || findLogic()),
    shootId: () => shootId,
    card(present, info) {
      if (cfg.parity) return;              // test-only: keep the sample card for pixel parity
      // A card not readable yet (sandbox, first insert) has no count and no Sony flag. As `card` the
      // page would read it as "no ARW found · 0 photos" with nothing to click, so it waits in
      // `cardPending` (data only) until the user picks it and the app sends the whole card.
      const pending = !!(present && info && info.known === false);
      window.lumina.cardPending = pending ? info : null;
      window.lumina.card = present && !pending ? (info || {}) : null;
      const l = window.__lumina.logic();
      if (!present && l && l.state.realLoad) cardPulledWhileReading = true;
      if (l) { l.impSet({ card: !!window.lumina.card }); l.forceUpdate && l.forceUpdate(); }
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
        shootId, card: window.lumina.card, cardPending: window.lumina.cardPending, readingCard: window.lumina.readingCard,
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
