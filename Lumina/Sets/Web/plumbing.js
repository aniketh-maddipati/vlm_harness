// Lumina app plumbing. Injected at document start into the design's page, which ships byte-identical.
// This file is the only place the app differs from the prototype: it swaps the page's browser I/O
// (openFolder / onDir / writeInto keep their names, only the insides change) for calls to the native
// bridge, and provides `window.lumina`, the page's data contract. Layout, styles, copy and keys are
// untouched: plumbing supplies behaviour and data, never UI.
(() => {
  const cfg = Object.assign({}, window.__luminaConfig || {});
  const native = (op, args) => window.webkit.messageHandlers.lumina.postMessage(Object.assign({ op }, args || {}));
  // The page's notices (CHANGES-v0.04 A4): its own words for a folder too big to be a shoot, a sidecar
  // the Mac did not read, a session the Mac refused.
  // Result reasons are the page's REASON keys (CHANGES-v0.04 D1/D2, PARITY-v0.05 §4). The Mac's
  // other words fold into the nearest one; 'on the card' stays (the page's Save guard comes first).
  const REASONS = ['changed on disk', 'unreadable', 'name too long', 'locked', 'read-only', 'missing', 'disk full', 'failed', 'on the card'];
  const reasons = r => {
    if (r && Array.isArray(r.errors)) r.errors.forEach(e => { if (e && !REASONS.includes(e.reason)) e.reason = e.reason === 'over 1 MB' ? 'unreadable' : 'failed'; });
    return r;
  };
  const notice = (kind, info) => { try { return typeof window.luminaNotice === 'function' ? window.luminaNotice(kind, info || {}) : false; } catch (_) { return false; } };

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
    'writeInto', 'runExport', 'impStart', 'impSet', 'libOpen', 'build', 'forget', 'kept', 'undec', 'land', 'xmpFor', 'reveal',
    'scrollAnchor', 'bridgeEmit', 'reshift', 'editShoot'];
  const GLOBALS = { 'LuminaCore.parseHead': () => window.LuminaCore && LuminaCore.parseHead, 'LuminaCore.measure': () => window.LuminaCore && LuminaCore.measure,
    'LuminaCore.hasDevelop': () => window.LuminaCore && LuminaCore.hasDevelop, 'LuminaCore.buildShoot': () => window.LuminaCore && LuminaCore.buildShoot,
    'LuminaCore.phoneOf': () => window.LuminaCore && LuminaCore.phoneOf, 'LuminaCore.assemblePreview': () => window.LuminaCore && LuminaCore.assemblePreview,
    'LuminaV4.fmt.base': () => window.LuminaV4 && LuminaV4.fmt && LuminaV4.fmt.base };
  // Set by the page when it mounts (MENUS.md, SAFETY.md 3 and 5).
  const HOOKS = ['luminaCommand', 'luminaCardGone', 'luminaAccess', 'luminaState', 'luminaStep', 'luminaOpening', 'luminaNotice'];
  const missing = logic => REQUIRED.filter(k => typeof logic[k] !== 'function').concat(
    logic.constructor && Array.isArray(logic.constructor.SHOOTS) ? [] : ['static SHOOTS'],
    logic.constructor && typeof logic.constructor.clean === 'function' ? [] : ['static clean'],
    Object.keys(GLOBALS).filter(k => typeof GLOBALS[k]() !== 'function'),
    HOOKS.filter(k => typeof window[k] !== 'function').map(k => 'window.' + k));
  // The native read (below) repeats the page's onDir and readOne step for step. When a design sync
  // changes either, the contract check reports it so the repeat gets reviewed; the app keeps working.
  const ONDIR = 623750811;
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
  let shootId = null, lastSaved = '', base = null, savedKeepers = null, cardPulledWhileReading = false, sessionRefused = null;
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
    // Shift Capture Time (CHANGES-v0.04 B2): the page's shifts, by photo path, kept with the session only.
    out.shifts = logic._shifts || [];
    return out;
  };
  // For the Open screen's recent cards: the same numbers the prototype's persist() keeps.
  const summary = logic => ({ n: logic.data.order.length, dec: logic.data.order.filter(id => !logic.undec(id)).length,
    kp: logic.kept().length, last: LuminaV4.fmt.base((logic.data.byId[logic.state.cur] || {}).file) || '' });
  // `live`: the reader moved or decided while the folder was being read. Those decisions win over
  // the saved ones and the cursor stays where it is (nothing jumps when the read ends).
  const restore = (logic, saved, live) => {
    base = saved; savedKeepers = typeof saved.saved === 'string' ? saved.saved : null;
    // The shoot's capture-time shifts come first: rows, stacks and ids are built from the shifted times.
    // The page's reshift remaps what was decided during the read; without one, a plain rebuild.
    if (Array.isArray(saved.shifts) && saved.shifts.length) {
      if (live && typeof logic.reshift === 'function') logic.reshift(saved.shifts);
      else { logic._shifts = saved.shifts; logic.data = logic.build(logic.state.cuts || {}); }
    }
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
  const saveNow = force => {
    const l = current;
    if (!(l && l.real && shootId && !reading && !l.state.realLoad)) return;
    if (!force && performance.now() - lastChange < SAVE_DEBOUNCE) { scheduleSave(); return; }
    const json = JSON.stringify(snapshot(l));
    if (json !== lastSaved) {
      lastSaved = json; base = JSON.parse(json);
      // A session over the Mac's limit (threat model T5) is refused: the page says so once per shoot
      // (luminaNotice 'sessionBig'). Other failures stay as before (not shown). A write changes the
      // working files' size: pushed to the storage meter (BRIDGE-v0.03 §7, luminaWorkingFiles).
      const id = shootId;
      Promise.resolve(native('saveSession', { id, json, summary: summary(l) })).then(() => {
        if (cfg.parity || typeof window.luminaWorkingFiles !== 'function' || shootId !== id) return;
        return native('workingFiles', { id }).then(b => { if (b != null && shootId === id) window.luminaWorkingFiles(b); }, () => {});
      }).catch(err => {
        if (!/too big/.test(String((err && err.message) || err))) throw err;
        if (sessionRefused !== id) { sessionRefused = id; notice('sessionBig', {}); }
      });
    }
  };
  const scheduleSave = () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => { saveTimer = 0; saveNow(); }, Math.max(1, SAVE_DEBOUNCE - (performance.now() - lastChange) + 1));
  };
  // Every 2 s and on every view change (SAFETY.md 2). A decision (keep, drop, flag, star, cut, a row
  // seen) is saved on the next 150 ms tick, not the next 2 s one: the page's process can be gone
  // within a second of a key. The page replaces these objects on every change, so identity tells.
  const DECISIONS = ['marks', 'flags', 'stars', 'cuts', 'seen'];
  let lastView = null, lastDecided = null, lastDecisions = [];
  const decided = l => {
    if (!(l && l.real && shootId)) { lastDecided = null; return false; }
    const now = DECISIONS.map(k => l.state[k]), same = lastDecided === shootId && now.every((v, i) => v === lastDecisions[i]);
    const first = lastDecided !== shootId;
    lastDecided = shootId; lastDecisions = now;
    return !same && !first;
  };
  // The window going to the background is the last moment timers run at full rate: save then,
  // without waiting for a slider's debounce.
  const saveLeaving = () => { try { saveNow(true); } catch (_) {} };
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') saveLeaving(); });
  window.addEventListener('blur', saveLeaving);
  window.addEventListener('pagehide', saveLeaving);
  const saveLoop = () => {
    try { saveNow(); } finally { setTimeout(saveLoop, 2000); }
  };
  const viewLoop = () => {
    try {
      const l = current, v = l && l.state.view;
      if (decided(l)) saveNow();
      if (v !== lastView) {
        lastView = v; saveNow();
        // The Edit canvas overlay shows only while Edit is the active step.
        // (Edit v22 sends canvasRect(null) itself when it unmounts; this covers a page that doesn't.)
        if (v !== 'edit' && edit.state().visible && !edit.state().force) { edit.layout(null, false); watchHoles(false); }
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
    // Exports a crash or kill cut short, found at launch (SetsExportJournal.recover): the page says so
    // once on Open (CHANGES-v0.04 D3). [{folder, done, planned, cleaned}], newest first.
    cutShort: Array.isArray(cfg.cutShort) ? cfg.cutShort : [],
    // Help ▸ Acknowledgements (Prompt 7): the bundled THIRD-PARTY-NOTICES.txt.
    notices: () => native('notices', {}),
    // Warm-ahead lists from Sets and Edit (BRIDGE-v0.03 §6).
    prefetch: list => prefetch(list),
    // The page's events (BRIDGE-v0.03 §3): flow, moved, stayed, readEnd, leadReady, shifted, openCancel.
    // Esc on "Opening <name>…" cancels the listing, so a late answer can't open the folder.
    emit: (type, detail) => {
      events.push({ type, detail, t: Math.round(performance.now()) }); if (events.length > 200) events.shift();
      if (type === 'openCancel') native('openCancel', {}).catch(() => {});
    },
  });
  const events = [];
  // Parity mode (test only): the storage meter is measured the prototype's way (see patch), so the page
  // must not ask the Mac for its working files either; it asks on mount, before patch runs.
  if (cfg.parity) delete window.lumina.workingFiles;

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

    // Parity mode (test only): the storage meter (header, Save) counts the Mac's working files in the app
    // and the browser's own storage in the prototype. Measure it the prototype's way so the twins compare.
    if (cfg.parity) for (const k of ['cacheParts', 'cacheView']) {
      if (typeof logic[k] !== 'function') continue;
      const f = logic[k].bind(logic), C = logic.constructor;
      logic[k] = () => { const app = C.app; C.app = () => false; try { return f(); } finally { C.app = app; } };
    }

    // The Edit step's photos (Edit v22 reads them through window.luminaShoot = editShoot). The page
    // names a photo by its file name without the folder or extension, so the canvas could not find
    // it: give each one its path in the opened folder as `rel` (the page's rel(p) prefers it), and the
    // RAW's own as-shot white balance once the Mac has read it (`asShot`, from the canvas's base).
    const editShoot0 = logic.editShoot.bind(logic);
    logic.editShoot = () => {
      const s = editShoot0(); if (!s || !Array.isArray(s.P)) return s;
      const name = (logic.state.realInfo && logic.state.realInfo.name) || '';
      for (const p of s.P) { const f = logic.data.byId[p.id], k = keyOf(f); if (!f || !k) continue; p.rel = name + '/' + k; applyAsShot(p); }
      return s;
    };

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
      // The Mac lets the canvas go when a shoot opens. A photo already in Edit (the read ended under
      // it) goes back on, at the rect the page last gave.
      if (ed.rel) { const rel = ed.rel, look = ed.look; ed.rel = null; edit.enter(rel, look).then(() => { if (ed.rel === rel && ed.rect) edit.layout(ed.rect, ed.visible || ed.force, { holes: ed.holes, force: ed.force }); }).catch(() => {}); }
      const live = !!(logic._readEnd && logic._readEnd.stay);
      if (r && r.session) { try { restore(logic, JSON.parse(r.session), live); } catch (_) {} }
      // Decisions made while the folder was read aren't in the session yet: the next save sends them.
      lastSaved = live ? '' : JSON.stringify(snapshot(logic));
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
      // The Mac shows "Opening <name>…" (window.luminaOpening) once the folder is picked and clears it
      // here, whatever the listing's outcome.
      const L = await native('openFolder', {});
      if (typeof window.luminaOpening === 'function') window.luminaOpening(null);
      if (!L) return;                                        // cancelled (or Esc while it was listed)
      if (L.denied != null) { window.luminaAccess(true, L.denied); return; }
      window.luminaAccess(false);
      // `/`, a home folder, a whole disk: the Mac stopped listing it (threat model T5).
      if (L.tooBig) { notice(L.tooBig.why === 'tooDeep' ? 'tooDeep' : 'tooBig', { folder: L.tooBig.name }); return; }
      window.luminaCardGone(false);
      window.lumina.readingCard = !!L.onCard;
      await ingest(L);
      await afterRead();
    };

    // One ARW or DNG, as the page's readOne reads it, from the Mac's reader.
    const readOne = async (f, xmpMap) => {
      const rel = f.rel, name = rel.split('/').pop();
      const head = new Uint8Array(await (await get(media('head', { p: rel }))).arrayBuffer());
      const m = LuminaCore.parseHead(head, f.size); if (!m) throw new Error('unreadable');
      let blob = null, pq = null, nt = null;
      // The page tries each embedded preview in turn; the first that starts FF D8 wins.
      for (const [po, pl] of (m.previews && m.previews.length ? m.previews : m.preview ? [m.preview] : [])) {
        if (po + pl > f.size) continue;
        const q = { p: rel, o: po, l: pl, ori: m.orient || 1 };
        // As stored (ori 1): the page's own canvas turns it, below.
        const b = await (await get(media('preview', Object.assign({}, q, { ori: 1 })))).blob();
        const sig = new Uint8Array(await b.slice(0, 2).arrayBuffer());
        if (sig[0] !== 0xFF || sig[1] !== 0xD8) continue;
        blob = b; pq = q;
        previewAt.set(rel, pq);
        nt = nativeTile(pq);                                 // made by the Mac while the page measures
        break;
      }
      // Tiled or multi-strip previews, or only an RGB thumbnail: the page assembles them on a canvas
      // from byte ranges of the file, which the Mac reads here as it reads a preview.
      if (!blob && (m.pvParts || m.pvRGB)) {
        const file = { name, size: f.size, slice: (o, e) => ({ arrayBuffer: async () => (await get(media('preview', { p: rel, o, l: e - o, ori: 1 }))).arrayBuffer() }) };
        try { const ap = await LuminaCore.assemblePreview(file, m); if (ap && ap.blob) { blob = ap.blob; m._lowpv = ap.low; } } catch (err) { if (err instanceof Gone) throw err; blob = null; }
      }
      const ph = LuminaCore.phoneOf(m); if (ph) { m.flReal = m.fl; if (m.fl35) m.fl = m.fl35; m.model = ph.short; m.lens = ph.zoom ? ph.zoom + ' camera' : m.lens; }
      const xk = rel.replace(/\.[^.\/]+$/, '').toLowerCase(), xo = xmpMap[xk] || null, xpath = xo ? xo.path : rel.replace(/\.[^.\/]+$/, '') + '.xmp';
      const baseP = { lowpv: !!m._lowpv, wbK: m.wbK ?? null, wbTint: m.wbTint ?? null, model: m.model || null, make: m.make || null, fnum: m.fnum || null, w: m.w || null, h: m.h || null, bytes: f.size, lens: m.lens || null, serial: m.serial || null,
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
      return Object.assign(baseP, { portrait, dhash: me.dhash, lum: me.lum, focus: me.focus, clip: me.clip, src: URL.createObjectURL(tb), lg: pq ? media('preview', pq) : URL.createObjectURL(blob) });
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
      // A sidecar that is there but is not UTF-8 text (L.unreadableXmp): no text to merge into, but the
      // photo keeps its path, so Save aims at that very file and the Mac refuses to replace it.
      for (const rel of L.unreadableXmp || []) { const k = rel.replace(/\.[^.\/]+$/, '').toLowerCase(); if (!xmpMap[k]) xmpMap[k] = { tx: null, path: rel }; }
      const arws = (L.files || []).map(f => Object.assign(fileRef(f.rel), { size: f.size }));
      const allF = arws.concat((L.xmp || []).map(x => fileRef(x.rel)), (L.others || []).map(fileRef));
      const files = (L.files || []).slice().sort((a, b) => a.rel.localeCompare(b.rel));
      logic._intake = logic.intake(allF, arws);
      if (!files.length) {
        const I = logic._intake, parts = [...Object.entries(I.raw).map(([e, n]) => n + ' ' + e.toUpperCase()), I.jp + I.ja ? (I.jp + I.ja) + ' JPEG / HEIF' : '', I.vid ? I.vid + ' videos' : ''].filter(Boolean);
        const msg = 'no ARW or DNG found' + (parts.length ? ' · ' + parts.join(' · ') + ' · Lumina reads ARW and DNG' : ' · 0 photos');
        logic.setState({ openNote: msg }); return logic.say(msg);
      }
      (logic.real || []).forEach(p => { p.src && URL.revokeObjectURL(p.src); /^blob:/.test(p.lg || '') && URL.revokeObjectURL(p.lg); });
      const run = reading = { name: L.name, total: files.length, done: 0, gone: false };
      const t0 = performance.now(), res = new Array(files.length); let done = 0, i = 0, pre = 0, shown = false, lastB = 0;
      previewAt.clear();
      logic._gold = []; logic._failed = []; logic.real = [];
      // The page's own read state: its onScroll marks the reader as moved (_rd) while _reading is set.
      logic._reading = true; logic._rd = { moved: false, cur: null, top: 0 };
      // Sidecars over 1 MB the Mac did not read (threat model T5): the page's notice lists each one.
      for (const rel of L.skippedXmp || []) notice('sidecarBig', { name: rel.split('/').pop() });
      // Sidecars that are not text (Latin-1, UTF-16, binary): the same list, until the page has its own line.
      for (const rel of L.unreadableXmp || []) logic._failed.push({ name: rel.split('/').pop(), reason: 'sidecar unreadable, not read' });
      if (!logic._addFrom) logic._shifts = [];
      logic.setState({ opening: null, realLoad: { done: 0, total: files.length, t0 }, realInfo: null, xsaved: {}, sel: {}, marks: {}, seen: {}, flags: {}, stars: {}, cuts: {}, undo: [], open: null, undec: false, pend: null });
      // Rows appear as the contiguous prefix grows, paced as the page paces them: not while the reader
      // scrolls (450 ms), at most every 700 ms, keeping the row at the top of the view where it was.
      const grow = force => {
        if (reading !== run) return;
        while (pre < files.length && res[pre] !== undefined) pre++;
        const now = performance.now(); if (!force && pre < 48) return;
        if (!force && Date.now() - (logic._scrollT || 0) < 450) { clearTimeout(logic._growT); logic._growT = setTimeout(() => grow(false), 480); return; }
        if (!force && now - lastB < 700) return; lastB = now;
        const anc = shown && typeof logic.scrollAnchor === 'function' ? logic.scrollAnchor() : null;
        logic.real = res.slice(0, pre).filter(p => p && !p.err); if (!logic.real.length) return; logic.data = logic.build(logic.state.cuts || {}); logic._lk = null; logic._anc = anc;
        if (!shown) {
          shown = true; logic._rd.cur = logic.data.order[0];
          const se = logic.scrollRef && logic.scrollRef.current; logic._rd.top = se ? se.scrollTop : 0;
          logic.setState({ cur: logic.data.order[0] }); logic.setView('cull', true);
        } else logic.forceUpdate();
      };
      // A file that can't be read stays, as a grey tile (CHANGES-v0.05 B1): the page's own record.
      // Only a pulled card drops what it cut off.
      const unread = f => {
        const pth = f.rel, xk = pth.replace(/\.[^.\/]+$/, '').toLowerCase(), xo = xmpMap[xk] || null;
        return { unread: true, nopv: true, name: pth.split('/').pop(), path: pth, date: '', bytes: f.size, fileObj: fileRef(pth), xpath: xo ? xo.path : pth.replace(/\.[^.\/]+$/, '') + '.xmp', xmp: xo && xo.tx,
          lrEd: LuminaCore.hasDevelop(xo && xo.tx), portrait: false, lum: null, focus: 0, clip: 0, dhash: null, src: '', lg: '', exp: null, fl: null, ev: null, iso: null };
      };
      const one = async (f, k) => {
        try { res[k] = await readOne(f, xmpMap); }
        catch (err) {
          if (err instanceof Gone) { run.gone = true; res[k] = { err: true }; logic._failed.push({ name: f.rel.split('/').pop(), reason: 'card removed' }); }
          else { res[k] = unread(f); logic._failed.push({ name: f.rel.split('/').pop(), reason: 'unreadable' }); }
        }
        done++; run.done = done;
        if (done % 8 === 0 || done === files.length) logic.setState({ realLoad: { done, total: files.length, t0 } });
        grow(false);
      };
      await Promise.all(Array.from({ length: Math.max(1, L.workers || 4) }, async () => { while (i < files.length && !run.gone) { const k = i++; await one(files[k], k); } }));
      clearTimeout(logic._growT);
      // Card pulled: the readers stopped. What wasn't read counts as unreadable, as the page counts it.
      for (; i < files.length; i++) { res[i] = { err: true }; logic._failed.push({ name: files[i].rel.split('/').pop(), reason: 'card removed' }); }
      const ok = res.filter(p => p && !p.err), s1 = logic.state, rd = logic._rd || {};
      reading = null; logic._reading = false;
      if (ok.length && ok.every(p => p.unread)) ok.length = 0;
      lastRead = { name: L.name, total: files.length, read: ok.filter(p => !p.unread).length, unreadable: files.length - ok.filter(p => !p.unread).length, stopped: run.gone ? 'card removed' : null, secs: +((performance.now() - t0) / 1000).toFixed(1) };
      window.lumina.read = Object.assign({}, lastRead);
      // The page's readEnd (BRIDGE-v0.03 §3): the reader moved, kept or scrolled during the read, so the
      // page keeps the cursor and the scroll where they are.
      const moved = !!(rd.moved || (rd.cur != null && s1.cur !== rd.cur) || Object.keys(s1.marks || {}).length || Object.keys(s1.flags || {}).length);
      logic._readEnd = { stay: moved, cur: s1.cur };
      if (typeof logic.bridgeEmit === 'function') logic.bridgeEmit('readEnd', { stay: moved, cur: s1.cur, photos: ok.length });
      if (!ok.length) { logic.real = null; logic.data = logic.build({}); logic.setState({ realLoad: null }); return logic.say(run.gone ? 'Card removed · re-insert to keep going' : '0 photos · ' + files.length + ' unreadable'); }
      const ancF = typeof logic.scrollAnchor === 'function' ? logic.scrollAnchor() : null;
      logic.real = ok; logic.data = logic.build(s1.cuts || {}); logic._lk = null; logic._anc = ancF;
      const G = Object.values(logic.data.G), first = ok.map(p => p.date).filter(Boolean).sort()[0] || '';
      const info = { name: L.name, n: ok.length, rows: logic.data.R.length, stacks: G.filter(g => g.kind !== 'single').length, bad: logic._failed.length, nopic: ok.filter(p => p.nopv || p.unread).length,
        secs: lastRead.secs.toFixed(1), date: first.slice(0, 10).replace(/:/g, '-') };
      const B = logic.data.byId;
      logic.setState({ realLoad: null, realInfo: info, openNote: null, notes: logic.notesFor(), notesOn: true, cur: moved && B[s1.cur] ? s1.cur : logic.data.order[0] });
      logic._landT = Date.now(); logic.setView('cull', true); if (!moved) setTimeout(() => logic.land(), 0);
      if (run.gone) logic.say('Card removed · ' + ok.length + ' of ' + files.length + ' read · re-insert to keep going');
    };

    // The page's own folder input still works (drag-in, or anything that clicks it): WebKit hands it
    // Files and the page reads them itself.
    const onDir = logic.onDir.bind(logic);
    logic.onDir = async e => {
      cardPulledWhileReading = false;
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
        const list = files.filter(f => f && f.look && f.look.src).map(f => ({ name: f.name, look: { src: f.look.src, look: macLook(f.look.look || '', byPath[f.look.src]), px: f.look.px == null ? null : f.look.px, model: (byPath[f.look.src] || {}).model || null } }));
        return native('writeInto', { label: 'jpeg', files: list }).then(reasons);
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
      const r = reasons(await native('writeSidecars', { root, files: list }));
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

  // Warm-ahead (BRIDGE-v0.03 §6): the page decides what, the Mac decides when. Sets sends its picks
  // (Pick, ⇧P, Save) and Edit its neighbours, as [{rel, pri, px: 'full' | 'screen'}]; each photo's
  // embedded preview is read into the Mac's cache (never into the page), most urgent first. The
  // page's own ±2 big-view preloads load the same previews by URL.
  const prefetch = list => {
    const l = current; if (!l || !l.data || !Array.isArray(list)) return 0;
    const byRel = {}; for (const p of Object.values(l.data.byId)) if (p.path) byRel[p.path] = p;
    const items = list.filter(x => x && x.rel).sort((a, b) => (a.pri || 0) - (b.pri || 0)).map(x => byRel[x.rel] && previewOf(byRel[x.rel].lg)).filter(Boolean);
    if (items.length) native('prefetch', { items }).catch(() => {});
    return items.length;
  };

  // ——— The Edit canvas (roadmap addendum, RAW 9). Behaviour and data only: the page draws the
  // filmstrip, sliders and facts; the Mac draws the pixels, either natively (an MTKView over the
  // page's canvas rect: `canvas: native`) or, without Metal, through lumina://render images the
  // page shows in its own <img> (`canvas: image`). The page's contract is DESIGN-ASKS Prompt 1 §3:
  //   window.lumina.preview(rel, look, px, seq) → a lumina://render URL (image path) or null (native)
  //   window.lumina.canvasRect({x, y, w, h, dpr} | null)   on Edit open, layout, resize, scroll, zoom
  //                                                        (+ holes: [{x, y, w, h}], page chrome over the photo left see-through)
  //   window.lumina.drag('start' | 'end')                  a slider's pointer-down / release
  //   window.lumina.roi({x, y, w, h} | null)               the visible region at 100 % (also refines it with RAW 9; the region itself is read off the page, zoomView)
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
  const ed = { rel: null, look: '', model: null, rect: null, visible: false, dragging: false, path: 'image', native: null, header: null, factsText: '', roi: null, loupe: false, seq: 0, decoder: null, rectTimer: 0, preview: null, photo: null, entered: false, late: null, refused: null };
  // The image path's latest-wins renderer (addendum §7): one fetch in flight, the newest look
  // waits, a quarter-size render while dragging, the full one at rest (drag end, key, 120 ms idle).
  const img = { pending: null, inFlight: false, shown: 0, tier: null, url: null, fetches: 0, superseded: 0, restTimer: 0, last: null };
  // The embedded JPEG's byte range (o, l, ori) rides along so the Mac can stand it in when the RAW can't be developed.
  const withPreview = q => { const p = ed.preview; if (p && +p.l > 0) { q.o = p.o; q.l = p.l; q.ori = p.ori || 1; } return q; };
  const imgSubmit = (tier, key) => {
    if (!ed.rel || !ed.rect) return;
    ed.seq++;
    img.pending = { look: macLook(ed.look, ed.photo), seq: ed.seq, tier, key: !!key };
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
    if (ed.refused) notes.push("can't show " + ed.refused.rel.split('/').pop() + ' · ' + ed.refused.why);
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
  // The RAW's as-shot white balance per path, as the canvas read it (canvasEnter's answer or
  // __lumina.editHeader once the base lands): Edit's White balance starts there and Auto starts from it.
  const asShot = new Map();
  const applyAsShot = p => { const a = p && p.rel && asShot.get(p.rel); if (!a) return false; if (p.wbShot === a.kelvin && p.tintShot === a.tint) return false; p.wbShot = a.kelvin; p.tintShot = a.tint; return true; };
  const findEditLogic = () => {
    const el = document.querySelector('[data-lumina="canvas"]'); if (!el) return null;
    const k = Object.keys(el).find(x => x.startsWith('__reactFiber$')); if (!k) return null;
    for (let f = el[k]; f; f = f.return) { const sn = f.stateNode; if (sn && sn.logic && typeof sn.logic.nbInfo === 'function') return sn.logic; }
    return null;
  };
  const noteAsShot = h => {
    const a = h && h.asShot, rel = h && h.asShotRel;
    if (!a || typeof rel !== 'string' || !Number.isFinite(+a.kelvin) || !Number.isFinite(+a.tint)) return;
    asShot.set(rel, { kelvin: Math.round(+a.kelvin), tint: Math.round(+a.tint) });
    // The Edit page built its photos when it opened: update the one on the canvas in place.
    const E = findEditLogic(), P = E && E.data && E.data.byId; if (!P) return;
    let changed = false; for (const p of Object.values(P)) if (p && p.rel === rel) changed = applyAsShot(p) || changed;
    if (changed) try { E.setState({}); } catch (_) {}
  };
  // Page chrome over the photo (the zoom pill, the state chip, the loading chip, the crop bar, the
  // colour picker's label): Edit v22 sends canvasRect without `holes`, so they are read off the
  // page here, as the absolutely placed boxes inside the canvas element that cover only part of it.
  // Full-size layers (the photo itself, crop and grid overlays) are looked into, never cut out:
  // a hole that size would show the page's empty canvas instead of the photo.
  const MAX_HOLES = 16;
  const holesOf = rect => {
    const root = document.querySelector('[data-lumina="canvas"]'), out = [];
    if (!root || !rect || !(rect.w > 0) || !(rect.h > 0)) return out;
    const area = rect.w * rect.h;
    const walk = (el, depth) => {
      for (const c of el.children) {
        if (out.length >= MAX_HOLES) return;
        if (c.matches('[data-lumina-img]') || c.querySelector('[data-lumina-img]')) continue;
        const cs = getComputedStyle(c);
        if (cs.display === 'none' || cs.visibility === 'hidden' || +cs.opacity === 0) continue;
        const b = c.getBoundingClientRect(), placed = cs.position === 'absolute' || cs.position === 'fixed';
        if (!placed || b.width < 1 || b.height < 1 || b.width * b.height >= 0.6 * area) { if (depth < 4) walk(c, depth + 1); continue; }
        const x0 = Math.max(rect.x, Math.floor(b.left) - 1), y0 = Math.max(rect.y, Math.floor(b.top) - 1);
        const x1 = Math.min(rect.x + rect.w, Math.ceil(b.right) + 1), y1 = Math.min(rect.y + rect.h, Math.ceil(b.bottom) + 1);
        if (x1 > x0 && y1 > y0) out.push({ x: x0, y: y0, w: x1 - x0, h: y1 - y0 });
      }
    };
    walk(root, 0);
    // Sets' working-files pill sits over the Edit canvas too, outside its element.
    const pill = document.querySelector('[data-lumina="cache-pill-edit"]'), pb = pill && pill.getBoundingClientRect();
    if (pb && pb.width >= 1 && pb.height >= 1 && out.length < MAX_HOLES) {
      const x0 = Math.max(rect.x, Math.floor(pb.left) - 1), y0 = Math.max(rect.y, Math.floor(pb.top) - 1);
      const x1 = Math.min(rect.x + rect.w, Math.ceil(pb.right) + 1), y1 = Math.min(rect.y + rect.h, Math.ceil(pb.bottom) + 1);
      if (x1 > x0 && y1 > y0) out.push({ x: x0, y: y0, w: x1 - x0, h: y1 - y0 });
    }
    return out;
  };
  // The chips come and go without the rect changing: watch the canvas element and send the new
  // holes with the same rect, once per frame at most.
  let holesObs = null, holesRaf = 0;
  const watchHoles = on => {
    if (!on) { if (holesObs) holesObs.disconnect(); holesObs = null; return; }
    const root = document.querySelector('[data-lumina="canvas"]'); if (!root || (holesObs && holesObs.root === root)) return;
    if (holesObs) holesObs.disconnect();
    holesObs = new MutationObserver(() => {
      zoomWatch();
      if (holesRaf) return;
      holesRaf = requestAnimationFrame(() => { holesRaf = 0; if (ed.visible && ed.rect && ed.autoHoles) { const h = holesOf(ed.rect); if (JSON.stringify(h) !== ed.holesKey) edit.layout(ed.rect, true, { holes: h, auto: true }); } });
    });
    holesObs.root = root;
    holesObs.observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ['style'] });
  };
  // The page zooms and pans its own picture (pinch, ⌃-wheel, the zoom pill, a drag) with a CSS
  // transform on the layer that holds the photo's box; the canvas above it has to show the same
  // part. Edit v22's lumina.roi comes only above 1.2×, clamped to the photo and in image px, so
  // the region is read off the page instead: the canvas box in fractions of the photo's box as
  // it sits on screen (x and y from its top-left; below 0 or past 1 where the canvas shows
  // beyond the photo, as zoomed out). null at fit, where the Mac fits the photo itself.
  const zoomView = () => {
    const im = document.querySelector('[data-lumina="canvas"] [data-lumina-img]'), box = im && im.parentElement, layer = box && box.parentElement, r = ed.rect;
    if (!layer || !r || getComputedStyle(layer).transform === 'none') return null;
    const b = box.getBoundingClientRect(); if (!(b.width >= 1) || !(b.height >= 1)) return null;
    const f = v => +v.toFixed(5);
    return { x: f((r.x - b.left) / b.width), y: f((r.y - b.top) / b.height), w: f(r.w / b.width), h: f(r.h / b.height) };
  };
  // Followed frame by frame while it moves (the page eases a zoom step over 200 ms) and for
  // ZOOM_REST ms after; then, with the page's roi on, the region at rest goes to RAW 9.
  const ZOOM_REST = 300;
  let zoomRaf = 0, zoomUntil = 0;
  const zoomTick = () => {
    zoomRaf = 0;
    if (!ed.visible || !ed.rel) return;
    const z = zoomView(), k = JSON.stringify(z);
    if (k !== ed.zoomKey) { ed.zoomKey = k; ed.zoom = z; ed.zoomMoving = true; zoomUntil = performance.now() + ZOOM_REST; native('canvasZoom', { roi: z }).catch(() => {}); }
    if (performance.now() < zoomUntil) { zoomRaf = requestAnimationFrame(zoomTick); return; }
    // Still: the Mac drew the moving zoom at its drag quality with its background work held; now the full one.
    if (ed.zoomMoving) { ed.zoomMoving = false; native('canvasZoom', { roi: z, rest: true }).catch(() => {}); }
    if (ed.loupe && z && k !== ed.loupeKey) { ed.loupeKey = k; native('canvasLoupe', { on: true, roi: z }); }
  };
  const zoomWatch = () => { zoomUntil = performance.now() + ZOOM_REST; if (!zoomRaf) zoomRaf = requestAnimationFrame(zoomTick); };
  // The page's look string (Edit v22, LuminaCore.lookString) → the one the Mac renders. Two of the
  // page's numbers rest on the photo, not on zero:
  //   · Temperature and Tint rest on the photo's as-shot pair as the page knows it (the canvas's,
  //     once noteAsShot has it; before that Sets' wbK, else 5500, and wbTint, else 0; the
  //     temperature slider is a ratio scale). That pair rides along as `wbref:K/T` and the Mac
  //     applies the move to its own as-shot pair (Look.WhiteBalance.resolved): the same on the
  //     canvas, the image path and the JPEG export, whichever reference the page had then.
  //   · Sharpening rests at 40 on the page, Lightroom's RAW default; the Mac's 0 is no sharpening
  //     (its Sharpness sweep starts from 0, Tools/parity/README.md). A look without `shp` is 40.
  const SHP_DEFAULT = 40;
  const macLook = (look, p) => {
    const out = String(look || '').trim().split(/\s+/).filter(Boolean);
    if (out.some(t => t.startsWith('wb:')) && !out.some(t => t.startsWith('wbref:'))) {
      const a = p && asShot.get(((current && current.state.realInfo && current.state.realInfo.name) || '') + '/' + keyOf(p));
      const k = a ? a.kelvin : Math.round(+(p && p.wbK) || 5500), t = a ? a.tint : p && p.wbTint != null && isFinite(+p.wbTint) ? Math.round(+p.wbTint) : 0;
      out.push('wbref:' + k + '/' + (t > 0 ? '+' : '') + t);
    }
    if (!out.some(t => t.startsWith('shp:'))) out.push('shp:' + SHP_DEFAULT);
    return out.join(' ');
  };
  // A photo the Mac can't put on the canvas (not in the shoot, canvasEnter refused): there is no
  // frame to wait for, so the page's look is answered and the facts line says why.
  const refused = (rel, why, seq) => { ed.refused = { rel, why }; pushFacts(true); if (seq) hook('luminaPresented', seq); };
  const edit = {
    // Entering Edit for a photo (its path, "<folder>/DSC.ARW"): the Mac builds its bases now and its
    // neighbours' in the background. `look` is the photo's look string; `opt.seq` the page's seq for
    // it, which goes with the photo so the frame that shows it is acknowledged (luminaPresented).
    // Looks that follow wait until the Mac has the photo (`ed.late`): one sent before that has no
    // photo to land on.
    async enter(rel, look, opt) {
      const l = current; if (!l || !l.data) return null;
      const seq = (opt && opt.seq) || 0;
      const [id, p] = photoAt(l, rel); if (!p) { refused(rel, 'not in this shoot', seq); return null; }
      const o = l.data.order, k = o.indexOf(id), nb = d => { const q = l.data.byId[o[k + d]]; return q ? [q.path, previewOf(q.lg)] : [null, null]; };
      const [prev, prevPreview] = nb(-1), [next, nextPreview] = nb(1);
      ed.rel = rel; ed.photo = p; ed.model = p.model || null; ed.look = look || (l.state.look || {})[id] || ''; ed.loupe = ed.loupe && !!zoomView(); ed.roi = null; ed.zoom = null; ed.zoomKey = undefined; ed.zoomMoving = false; ed.loupeKey = null; ed.preview = previewOf(p.lg);
      img.shown = 0; img.tier = null; img.pending = null; ed.seq = seq; ed.entered = false; ed.late = null; ed.refused = null;
      let r;
      try { r = await native('canvasEnter', { rel, look: macLook(ed.look, p), seq, model: ed.model, preview: previewOf(p.lg), prev, prevPreview, next, nextPreview }); }
      catch (e) { if (ed.rel === rel) refused(rel, String((e && e.message) || e || 'refused'), Math.max(seq, ed.late ? ed.late.o.seq : 0)); return null; }
      if (ed.rel !== rel) return null;
      ed.entered = true;
      if (r && typeof r === 'object') { ed.header = Object.assign({}, ed.header || {}, r); ed.path = r.canvas || 'image'; ed.decoder = r.decoderCanvas != null ? r.decoderCanvas : null; noteAsShot(r); }
      pushFacts(true);
      if (ed.path === 'image') imgSubmit('base', true);
      else if (ed.late) { const q = ed.late; ed.late = null; edit.look(q.look, q.o); }
      zoomWatch();
      return edit.facts();
    },
    leave() { watchHoles(false); ed.rel = null; ed.entered = false; ed.late = null; ed.refused = null; ed.loupe = false; ed.zoom = null; clearTimeout(img.restTimer); img.pending = null; native('canvasLeave', {}); edit.layout(null, false); },
    // The canvas rect in CSS px from the page's top-left, on layout and resize; `visible` = Edit shows.
    // {force: true} (the probe) keeps the canvas up whatever the page's view is.
    // `holes` (on the rect or in `o`): page chrome lying over the photo, [{x, y, w, h}] in CSS px as
    // the rect, for the Mac to leave see-through (it reads at most 16).
    // `vh`: the page's viewport height. The web view can keep its top under the title bar out of the
    // page (macOS 26's obscured content inset), so the Mac places the rect up from the viewport's
    // bottom, not down from the web view's top.
    layout(rect, visible, o) {
      ed.force = !!(o && o.force) && !!visible;
      ed.rect = rect && rect.w > 0 && rect.h > 0 ? { x: rect.x, y: rect.y, w: rect.w, h: rect.h } : null; ed.visible = !!visible && !!ed.rect;
      const holes = (o && Array.isArray(o.holes) && o.holes) || (rect && Array.isArray(rect.holes) && rect.holes) || [];
      ed.holes = holes;
      ed.holesKey = JSON.stringify(ed.visible ? holes : []);
      native('canvasLayout', Object.assign({ visible: ed.visible, dpr: dpr(), holes: ed.visible ? holes : [], vh: window.innerHeight }, ed.rect || { x: 0, y: 0, w: 0, h: 0 })).then(r => { if (r && r.path) { ed.path = r.path; pushFacts(); } }).catch(() => {});
      if (ed.path === 'image' && ed.visible && ed.rel && !img.shown) imgSubmit('base', true);
      if (ed.visible) zoomWatch();
    },
    // A slider value, as often as the slider emits. {drag: true} while the thumb is held, {key: true}
    // for a keystroke, roi: the visible region {x, y, w, h} in fractions of the frame when zoomed.
    look(look, o) {
      o = o || {};
      ed.look = look; lastChange = performance.now(); scheduleSave();
      if (o.roi !== undefined) ed.roi = o.roi;
      if (!ed.rel) return 0;
      if (ed.path === 'native') { const seq = o.seq != null ? o.seq : ++ed.seq; ed.seq = Math.max(ed.seq, seq);
        if (ed.refused) { hook('luminaPresented', seq); return seq; }
        if (!ed.entered) { ed.late = { look, o: Object.assign({}, o, { seq }) }; return seq; }
        native('canvasLook', { look: macLook(look, ed.photo), drag: !!o.drag && !o.key, key: !!o.key, roi: ed.zoom || ed.roi, t: pageNow(), seq }).catch(() => {}); return seq; }
      imgSubmit(o.drag && !o.key ? 'small' : 'base', o.key); return ed.seq;
    },
    // Prompt 1 §3: the page's one preview call. Native path: the look goes to the canvas and null
    // comes back (the app presents; luminaPresented(seq) follows). Image path: the URL to show,
    // quarter-size while a slider drags, full otherwise; superseded requests answer 409.
    preview(rel, look, px, seq) {
      if (!rel) return null;
      if (ed.rel !== rel) {
        const entering = edit.enter(rel, look || '', { seq });
        // Native: the photo and its first look went together; nothing more to send, nothing for the page to draw.
        if (ed.path === 'native') { lastChange = performance.now(); scheduleSave(); return entering.then(() => null, () => null); }
      }
      if (ed.refused && ed.refused.rel === rel && ed.path === 'native') { if (seq) Promise.resolve().then(() => hook('luminaPresented', seq)); return null; }
      ed.look = look || ''; lastChange = performance.now(); scheduleSave();
      if (ed.path === 'native') { if (ed.rect) edit.look(ed.look, { drag: ed.dragging, seq }); return null; }
      const q = { look: macLook(ed.look, ed.photo), px: Math.max(64, Math.round(px || (ed.rect ? Math.max(ed.rect.w, ed.rect.h) * dpr() : 1024))), seq: seq != null ? seq : ++ed.seq, tier: ed.dragging ? 'small' : 'base' };
      if (ed.decoder != null) q.decoder = ed.decoder;
      ed.seq = Math.max(ed.seq, q.seq);
      return renderURL(rel, withPreview(q));
    },
    // A rect without `holes` (Edit v22) gets them read off the page, and kept current while it shows.
    canvasRect(r) {
      // Edit shows again with the photo it left on (no canvasEnter follows): its hooks are new, so the facts go again.
      const back = !!r && !ed.rect && !!ed.rel && ed.entered;
      ed.autoHoles = !!r && !Array.isArray(r.holes);
      if (ed.autoHoles) { edit.layout(r, true, { holes: holesOf(r) }); watchHoles(true); }
      else { edit.layout(r, !!r); if (!r) watchHoles(false); }
      if (back) pushFacts(true);
    },
    drag(what) { if (what === 'start') edit.dragStart(); else edit.dragEnd(); },
    // The visible region at 100 %: small renders show only it, and the Mac refines it with RAW 9.
    // While the page's own zoom is on, the region is the one read off the page (zoomView), sent
    // once the zoom rests; the page's numbers (image px in Edit v22) only say that it is on.
    roi(r) {
      if (!r) { ed.roi = null; ed.loupeKey = null; edit.loupe(false); zoomWatch(); return; }
      if (zoomView()) { ed.loupe = true; zoomWatch(); return; }
      ed.roi = r; edit.loupe(true, r);
    },
    dragStart() { ed.dragging = true; lastChange = performance.now(); if (ed.rel) native('canvasDrag', { start: true }); },
    dragEnd() { ed.dragging = false; lastChange = performance.now(); scheduleSave(); if (!ed.rel) return; native('canvasDrag', { start: false }); if (ed.path === 'image') { clearTimeout(img.restTimer); imgSubmit('base'); } },
    // 100 % with G held: RAW 9 on the visible region (RAW 9 §2).
    loupe(on, roi) { ed.loupe = !!on; if (roi) ed.roi = roi; if (ed.rel) native('canvasLoupe', { on: !!on, roi: on ? ed.roi : null }); },
    // The facts line's inputs: the canvas path, raw 9 yes/no, the pin, the offer (+ Prompt 1's {canvas, raw9, decoder, note}).
    facts() { return Object.assign({ text: factsText(), rel: ed.rel }, ed.header || {}, factsObj()); },
    // The Mac's numbers (the probe reads them): latency, dropped frames, bases resident, tiles, …
    stats(reset) { return native('canvasStats', { reset: !!reset }); },
    // The facts line's offer: pin the shoot to the newest decoder (RAW 9 §7).
    updateDecoder() { return native('decoderUpdate', {}).then(h => { edit.header(h); return edit.facts(); }); },
    header(h) { if (h && typeof h === 'object') { ed.header = Object.assign({}, ed.header || {}, h); if (h.canvas) ed.path = h.canvas; noteAsShot(h); } pushFacts(); },
    get image() { return img.url; },
    state() { return { rel: ed.rel, look: ed.look, path: ed.path, rect: ed.rect, visible: ed.visible, force: !!ed.force, dragging: ed.dragging, seq: ed.seq, loupe: ed.loupe, roi: ed.roi, zoom: ed.zoom || null,
      image: { shown: img.shown, tier: img.tier, fetches: img.fetches, superseded: img.superseded, inFlight: img.inFlight, pending: !!img.pending, url: img.url }, facts: ed.factsText, header: ed.header }; },
  };
  window.lumina.edit = edit;
  // Prompt 1 §3's four calls, on window.lumina itself.
  window.lumina.preview = edit.preview;
  window.lumina.canvasRect = edit.canvasRect;
  window.lumina.drag = edit.drag;
  window.lumina.roi = edit.roi;

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
    // A menu item (BRIDGE.md, MENUS v7). While Edit is the active step, Undo, Redo, Copy and Paste
    // are Edit's own (window.luminaEdit); everything else goes to Sets' luminaCommand.
    // Keys typed fast wait in the page's queue (one per frame). A menu shortcut is a ⌘ key the page
    // never sees, so it would act before them (⌘Z undoing the keep before the last one); the page's
    // own rule for ⌘ keys is to run the queue first, so plumbing does that here.
    command(name) {
      const l = current, E = window.luminaEdit;
      if (l && typeof l.flushKeys === 'function') l.flushKeys();
      if (l && l.state.view === 'edit' && E && ['undo', 'redo', 'copy', 'paste'].includes(name) && typeof E[name] === 'function') { E[name](); return true; }
      return typeof window.luminaCommand === 'function' ? window.luminaCommand(name) : false;
    },
    // View ▸ Zoom 100%: Z is a hold key in the page; the menu toggles it through the page's gesture hook.
    zoom() { const l = window.__lumina.logic(); if (l && typeof l.flushKeys === 'function') l.flushKeys(); if (l && typeof window.luminaGesture === 'function') window.luminaGesture('hold', { key: 'z', down: !l.state.zoom }); },
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
    // The page's bridge events (BRIDGE-v0.03 §3), newest last: what the probe checks flow, moves and reads by.
    events: () => events.slice(),
    say(t) { const l = window.__lumina.logic(); if (l) l.say(t); },
    openFolder() { const l = window.__lumina.logic(); if (l) l.openFolder(true); },
    undo() {
      const a = document.activeElement;
      if (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA')) return document.execCommand('undo');
      const l = window.__lumina.logic(); if (l) l.undo();
    },
  };
})();
