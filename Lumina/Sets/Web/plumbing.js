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
  // The same for the few other keys the page keeps there and that must outlive a launch (v7: the tour
  // was seen, shoot names, the seen-before memory, the "before you open" tick, the phone page's
  // choice, Edit's intro). The Mac holds them (SetsPageStore, the same list); seeded here, and every
  // later write of one of them is handed over half a second after the last. Not in the probe's twins.
  const STORED = ['lumina-v4-toured', 'lumina-v4-pre-ok', 'lumina-v4-names', 'lumina-v4-seen', 'lumina-phone-kind', 'lumina-phone-used', 'lumina.edit.intro.v1'];
  if (cfg.store && typeof cfg.store === 'object' && !cfg.parity) {
    try { for (const k of STORED) if (typeof cfg.store[k] === 'string') localStorage.setItem(k, cfg.store[k]); } catch (_) {}
    const timers = {}, hand = k => { clearTimeout(timers[k]); timers[k] = setTimeout(() => { let v = null; try { v = localStorage.getItem(k); } catch (_) {} native('storeSet', { key: k, value: v }); }, 500); };
    const set0 = Storage.prototype.setItem, rem0 = Storage.prototype.removeItem;
    Storage.prototype.setItem = function (k, v) { const r = set0.call(this, k, v); if (this === localStorage && STORED.includes(String(k))) hand(String(k)); return r; };
    Storage.prototype.removeItem = function (k) { const r = rem0.call(this, k); if (this === localStorage && STORED.includes(String(k))) hand(String(k)); return r; };
  }

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
    // adding to the open shoot (v7's onDir with `add`)
    'addSource', 'clockOffset', 'shiftDate', 'rememberSeen', 'restoreSeen', 'nameKey', 'shootName', 'names'];
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
  const ONDIR = 2481318810;
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
  const BY_ID = ['marks', 'flags', 'stars', 'cuts', 'look', 'xsaved'];      // xsaved (v7): the picks the last Save wrote
  const SCALAR = ['seen', 'tsz', 'regions', 'lastEx', 'rowLook'];
  let shootId = null, lastSaved = '', base = null, savedKeepers = null, cardPulledWhileReading = false, readMoved = false, sessionRefused = null;
  // Last scroll in the page (any scroller), for pacing the grid's refresh while a folder is read.
  let scrollT = 0;
  document.addEventListener('scroll', () => { scrollT = performance.now(); }, { capture: true, passive: true });
  // Path inside the opened folder ("sub/DSC00001.ARW"): stable across reopen and new files. A shoot
  // can have more sources than the folder it was opened from (BRIDGE.md "Sources"): a photo of
  // another source is keyed by its whole path behind a slash ("/100MSDCF 2/DSC00001.ARW"), which no
  // path inside the first folder can be, so two sources that both hold DSC00001.ARW keep separate
  // decisions and a session written before sources existed reads as it always did.
  let primaryTop = null;         // the first source's root name: the first segment of its photos' paths
  const keyOf = p => {
    const r = (p && p.fileObj && p.fileObj.webkitRelativePath) || (p && p.path) || '';
    if (!r) return (p && p.file) || '';
    const i = r.indexOf('/');
    if (primaryTop == null) return i < 0 ? '' : r.slice(i + 1);
    return i >= 0 && r.slice(0, i) === primaryTop ? r.slice(i + 1) : '/' + r;
  };
  // The page's sources ('s1', 's2'…, its Sources panel) and the Mac's (`nid`, with the bookmark that
  // finds the folder again). The first source is the shoot itself and has no nid unless the shoot
  // was opened from single files.
  let srcNid = {}, srcMissing = {};
  const pushSources = l => {
    window.lumina.sources = ((l && l._sources) || []).map(so => ({ id: so.id, missing: !!(srcNid[so.id] && srcMissing[srcNid[so.id]]) }));
    if (l && l.forceUpdate) l.forceUpdate();
  };
  const sourceStatus = (l, list) => { if (!Array.isArray(list)) return; for (const x of list) if (x && x.nid) srcMissing[x.nid] = !!x.missing; pushSources(l); };
  // What the Mac keeps per source: the clock shift the reader chose and how many photos it has.
  const tellSources = l => {
    if (!shootId || !l) return Promise.resolve();
    const by = {}, cnt = {};
    for (const p of l.real || []) { const id = (l._srcOf || {})[p.path]; if (id) cnt[id] = (cnt[id] || 0) + 1; }
    for (const so of l._sources || []) { const nid = srcNid[so.id]; if (!nid) continue; const e = by[nid] = by[nid] || { nid, offset: 0, n: 0 }; e.n += cnt[so.id] || (srcMissing[nid] ? so.n || 0 : 0); if (so.offset) e.offset = so.offset; }
    return Promise.resolve(native('shootSources', { id: shootId, sources: Object.values(by) })).then(st => sourceStatus(l, st), () => {});
  };
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
    const e = editOut(logic); if (e) out.edit = e; else if (base && base.edit) out.edit = base.edit;
    return out;
  };
  // The Edit step (v21) keeps its state in localStorage under 'lumina-edit.<shoot key>':
  // { looks, tags, keep, done, vers, cur }, keyed by photo id, or by stack id for a stack edited as
  // one. The web view's storage ends with the launch and ids are not stable across reads, so the
  // session carries it by path: a photo as its path, a stack as 'g|' + the first of its members'
  // paths. `keep` is not kept: the page folds it into its own marks when it leaves Edit.
  const EDIT_MAPS = ['looks', 'tags', 'done', 'vers'];
  const editKeyOf = logic => { try { return typeof logic.editKey === 'function' ? logic.editKey() : null; } catch (_) { return null; } };
  const stackPath = (logic, gid) => { const g = logic.data.G && logic.data.G[gid]; if (!g || !Array.isArray(g.ids)) return null; const ps = g.ids.map(id => pathOf(logic, id)).filter(Boolean).sort(); return ps.length ? 'g|' + ps[0] : null; };
  const editOut = logic => {
    const key = editKeyOf(logic); if (!key || !logic.real) return null;
    let st = null; try { st = JSON.parse(localStorage.getItem(key) || 'null'); } catch (_) {}
    if (!st || typeof st !== 'object') return null;
    const B = logic.data.byId, to = k => B[k] ? pathOf(logic, k) : stackPath(logic, k), out = { cur: (st.cur && B[st.cur] && pathOf(logic, st.cur)) || null };
    for (const m of EDIT_MAPS) { const o = {}; for (const [k, v] of Object.entries(st[m] || {})) { const p = to(k); if (p) o[p] = v; } out[m] = o; }
    return out;
  };
  // Back into the page's own key, before the reader enters Edit (Edit reads it when it mounts).
  const editIn = (logic, saved) => {
    const key = editKeyOf(logic); if (!key || !saved || typeof saved !== 'object') return;
    const idOf = {}, gidOf = {}; for (const [id, p] of Object.entries(logic.data.byId)) { const k = keyOf(p); idOf[k] = id; if (p.gid) gidOf[k] = p.gid; }
    const from = k => /^g\|/.test(k) ? gidOf[k.slice(2)] : idOf[k], st = { keep: {}, cur: (saved.cur && idOf[saved.cur]) || null };
    for (const m of EDIT_MAPS) { const o = {}; for (const [k, v] of Object.entries(saved[m] || {})) { const id = from(k); if (id) o[id] = v; } st[m] = o; }
    try { localStorage.setItem(key, JSON.stringify(st)); } catch (_) {}
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
    if (!live || !editOut(logic)) editIn(logic, saved.edit);
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
    if (json !== lastSaved) {
      lastSaved = json; base = JSON.parse(json);
      // A session over the Mac's limit (threat model T5) is refused: said once per shoot. The wording
      // is a stand-in until DESIGN-ASKS Prompt 6 lands. Other failures stay as before (not shown).
      const id = shootId;
      Promise.resolve(native('saveSession', { id, json, summary: summary(l) })).catch(err => {
        if (!/too big/.test(String((err && err.message) || err))) throw err;
        if (sessionRefused !== id) { sessionRefused = id; l.say('decisions not saved · session too big'); }
      });
    }
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
    // The page's clear (v7, from any step): the decisions stay (BRIDGE.md "keep the session until saved").
    removeWorkingFiles: () => shootId ? native('removeWorkingFiles', { id: shootId }) : Promise.resolve(false),
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
    // Sources (BRIDGE.md "Sources"). `sources` marks a source "not connected" in the page's panel;
    // `addFrom` is the panel's Add (the Mac's picker), `reconnect` its Reconnect. `pending` /
    // `pullPending` stay unset: AirDrop arrivals reach the page through luminaPhoneArrived (v0.0.1).
    sources: [],
    pending: null,
    addFrom: where => (current && current.__luminaAddFrom ? current.__luminaAddFrom(where) : Promise.resolve()),
    reconnect: id => (current && current.__luminaReconnect ? current.__luminaReconnect(id) : Promise.resolve()),
    // AirDrop (BRIDGE.md "Phone upload"): the Mac watches Downloads, asked for once. The page turns
    // its "watching" state on without waiting for an answer, so when there is no folder to watch (the
    // panel was cancelled) it is turned off again through the page's own stop, with the page's own
    // "couldn't open" line.
    watchAirdrop: on => Promise.resolve(native('watchAirdrop', { on: !!on })).then(ok => {
      const l = current;
      if (on && !ok && l && typeof l.stopAirdrop === 'function') { l.stopAirdrop(); l.setState({ adMsg: 'Couldn’t open Downloads.' }); }
      return !!ok;
    }, () => false),
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
      const bodies = {}; for (const p of logic.real) { const m = p.model || '?'; if (m && p.path && !bodies[m]) bodies[m] = p.path; }
      const r = await native('shootOpened', { name: info.name, n: logic.real.length, date: first, bodies });
      shootId = r && r.id; lastSaved = ''; base = null; savedKeepers = null;
      edit.header(r && r.header);
      if (r && r.session) { try { restore(logic, JSON.parse(r.session), readMoved); } catch (_) {} }
      // A shoot never opened before and not yet named: the name field takes the keyboard with the page's
      // suggestion (v7's onDir), unless the reader has moved. A shoot with a session is left alone.
      else if (!readMoved && typeof logic.names === 'function' && typeof logic.nameKey === 'function' && !logic.names()[logic.nameKey()])
        setTimeout(() => { const el = logic.nameRef && logic.nameRef.current; if (el && !readMoved) { el.focus(); try { el.select(); } catch (_) {} } }, 350);
      // Decisions made while the folder was read aren't in the session yet: the next save sends them.
      lastSaved = readMoved ? '' : JSON.stringify(snapshot(logic));
      // v7's onDir ends every read with its seen-before memory: photos decided in another shoot (the
      // card, then the copy on disk) get those decisions, with the page's own note. After the
      // session, which wins, and after `lastSaved`, so what it brings is written with the next save.
      if (typeof logic.restoreSeen === 'function') { try { logic.restoreSeen(); } catch (_) {} }
      // The sources read with it (a reopen brings them back): the Mac keeps exactly these.
      tellSources(logic);
      loadRecents(logic);
    };

    // Opening a folder reads it natively. The steps and wording are the page's own onDir; only
    // where the bytes come from differs.
    const openFolder0 = logic.openFolder.bind(logic);
    logic.openFolder = async force => {
      // v7: with picks not saved yet the first ⌘O only warns ("⌘O again opens anyway"); the page's own
      // openFolder arms it and says so. The second, within 5 s, goes on.
      if (!force && logic.data.order.length && typeof logic.unsaved === 'function' && logic.unsaved() > 0 && !(logic._opArm && Date.now() - logic._opArm < 5000)) return openFolder0(false);
      logic._opArm = 0; if (logic.state.armed === 'open') logic.setState({ armed: null });
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
      // `/`, a home folder, a whole disk: the Mac stopped listing it (threat model T5). Said where the
      // page says "no ARW found"; the wording is a stand-in until DESIGN-ASKS Prompt 6 lands.
      if (L.tooBig) {
        const T = L.tooBig, msg = 'not available · ' + T.name + ' · ' + (T.why === 'tooDeep' ? 'folders over ' + T.depth + ' deep' : 'over ' + T.files + ' files') + ' · open one shoot';
        logic.setState({ openNote: msg }); return logic.say(msg);
      }
      window.luminaCardGone(false);
      window.lumina.readingCard = !!L.onCard;
      await ingest(L);
      await afterRead();
    };

    // One RAW (ARW or DNG), as the page's readOne reads it, from the Mac's reader.
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
      // A phone, told from EXIF Make / Model only: its name, its "1× camera" lens, and the 35 mm
      // equivalent as the focal length the shake check and the row splits use.
      const ph = LuminaCore.phoneOf(m); if (ph) { m.flReal = m.fl; if (m.fl35) m.fl = m.fl35; m.model = ph.short; m.lens = ph.zoom ? ph.zoom + ' camera' : m.lens; }
      const xk = rel.replace(/\.[^.\/]+$/, '').toLowerCase(), xo = xmpMap[xk] || null, xpath = xo ? xo.path : rel.replace(/\.[^.\/]+$/, '') + '.xmp';
      const baseP = { model: m.model || null, make: m.make || null, fnum: m.fnum || null, w: m.w || null, h: m.h || null, bytes: f.size, lens: m.lens || null, serial: m.serial || null,
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

    // A native listing as the page's files: the stand-ins it keeps per photo, and the sidecar texts.
    const standIns = L => {
      const arws = (L.files || []).map(f => Object.assign(fileRef(f.rel), { size: f.size }));
      return { arws, all: arws.concat((L.xmp || []).map(x => fileRef(x.rel)), (L.others || []).map(fileRef)) };
    };
    const sidecarsOf = (L, xmpMap) => {
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
      return xmpMap;
    };
    // Sidecars over 1 MB the Mac did not read (threat model T5), and sidecars that are not text
    // (Latin-1, UTF-16, binary): counted with the unreadable files, until the page has its own line.
    const sidecarFailures = L => {
      for (const rel of L.skippedXmp || []) logic._failed.push({ name: rel.split('/').pop(), reason: 'sidecar over 1 MB, not read' });
      for (const rel of L.unreadableXmp || []) logic._failed.push({ name: rel.split('/').pop(), reason: 'sidecar unreadable, not read' });
    };
    // The page's addSource, remembering which of the Mac's sources it is. The page makes no source
    // out of files without a RAW; then there is none here either.
    const addSource = (src, files, nid, offset) => {
      const S = logic._sources = logic._sources || [], n0 = S.length;
      if (typeof logic.addSource === 'function') logic.addSource(src, files);
      if (S.length === n0) return null;
      const so = S[S.length - 1]; srcNid[so.id] = nid || null;
      if (offset) so.offset = offset;
      return so;
    };
    const topOf = rel => String(rel || '').split('/')[0];
    // The page's test for "the same photo from another place" when files are added.
    const rfp = p => [p.model || '', p.serial || '', p.date || '', p.bytes || ''].join('|');
    const dropPhoto = p => { p.src && URL.revokeObjectURL(p.src); /^blob:/.test(p.lg || '') && URL.revokeObjectURL(p.lg); previewAt.delete(p.path); };

    // The page's onDir, step for step, over the native listing. `L.more`: the shoot's other sources
    // as the Mac kept them (a reopen), each a listing of its own or `missing`; they are read in the
    // same pass and joined the way they were added: the same duplicates left out, the same clock shift.
    const ingest = async L => {
      const more = Array.isArray(L.more) ? L.more : [], parts = [L].concat(more.filter(m => m && !m.missing && Array.isArray(m.files)));
      const xmpMap = {}; for (const P of parts) sidecarsOf(P, xmpMap);
      const own = parts.map(standIns), arws = [].concat(...own.map(o => o.arws)), allF = [].concat(...own.map(o => o.all));
      // A new shoot (the page's onDir without `add`): the Sources panel reads these.
      logic._addFrom = null; logic._sources = []; logic._srcOf = {}; srcNid = {}; srcMissing = {};
      primaryTop = L.name;
      addSource(L.source || { kind: L.onCard ? 'card' : 'folder' }, own[0].all, L.nid);
      for (const m of more) {
        if (!m) continue;
        const k = parts.indexOf(m);
        if (k > 0) { addSource({ kind: m.kind, label: m.label || undefined }, own[k].all, m.nid, m.offset); continue; }
        // Not connected (card out, folder moved): no photos, but the panel still lists it, with Reconnect.
        const S = logic._sources, so = { id: 's' + (S.length + 1), kind: m.kind || 'folder', label: m.label || m.name || 'Folder', top: m.name || '', n: m.n || 0, t: Date.now(), status: 'ok' };
        if (m.offset) so.offset = m.offset;
        S.push(so); srcNid[so.id] = m.nid || null; if (m.nid) srcMissing[m.nid] = true;
      }
      pushSources(logic);
      logic._allF = allF;
      const files = [].concat(...parts.map(P => P.files || [])).sort((a, b) => a.rel.localeCompare(b.rel));
      logic._intake = logic.intake(allF, arws);
      if (!files.length) {
        const I = logic._intake, parts = [...Object.entries(I.raw).map(([e, n]) => n + ' ' + e.toUpperCase()), I.jp + I.ja ? (I.jp + I.ja) + ' JPEG / HEIF' : '', I.vid ? I.vid + ' videos' : ''].filter(Boolean);
        const msg = 'no ARW or DNG found' + (parts.length ? ' · ' + parts.join(' · ') + ' · Lumina reads ARW and DNG' : ' · 0 photos');
        logic.setState({ openNote: msg }); return logic.say(msg);
      }
      (logic.real || []).forEach(p => { p.src && URL.revokeObjectURL(p.src); /^blob:/.test(p.lg || '') && URL.revokeObjectURL(p.lg); });
      const run = reading = { name: L.name, total: files.length, done: 0, gone: false };
      const t0 = performance.now(), res = new Array(files.length); let done = 0, i = 0, pre = 0, shown = false, lastB = 0, firstCur = null;
      readMoved = false;
      previewAt.clear();
      logic._gold = []; logic._failed = []; logic.real = [];
      logic._reading = true; logic._rd = { moved: false, cur: null, top: 0 };       // the page's own scroll handler marks `moved`
      for (const P of parts) sidecarFailures(P);
      logic.setState({ realLoad: { done: 0, total: files.length, t0 }, realInfo: null, xsaved: {}, sel: {}, marks: {}, seen: {}, flags: {}, stars: {}, cuts: {}, undo: [], open: null, undec: false, pend: null });
      // Rows appear as the contiguous prefix grows: every 400 ms; every 1.5 s while the reader has
      // scrolled in the last 1.5 s, so the grid isn't rebuilt under a moving scroll (the page's pacing since v7).
      const grow = force => {
        while (pre < files.length && res[pre] !== undefined) pre++;
        const now = performance.now(); if (!force && (pre < 48 || now - lastB < (now - scrollT < 1500 ? 1500 : 400))) return; lastB = now;
        logic.real = res.slice(0, pre).filter(p => p && !p.err); if (!logic.real.length) return; logic.data = logic.build(logic.state.cuts || {}); logic._lk = null;
        if (!shown) { shown = true; firstCur = logic.data.order[0]; logic._rd.cur = firstCur; const se = logic.scrollRef && logic.scrollRef.current; logic._rd.top = se ? se.scrollTop : 0; logic.setState({ cur: firstCur }); logic.setView('cull', true); } else logic.forceUpdate();
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
      const ok = res.filter(p => p && !p.err), rd = logic._rd || {};
      reading = null; logic._reading = false;
      lastRead = { name: L.name, total: files.length, read: ok.length, unreadable: files.length - ok.length, stopped: run.gone ? 'card removed' : null, secs: +((performance.now() - t0) / 1000).toFixed(1) };
      window.lumina.read = Object.assign({}, lastRead);
      if (!ok.length) { logic.real = null; logic.data = logic.build({}); logic.setState({ realLoad: null }); return logic.say(run.gone ? 'Card removed · re-insert to keep going' : '0 photos · ' + files.length + ' unreadable'); }
      // The other sources join as they did when they were added, in that order: a photo the shoot
      // already had (the page's test: body, serial, time, size) is left out, then the source's clock
      // shift is applied. No sheet and no toast: the reader chose all of it before.
      const tops = new Set([L.name]);
      for (const m of parts.slice(1)) {
        const have = new Set(ok.filter(p => tops.has(topOf(p.path))).map(rfp));
        for (let q = ok.length - 1; q >= 0; q--) {
          const p = ok[q]; if (topOf(p.path) !== m.name) continue;
          if (have.has(rfp(p))) { dropPhoto(p); ok.splice(q, 1); } else if (m.offset) p.date = logic.shiftDate(p.date, m.offset);
        }
        tops.add(m.name);
      }
      // The page ends a read on the first photo and scrolls to it (land). When the reader has already
      // moved (cursor, keeps, or scrolled), plumbing keeps them where they are instead: same photo,
      // same scroll, no fly-back across the shoot. Design ask 8 asks the page for the same.
      const sc = logic.scrollRef && logic.scrollRef.current, was = logic.state.cur, wasKey = shown && was && logic.data.byId[was] ? keyOf(logic.data.byId[was]) : null;
      readMoved = shown && (!!rd.moved || was !== firstCur || Object.keys(logic.state.marks || {}).length > 0 || Object.keys(logic.state.flags || {}).length > 0 || !!(sc && sc.scrollTop > 40));
      logic.real = ok; logic.data = logic.build(logic.state.cuts || {});
      let stay = null;
      if (readMoved && wasKey) for (const [id, p] of Object.entries(logic.data.byId)) if (keyOf(p) === wasKey) { stay = id; break; }
      const G = Object.values(logic.data.G), first = ok.map(p => p.date).filter(Boolean).sort()[0] || '';
      const info = { name: L.name, n: ok.length, rows: logic.data.R.length, stacks: G.filter(g => g.kind !== 'single').length, bad: logic._failed.length, secs: lastRead.secs.toFixed(1), date: first.slice(0, 10).replace(/:/g, '-') };
      logic.setState({ realLoad: null, realInfo: info, openNote: null, notes: logic.notesFor(), notesOn: true, cur: stay || logic.data.order[0] });
      logic._landT = Date.now(); logic.setView('cull', true); if (!stay) setTimeout(() => logic.land(), 0);
      if (run.gone) logic.say('Card removed · ' + ok.length + ' of ' + files.length + ' read · re-insert to keep going');
    };

    // The page's onDir with `add` (v7): one more source for the open shoot. The page reads the
    // whole shoot again and starts its decisions from nothing; here only the files that are new are
    // read, and the shoot stays as it is (cursor, decisions, Edit's looks) while they are. The steps
    // and the wording are the page's: files already here by path and size are skipped ("nothing new"),
    // then photos already here by body, serial, time and size; the second-camera clock check and its
    // sheet; the shoot's name carried to its new key; the seen-before memory; the toast; the Picks
    // tray's "pick what was dropped". The shoot keeps its first folder's name and its identity.
    // `o.src`: what the page passed as e.src. `o.fill`: the page's source this listing belongs to
    // already (a source that was not connected, found again): no new source, no sheet, no toast.
    const ingestAdd = async (L, o) => {
      o = o || {};
      const own = standIns(L), kf = f => (f.webkitRelativePath || f.name) + '|' + f.size;
      const seen = new Set(logic._allF.map(kf)), fresh = own.all.filter(f => !seen.has(kf(f)));
      const filling = o.fill ? (logic._sources || []).find(so => so.id === o.fill) : null;
      if (!fresh.length) { pushSources(logic); return filling ? undefined : logic.say('nothing new · those photos are already in this shoot'); }
      const isRaw = f => /\.(arw|dng)$/i.test(f.name), kk = p => p.path + '|' + p.bytes;
      const af = { key: logic.nameKey(), name: logic.shootName(), n: fresh.filter(isRaw).length, fresh: new Set(fresh.map(kf)) };
      if (filling) { for (const f of fresh.filter(isRaw)) logic._srcOf[f.webkitRelativePath] = filling.id; }
      else { logic.rememberSeen(); logic._addFrom = af; addSource(o.src, fresh, L.nid); }
      const so = filling || (logic._sources || [])[logic._sources.length - 1];
      logic._allF = logic._allF.concat(fresh);
      logic._intake = logic.intake(logic._allF, logic._allF.filter(isRaw));
      const want = new Set(fresh.filter(isRaw).map(f => f.webkitRelativePath));
      const files = (L.files || []).filter(f => want.has(f.rel)).sort((a, b) => a.rel.localeCompare(b.rel));
      const xmpMap = sidecarsOf(L, {});
      const run = reading = { name: L.name, total: files.length, done: 0, gone: false };
      const t0 = performance.now(), res = new Array(files.length); let done = 0, i = 0;
      logic._gold = logic._gold || []; logic._failed = logic._failed || [];
      sidecarFailures(L);
      if (files.length) logic.setState({ realLoad: { done: 0, total: files.length, t0 } });
      const one = async (f, k) => {
        try { res[k] = await readOne(f, xmpMap); }
        catch (err) { if (err instanceof Gone) run.gone = true; res[k] = { err: true }; logic._failed.push({ name: f.rel.split('/').pop(), reason: err instanceof Gone ? 'card removed' : 'unreadable' }); }
        done++; run.done = done;
        if (done % 8 === 0 || done === files.length) logic.setState({ realLoad: { done, total: files.length, t0 } });
      };
      await Promise.all(Array.from({ length: Math.max(1, L.workers || 4) }, async () => { while (i < files.length && !run.gone) { const k = i++; await one(files[k], k); } }));
      for (; i < files.length; i++) { res[i] = { err: true }; logic._failed.push({ name: files[i].rel.split('/').pop(), reason: 'card removed' }); }
      const old = (logic.real || []).slice(), have = new Set(old.map(rfp));
      let nw = res.filter(p => p && !p.err);
      const dup = nw.filter(p => have.has(rfp(p)));
      if (dup.length) { const D = new Set(dup); nw = nw.filter(p => !D.has(p)); dup.forEach(dropPhoto); }
      af.dup = dup.length; af.n = nw.length;
      if (filling) { if (filling.offset) nw.forEach(p => { p.date = logic.shiftDate(p.date, filling.offset); }); }
      else {
        // A second camera whose clock is off: the page's own check and its own sheet decide.
        const off = nw.length ? logic.clockOffset(old, nw) : null;
        if (off) {
          const ch = await new Promise(res => logic.setState({ merge: Object.assign({}, off, { res }) }));
          logic.setState({ merge: null });
          if (ch === 'shift') { off.items.forEach(p => { p.date = logic.shiftDate(p.date, -off.sec); }); if (so) so.offset = -off.sec; }
        }
      }
      // The shoot as it is now, decisions by path (they may have changed while the files were read),
      // then the photos together in path order, as the page's own read leaves them.
      const snap = snapshot(logic);
      logic.real = old.concat(nw).sort((a, b) => a.path.localeCompare(b.path));
      logic.data = logic.build({}); logic._lk = null;
      reading = null;
      const G0 = () => Object.values(logic.data.G), first = logic.real.map(p => p.date).filter(Boolean).sort()[0] || '';
      const prev = logic.state.realInfo || {};
      restore(logic, snap, false);
      const info = Object.assign({}, prev, { name: primaryTop || prev.name, n: logic.real.length, rows: logic.data.R.length, stacks: G0().filter(g => g.kind !== 'single').length, bad: logic._failed.length,
        secs: ((performance.now() - t0) / 1000).toFixed(1), date: first.slice(0, 10).replace(/:/g, '-') });
      logic.setState({ realLoad: null, realInfo: info, openNote: null, notes: logic.notesFor(), notesOn: true, undo: [], sel: {}, pend: null });
      lastRead = { name: L.name, total: files.length, read: nw.length + dup.length, unreadable: files.length - nw.length - dup.length, stopped: run.gone ? 'card removed' : null, secs: +info.secs };
      window.lumina.read = Object.assign({}, lastRead);
      if (!filling) {
        // The shoot's name goes with it to its new key (the page keys names by folder, count, first and last file).
        const N = logic.names(); N[logic.nameKey()] = af.name; try { localStorage.setItem('lumina-v4-names', JSON.stringify(N)); } catch (_) {}
        logic.restoreSeen(af.key);
        logic._addFrom = null;
        logic.say('added ' + af.n + ' photo' + (af.n === 1 ? '' : 's') + ' to ' + af.name + (af.dup ? ' · ' + af.dup + ' already here, skipped' : ''));
        if (logic._pickOnAdd) {
          logic._pickOnAdd = false; const m = {};
          logic.data.order.forEach(id => { const p = logic.data.byId[id]; if (af.fresh.has(kk(p)) && !logic.state.marks[id]) m[id] = 'keep'; });
          if (Object.keys(m).length && typeof logic.apply === 'function') logic.apply({ marks: m }, 'picked ' + Object.keys(m).length + ' · dropped');
        }
      }
      if (run.gone) logic.say('Card removed · ' + nw.length + ' of ' + files.length + ' read · re-insert to keep going');
      logic.forceUpdate();
      pushSources(logic);
      // Kept by the Mac with the shoot (the source, its clock shift), and the session written now.
      await tellSources(logic);
      lastSaved = ''; lastChange = 0; saveNow();
      loadRecents(logic);
    };

    // Listings the Mac made of what was picked, dropped or arrived: the one marked `primary` is a
    // new shoot (there was none, or the page asked for one), the others join the open shoot.
    const tooBigLine = T => 'not available · ' + T.name + ' · ' + (T.why === 'tooDeep' ? 'folders over ' + T.depth + ' deep' : 'over ' + T.files + ' files') + ' · open one shoot';
    const take = async (list, src) => {
      for (const S of list) {
        if (!S) continue;
        if (S.denied != null) { window.luminaAccess(true, S.denied); continue; }
        if (S.tooBig) { const msg = tooBigLine(S.tooBig); if (S.primary) logic.setState({ openNote: msg }); logic.say(msg); continue; }
        if (!Array.isArray(S.files)) continue;
        if (S.primary) {
          window.luminaAccess(false); window.luminaCardGone(false);
          window.lumina.readingCard = !!S.onCard;
          S.source = Object.assign({ kind: S.kind || 'folder' }, src || {});
          await ingest(S); await afterRead();
        } else if (logic.real && logic._allF) await ingestAdd(S, { src: Object.assign({ kind: S.kind || 'folder' }, src || {}) });
      }
    };

    // The Sources panel's Add (the page's addAt): the Mac's picker, then what was picked joins the
    // shoot. With no shoot open it is an open. 'card' and 'phone' are not pickers (the card panel
    // and the phone page are the page's own).
    logic.__luminaAddFrom = async where => {
      if (where === 'card' || where === 'phone' || reading) return;
      const add = !!(logic.real && logic._allF);
      if (!add) saveNow();
      const r = await native('addFrom', { where: String(where || 'folder'), add, id: shootId });
      if (r && Array.isArray(r.sources)) await take(r.sources, { kind: ['pictures', 'downloads', 'desktop'].includes(where) ? where : 'folder' });
    };
    // The panel's Reconnect: the Mac finds the folder again (its bookmark, else the reader shows it
    // where it is); photos of a source that was not connected when the shoot opened are read now.
    logic.__luminaReconnect = async id => {
      const nid = srcNid[id]; if (!nid || reading || !shootId) return;
      const r = await native('sourceReconnect', { nid, id: shootId });
      if (!r || !r.source || !Array.isArray(r.source.files)) return;
      srcMissing[nid] = false;
      await ingestAdd(r.source, { fill: id });
    };

    // What the page hands its own onDir: `File`s from a drop on the window or one of its file
    // inputs, or the stand-ins for AirDrop arrivals (phoneArrived, below). In the app the Mac was
    // handed the same items (the drop's file URLs, the panel's picks), so it reads them: the photos
    // get a root of their own, which is what lets Save write a sidecar beside them, Edit render them
    // and a session find them again. `e.add` and `e.src` are the page's. Files the Mac was not
    // handed (nothing to claim) are read by the page itself, as before.
    const onDir = logic.onDir.bind(logic);
    logic.onDir = async e => {
      const given = [...((e && e.target && e.target.files) || [])];
      if (given.length && !cfg.parity) {
        if (reading) return;
        const add = !!(e.add && logic._allF && logic.real);
        if (!add) saveNow();
        const r = await Promise.resolve(native('claimFiles', { files: given.map(f => ({ rel: f.__luminaRel || f.webkitRelativePath || f.name, size: f.size })), add, id: shootId,
          kind: (e.src && e.src.kind) || null, label: (e.src && e.src.label) || null })).catch(() => null);
        if (r && Array.isArray(r.sources) && r.sources.length) return take(r.sources, e.src);
      }
      cardPulledWhileReading = false; readMoved = false;
      const adding = !!(e && e.add && logic._allF && logic.real);
      if (!adding) { window.lumina.readingCard = false; srcNid = {}; srcMissing = {}; }
      await onDir(e);
      if (!adding) primaryTop = (logic.state.realInfo || {}).name || null;
      pushSources(logic);
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
      // v7 sends two kinds in one call: ratings as .xmp bytes, and DNG picks as `Picks/<file>.DNG` whose
      // data is the photo's file (Lightroom ignores sidecars for DNG). The copies are made by the Mac,
      // streamed and SHA-256 verified, into a folder asked for once; the sidecars go next to the RAWs.
      const copies = files.filter(f => f && f.data && f.data.__luminaRel && /^Picks\//.test(f.name || ''));
      if (copies.length) files = files.filter(f => !copies.includes(f));
      const withCopies = async r => {
        if (!copies.length) return r;
        const c = await native('writeInto', { label: 'picks', files: copies.map(f => ({ name: f.name, copy: f.data.__luminaRel })) });
        const out = Object.assign({ n: 0, errors: [] }, r || {}), errs = (out.errors || []).slice();
        if (!c || c.aborted) for (const f of copies) errs.push({ name: f.name, reason: (c && c.say) || 'not copied · no folder chosen' });
        else { out.n = (out.n || 0) + (c.n || 0); for (const e of c.errors || []) errs.push(e); if (!files.length) { out.path = c.path; out.folder = c.folder; } }
        // The page marks a pick saved unless an error's name matches its sidecar path: a failed copy is
        // named by that path too, so the pick stays unsaved (DESIGN-ASKS: match copy errors by the DNG's name).
        const stem = n => String(n || '').split('/').pop().replace(/\.[^.]+$/, '').toLowerCase(), xp = {};
        for (const p of Object.values((logic.data && logic.data.byId) || {})) if (/\.dng$/i.test(p.path || '')) xp[stem(p.path)] = (p.xpath || '').split('/').pop();
        out.errors = errs.map(e => (/^Picks\//.test(e.name || '') && xp[stem(e.name)]) ? { name: xp[stem(e.name)], reason: e.name.split('/').pop() + ' not copied · ' + e.reason } : e);
        return out;
      };
      if (!files.length) return withCopies(null);
      // The page merged each rating into the sidecar text it holds from the open (xmpFor on p.xmp),
      // which can be hours old: Lightroom may have written the file since. So the Mac reads every
      // sidecar again now (text + base: the SHA-256 of those bytes, or "none"). Where the text differs
      // from the page's, the photo gets the text on disk and the page's own xmpFor merges again. The
      // base goes with the write: a file that is no longer its base (written in the instant between)
      // is left as it is and comes back "changed on disk"; nothing is retried silently (SAFETY.md 6),
      // the next Save reads again. The text from the open is never written over a newer file.
      // A shoot can have several sources: each sidecar goes under its own photo's root (the first
      // segment of the photo's path), so two sources that both hold DSC00001.ARW each get their own.
      // The page names a file by its path inside its root only, so the photo is found by position:
      // runExport lists its non-DNG picks in kept() order. A name that does not fit that order falls
      // back to the photo whose sidecar has that name.
      const enc = new TextEncoder(), byId = (logic.data && logic.data.byId) || {}, owner = {};
      const inRoot = p => { const q = (p.xpath || (p.file || '').replace(/\.[^.]+$/, '') + '.xmp').split('/'); return q.length > 1 ? q.slice(1).join('/') : q[0]; };
      const rootOf = p => { const q = (p.xpath || p.path || '').split('/'); return q.length > 1 ? q[0] : (info.name || ''); };
      for (const [id, p] of Object.entries(byId)) owner[inRoot(p)] = id;
      const picks = logic.kept().filter(id => byId[id] && !/\.dng$/i.test(byId[id].path || ''));
      const inOrder = picks.length === files.length && files.every((f, k) => inRoot(byId[picks[k]]) === f.name);
      const groups = {};                                     // root name → [{ f, id }]
      files.forEach((f, k) => { const id = inOrder ? picks[k] : owner[f.name], p = id != null ? byId[id] : null, root = p ? rootOf(p) : (info.name || ''); (groups[root] = groups[root] || []).push({ f, id, p }); });
      let r = null;
      for (const root of Object.keys(groups).sort((a, b) => (a === primaryTop ? -1 : b === primaryTop ? 1 : a < b ? -1 : 1))) {
        const G = groups[root], now = {};
        for (const s of (await native('readSidecars', { root, files: G.map(g => g.f.name) })) || []) now[s.name] = s;
        const list = [];
        for (const { f, id, p } of G) {
          const s = now[f.name], it = { name: f.name };
          let d = f.data;
          if (p && s && s.base != null) {
            const tx = s.text == null ? null : s.text;
            if ((p.xmp || null) !== (tx || null)) { p.xmp = tx; p.lrEd = LuminaCore.hasDevelop(tx); d = logic.xmpFor(id); }
            it.base = s.base;
          } else if (p) it.base = 'unread';                  // couldn't be read now: no file matches this, the write says why
          // (No photo for the name: nothing the page merged from. Sent as it is, unchecked.)
          const u = d instanceof Uint8Array ? d : d instanceof Blob ? new Uint8Array(await d.arrayBuffer()) : typeof d === 'string' ? enc.encode(d) : null;
          if (u) { it.b64 = b64(u); list.push(it); }
        }
        const one = await native('writeSidecars', { root, files: list });
        // A root the Mac does not have (photos the page read by itself): each of its files is an error.
        const part = one || { n: 0, bak: 0, errors: G.map(g => ({ name: g.f.name.split('/').pop().replace(/\.[^.]+$/, ''), reason: 'not available' })) };
        if (!r) r = one ? Object.assign({}, part, { errors: (part.errors || []).slice() }) : (Object.keys(groups).length > 1 ? Object.assign({}, part) : null);
        else { r.n = (r.n || 0) + (part.n || 0); r.bak = (r.bak || 0) + (part.bak || 0); r.errors = (r.errors || []).concat(part.errors || []); if (r.path == null && part.path != null) { r.path = part.path; r.folder = part.folder; } }
      }
      if (r && !(r.errors || []).length && (r.n || 0) > 0) savedKeepers = keepersOf(logic);
      if (r) setTimeout(saveNow, 0);
      return withCopies(r);
    };

    // "Cull This Card": the card's DCIM folder, read in place.
    const impStart = logic.impStart.bind(logic);
    // Since v7 the page also calls impStart(to) for ⌘2 / ⌘3 / ⌘4 from Open with a shoot loaded (to: 'cull',
    // 'edit' or null) and for the card's Edit button: those are the page's own. Only the bare call is the card.
    logic.impStart = v => (v === undefined || !logic.data.order.length)
      ? native('cullCard', {}).then(opened => { if (!opened) impStart(v); })
      : impStart(v);

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
    rowKeys();
    const l = findLogic();
    if (l && l !== current) { current = l; patch(l); lead(l); if (!missing(l).length) native('ready', {}); }
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

  // A Cull row keeps its own element while the grid scrolls. The page mounts the rows around the
  // viewport as a list, and its runtime keys list items by position: each time the first mounted row
  // changes, every row's element is handed the next row's photos, its height animates 180 ms to that
  // row's height and its images swap under the reader (measured: 50 to 85 % of the rows on screen out
  // of place while scrolling a shoot whose rows differ in height). Keyed by the row's id instead, the
  // rows that stay are not touched and only the ones entering or leaving mount. Same elements, same
  // styles; DESIGN-ASKS 11 asks the page for it.
  let rowKeysOn = cfg.rowKeys !== false && !cfg.parity;
  const rowKeys = () => {
    const R = window.React;
    if (!R || R.__luminaRowKeys || typeof R.createElement !== 'function') return;
    const make = R.createElement, Frag = R.Fragment;
    // A row item is a list item whose sc-if holds the row's element directly: that level and no other
    // (keyed one level up, the list itself would be remounted every time its first row changes).
    const rowId = kids => {
      for (const c of kids) {
        if (!c || c.type !== Frag || !c.props) continue;
        const inner = c.props.children;
        for (const e of Array.isArray(inner) ? inner : [inner]) {
          if (e && e.props && e.props['data-lumina'] === 'row' && e.props['data-id'] != null) return e.props['data-id'];
        }
      }
      return null;
    };
    R.createElement = function (type, props, kids) {
      if (rowKeysOn && type === Frag && props && typeof props.key === 'number' && Array.isArray(kids)) {
        const id = rowId(kids);
        if (id != null) { const a = Array.prototype.slice.call(arguments); a[1] = Object.assign({}, props, { key: 'row:' + id }); return make.apply(this, a); }
      }
      return make.apply(this, arguments);
    };
    R.__luminaRowKeys = true;
  };

  // With rows keyed, a row entering the window is a new element, and the page starts every tile
  // image at opacity 0, loads it lazily and fades it in over 180 ms: at scrolling speed the rows
  // arrive on screen still blank. Two behaviours, both asked of the page in DESIGN-ASKS 7 (b), (c):
  // a thumbnail that exists is loaded at once and shown the moment it has loaded (the fade stays for
  // thumbnails that arrive while the reader looks on: a read in progress, the grid at rest); and the
  // mounted rows lead the scroll by 0.4 s of travel, up to two viewports, 700 px behind as the page
  // has it, and return to the page's own ±700 px when the scroll rests.
  const CULL = '[data-screen-label="1 Cull"]';
  let tilesOn = cfg.readyTiles !== false && !cfg.parity;
  const readyTile = im => {
    if (im.loading === 'lazy') im.loading = 'eager';
    if (!(reading && performance.now() - scrollT > 300)) im.style.transition = 'none';
  };
  if (typeof MutationObserver === 'function') new MutationObserver(list => {
    if (!tilesOn || !current || !current.real) return;
    for (const m of list) for (const n of m.addedNodes) {
      if (n.nodeType !== 1) continue;
      const root = n.closest(CULL) ? n : n.querySelector(CULL);
      if (!root) continue;
      if (root.tagName === 'IMG') readyTile(root); else for (const im of root.querySelectorAll('img')) readyTile(im);
    }
  }).observe(document, { childList: true, subtree: true });      // the document: at document start there may be no root element yet

  let leadOn = cfg.leadWindow !== false && !cfg.parity;
  const lead = logic => {
    if (logic.__luminaLead || typeof logic.onScroll !== 'function' || typeof logic.layout !== 'function' || !logic.scrollRef || !Array.isArray(logic.state.vr)) return;
    logic.__luminaLead = true;
    const own = logic.onScroll;
    // Since v7 the page leads its own window (two viewports in the direction of travel) and its
    // scroll handler also keeps the time axis and the read's "moved" mark: nothing to replace.
    if (/_dir\b/.test(String(own))) return;
    let lastTop = null, lastT = 0, rest = 0, held = 0, dir = 0;
    logic.onScroll = function () {
      if (!leadOn) return own.call(logic);
      cancelAnimationFrame(logic._sr);
      logic._sr = requestAnimationFrame(() => {
        const el = logic.scrollRef.current; if (!el) return;
        const now = performance.now(), y = el.scrollTop, dt = now - lastT, resting = lastTop == null || dt > 250;
        const v = resting ? 0 : (y - lastTop) / Math.max(8, dt);                                             // px per ms
        lastTop = y; lastT = now;
        // The lead holds while the scroll keeps its direction (a frame without movement must not unmount
        // rows the next one mounts again) and goes when the scroll turns or rests.
        if (resting) { dir = 0; held = 0; } else if (v && Math.sign(v) !== dir) { dir = Math.sign(v); held = 0; }
        const ahead = held = Math.max(Math.min(2 * el.clientHeight, Math.abs(v) * 400), held * 0.9);
        const L = logic.layout(), top = y - 700 - (dir < 0 ? ahead : 0), bot = y + el.clientHeight + 700 + (dir > 0 ? ahead : 0);
        let a = 0; while (a < L.rows.length - 1 && L.rows[a].y + L.rows[a].h < top) a++;
        let b = a; while (b < L.rows.length - 1 && L.rows[b + 1].y < bot) b++;
        const w = logic.state.vr; if (w[0] !== a || w[1] !== b) logic.setState({ vr: [a, b] });
        clearTimeout(rest); if (ahead) rest = setTimeout(() => logic.onScroll(), 400);
      });
    };
  };

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
  // ——— Edit v21 on the canvas above. The page (Lumina Edit v21, mounted by Sets v7) makes none of
  // Prompt 1 §3's calls: in the app it leaves its photo box empty and keeps its state to itself. So
  // while its Edit step is the active one, plumbing reads that state once per animation frame (the
  // page announces drags, zoom and pan through lumina.emit, but not keys, Auto, paste, undo or a
  // pointer pan, so events alone would miss changes) and drives the calls above with it:
  //   photo   luminaState.__owner (the Edit logic): state.cur → Sets' data.byId[id].path → edit.enter
  //   look    owner.look(photo), an object → lookString → edit.look
  //   box     where the page would draw the photo: the crop fitted into [data-lumina="canvas"], then
  //           the page's zoom and pan, clipped to that element → edit.layout; what is left of the frame
  //           inside it → roi (the canvas draws the uncropped frame, so a crop is a region too)
  //   drags   lumina.emit('dragStart' | 'dragEnd') → edit.dragStart / dragEnd
  // The canvas hides (null rect) whenever the page shows something of its own in that box.
  // Decisions still open (the owner's): the page's Sharpening rests at 40 and the Mac's at 0, so 40
  // is taken as the Mac's 0 here (SHP_BASE); the page's as-shot temperature is a fixed 5500 K, so a
  // temperature is sent as a ratio of the photo's own as-shot value when the Mac names it
  // (header.asShot for header.asShotRel), else as the page's number.
  const SHP_BASE = 40;
  // `\` held: the as-shot render, not a hidden canvas (the page would show the untouched preview).
  const BEFORE_RENDERS = true;
  const lookNum = (v, d) => { const r = +(+v).toFixed(d); return r === 0 ? (d ? (0).toFixed(d) : '0') : (r > 0 ? '+' : '') + r.toFixed(d); };
  // LookString.swift's grammar, values at reset left out. The page's keys with no stage on the Mac
  // (tone curve, colour mixer, vignette shape, 90° turns) are dropped.
  const lookString = (L, p, asShot) => {
    L = L || {};
    const out = [], has = k => L[k] != null && isFinite(+L[k]), cl = (v, a, b) => Math.min(b, Math.max(a, +v));
    if (has('ev') && +L.ev !== 0) out.push('ev:' + lookNum(cl(L.ev, -5, 5), 2));
    if (has('wb') || (has('tint') && +L.tint !== 0)) {
      const shot = +(p && p.wbShot) || 5500, k = has('wb') ? +L.wb : shot, t = has('tint') ? +L.tint : 0;
      const K = asShot && +asShot.kelvin > 0 ? +asShot.kelvin * k / shot : k, T = (asShot ? +asShot.tint || 0 : 0) + t;
      out.push('wb:' + Math.round(cl(K, 2000, 50000)) + '/' + lookNum(cl(T, -150, 150), 0));
    }
    for (const k of ['con', 'hl', 'sh', 'wh', 'bl', 'sat']) if (has(k) && Math.round(+L[k]) !== 0) out.push(k + ':' + lookNum(cl(L[k], -100, 100), 0));
    if (has('shp')) { const v = Math.round(cl(+L.shp - SHP_BASE, 0, 150)); if (v) out.push('shp:' + v); }
    if (has('vig') && Math.round(+L.vig) !== 0) out.push('vig:' + lookNum(cl(L.vig, -100, 100), 0));
    if (has('nr') && Math.round(+L.nr) > 0) out.push('nr:' + Math.round(cl(L.nr, 0, 100)));
    if (p && p.bw) out.push('bw:1');
    const c = cropOf(L);
    if (c.set) out.push('crop:' + [c.x, c.y, c.w, c.h].map(v => v.toFixed(4)).join(',') + (c.ang ? '/' + c.ang.toFixed(2) : ''));
    return out.join(' ');
  };
  // The page's crop ({x, y, w, h} in fractions of the frame, `ang` degrees), kept inside the frame.
  const cropOf = L => {
    const c = (L && L.crop) || {}, f = v => (isFinite(+v) ? +v : NaN);
    let x = f(c.x), y = f(c.y), w = f(c.w), h = f(c.h);
    if (!(w > 0 && h > 0) || isNaN(x) || isNaN(y)) return { x: 0, y: 0, w: 1, h: 1, ang: 0, set: false };
    x = Math.min(1, Math.max(0, x)); y = Math.min(1, Math.max(0, y));
    w = Math.floor(Math.min(w, 1 - x) * 1e4) / 1e4; h = Math.floor(Math.min(h, 1 - y) * 1e4) / 1e4;
    const ang = Math.min(45, Math.max(-45, f(c.ang) || 0));
    if (!(w > 0 && h > 0)) return { x: 0, y: 0, w: 1, h: 1, ang: 0, set: false };
    return { x, y, w, h, ang, set: !!ang || x > 0.001 || y > 0.001 || w < 0.999 || h < 0.999 };
  };
  const pg = { on: false, raf: 0, timer: 0, rel: null, entering: null, lay: null, roiKey: '', lastLook: 0, endDrag: false, miss: 0, loupeT: 0, loupeKey: '', why: '', error: null };
  const pageOwner = () => { const f = window.luminaState, o = f && f.__edit && f.__owner; return o && o.state && o.data && o.data.byId && typeof o.look === 'function' ? o : null; };
  // Why the canvas may not show now: the page (Edit, or Sets above it) is drawing in the photo's box.
  const pageCovered = (o, l, L) => {
    const s = o.state, t = l.state;
    return s.crop ? 'crop' : s.pick ? 'white picker' : s.stMode || s.rHeld || s.sLine ? 'straighten' : s.alt && s.sec === 'colour' ? 'colour' :
      s.spec ? 'variations' : s.sg ? 'scene review' : s.verOpen ? 'versions' : s.help ? 'help' : s.intro ? 'intro' : !BEFORE_RENDERS && s.before ? 'before' :
      (+L.rot || 0) % 360 ? 'turned' : t.faq ? 'faq' : t.tour != null ? 'tour' : t.prefsOn ? 'settings' : t.betaOn ? 'known issues' : t.cacheOn ? 'working files' :
      t.pre ? 'access' : t.phonePage ? 'phone' : '';
  };
  const pageGeo = (o, p, L) => {
    const el = document.querySelector('[data-lumina="canvas"]'); if (!el) return null;
    const CW = el.clientWidth, CH = el.clientHeight; if (CW < 20 || CH < 20) return null;
    // The photo's own shape (Sets' number), not the page's measure of the image it shows: in the app
    // that image is a 1 × 1 stand-in.
    const s = o.state, A = +p.ar > 0 ? +p.ar : 1.5, c = cropOf(L), zm = +s.zm > 0 ? +s.zm : 1;
    const k = Math.min(CW / (c.w * A), CH / c.h), w = c.w * A * k, h = c.h * k;
    const X = Math.round(+s.zx || 0) + zm * (CW - w) / 2, Y = Math.round(+s.zy || 0) + zm * (CH - h) / 2, W = zm * w, H = zm * h;
    const x0 = Math.max(0, X), y0 = Math.max(0, Y), x1 = Math.min(CW, X + W), y1 = Math.min(CH, Y + H);
    if (x1 - x0 < 1 || y1 - y0 < 1) return null;
    const b = el.getBoundingClientRect(), bx = b.left + el.clientLeft, by = b.top + el.clientTop;
    const rect = { x: Math.round(bx + x0), y: Math.round(by + y0), w: Math.round(x1 - x0), h: Math.round(y1 - y0) };
    const r5 = v => +v.toFixed(5);
    let roi = { x: r5(c.x + (x0 - X) / W * c.w), y: r5(c.y + (y0 - Y) / H * c.h), w: r5((x1 - x0) / W * c.w), h: r5((y1 - y0) / H * c.h) };
    if (roi.x <= 0.0005 && roi.y <= 0.0005 && roi.w >= 0.999 && roi.h >= 0.999) roi = null;
    // The page's chrome inside the element (zoom pill, state chip, colour chip) and Sets' working
    // files pill: whatever lies over the photo and is not the photo's own layer or a full cover.
    const holes = [], photo = el.querySelector('[data-lumina-img]');
    const add = n => {
      if (!n || n.nodeType !== 1 || (photo && n.contains(photo))) return;
      const q = n.getBoundingClientRect();
      if (q.width < 1 || q.height < 1) { for (const m of n.children) add(m); return; }
      if (q.width >= CW * 0.9 && q.height >= CH * 0.9) return;
      const hx = Math.max(q.left, rect.x), hy = Math.max(q.top, rect.y), hw = Math.min(q.right, rect.x + rect.w) - hx, hh = Math.min(q.bottom, rect.y + rect.h) - hy;
      if (hw >= 1 && hh >= 1 && holes.length < 16) holes.push({ x: Math.round(hx), y: Math.round(hy), w: Math.round(hw), h: Math.round(hh) });
    };
    for (const n of el.children) add(n);
    add(document.querySelector('[data-lumina="cache-pill-edit"]'));
    return { rect, roi, holes };
  };
  const pageStop = () => {
    if (!pg.on) return;
    pg.on = false; cancelAnimationFrame(pg.raf); clearTimeout(pg.timer); clearTimeout(pg.loupeT);
    pg.endDrag = false; pg.miss = 0; pg.loupeKey = ''; pg.roiKey = ''; pg.lay = null; pg.entering = null; pg.why = '';
    if (ed.dragging) edit.dragEnd();
    if (pg.rel) { pg.rel = null; edit.leave(); }
  };
  // One pass: false when the page's Edit step is no longer the active one (the loop ends).
  const pageSync = () => {
    const l = current;
    if (!l || l.state.view !== 'edit' || typeof window.luminaEditRect === 'function') { pageStop(); return false; }
    const o = pageOwner(), s = o && o.state, p = o && s.cur != null ? o.data.byId[s.cur] : null;
    const q = p && l.data && l.data.byId ? l.data.byId[p.id] : null, rel = (q && q.path) || null;
    if (!rel) {
      if (pg.rel) { pg.rel = null; pg.lay = null; if (ed.dragging) edit.dragEnd(); edit.leave(); }
      pg.why = o ? 'no photo' : 'not mounted'; return true;
    }
    let L = {}; try { L = o.look(p) || {}; } catch (_) {}
    const asShot = ed.header && ed.header.asShot && ed.header.asShotRel === rel ? ed.header.asShot : null;
    const look = BEFORE_RENDERS && s.before ? 'none' : lookString(L, p, asShot);
    if (pg.rel !== rel) {
      pg.rel = rel; pg.entering = rel; pg.roiKey = ''; pg.loupeKey = ''; clearTimeout(pg.loupeT);
      Promise.resolve(edit.enter(rel, look)).catch(() => null).then(() => { if (pg.entering === rel) pg.entering = null; });
    }
    pg.why = pageCovered(o, l, L);
    const geo = pg.why ? null : pageGeo(o, p, L);
    const lay = geo ? JSON.stringify([geo.rect, geo.holes]) : '';
    if (lay !== pg.lay || (!!geo) !== ed.visible) { pg.lay = lay; edit.layout(geo ? geo.rect : null, !!geo, geo ? { holes: geo.holes } : null); }
    if (pg.entering === rel || ed.rel !== rel) return true;
    // The look and the region. A change within 100 ms of the last one is a run (a wheel on a slider,
    // a held key): the quarter tier, as a drag; one alone is a keystroke: once, at full quality.
    const roi = geo ? geo.roi : ed.roi, roiKey = geo ? (roi ? JSON.stringify(roi) : '') : pg.roiKey;
    const moved = look !== ed.look;
    if (moved || roiKey !== pg.roiKey) {
      const now = performance.now(), drag = ed.dragging || !moved || now - pg.lastLook < 100;
      if (moved) pg.lastLook = now;
      pg.roiKey = roiKey;
      edit.look(look, { drag, key: !drag, roi });
    }
    // 100 %: the region is refined (RAW 9) once it has stood still for 150 ms.
    const lk = geo && zoomedIn(s) && roi ? roiKey : '';
    if (lk !== pg.loupeKey) {
      pg.loupeKey = lk; clearTimeout(pg.loupeT);
      if (!lk) { if (ed.loupe) edit.loupe(false); }
      else pg.loupeT = setTimeout(() => { if (pg.on && pg.loupeKey === lk && ed.rel === rel) edit.loupe(true, roi); }, 150);
    }
    // Drags: the page's events lead; its state is the fallback (three passes of disagreement).
    const sd = !!s.dragging;
    if (pg.endDrag) { pg.endDrag = false; pg.miss = 0; if (ed.dragging) edit.dragEnd(); }
    else if (sd === ed.dragging) pg.miss = 0;
    else if (++pg.miss >= 3) { pg.miss = 0; if (sd) edit.dragStart(); else edit.dragEnd(); }
    return true;
  };
  const zoomedIn = s => (+s.zm || 1) > 1.001;
  // Once per animation frame while Edit shows; every 250 ms when frames are not running (a hidden window).
  const pageRun = () => {
    cancelAnimationFrame(pg.raf); clearTimeout(pg.timer);
    let more = pg.on;
    try { if (more) more = pageSync(); pg.error = null; } catch (e) { pg.error = String((e && e.message) || e); }
    if (more && pg.on) { pg.raf = requestAnimationFrame(pageRun); pg.timer = setTimeout(pageRun, 250); }
  };
  // What the page announces (Edit v21's emit): a drag's start and end. Zoom and pan carry no
  // position and arrive before the page's state has moved, so the region is read from that state on
  // the next pass; the other types (spectrum, wbPick, colourAt, step) are the page's own business.
  const pageEmit = (type, detail) => {
    if (!pg.on) return;
    if (type === 'dragStart') { pg.endDrag = false; pg.miss = 0; if (!ed.dragging) edit.dragStart(); }
    else if (type === 'dragEnd') pg.endDrag = true;
  };
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
      // `holes`: page chrome lying over the photo (CSS px, as the rect), for the Mac to leave uncovered.
      native('canvasLayout', Object.assign({ visible: ed.visible, dpr: dpr(), holes: ed.visible && o && Array.isArray(o.holes) ? o.holes : [] }, ed.rect || { x: 0, y: 0, w: 0, h: 0 })).then(r => { if (r && r.path) { ed.path = r.path; pushFacts(); } }).catch(() => {});
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
      const l = current; if (!l || l.state.view !== 'edit') return;
      // Edit v21 reports nothing: the photo, its look and its box are read from the page (pageSync, below).
      if (typeof window.luminaEditRect !== 'function') { if (!pg.on) { pg.on = true; pg.lay = null; pg.rel = null; pageRun(); } return; }
      const r = window.luminaEditRect();
      const same = ed.rect && r && ed.rect.x === r.x && ed.rect.y === r.y && ed.rect.w === r.w && ed.rect.h === r.h;
      if (!same || !ed.visible) edit.layout(r, !!r);
      ed.rectTimer = setTimeout(edit.pollRect, 250);
    },
    // Menu commands while the page's Edit step is the active one (Edit v21 leaves ⌘Z ⇧⌘Z ⌘C ⌘V to the
    // app and answers them on window.luminaEdit; a step goes through its 'lumina:step' event).
    // undefined = not Edit's: the caller falls through to window.luminaCommand.
    command(name) {
      const l = current; if (!l || l.state.view !== 'edit') return undefined;
      if (name === 'undo' || name === 'redo' || name === 'copy' || name === 'paste') {
        const e = window.luminaEdit; if (!e || typeof e[name] !== 'function') return false;
        e[name](); return true;
      }
      const view = { stepOpen: 'open', stepCull: 'cull', stepEdit: 'edit', stepSave: 'save' }[name];
      if (!view) return undefined;
      window.dispatchEvent(new CustomEvent('lumina:step', { detail: { view } })); return true;
    },
    lookString: (L, p, asShot) => lookString(L, p, asShot),
    get image() { return img.url; },
    state() { return { rel: ed.rel, look: ed.look, path: ed.path, rect: ed.rect, visible: ed.visible, force: !!ed.force, dragging: ed.dragging, seq: ed.seq, loupe: ed.loupe, roi: ed.roi,
      page: { on: pg.on, rel: pg.rel, entering: pg.entering, hidden: pg.why, error: pg.error },
      image: { shown: img.shown, tier: img.tier, fetches: img.fetches, superseded: img.superseded, inFlight: img.inFlight, pending: !!img.pending, url: img.url }, facts: ed.factsText, header: ed.header }; },
  };
  window.lumina.edit = edit;
  // Prompt 1 §3's four calls, on window.lumina itself.
  window.lumina.preview = edit.preview;
  window.lumina.canvasRect = edit.canvasRect;
  window.lumina.drag = edit.drag;
  window.lumina.roi = edit.roi;
  // Edit v21 calls this when it is there (its drags; see pageEmit).
  window.lumina.emit = pageEmit;
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
    // The open shoot's sources as the Mac sees them now: [{nid, missing}] (a card with one of them went or came back).
    sources(list) { sourceStatus(window.__lumina.logic(), list); },
    // AirDrop arrivals in the watched Downloads folder: [{rel: 'AirDrop/<name>', size}] and how many
    // HEIC / JPEG came with them. The page's phoneArrived shows them ("N RAWs from phone · Add to
    // shoot") and makes a thumbnail from each file's head and embedded preview, so the stand-ins
    // answer slice().arrayBuffer() from the Mac's reader; adding them goes through the page's onDir.
    phoneArrived(files, lossy) {
      if (typeof window.luminaPhoneArrived !== 'function') return 0;
      const made = (files || []).filter(f => f && typeof f.rel === 'string').map(f => {
        const size = +f.size || 0;
        return Object.assign(fileRef(f.rel), { size, type: '', lastModified: Date.now(),
          slice(a, b) {
            a = Math.max(0, a || 0); b = Math.min(b == null ? size : b, size);
            return { size: Math.max(0, b - a), arrayBuffer: async () => {
              if (b <= 262144) return (await (await get(media('head', { p: f.rel }))).arrayBuffer()).slice(a, b);
              return (await get(media('preview', { p: f.rel, o: a, l: b - a, ori: 1 }))).arrayBuffer();
            } };
          } });
      });
      window.luminaPhoneArrived(made, typeof lossy === 'number' ? lossy : Array.isArray(lossy) ? lossy : 0);
      return made.length;
    },
    // Edit's own first (undo / redo / copy / paste, and the step menu while Edit is the active step).
    command(name) { const h = edit.command(name); if (h !== undefined) return h; return typeof window.luminaCommand === 'function' ? window.luminaCommand(name) : false; },
    // View ▸ Zoom 100%: Z is a hold key in the page; the menu toggles it through the page's gesture hook.
    zoom() { const l = window.__lumina.logic(); if (l && typeof window.luminaGesture === 'function') window.luminaGesture('hold', { key: 'z', down: !l.state.zoom }); },
    // Quit asks when there are keepers not yet saved (MENUS.md): their count, or 0.
    unsaved() {
      const l = window.__lumina.logic();
      if (!l || !l.real || !l.real.length) return 0;
      // v7 counts it itself (picks, or everything not removed, minus what the last Save wrote).
      if (typeof window.luminaUnsaved === 'function') return window.luminaUnsaved() || 0;
      const k = l.kept().length;
      return k && keepersOf(l) !== savedKeepers ? k : 0;
    },
    closeShoot() {
      const l = window.__lumina.logic(); if (!l) return;
      saveNow();
      shootId = null; lastSaved = ''; base = null; savedKeepers = null; lastRead = null;
      primaryTop = null; srcNid = {}; srcMissing = {}; window.lumina.sources = [];
      window.lumina.readingCard = false; window.lumina.read = null;
      window.luminaCardGone(false);
      l.forget();
      loadRecents(l);
    },
    removeWorkingFiles() {
      const l = window.__lumina.logic();
      // File ▸ Remove Working Files…: the shoot's session goes too (the alert says its decisions are
      // forgotten; THREAT-MODEL T11's answer for sessions left in the container). The page's own clear,
      // `lumina.removeWorkingFiles`, keeps them.
      const gone = shootId ? native('removeShoot', { id: shootId }).then(ok => { shootId = null; lastSaved = ''; base = null; return ok; }) : Promise.resolve(false);
      return gone.then(ok => { if (ok && l) { l.forget(); loadRecents(l); } return ok; });
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
        sources: ((l && l._sources) || []).map(so => ({ id: so.id, kind: so.kind, label: so.label, top: so.top, n: so.n, offset: so.offset || 0, nid: srcNid[so.id] || null, missing: !!(srcNid[so.id] && srcMissing[srcNid[so.id]]) })),
        shootId, card: window.lumina.card, cardPending: window.lumina.cardPending, readingCard: window.lumina.readingCard,
      };
    },
    nativeStats: () => native('ingestStats', {}),
    // Probe A/B: decode thumbnails ahead of a scroll or not. Returns how many are held.
    warmAhead(on) { if (on != null) { warmOn = !!on; if (!warmOn) warm.clear(); } return warm.size; },
    // Probe A/B: Cull rows keyed by row id (on) or by position, as the page's runtime keys them.
    rowKeys(on) { if (on != null) { rowKeysOn = !!on; if (current) current.forceUpdate(); } return rowKeysOn && !!(window.React && window.React.__luminaRowKeys); },
    // Probe A/B: thumbnails that exist shown without the fade, and the mounted rows leading the scroll.
    readyTiles(on) { if (on != null) tilesOn = !!on; return tilesOn; },
    leadWindow(on) { if (on != null) leadOn = !!on; return leadOn; },
    say(t) { const l = window.__lumina.logic(); if (l) l.say(t); },
    openFolder() { const l = window.__lumina.logic(); if (l) l.openFolder(true); },
    undo() {
      const a = document.activeElement;
      if (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA')) return document.execCommand('undo');
      const l = window.__lumina.logic(); if (l) l.undo();
    },
  };
})();
