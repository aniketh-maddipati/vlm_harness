// Lumina app plumbing. Injected at document start into the design's page, which ships byte-identical.
// This file is the only place the app differs from the prototype: it swaps the page's browser I/O
// (BUILD-exact rule 2: openFolder / writeInto / renderJpg / download keep their names, only the
// insides change) for calls to the native bridge. Layout, styles, copy and keys are untouched.
(() => {
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

  const patch = logic => {
    if (logic.__luminaPlumbed) return;
    logic.__luminaPlumbed = true;

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
    if (l && l !== current) { current = l; patch(l); native('ready', {}); }
    setTimeout(watch, current ? 1000 : 30);
  };
  watch();

  // Native → page. Only existing page actions are used.
  window.__lumina = {
    logic: () => current || findLogic(),
    card(present) { const l = window.__lumina.logic(); if (l) l.impSet({ card: !!present }); },
    say(t) { const l = window.__lumina.logic(); if (l) l.say(t); },
    openFolder() { const l = window.__lumina.logic(); if (l) l.openFolder(); },
    undo() {
      const a = document.activeElement;
      if (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA')) return document.execCommand('undo');
      const l = window.__lumina.logic(); if (l) l.undo();
    },
  };
})();
