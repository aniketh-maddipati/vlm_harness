// Stills: every move has an inverse and no step is final.
//   = opens the large view at one per row, − closes it; Space on a stack and Esc leave the stack as it was;
//   a stack folds shut the way it opened; a new pass and start over are one ⌘Z each;
//   Esc backs out of Open and Edit; leaving Pick and coming back finds the large view where it was.
// Also checks the things taken out stay out: "0 automatic", Settings' tile size, Caps Lock, the ? sheet's social links.
//   node Tests/web/stills-reversible.mjs
import { pw, open, LOGIC, deadline } from './lib.mjs';

deadline('stills-reversible.mjs', 240);
const fails = [];
const ok = (c, m, extra) => { console.log((c ? 'ok   ' : 'FAIL ') + m + (extra !== undefined && !c ? '  ' + JSON.stringify(extra) : '')); if (!c) fails.push(m); };

const browser = await pw.chromium.launch();
const { ctx, page, errors } = await open(browser, null, { app: false, size: [1440, 900] });
await page.evaluate(`window.__l = ${LOGIC}`);
const L = (f, a) => page.evaluate(f, a);
const wait = ms => page.waitForTimeout(ms);
const key = async (k, ms = 120) => { await page.keyboard.press(k); await wait(ms); };
const st = () => L(() => { const l = __l(), s = l.state, c = l.curCell(); return { view: s.view, large: !!s.large, open: s.open || null, cur: s.cur, t: c && c.t, tsz: s.tsz, max: l.tszMax(), zl: s.zl || 1, passN: s.passN || 1, pass: s.pass || 1, seen: Object.keys(s.seen || {}).length, kept: l.kept().length, marks: Object.keys(s.marks).length }; });
await L(() => { __l().setView('cull'); __l().setState({ tour: null, glance: false, faq: false, prefsOn: false }); }); await wait(400);

// = at one per row opens the photo; − at Fit closes it; = and − zoom the photo in between
await L(() => __l().setState({ tsz: __l().tszMax() })); await wait(300);
const s0 = await st();
await key('Equal', 300);
let s = await st();
ok(s.large && s.cur === s0.cur, '= at one per row opens the photo', s);
await key('Equal', 300); s = await st();
ok(s.large && s.zl > 1.2, '= in the large view zooms in', s);
await key('Minus', 300); s = await st();
ok(s.large && s.zl === 1, '− zooms back out to Fit', s);
await key('Minus', 400); s = await st();
ok(!s.large && s.tsz === s.max && s.cur === s0.cur, '− at Fit goes back to the grid, one per row, same photo', s);
await key('Digit0', 300);

// Space on a closed stack opens it in the large view; Esc closes both
const gid = await L(() => { const l = __l(), c = l.layout().cells.find(x => x.t === 'stack'); l.setState({ cur: c.id, open: null }); return c.gid; }); await wait(300);
const sb = await st();
ok(sb.t === 'stack' && !sb.open, 'on a closed stack', sb);
await key('Space', 300); s = await st();
ok(s.large && s.open === gid, 'Space opens the stack in the large view', s);
await key('ArrowRight', 150);
await key('Escape', 400); s = await st();
ok(!s.large && !s.open && s.cur === sb.cur && s.t === 'stack', 'Esc closes the large view and the stack it opened, cursor back on the stack', [s, sb.cur]);

