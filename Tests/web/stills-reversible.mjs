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
