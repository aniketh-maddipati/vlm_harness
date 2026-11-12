// The ingest prototype's clock alignment on real ARWs, in headless Chromium: the page from
// design/handoff/lumina-ingest with lumina-core-v4.js, files handed to its picker.
//
//   node Tests/web/ingest-clocks.mjs        (fixtures: LUMINA_FIXTURE_ROOT, default ~/LuminaEvidence/fixtures)
//
// two-bodies: 2 × ILCE-7M3 (serials …1111 / …2222), 3 photos each, interleaved a minute apart, no shared frame.
// tz-jump: one ILCE-7M3, DSC00500–502 at 18:00, DSC00503–505 at 09:13 (clock set back), the same six frames as two-bodies.
// "shifted copy": two-bodies' A with its serial changed and every date moved −1 h 03 min, the same frames as A.
import fs from 'fs';
import os from 'os';
import path from 'path';
import { pw, deadline, ROOT } from './lib.mjs';

deadline('ingest-clocks', 120);
const FIX = process.env.LUMINA_FIXTURE_ROOT || path.join(os.homedir(), 'LuminaEvidence/fixtures');
const DIR = path.join(ROOT, 'design/handoff/lumina-ingest'), CORE = path.join(ROOT, 'design/handoff/lumina-cull/lumina-core-v4.js');
if (!fs.existsSync(path.join(FIX, 'two-bodies'))) { console.log('SKIP  no fixtures at ' + FIX); process.exit(0); }

