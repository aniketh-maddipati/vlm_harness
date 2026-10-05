// Linux preview of the probe's app-vs-design check: runs a screens scenario in headless Chromium
// twice, as the prototype and through plumbing.js in parity mode, and compares every snapshot and
// state dump. Chromium is not WebKit: this finds differences the plumbing causes (a branch the
// page takes in app mode, state the plumbing changes), not the 0 px WebKit reference, which only
// `probe.sh reference` on the Mac can check.
//
//   node Tests/web/parity.mjs [Tests/probe/scenarios/screens-1440.json …] [--out DIR] [--selftest]
import fs from 'fs';
import path from 'path';
import { pw, ROOT, Bridge, open, LOGIC, deadline, warmStandIns } from './lib.mjs';

deadline('parity.mjs', 600);

const args = process.argv.slice(2);
const outI = args.indexOf('--out');
const OUT = outI >= 0 ? args[outI + 1] : path.join(process.env.LUMINA_HARNESS_TMP || '/tmp', 'lumina-parity');
const files = args.filter((a, i) => a.endsWith('.json') && args[i - 1] !== '--out');
const scenarios = files.length ? files : ['screens-1440.json', 'screens-1920.json'].map(f => path.join(ROOT, 'Tests/probe/scenarios', f));
fs.mkdirSync(OUT, { recursive: true });

const MODS = s => [s.cmd && 'Meta', s.shift && 'Shift', s.alt && 'Alt', s.ctrl && 'Control'].filter(Boolean);
const KEY = k => ({ ' ': 'Space', '?': 'Shift+Slash' }[k] || k);
const combo = s => [...MODS(s), KEY(s.k)].join('+');

// JSON-safe page state, as probe.js's __probe.state() makes it.
const STATE = `(() => { const l = (${LOGIC})(), seen = new WeakSet();
  return { state: JSON.parse(JSON.stringify(l.state, (k, v) => { if (typeof v === 'function') return undefined;
    if (v && typeof v === 'object') { if (v.nodeType || v instanceof Blob || ('current' in v && Object.keys(v).length === 1)) return undefined; if (seen.has(v)) return undefined; seen.add(v); } return v; })),
    order: l.data ? l.data.order.length : 0, real: !!l.real }; })()`;

// As the Mac probe's snapshots (probe.js meterMask): the header's working-files meter is hidden while
// a snapshot is taken; what it shows depends on the moment (a 1 s total, 360 ms fades).
const shot = async page => {
  await page.evaluate(css => { const el = document.createElement('style'); el.id = '__probe-meter-mask'; el.textContent = css; document.head.appendChild(el); }, '[data-lumina="cache-pill"] > * { visibility: hidden !important; }');
  try { return await page.screenshot(); } finally { await page.evaluate(() => { const el = document.getElementById('__probe-meter-mask'); if (el) el.remove(); }); }
};

async function run(browser, spec, app, dir) {
  fs.mkdirSync(dir, { recursive: true });
  const clockBase = spec.clock ? new Date(spec.clock).getTime() : undefined;
  const { ctx, page, errors } = await open(browser, app ? new Bridge() : null, { app, size: spec.size, scale: spec.scale || 1, clockBase, parity: !!(spec.app && spec.app.parity) || app, toured: !spec.tour });
  await page.evaluate(`window.__probe = { logic: ${LOGIC} }`);
  if (spec.storageWrites === false) await page.evaluate(() => { Storage.prototype.setItem = function () { throw new DOMException('storage writes off', 'QuotaExceededError'); }; });
  const out = { snaps: {}, states: {}, fails: [] };
  for (const [i, s] of (spec.steps || []).entries()) {
    try {
      switch (s.do) {
        case 'wait': await page.waitForTimeout(s.ms || 100); break;
        case 'key': for (let t = 0; t < (s.times || 1); t++) await page.keyboard.press(combo(s)); await page.waitForTimeout(s.settleMs ?? 60); break;
        case 'hold': await page.keyboard.down(KEY(s.k)); await page.waitForTimeout(s.ms || 400);
          if (s.snap) { const b = await shot(page); fs.writeFileSync(path.join(dir, s.snap + '.png'), b); out.snaps[s.snap] = b; }
          await page.keyboard.up(KEY(s.k)); await page.waitForTimeout(60); break;
        case 'snap': { const b = await shot(page); fs.writeFileSync(path.join(dir, s.name + '.png'), b); out.snaps[s.name] = b; break; }
        case 'state': { const st = await page.evaluate(STATE); fs.writeFileSync(path.join(dir, s.name + '.state.json'), JSON.stringify(st, null, 1)); out.states[s.name] = st; break; }
        case 'js': await page.evaluate(src => (new Function(src))(), s.src); break;
        case 'expect': { const got = await page.evaluate(src => (new Function(src))(), s.js);
          if ('equals' in s ? JSON.stringify(got) !== JSON.stringify(s.equals) : !got) out.fails.push(`step ${i} expect ${s.js} → ${JSON.stringify(got)}`); break; }
        default: out.fails.push(`step ${i}: ${s.do} not supported here`);
      }
    } catch (e) { out.fails.push(`step ${i} ${s.do}: ${e.message}`); }
  }
  out.fails.push(...errors.map(e => 'page error: ' + e));
  await ctx.close();
  return out;
}

