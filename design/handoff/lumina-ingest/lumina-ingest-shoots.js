// Lumina Ingest: where a shoot starts and ends, and the folders a shoot is copied into.
//
// Shoots are proposed from the capture times alone (after the clocks are aligned), no model:
//   - a gap of 6 hours or more between two consecutive captures starts a new part (a night, mostly);
//   - a gap of 2 hours or more does too when the camera or the source (card, folder) changes across it;
//   - parts less than 36 hours apart stay one shoot (a trip is one shoot holding its days); a longer
//     gap starts a new shoot.
// The owner corrects a proposal by hand: `cut` (ids where a new shoot was started: "split here") and
// `join` (ids whose proposed start of a shoot was taken away: "merge with next"). Both are plain sets,
// so every correction is undone by taking its id out again.
//
// Folders come from a pattern the owner may set once ("{year}/{start} {shoot}/{kind}"); without one
// they are the plain dated folders ("2026-10-28"). Every folder a pattern makes is cleaned so that
// the Mac's IngestCopy.safeFolder takes it: no "..", no part that starts with a dot, no empty part.
(function (root) {
  'use strict';
  const H = 3600e3;
  const O = { partGap: 6 * H, changeGap: 2 * H, shootGap: 36 * H };

  // items: [{id, t, body, src}] (t in ms; undated items are left out by the caller).
  // Answers shoots in time order: [{ids, lo, hi, parts: [{ids, lo, hi}], start, cut, joined: [ids]}].
  function propose(items, fix, opts) {
    const o = Object.assign({}, O, opts || {});
    const cut = (fix && fix.cut) || new Set(), join = (fix && fix.join) || new Set();
    const list = items.filter((i) => i.t).slice().sort((a, b) => a.t - b.t || String(a.id).localeCompare(String(b.id)));
    const shoots = [];
    let shoot = null, part = null, prev = null;
    for (const it of list) {
      let newPart = !prev, newShoot = !prev;
      if (prev) {
        const gap = it.t - prev.t;
        const changed = (it.body || '') !== (prev.body || '') || (it.src || '') !== (prev.src || '');
        if (gap >= o.partGap || (gap >= o.changeGap && changed)) newPart = true;
        if (gap >= o.shootGap) newShoot = true;
        if (newShoot && join.has(it.id)) { newShoot = false; shoot.joined.push(it.id); }
        // a split by hand lands on the start of a part (the page offers it there)
        if (cut.has(it.id)) { newShoot = true; newPart = true; }
      }
      if (newShoot) { shoot = { ids: [], lo: it.t, hi: it.t, parts: [], start: it.id, cut: !!prev && cut.has(it.id), joined: [] }; shoots.push(shoot); newPart = true; }
      if (newPart) { part = { ids: [], lo: it.t, hi: it.t, start: it.id }; shoot.parts.push(part); }
      part.ids.push(it.id); part.hi = it.t; shoot.ids.push(it.id); shoot.hi = it.t;
      prev = it;
    }
    return shoots;
  }

  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const pad = (n) => String(n).padStart(2, '0');
  const ymd = (t) => { const d = new Date(t); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; };
  // The name a shoot is drafted with: its dates ("Oct 28, 2026", "Oct 28 – 30, 2026").
  function draftName(lo, hi) {
    const a = new Date(lo), b = new Date(hi);
    if (a.toDateString() === b.toDateString()) return `${MON[a.getMonth()]} ${a.getDate()}, ${a.getFullYear()}`;
    if (a.getMonth() === b.getMonth() && a.getFullYear() === b.getFullYear()) return `${MON[a.getMonth()]} ${a.getDate()} – ${b.getDate()}, ${a.getFullYear()}`;
    return `${MON[a.getMonth()]} ${a.getDate()} – ${MON[b.getMonth()]} ${b.getDate()}, ${b.getFullYear()}`;
  }

  // ---- the folder pattern ---------------------------------------------------------------------
  const TOKENS = ['year', 'month', 'date', 'start', 'shoot', 'kind', 'camera'];
  // One folder name: nothing that could leave the library or hide (no slash, no colon, no leading dot).
  function clean(s) {
    return String(s == null ? '' : s).replace(/[\/\\:\u0000-\u001f]/g, '-').replace(/\s+/g, ' ').replace(/^[.\s-]+/, '').replace(/[\s.]+$/, '').slice(0, 80);
  }
  // What safeFolder (IngestCopy.swift) takes: parts that are not empty, not "..", not dot-names.
  function safe(folder) {
    const parts = String(folder).split('/').filter(Boolean);
    return parts.length && !parts.some((p) => p === '..' || p === '.' || p.startsWith('.')) ? parts.join('/') : null;
  }
  // The pattern as the owner typed it, checked: answers {ok, pattern, unknown: [tokens]}.
  function check(pattern) {
    const p = String(pattern || '').trim().slice(0, 200);
    const unknown = []; p.replace(/\{([^{}]*)\}/g, (_, t) => { if (!TOKENS.includes(t.trim().toLowerCase())) unknown.push(t); return ''; });
    const stray = /[{}]/.test(p.replace(/\{[^{}]*\}/g, ''));
    return { ok: !!p && !unknown.length && !stray && TOKENS.some((t) => new RegExp('\\{\\s*' + t + '\\s*\\}', 'i').test(p)), pattern: p, unknown };
  }
  // v: {t, start, shoot, kind, camera}. Without a pattern, or without a date: the plain dated folder.
  function folder(pattern, v) {
    if (!v.t) return 'No date';
    const plain = ymd(v.t);
    if (!pattern || !check(pattern).ok) return plain;
    const d = new Date(v.t);
    const val = { year: String(d.getFullYear()), month: pad(d.getMonth() + 1), date: plain, start: ymd(v.start || v.t), shoot: v.shoot || '', kind: v.kind || '', camera: v.camera || '' };
    const parts = pattern.split('/').map((seg) => clean(seg.replace(/\{\s*([a-z]+)\s*\}/gi, (_, t) => clean(val[t.toLowerCase()]))));
    return safe(parts.filter(Boolean).join('/')) || plain;
  }

  const API = { propose, draftName, folder, check, clean, safe, ymd, TOKENS, defaults: O };
  root.LuminaIngestShoots = API;
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
})(typeof window !== 'undefined' ? window : globalThis);