const files = (d) => fs.readdirSync(path.join(FIX, d)).filter((f) => /\.arw$/i.test(f)).sort().map((f) => ({ name: f, buf: fs.readFileSync(path.join(FIX, d, f)) }));
// every EXIF date in the first 256 KB moved by `sec`, the body serial swapped (same length, so offsets hold)
function shifted(list, sec, fromSerial, toSerial, prefix) {
  return list.map(({ name, buf }) => {
    const b = Buffer.from(buf), head = b.subarray(0, 262144).toString('latin1');
    for (const m of head.matchAll(/(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)/g)) {
      const t = new Date(Date.UTC(+m[1], m[2] - 1, +m[3], +m[4], +m[5], +m[6]) + sec * 1000), p = (x) => String(x).padStart(2, '0');
      b.write(`${t.getUTCFullYear()}:${p(t.getUTCMonth() + 1)}:${p(t.getUTCDate())} ${p(t.getUTCHours())}:${p(t.getUTCMinutes())}:${p(t.getUTCSeconds())}`, m.index, 'latin1');
    }
    let i; while ((i = b.subarray(0, 262144).indexOf(fromSerial, 0, 'latin1')) >= 0) b.write(toSerial, i, 'latin1');
    return { name: prefix + name.replace(/^[A-Z]_/, ''), buf: b };
  });
}

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'lumina-ingest-clocks-'));
process.on('exit', () => fs.rmSync(TMP, { recursive: true, force: true }));
const browser = await pw.chromium.launch();
async function run(label, list) {
  const page = await browser.newPage(); page.on('console', (m) => process.env.V && console.log('   page:', m.text()));
  const errs = []; page.on('pageerror', (e) => errs.push(e.message));
  await page.route('http://ingest.test/**', (r) => {
    const f = decodeURIComponent(new URL(r.request().url()).pathname.slice(1));
    const p = f === 'lumina-core-v4.js' ? CORE : path.join(DIR, f);
    if (!fs.existsSync(p)) return r.fulfill({ status: 404 });
    r.fulfill({ body: fs.readFileSync(p), contentType: p.endsWith('.js') ? 'text/javascript' : 'text/html' });
  });
  await page.goto('http://ingest.test/' + encodeURIComponent('Lumina Ingest v1.html'));
  // over 50 MB Playwright wants paths: the files go to a temp folder (removed at the end)
  const d = fs.mkdtempSync(path.join(TMP, 'run-'));
  for (const f of list) fs.writeFileSync(path.join(d, f.name), f.buf);
  await page.setInputFiles('#pick', d);
  await page.waitForFunction(() => { const s = window.__ingest.state(); return s.total && s.done >= s.total && window.__ingest.clocks(); }, null, { timeout: 60000 });
  await page.evaluate(() => document.querySelector('#foot [data-more]').click());
  const r = await page.evaluate(() => ({ clocks: window.__ingest.clocks(), notes: document.querySelector('#notes').innerText, days: window.__ingest.days() }));
  r.page = page; r.errs = errs;
  console.log(`\n== ${label}`);
  for (const c of r.clocks.clocks) console.log(`   ${c.key.padEnd(28)} n ${c.n}  shift ${c.shift ? fmt(c.shift) : '0'}${c.tz ? ' tz ' + c.tz : ''}  matches ${c.matches}${c.small ? '  (found ' + fmt(c.small) + ', under 2 min)' : ''}${c.jump ? '  jump after ' + c.jump.after : ''}`);
  for (const e of r.clocks.edges) console.log(`   pairs ${e.a} ↔ ${e.b}: ${e.n} of ${e.of} agree, ${fmt(e.off)}`);
  console.log('   notes:', r.notes.split('\n').filter((l) => /shift|clock|moment|own clock/.test(l)).join(' | ') || '(no clock lines)');
  console.log('   days:', r.days.join(' | '));
  return r;
}
const fmt = (ms) => { const s = Math.round(Math.abs(ms) / 1000); return (ms < 0 ? '−' : '+') + Math.floor(s / 3600) + ':' + String(Math.floor(s % 3600 / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0'); };
let fails = 0; const check = (ok, what) => { console.log((ok ? '   ok   ' : '   FAIL ') + what); if (!ok) fails++; };
const by = (r, k) => r.clocks.clocks.find((c) => c.key === k);

const two = files('two-bodies'), tz = files('tz-jump');
const A = two.filter((f) => f.name.startsWith('A_'));

let r = await run('two-bodies', two);
check(r.clocks.clocks.every((c) => !c.shift), 'no shift (no frame shot on both)');
check(/not shifted: no matching moments/.test(r.notes), 'Details says so');
check(!r.errs.length, 'no page errors ' + r.errs.join('; '));

r = await run('tz-jump', tz);
check(r.clocks.clocks.length === 2 && r.clocks.clocks.every((c) => !c.shift), 'two clocks, nothing to match against, no shift');
check(/clock set back 8 h 49 min after DSC00502/.test(r.notes), 'Details names the jump');

r = await run('A + its copy 1 h 03 min slow (serial …3333)', [...A, ...shifted(A, -(3600 + 180), '1111111', '3333333', 'C_')]);
const c = by(r, 'ILCE-7M3 #3333');
check(c && Math.abs(c.shift - 3780e3) <= 1000 && c.matches === 3, 'copy shifted +1 h 03 min on 3 moments');
check(/ILCE-7M3 #3333 shifted \+1 h 03 min \(3 matching moments\) Undo/.test(r.notes), 'Details line + Undo');
const d0 = r.days.join('|');
await r.page.click('#notes [data-clk]'); await r.page.waitForTimeout(200);
const after = await r.page.evaluate(() => ({ off: window.__ingest.clocks().clocks.find((c) => c.key === 'ILCE-7M3 #3333').off, notes: document.querySelector('#notes').innerText }));
check(after.off && /left on its own clock \(\+1 h 03 min found, 3 matching moments\) Shift/.test(after.notes), 'Undo puts it back on its own clock, Shift offered');

r = await run('A copy 14 h fast: past midnight, a time zone', [...A, ...shifted(A, 14 * 3600 + 40, '1111111', '4444444', 'D_')]);
const dd = by(r, 'ILCE-7M3 #4444');
check(dd && Math.abs(dd.shift + (14 * 3600 + 40) * 1000) <= 1000 && dd.tz === -14, 'shifted −14 h 01 min, tz −14');
check(r.days.length === 1, 'one day after the shift: ' + r.days.join(' | '));
await r.page.click('#notes [data-clk]'); await r.page.waitForTimeout(800);
const undone = await r.page.evaluate(() => window.__ingest.days());
check(undone.length === 2, 'Undo: two days again: ' + undone.join(' | '));

r = await run('two-bodies + tz-jump together (the same six frames)', [...two, ...tz]);
const s1 = by(r, 'ILCE-7M3 from DSC00500'), s2 = by(r, 'ILCE-7M3 from DSC00503');
check(s1 && s1.tz === -8 && Math.abs(s1.shift + 7 * 3600e3 + 58 * 60e3 + 50e3) <= 60e3, 'tz-jump before the jump: −7 h 59 min onto …1111 (time zone 8 h)');
// how alike frames of the same place a minute or two apart are, against the threshold: across the two bodies
// (what could pair wrongly) and within one body (B's three frames are nearly one picture; never compared)
const cal = await r.page.evaluate(() => { const K = window.LuminaIngestClocks, A = [], B = [];
  for (const i of S.items.values()) if (i.sig && /^A_/.test(i.name)) A.push(i.sig); else if (i.sig && /^B_/.test(i.name)) B.push(i.sig);
  const x = [], w = []; for (const a of A) for (const b of B) x.push(K.dist(a, b));
  for (const L of [A, B]) for (let i = 0; i < L.length; i++) for (let j = i + 1; j < L.length; j++) w.push(K.dist(L[i], L[j]));
  return { across: Math.min(...x), within: Math.min(...w), near: K.defaults.near }; });
console.log(`   distances: across bodies ≥ ${cal.across.toFixed(3)}, within one body ≥ ${cal.within.toFixed(3)}; threshold ${cal.near}`);
check(cal.across > cal.near, 'different frames on two bodies stay above the threshold');
check(s2 && Math.abs(s2.shift - (49 * 60e3 + 10e3)) <= 60e3, 'tz-jump after the jump: +49 min onto …2222');

await browser.close();
console.log(fails ? `\nFAIL ${fails}` : '\nPASS');
process.exit(fails ? 1 : 0);