// Differing pixels between two PNGs, counted in the browser.
async function diff(browser, a, b) {
  const p = await browser.newPage();
  const n = await p.evaluate(async ([a, b]) => {
    const img = async s => { const i = new Image(); i.src = 'data:image/png;base64,' + s; await i.decode(); return i; };
    const [x, y] = [await img(a), await img(b)];
    if (x.width !== y.width || x.height !== y.height) return -1;
    const c = document.createElement('canvas'); c.width = x.width; c.height = x.height; const g = c.getContext('2d');
    g.drawImage(x, 0, 0); const d1 = g.getImageData(0, 0, c.width, c.height).data; g.clearRect(0, 0, c.width, c.height); g.drawImage(y, 0, 0); const d2 = g.getImageData(0, 0, c.width, c.height).data;
    let n = 0; for (let i = 0; i < d1.length; i += 4) if (d1[i] !== d2[i] || d1[i + 1] !== d2[i + 1] || d1[i + 2] !== d2[i + 2]) n++; return n;
  }, [a.toString('base64'), b.toString('base64')]);
  await p.close();
  return n;
}

(async () => {
  const browser = await pw.chromium.launch();
  await warmStandIns(browser);   // both twins get every sample photo at once
  let bad = 0;
  for (const f of scenarios) {
    const spec = JSON.parse(fs.readFileSync(f, 'utf8')), name = path.basename(f, '.json');
    const proto = await run(browser, spec, false, path.join(OUT, name));
    const app = await run(browser, spec, true, path.join(OUT, name + '-app'));
    for (const [m, r] of [['design', proto], ['app', app]]) for (const x of r.fails) { bad++; console.log(`FAIL ${name} (${m}) ${x}`); }
    for (const k of Object.keys(proto.snaps)) {
      const n = app.snaps[k] ? (proto.snaps[k].equals(app.snaps[k]) ? 0 : await diff(browser, proto.snaps[k], app.snaps[k])) : -2;
      if (n) bad++;
      console.log((n ? 'DIFF ' : 'same ') + `${name}/${k}.png` + (n ? (n === -2 ? '  missing in app' : n === -1 ? '  size differs' : `  ${n} px`) : ''));
    }
    for (const k of Object.keys(proto.states)) {
      const a = JSON.stringify(proto.states[k]), b = JSON.stringify(app.states[k]);
      if (a !== b) {
        bad++;
        const sa = proto.states[k].state, sb = (app.states[k] || {}).state || {};
        const keys = [...new Set([...Object.keys(sa), ...Object.keys(sb)])].filter(x => JSON.stringify(sa[x]) !== JSON.stringify(sb[x]));
        console.log(`DIFF ${name}/${k}.state.json  keys: ${keys.join(', ')}`);
      } else console.log(`same ${name}/${k}.state.json`);
    }
  }
  await browser.close();
  console.log(bad ? bad + ' differences · evidence in ' + OUT : 'app matches design on every screen · ' + OUT);
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error(e); process.exit(2); });
