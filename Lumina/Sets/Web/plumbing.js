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

  // Everything below leans on these page members. A design sync that renames one shows up here
  // (and in the probe's plumbing-contract scenario) instead of as a silent break.
  const REQUIRED = ['onKey', 'setState', 'setView', 'say', 'undo', 'openFolder', 'onDir', 'writeInto', 'renderJpg',
    'impStart', 'impSet', 'simCard', 'libOpen', 'build', 'cssR', 'eff', 'forget', 'saveGolden'];
  const missing = logic => REQUIRED.filter(k => typeof logic[k] !== 'function').concat(
    logic.constructor && Array.isArray(logic.constructor.SHOOTS) ? [] : ['static SHOOTS']);

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

    // Reading a folder: after the page has built the shoot, remember it and bring its decisions back.
    const onDir = logic.onDir.bind(logic);
    logic.onDir = async e => {
      cardPulledWhileReading = false;
      await onDir(e);
      // The page counts files lost to a pulled card as "unreadable"; say what happened, in its words.
      if (cardPulledWhileReading) logic.say('Card removed · re-insert to keep going');
      if (!logic.real) return;
      const first = logic.real.map(p => p.date).filter(Boolean).sort()[0] || '';
      const r = await native('shootOpened', { name: (logic.state.realInfo || {}).name, n: logic.real.length, date: first });
      shootId = r && r.id; lastSaved = '';
      if (r && r.session) { try { restore(logic, JSON.parse(r.session)); } catch (_) {} }
      lastSaved = JSON.stringify(snapshot(logic));
      loadRecents(logic);
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

  // Native → page. Only existing page actions are used.
  window.__lumina = {
    logic: () => current || findLogic(),
    ready: () => !!(current && current.__luminaPlumbed),
    missing: () => { const l = current || findLogic(); return l ? missing(l) : ['page not found']; },
    shootId: () => shootId,
    card(present, info) {
      if (cfg.parity) return;              // test-only: keep the design's sample card state for pixel parity
      window.lumina.card = present ? (info || {}) : null;
      const l = window.__lumina.logic();
      if (!present && l && l.state.realLoad) cardPulledWhileReading = true;
      if (l) l.impSet({ card: !!present });
    },
    say(t) { const l = window.__lumina.logic(); if (l) l.say(t); },
    openFolder() { const l = window.__lumina.logic(); if (l) l.openFolder(); },
    undo() {
      const a = document.activeElement;
      if (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA')) return document.execCommand('undo');
      const l = window.__lumina.logic(); if (l) l.undo();
    },
  };
})();