// a stack folds shut the way it unfolded
await key('ArrowDown', 400); s = await st();
ok(s.open === gid, '↓ opens the stack', s);
const ghosts = await page.evaluate(async () => { const seen = []; const mo = new MutationObserver(r => r.forEach(m => m.addedNodes.forEach(n => { if (n.nodeType === 1 && n.getAttribute('aria-hidden') === 'true' && n.style.position === 'fixed') seen.push(n.childElementCount); }))); mo.observe(document.body, { childList: true }); window.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', code: 'ArrowUp', bubbles: true })); await new Promise(r => setTimeout(r, 300)); mo.disconnect(); return { seen, left: document.querySelectorAll('body > div[aria-hidden="true"]').length }; });
s = await st();
ok(!s.open, '↑ closes it', s);
ok(ghosts.seen.length === 1 && ghosts.seen[0] > 0, 'closing plays the frames folding away', ghosts);
await wait(500);
ok(await L(() => [...document.body.children].filter(n => n.getAttribute('aria-hidden') === 'true' && n.style.position === 'fixed').length) === 0, 'and the fold leaves nothing behind');

// a new pass is one undo step, and so is start over (seen rows come back with it)
await L(() => { const l = __l(), C = l.layout().cells.filter(c => c.t === 'single').slice(0, 3); const m = {}; C.forEach(c => m[c.id] = 'keep'); l.commit(m, 'kept 3'); }); await wait(200);
await L(() => { const l = __l(); l.setState({ seen: { [l.data.R[0].id]: true } }); }); await wait(200);
const sp = await st();
await key('Shift+KeyP', 400); s = await st();
ok(s.passN === sp.passN + 1 && s.pass === 2 && s.seen === 0, '⇧P starts the next pass', s);
await key('Meta+KeyZ', 400); s = await st();
ok(s.passN === sp.passN && s.pass === sp.pass && s.seen === sp.seen && s.kept === sp.kept, '⌘Z undoes the new pass, seen rows and all', [s, sp]);
await key('Meta+Shift+KeyZ', 400); s = await st();
ok(s.passN === sp.passN + 1 && s.pass === 2, '⇧⌘Z redoes it', s);
await key('Meta+KeyZ', 400);
await L(() => __l().setState({ pass: 1 })); await wait(200);
const so = await st();
await key('Meta+Alt+Backspace', 150); await key('Meta+Alt+Backspace', 300); s = await st();
ok(s.marks === 0 && s.seen === 0, '⌥⌘⌫ twice clears every decision', s);
await key('Meta+KeyZ', 400); s = await st();
ok(s.marks === so.marks && s.seen === so.seen, '⌘Z brings the decisions and the seen rows back', [s, so]);

// Open: Esc goes back to the shoot
const cur = (await st()).cur;
await key('Meta+Digit1', 300); s = await st();
ok(s.view === 'import', '⌘1 goes to Open', s);
await key('Escape', 400); s = await st();
ok(s.view === 'cull' && s.cur === cur, 'Esc on Open goes back to Pick, same photo', s);

// leaving Pick from the large view and coming back finds the large view
await key('Space', 300);
s = await st(); ok(s.large, 'large view open', s);
const lc = s.cur;
await key('Meta+Digit4', 400); s = await st();
ok(s.view === 'export' && !s.large, '⌘4 goes to Save', s);
await key('Meta+Digit2', 500); s = await st();
ok(s.view === 'cull' && s.large && s.cur === lc, 'back in Pick, the large view is still open on the same photo', s);
await key('Escape', 300);

// Edit: Esc with nothing open goes back to where Edit was opened from
await key('Meta+Digit3', 1500); s = await st();
ok(s.view === 'edit', '⌘3 goes to Edit', s);
for (let i = 0; i < 4 && (await st()).view === 'edit'; i++) await key('Escape', 400);
s = await st();
ok(s.view === 'cull', 'Esc in Edit backs out to Pick once nothing is open', s);

// select-in: S orders untouched rows sharpest first and S again is time order; D finishes a row, ⌘Z or ⇧D opens it;
// [ and ] set the target; ⇧T shows the keepers alone to trim, ⇧T or Esc goes back. Each move is a 120 ms transform / opacity snap.
const sel = () => L(() => { const l = __l(), s = l.state, Lo = l.layout(); return { cur: s.cur, done: Object.keys(s.done || {}).length, ord: Object.keys(s.ord || {}).length, aim: l.aimN(), pass: s.pass || 1, trim: !!s.trim, kept: l.kept().length, marks: JSON.stringify(Object.entries(s.marks).sort()), cells: Lo.cells.map(c => c.id).join(','), rows: Lo.rows.map(r => r.cells.map(c => c.id).join(',')), touched: Lo.rows.map(r => r.r.ids.some(id => s.marks[id])), bars: Lo.rows.filter(r => r.bar).length, undo: s.undo.length, flips: l._flipN || 0, last: l._flipLast || null }; });
const anims = () => L(() => document.getAnimations().filter(a => a.effect && a.effect.target && a.effect.target.closest && a.effect.target.closest('[data-screen-label="1 Cull"]') && a.effect.target.matches('[data-tile],[data-lumina="row"]')).map(a => ({ props: [...new Set(a.effect.getKeyframes().flatMap(k => Object.keys(k)).filter(k => !['offset', 'easing', 'composite', 'computedOffset'].includes(k)))], ms: a.effect.getTiming().duration })));
await L(() => { const l = __l(); l.setState({ pass: 1, trim: false, open: null, large: false, done: {}, ord: {}, aim: 0, tsz: 2, cur: l.data.order[0] }); }); await wait(400);
const a0 = await sel();
await page.keyboard.press('KeyS'); const sAn = await anims(); await wait(250); s = await sel();
ok(s.ord > 0 && s.cells !== a0.cells && s.cells.split(',').sort().join() === a0.cells.split(',').sort().join(), 'S puts the rows sharpest first: same photos, another order', [s.ord, s.cells === a0.cells]);
ok(s.marks === a0.marks && s.cur === a0.cur && s.undo === a0.undo, 'S decides nothing and keeps the cursor on its photo', s);
ok(a0.touched.some(Boolean) && a0.touched.every((t, i) => !t || s.rows[i] === a0.rows[i]), 'rows with a decision in them stay in time order', a0.touched);
ok(sAn.length > 0 && sAn.every(a => a.ms <= 130 && a.props.every(p => p === 'transform' || p === 'opacity')), 'the reorder is a snap of at most 130 ms on transform and opacity only', sAn.slice(0, 3));
const chips = await L(() => [...document.querySelectorAll('[data-lumina="tile-chips"]')].map(n => n.textContent).join('|'));
ok(/^(soft|motion|blown|peak|\|)*$/.test(chips), 'ranked tiles carry only soft / motion / blown / peak chips', chips);
await page.keyboard.press('KeyS'); const sAn2 = await anims(); await wait(250); s = await sel();
ok(s.ord === 0 && s.cells === a0.cells && s.cur === a0.cur, 'S again is time order, as it was', s.ord);
ok(sAn2.length === sAn.length, 'and plays the same number of moves back', [sAn.length, sAn2.length]);

// D on a row with a keeper and on one with none; one ⌘Z each; ⇧D opens the last one
for (const withKeep of [true, false]) {
  const name = withKeep ? 'a row with a keeper' : 'a row with no keeper';
  const found = await L(w => { const l = __l(), s = l.state, Lo = l.layout(); const row = Lo.rows.find(r => r.cells.length && r.r.ids.some(id => s.marks[id] === 'keep') === w && Lo.rows.some(x => x !== r && x.cells.length)); if (!row) return false; l.setState({ cur: row.cells[0].id, open: null }); return true; }, withKeep); await wait(250);
  if (!found) { ok(false, 'found ' + name); continue; }
  const b0 = await sel();
  await page.keyboard.press('KeyD'); const dAn = await anims(); await wait(250); s = await sel();
  ok(s.done === b0.done + 1 && s.bars === b0.bars + 1 && s.marks === b0.marks && s.undo === b0.undo + 1, 'D finishes ' + name + ': it folds, nothing in it is decided, one undo step', s);
  ok(s.cur !== b0.cur && s.cells.split(',').includes(s.cur), 'and the cursor is on the next row', [s.cur, b0.cur]);
  ok(dAn.length > 0 && dAn.every(a => a.ms <= 130 && a.props.every(p => p === 'transform' || p === 'opacity')), 'the fold is a snap on transform and opacity', dAn.slice(0, 3));
  await key('Meta+KeyZ', 250); s = await sel();
  ok(s.done === b0.done && s.cells === b0.cells && s.cur === b0.cur && s.marks === b0.marks, '⌘Z opens the row again, cursor back where it was', [s.done, s.cur, b0.cur]);
  await key('Meta+Shift+KeyZ', 250); s = await sel();
  ok(s.done === b0.done + 1, '⇧⌘Z finishes it again', s.done);
  await key('Shift+KeyD', 250); s = await sel();
  ok(s.done === b0.done && s.cells === b0.cells && s.marks === b0.marks, '⇧D opens the finished row', [s.done, s.cells === b0.cells]);
}
ok(await L(() => document.querySelectorAll('[data-lumina-flip]').length) === 0, 'the fold leaves no copies behind');

// keys pressed while a snap is still playing apply in order
const q0 = await sel();
for (const k of ['KeyD', 'KeyD', 'KeyS', 'Meta+KeyZ', 'Meta+KeyZ', 'KeyS']) await page.keyboard.press(k);
await wait(400); s = await sel();
ok(s.done === q0.done && s.ord === 0 && s.cells === q0.cells && s.marks === q0.marks, 'D D S ⌘Z ⌘Z S with no pause ends where it began', [s.done, s.ord, s.cells === q0.cells]);

// the target, and the trim view
await key('BracketRight'); s = await sel(); ok(s.aim === 21, '] raises the target', s.aim);
await key('BracketLeft'); s = await sel(); ok(s.aim === 20, '[ lowers it back', s.aim);
await L(() => __l().setState({ aim: 2 })); await wait(150);
const t0 = await sel();
ok(t0.kept > 2, 'more kept than the target', t0.kept);
const lead = await L(() => document.body.innerText.split('\n').filter(x => /\d+ \/ \d+/.test(x)).join(' | '));
ok(new RegExp('\\b' + t0.kept + ' / 2\\b').test(lead), 'kept / target is on screen', lead);
await key('Shift+KeyT', 300); s = await sel();
ok(s.pass === 2 && s.trim && s.cells.split(',').length === t0.kept && s.marks === t0.marks, '⇧T shows the keepers alone', s);
const t1 = s;
await page.keyboard.press('KeyR'); const rAn = await anims(); await wait(250); s = await sel();
ok(s.kept === t0.kept - 1 && s.cells.split(',').length === t0.kept - 1, 'R drops one', s.kept);
ok(rAn.every(a => a.ms <= 130 && a.props.every(p => p === 'transform' || p === 'opacity')), 'the others close up on transform and opacity', rAn.slice(0, 3));
await key('Meta+KeyZ', 250); s = await sel();
ok(s.kept === t0.kept && s.cells === t1.cells && s.trim, '⌘Z brings it back in place', [s.kept, s.cells, t1.cells]);
await key('Shift+KeyT', 300); s = await sel();
ok(s.pass === 1 && !s.trim && s.cells === t0.cells && s.cur === t0.cur && s.marks === t0.marks, '⇧T again: all photos, cursor back where it was', [s.pass, s.cur, t0.cur]);
await key('Shift+KeyT', 300); await key('Escape', 300); s = await sel();
ok(s.pass === 1 && !s.trim && s.cells === t0.cells, 'Esc leaves the trim view too', s.pass);

// frames while finishing and reopening rows (reported, not gated: headless Chromium, the sample shoot)
const fr = await page.evaluate(async () => { const gaps = []; let last = performance.now(), on = true; const tick = t => { gaps.push(t - last); last = t; if (on) requestAnimationFrame(tick); }; requestAnimationFrame(tick);
  const press = (code, o = {}) => window.dispatchEvent(new KeyboardEvent('keydown', { key: o.key || code.replace('Key', '').toLowerCase(), code, bubbles: true, cancelable: true, ...o }));
  for (let i = 0; i < 12; i++) { press('KeyD'); await new Promise(r => setTimeout(r, 70)); press('KeyZ', { key: 'z', metaKey: true }); await new Promise(r => setTimeout(r, 70)); }
  for (let i = 0; i < 6; i++) { press('KeyS'); await new Promise(r => setTimeout(r, 70)); }
  await new Promise(r => setTimeout(r, 200)); on = false; const g = gaps.slice(2).sort((a, b) => a - b); return { frames: g.length, median: +g[g.length >> 1].toFixed(1), p95: +g[Math.floor(g.length * 0.95)].toFixed(1), max: +g[g.length - 1].toFixed(1), over25: g.filter(x => x > 25).length, over34: g.filter(x => x > 34).length }; });
console.log('note frames during 12 × (D, ⌘Z) + 6 × S at 70 ms: ' + JSON.stringify(fr));
s = await sel();
ok(s.done === 0 && s.ord === 0 && s.marks === t0.marks, 'after the storm: no row finished, time order, decisions untouched', [s.done, s.ord]);
await L(() => __l().setState({ aim: 0, done: {}, ord: {}, tsz: 5 })); await wait(200);

// taken out
await L(() => { const l = __l(); l.setState({ cur: l.data.order[0] }); }); await key('Enter', 300);
const foot = await L(() => (document.querySelector('[data-lumina="live"]') || {}).textContent || '');
ok(foot && !/automatic|picks only/.test(foot), 'footer count has no "0 automatic" or "⇧P picks only"', foot);
await L(() => __l().setState({ prefsOn: true })); await wait(300);
const prefs = await L(() => (document.querySelector('[data-lumina="settings"]') || document.body).textContent);
ok(!/Tile size/.test(prefs), 'Settings has no tile size', prefs.slice(0, 200));
await L(() => __l().setState({ prefsOn: false, glance: true })); await wait(300);
const sheet = await L(() => document.body.textContent);
ok(!/LinkedIn|@aniketh745/.test(sheet) && !/Caps Lock/.test(sheet), 'the ? sheet has no social links and no Caps Lock line');
await L(() => __l().setState({ glance: false }));
await page.keyboard.down('CapsLock'); await page.keyboard.up('CapsLock');
ok(await L(() => __l().adv()), 'Caps Lock does not stop auto-advance');

ok(!errors.length, 'no page errors', errors);
await ctx.close(); await browser.close();
console.log(fails.length ? fails.length + ' failed' : 'all ok');
process.exit(fails.length ? 1 : 0);
