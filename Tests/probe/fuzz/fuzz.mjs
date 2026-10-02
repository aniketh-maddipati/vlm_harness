// Q4 hostile input (stress matrix 7). Seeded cases for the head and preview-range fuzzer, the page's
// own parser on each, and the drivers that restart a tool after the case that stopped it.
//
//   node Tests/probe/fuzz/fuzz.mjs ingest --seed 1 --n 10000 --out <dir>   heads + ranges: page parser + SetsIngest
//   node Tests/probe/fuzz/fuzz.mjs decode --seed 1 --n 3000 --raw 300 --out <dir>   ImageIO / CIRAWFilter in the sandboxed helper
//   node Tests/probe/fuzz/fuzz.mjs xmp --out <dir>                          the page's sidecar code on hostile XMP
//   node Tests/probe/fuzz/fuzz.mjs fixtures --out <dir>                     the hostile-* scenarios' folders
//
// Tools are built by run.sh (HOSTILE_BIN). Every mutated input lives under <dir> (a `.noindex` folder
// with `.metadata_never_index`, so Spotlight and Quick Look leave it alone); an input that crashed,
// hung or blew memory is kept in <dir>/findings. Nothing here is sent anywhere.
import { spawn, spawnSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../../..');
const Core = require(path.join(ROOT, 'Lumina/Sets/Web/lumina-core-v4.js'));
const BIN = process.env.HOSTILE_BIN || path.join(os.homedir(), 'LuminaEvidence/hostile/build');

const args = process.argv.slice(2), mode = args[0];
const opt = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? args[i + 1] : d; };
const SEED = +opt('seed', 1), OUT = path.resolve(opt('out', path.join(os.homedir(), 'LuminaEvidence/hostile/run.noindex')));
const noindex = d => { fs.mkdirSync(d, { recursive: true }); fs.writeFileSync(path.join(d, '.metadata_never_index'), ''); };

// SplitMix64 in BigInt, the same generator as Fuzz.Rand (so a seed names the same cases everywhere).
function rng(seed) {
  let s = (BigInt(seed) + 0x9E3779B97F4A7C15n) & 0xFFFFFFFFFFFFFFFFn;
  const next = () => { s = (s + 0x9E3779B97F4A7C15n) & 0xFFFFFFFFFFFFFFFFn; let z = s; z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & 0xFFFFFFFFFFFFFFFFn; z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & 0xFFFFFFFFFFFFFFFFn; return z ^ (z >> 31n); };
  const r = { int: n => n <= 0 ? 0 : Number(next() % BigInt(n)), pick: a => a[r.int(a.length)], byte: () => Number(next() & 0xFFn) };
  return r;
}
const hex = bytes => Buffer.from(bytes).toString('hex');
const u16 = v => hex([v & 0xFF, (v >> 8) & 0xFF]);
const u32 = v => { const b = Buffer.alloc(4); b.writeUInt32LE(v >>> 0); return b.toString('hex'); };
const mutate = (base, c) => {                                     // Fuzz.mutate, the same rule
  let d = c.trunc != null ? Buffer.from(base.subarray(0, Math.max(0, c.trunc))) : Buffer.from(base);
  for (const [at, hx] of c.patches || []) { const b = Buffer.from(hx, 'hex'); if (at + b.length > d.length) d = Buffer.concat([d, Buffer.alloc(at + b.length - d.length)]); b.copy(d, at); }
  return d;
};

// ——— the page's read of one file (plumbing's readOne up to the requests it makes)
function pageParse(input) {
  const head = new Uint8Array(input.buffer, input.byteOffset, Math.min(input.length, 262144));
  const t0 = process.hrtime.bigint();
  let m = null, err = null;
  try { m = Core.parseHead(head, input.length); } catch (e) { err = String(e && e.message || e); }
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  const req = m && m.preview && m.preview[0] + m.preview[1] <= input.length ? { o: m.preview[0], l: m.preview[1], ori: m.orient || 1, src: 'page' } : null;
  return { ms, err, unreadable: !err && !m, req, orient: m ? m.orient ?? null : null };
}

// ——— ingest: the cases
const IFD0 = 8, N0 = 5, EXIF = IFD0 + 2 + N0 * 12 + 4, N1 = 4;
const ent = (base, i) => base + 2 + i * 12;
function sofOf(buf, at, len) { for (let p = at + 2; p + 9 < at + len; p++) if (buf[p] === 0xFF && (buf[p + 1] === 0xC0 || buf[p + 1] === 0xC2)) return p; return -1; }
function markerOf(buf, at, len, m) { for (let p = at + 2; p + 4 < at + len; p++) if (buf[p] === 0xFF && buf[p + 1] === m) return p; return -1; }

function ingestCases(bases, n, seed) {
  const r = rng(seed), out = [];
  const add = c => { c.i = out.length; out.push(c); };
  // Every 4 KB boundary of every base, the file cut there (a card pulled mid-copy, a short write).
  for (const b of bases) for (let k = 0; k * 4096 <= b.size; k++) add({ cls: 'trunc', base: b.name, trunc: k * 4096 });
  const big = [0, -1, -4096, 1, 2 ** 31 - 1, 2 ** 31, 2 ** 32, 2 ** 32 + 7, 2 ** 53 - 1, 64 << 20, (64 << 20) + 1];
  const classes = ['range', 'range', 'range', 'orient', 'exif', 'exif', 'exif', 'flip', 'flip', 'jpeg', 'jpeg', 'jpeg', 'combo'];
  while (out.length < n) {
    const b = r.pick(bases), cls = r.pick(classes), c = { cls, base: b.name, patches: [], reqs: [] };
    const rangeReq = () => {
      const o = r.pick([...big, 4095, 4096, 131072, 262143, 262144, 262145, b.size - 1, b.size, b.size + 1, b.size + 1e6, b.jpegAt, b.jpegAt + 1, r.int(b.size)]);
      const l = r.pick([...big, 4096, b.jpegLen, b.jpegLen + 1, b.size, 262144 - (o % 262144), r.int(b.size)]);
      return { o, l, ori: r.pick([1, 3, 6, 8, 0, 9, 65535, -1]), src: 'direct' };
    };
    if (cls === 'range') { c.reqs.push(rangeReq()); if (r.int(2)) c.reqs.push(rangeReq()); }
    if (cls === 'orient' || cls === 'combo') {
      const v = r.pick([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 255, 256, 65535, r.int(65536)]);
      if (r.int(4)) c.patches.push([ent(IFD0, 1) + 8, u16(v)]);
      else c.patches.push([ent(IFD0, 1) + 2, u16(4)], [ent(IFD0, 1) + 8, u32(v * 65536 + r.int(65536))]);   // a LONG where a SHORT goes
    }
    if (cls === 'exif' || cls === 'combo') {
      const k = r.int(9);
      if (k === 0) c.patches.push([IFD0, u16(r.pick([0, 1, 1000, 1001, 65535, r.int(65536)]))]);                  // entry count
      if (k === 1) c.patches.push([EXIF, u16(r.pick([0, 1000, 1001, 65535]))]);
      if (k === 2) { const e = r.pick([ent(IFD0, r.int(N0)), ent(EXIF, r.int(N1))]); c.patches.push([e + 4, u32(r.pick([0, 1, 0xFFFF, 0x7FFFFFFF, 0xFFFFFFFF, r.int(2 ** 32)]))]); }  // value count
      if (k === 3) { const e = r.pick([ent(IFD0, r.int(N0)), ent(EXIF, r.int(N1))]); c.patches.push([e + 2, u16(r.pick([0, 1, 2, 3, 4, 5, 7, 10, 12, 13, 99, 65535]))]); }     // type
      if (k === 4) c.patches.push([ent(IFD0, N0) - 2 + 2, u32(r.pick([8, EXIF, 4, 0xFFFFFFFF, b.size, r.int(b.size)]))]);                                         // next IFD → loop / far
      if (k === 5) c.patches.push([ent(IFD0, 4) + 8, u32(r.pick([8, EXIF, 0, 0xFFFFFFFF, b.size - 2, r.int(b.size)]))]);                                          // Exif IFD → loop / far
      if (k === 6) c.patches.push([ent(IFD0, 2) + 8, u32(r.pick([0, 1, 8, b.size, b.size - 1, 0xFFFFFFFF, 262143, r.int(b.size)]))]);                           // preview offset
      if (k === 7) c.patches.push([ent(IFD0, 3) + 8, u32(r.pick([0, 1, 2, b.jpegLen + 1, b.size, 0x7FFFFFFF, 0xFFFFFFFF, 64 << 20, r.int(b.size)]))]);          // preview length
      if (k === 8) c.patches.push([0, r.pick(['4d4d', '4949', '0000', 'ffd8'])]);                                                                                  // byte order
    }
    if (cls === 'flip' || cls === 'combo') { const f = 1 + r.int(24); for (let j = 0; j < f; j++) c.patches.push([r.int(Math.min(b.size, 4096)), hex([r.byte()])]); }
    if (cls === 'jpeg') {
      const k = r.int(6), buf = b.data;
      if (k === 0) { const sof = sofOf(buf, b.jpegAt, b.jpegLen); if (sof > 0) { const [w, h] = r.pick([[0xFFFF, 0xFFFF], [0xFFDC, 0xFFDC], [0, 0], [1, 0xFFFF], [0xFFFF, 1], [16000, 16000], [r.int(65536), r.int(65536)]]); c.patches.push([sof + 5, hex([h >> 8, h & 0xFF, w >> 8, w & 0xFF])]); c.bomb = [w, h]; } }
      if (k === 1) { const f = 1 + r.int(40); for (let j = 0; j < f; j++) c.patches.push([b.jpegAt + r.int(b.jpegLen), hex([r.byte()])]); }
      if (k === 2) { const at = b.jpegAt + r.int(b.jpegLen - 512); c.patches.push([at, '00'.repeat(256 + r.int(256))]); }
      if (k === 3) { const p = markerOf(buf, b.jpegAt, b.jpegLen, 0xC4); if (p > 0) c.patches.push([p + 4, hex(Array.from({ length: 16 }, () => r.byte()))]); }   // Huffman counts
      if (k === 4) { const p = markerOf(buf, b.jpegAt, b.jpegLen, 0xDB); if (p > 0) c.patches.push([p + 5, '00'.repeat(64)]); }                                      // quantisation zero
      if (k === 5) c.trunc = b.jpegAt + 2 + r.int(b.jpegLen - 2);                                                                                                   // JPEG cut short
      if (k === 0 && !c.patches.length) c.patches.push([b.jpegAt + 2, 'ff']);
    }
    add(c);
  }
  return out;
}

// ——— a tool run, restarted after the case that stops it
// Lines on stdout: {event:"start", i} before a case, {event:"case", i, …} after it, and on a stop
// {event:"hang"|"memory", i|case}. A signal (crash) is found as a start with no case after it.
async function drive({ name, cmd, argsFor, cases, keep, onLine, input, timeoutMs }) {
  let from = 0, stops = [];
  const findings = path.join(OUT, 'findings'); noindex(findings);
  while (from < cases.length) {
    const started = Date.now();
    const p = spawn(cmd, argsFor(from), { stdio: ['pipe', 'pipe', 'pipe'] });
    p.stdin.on('error', () => {});                                  // the tool died with input still queued
    let buf = '', last = null, done = new Set(), ended = false, err = '', lastAt = Date.now(), hung = null;
    const watch = timeoutMs ? setInterval(() => { if (last != null && !done.has(last) && Date.now() - lastAt > timeoutMs) { p.kill('SIGKILL'); hung = last; } }, 250) : null;
    p.stdout.on('data', d => { buf += d; let k; while ((k = buf.indexOf('\n')) >= 0) { const line = buf.slice(0, k); buf = buf.slice(k + 1); if (!line) continue; let o; try { o = JSON.parse(line); } catch { continue; }
      if (o.event === 'start') { last = o.i; lastAt = Date.now(); if (input) input(p, o.i); }
      else if (o.event === 'case') { done.add(o.i); onLine(o); }
      else if (o.event === 'end') ended = true;
      else onLine(o); } });
    p.stderr.on('data', d => { err = (err + d).slice(-4000); });
    if (input) input(p, null, from);
    const code = await new Promise(res => p.on('close', (c, s) => res(s || c)));
    if (watch) clearInterval(watch);
    if (ended || (code === 0 && (last == null || done.has(last)))) break;
    if (last == null || (last < from)) throw new Error(`${name} stopped before its first case (${code}): ${err.slice(-800)}`);
    const at = last != null && !done.has(last) ? last : (last ?? from);
    const kind = hung != null ? 'hang' : code === 3 ? 'hang' : code === 4 ? 'memory' : 'crash';
    const ips = kind === 'crash' ? newestReport(name, started) : null;
    const saved = keep(at, findings);
    stops.push({ i: at, kind, code, ips, saved, stderr: err.split('\n').slice(-6).join('\n') });
    console.log(`${name}: case ${at} stopped the tool (${kind}, ${code})${ips ? ' · ' + ips : ''}`);
    if (ips) fs.copyFileSync(ips, path.join(findings, path.basename(ips)));
    from = at + 1;
  }
  return stops;
}

function newestReport(name, since) {
  const dir = path.join(os.homedir(), 'Library/Logs/DiagnosticReports');
  // The crash report is written a moment after the process dies.
  for (let t = 0; t < 40; t++) {
    const hits = (fs.existsSync(dir) ? fs.readdirSync(dir) : []).filter(f => f.startsWith(name) && f.endsWith('.ips')).map(f => path.join(dir, f)).filter(f => fs.statSync(f).mtimeMs >= since - 1000);
    if (hits.length) return hits.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)[0];
    spawnSync('sleep', ['0.25']);
  }
  return null;
}

async function ingest() {
  const n = +opt('n', 10000);
  noindex(OUT);
  const bdir = path.join(OUT, 'bases'), work = path.join(OUT, 'work');
  noindex(work);
  if (!fs.existsSync(path.join(bdir, 'bases.json'))) spawnSync(path.join(BIN, 'hostile-ingest'), ['forge', bdir], { stdio: 'inherit' });
  const bases = JSON.parse(fs.readFileSync(path.join(bdir, 'bases.json'))).map(b => ({ ...b, data: fs.readFileSync(path.join(bdir, b.name)) }));
  const byName = Object.fromEntries(bases.map(b => [b.name, b]));
  const cases = ingestCases(bases, n, SEED);
  // The page's parser on every case, and the request it makes.
  const page = { throws: 0, unreadable: 0, slow: 0, maxMs: 0, reqs: 0, throwSamples: [] };
  const lines = cases.map(c => {
    const input = mutate(byName[c.base].data, c), p = pageParse(input);
    if (p.err) { page.throws++; if (page.throwSamples.length < 5) page.throwSamples.push({ i: c.i, err: p.err }); }
    if (p.unreadable) page.unreadable++;
    if (p.ms > 5000) page.slow++;
    page.maxMs = Math.max(page.maxMs, p.ms);
    const reqs = [...(p.req ? [p.req] : []), ...(c.reqs || [])];
    if (p.req) page.reqs++;
    return JSON.stringify({ i: c.i, cls: c.cls, base: c.base, trunc: c.trunc ?? null, patches: c.patches, reqs, pageMs: +p.ms.toFixed(3), pageErr: p.err });
  });
  const casesFile = path.join(OUT, 'ingest-cases.jsonl');
  fs.writeFileSync(casesFile, lines.join('\n') + '\n');
  console.log(`ingest: ${cases.length} cases (seed ${SEED}) · page parser: ${page.throws} threw, ${page.unreadable} unreadable, ${page.reqs} with a preview request, slowest ${page.maxMs.toFixed(2)} ms`);
  // SetsIngest on every case.
  const results = fs.createWriteStream(path.join(OUT, 'ingest-results.jsonl'));
  const sum = { cases: 0, viol: 0, violSamples: [], status: {}, maxMs: 0, maxFpMB: 0, byClass: {} };
  const stops = await drive({ name: 'hostile-ingest', cmd: path.join(BIN, 'hostile-ingest'), cases, timeoutMs: 15000,
    argsFor: from => ['run', casesFile, bdir, work, '--from', String(from)],
    keep: (i, dir) => { const c = cases[i]; if (!c) return null; const f = path.join(dir, `ingest-C${String(i).padStart(6, '0')}.ARW`); fs.writeFileSync(f, mutate(byName[c.base].data, c)); return f; },
    onLine: o => {
      results.write(JSON.stringify(o) + '\n');
      if (o.event !== 'case') return;
      sum.cases++; sum.maxMs = Math.max(sum.maxMs, o.ms); sum.maxFpMB = Math.max(sum.maxFpMB, o.fpMB);
      const cls = cases[o.i]?.cls; sum.byClass[cls] = (sum.byClass[cls] || 0) + 1;
      for (const a of o.reqs || []) for (const k of ['preview', 'previewUpright', 'thumb']) if (a[k] != null) { const key = `${k}:${a[k]}`; sum.status[key] = (sum.status[key] || 0) + 1; }
      if (o.viol) { sum.viol++; if (sum.violSamples.length < 20) sum.violSamples.push({ i: o.i, cls, viol: o.viol }); }
    } });
  results.end();
  const report = { mode: 'ingest', seed: SEED, n: cases.length, page, native: sum, stops };
  fs.writeFileSync(path.join(OUT, 'ingest-summary.json'), JSON.stringify(report, null, 1));
  console.log(JSON.stringify({ page, native: { ...sum, violSamples: sum.violSamples.slice(0, 5) }, stops: stops.map(s => ({ i: s.i, kind: s.kind })) }, null, 1));
}

// ——— decode: mutated JPEGs into ImageIO, mutated ARWs into Core Image's RAW decoder
function decodeCases(jpegs, raws, n, nRaw, seed) {
  const r = rng(seed ^ 0x5eed), out = [];
  const jmut = (data, kind) => {
    const c = { kind, patches: [] }, k = r.int(7);
    const sof = sofOf(data, 0, data.length), dht = markerOf(data, 0, data.length, 0xC4), dqt = markerOf(data, 0, data.length, 0xDB), sos = markerOf(data, 0, data.length, 0xDA);
    if (k === 0 && sof > 0) { const [w, h] = r.pick([[0xFFFF, 0xFFFF], [0xFFDC, 0xFFDC], [0, 0], [1, 0xFFFF], [0xFFFF, 1], [30000, 30000], [r.int(65536), r.int(65536)]]); c.patches.push([sof + 5, hex([h >> 8, h & 0xFF, w >> 8, w & 0xFF])]); c.bomb = [w, h]; }
    else if (k === 1) { const f = 1 + r.int(64); for (let j = 0; j < f; j++) c.patches.push([r.int(data.length), hex([r.byte()])]); }
    else if (k === 2 && dht > 0) c.patches.push([dht + 4 + r.int(32), hex(Array.from({ length: 1 + r.int(17) }, () => r.byte()))]);
    else if (k === 3 && dqt > 0) c.patches.push([dqt + 5, r.pick(['00'.repeat(64), 'ff'.repeat(64)])]);
    else if (k === 4 && sof > 0) c.patches.push([sof + 9, hex([r.pick([0, 1, 3, 4, 255]), r.byte(), r.byte(), r.byte()])]);    // component count / ids / sampling
    else if (k === 5) c.trunc = r.int(data.length);
    else if (k === 6 && sos > 0) c.patches.push([sos + 2, hex(Array.from({ length: 10 }, () => r.byte()))]);                  // scan header
    else c.patches.push([r.int(data.length), hex([r.byte()])]);
    return c;
  };
  for (let i = 0; i < n; i++) { const j = r.pick(jpegs); out.push({ ...jmut(j.data, 'jpeg'), base: j.name }); }
  for (let i = 0; i < nRaw; i++) {
    const b = r.pick(raws), c = { kind: 'raw', base: b.name, patches: [] };
    const head = Math.min(b.data.length, 65536), k = r.int(4);
    if (k === 0) { const f = 1 + r.int(32); for (let j = 0; j < f; j++) c.patches.push([r.int(head), hex([r.byte()])]); }       // TIFF structure
    else if (k === 1) { const f = 1 + r.int(64); for (let j = 0; j < f; j++) c.patches.push([r.int(b.data.length), hex([r.byte()])]); }  // anywhere: sensor data, tables
    else if (k === 2) c.trunc = r.pick([4096, 65536, 262144, r.int(b.data.length)]);
    else { const at = r.int(b.data.length - 4096); c.patches.push([at, '00'.repeat(4096)]); }
    out.push(c);
  }
  return out.map((c, i) => ({ ...c, i }));
}

async function decode() {
  const n = +opt('n', 3000), nRaw = +opt('raw', 300);
  noindex(OUT);
  const bdir = path.join(OUT, 'bases');
  if (!fs.existsSync(path.join(bdir, 'bases.json'))) spawnSync(path.join(BIN, 'hostile-ingest'), ['forge', bdir], { stdio: 'inherit' });
  const jpegs = ['j0.jpg', 'j1.jpg', 'j2.jpg'].map(name => ({ name, data: fs.readFileSync(path.join(bdir, name)) }));
  // RAW bases: the synthetic ARWs (they reach only the decoder's container parsing), and, when
  // LUMINA_FIXTURE_ROOT has real ones, up to 2 of those: their mutations stay under OUT, never in the repo.
  const raws = ['b0-head.ARW', 'b1-camera.ARW'].map(name => ({ name, data: fs.readFileSync(path.join(bdir, name)), synthetic: true }));
  const src = process.env.LUMINA_FIXTURE_ROOT && path.join(process.env.LUMINA_FIXTURE_ROOT, 'src');
  if (src && fs.existsSync(src)) for (const f of fs.readdirSync(src).filter(f => /\.arw$/i.test(f) && !f.startsWith('._')).sort().slice(0, 2)) raws.push({ name: 'fixture:' + f, data: fs.readFileSync(path.join(src, f)), synthetic: false });
  const byName = Object.fromEntries([...jpegs, ...raws].map(b => [b.name, b]));
  const cases = decodeCases(jpegs, raws, n, nRaw, SEED);
  const results = fs.createWriteStream(path.join(OUT, 'decode-results.jsonl'));
  const sum = { jpeg: { cases: 0, decoded: 0, refused: 0, maxMs: 0, maxFpMB: 0 }, raw: { cases: 0, decoded: 0, refused: 0, maxMs: 0, maxFpMB: 0 }, sandbox: null, rawBases: raws.map(r => ({ name: r.name, synthetic: r.synthetic, bytes: r.data.length })) };
  const helper = path.join(BIN, 'hostile-decode');
  const stops = await drive({ name: 'hostile-decode', cmd: helper, cases, timeoutMs: 20000,
    argsFor: () => [],
    // The helper is sandboxed and reads nothing from disk: each case goes in on stdin.
    input: (p, started, from) => {
      if (started != null) return;
      (async () => {
        for (let i = from; i < cases.length; i++) {
          const c = cases[i], data = mutate(byName[c.base].data, c);
          const hdr = Buffer.from(JSON.stringify({ i, kind: c.kind, len: data.length }) + '\n');
          if (!p.stdin.write(Buffer.concat([hdr, data]))) await new Promise(res => p.stdin.once('drain', res));
        }
        p.stdin.end();
      })().catch(() => {});
    },
    keep: (i, dir) => { const c = cases[i]; if (!c) return null; const f = path.join(dir, `decode-${c.kind}-C${String(i).padStart(6, '0')}${c.kind === 'raw' ? '.ARW' : '.jpg'}`); fs.writeFileSync(f, mutate(byName[c.base].data, c)); return f; },
    onLine: o => {
      results.write(JSON.stringify(o) + '\n');
      if (o.event === 'sandbox') { sum.sandbox = o; return; }
      if (o.event !== 'case') return;
      const s = sum[o.kind]; if (!s) return;
      s.cases++; if (o.ok) s.decoded++; else s.refused++; s.maxMs = Math.max(s.maxMs, o.ms); s.maxFpMB = Math.max(s.maxFpMB, o.fpMB);
    } });
  results.end();
  const report = { mode: 'decode', seed: SEED, n: cases.length, summary: sum, stops: stops.map(s => ({ ...s, base: cases[s.i]?.base, synthetic: !String(cases[s.i]?.base).startsWith('fixture:') })) };
  fs.writeFileSync(path.join(OUT, 'decode-summary.json'), JSON.stringify(report, null, 1));
  console.log(JSON.stringify(report, null, 1));
}

// ——— xmp: the page's sidecar code (mergeXmp, hasDevelop) on hostile text
function hostileXmps() {
  const lr = '<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>\n<x:xmpmeta xmlns:x="adobe:ns:meta/">\n <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n  <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" xmp:Rating="2" crs:Exposure2012="+0.50"/>\n </rdf:RDF>\n</x:xmpmeta>\n<?xpacket end="w"?>\n';
  const script = '<script>window.__pwned=1</script><img src=x onerror="window.__pwned=1">';
  return {
    'lightroom': lr,
    'entities': '<?xml version="1.0"?><!DOCTYPE lolz [<!ENTITY lol "lol"><!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;"><!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;"><!ENTITY lol9 "&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;&lol3;">]>' + lr.replace('xmp:Rating="2"', 'xmp:Rating="&lol9;"'),
    'external-entity': '<?xml version="1.0"?><!DOCTYPE x [<!ENTITY xxe SYSTEM "file:///etc/hosts">]>' + lr.replace('xmp:Label', 'x').replace('xmp:Rating="2"', 'xmp:Rating="2" xmp:Label="&xxe;"'),
    'nested-10000': lr.replace('</rdf:RDF>', '<a>'.repeat(10000) + '</a>'.repeat(10000) + '</rdf:RDF>'),
    'script-in-fields': lr.replace('xmp:Rating="2"', `xmp:Rating="2" xmp:Label="${script.replace(/"/g, '&quot;')}" dc:title="${script.replace(/"/g, '&quot;')}"`) + `<!-- ${script} -->`,
    'rating-as-element': lr.replace(' xmp:Rating="2"', '').replace('</rdf:Description>', '').replace('/>\n </rdf:RDF>', '><xmp:Rating>' + script.replace(/</g, '&lt;') + '</xmp:Rating></rdf:Description>\n </rdf:RDF>'),
    'regex-bait': '<rdf:Description ' + 'xmp:Rating = "'.repeat(20000) + '>' + '<xmp:Rating>'.repeat(20000),
    'no-description': '<x:xmpmeta>' + 'x'.repeat(500000) + '</x:xmpmeta>',
    'binary': Buffer.from(Array.from({ length: 65536 }, (_, i) => (i * 131 + 7) & 0xFF)).toString('latin1'),
  };
}

function xmp() {
  noindex(OUT);
  const rows = [];
  for (const [name, text] of Object.entries(hostileXmps())) {
    const t0 = process.hrtime.bigint(); let merged = null, err = null, dev = null;
    try { dev = Core.hasDevelop(text); merged = Core.mergeXmp(text, 3, ''); } catch (e) { err = String(e.message || e); }
    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    rows.push({ name, bytes: Buffer.byteLength(text), ms: +ms.toFixed(2), err, hasDevelop: dev, grew: merged ? merged.length - text.length : null, ratingSet: merged ? /xmp:Rating="3"|<xmp:Rating>3</.test(merged) : null, entityExpanded: merged ? merged.includes('lollollol') || merged.includes('localhost') : null });
  }
  fs.writeFileSync(path.join(OUT, 'xmp-page.json'), JSON.stringify(rows, null, 1));
  console.table(rows);
}

// ——— fixtures for Tests/probe/scenarios/hostile-*.json (under $LUMINA_FIXTURE_ROOT)
function fixtures() {
  const root = path.resolve(opt('out', process.env.LUMINA_FIXTURE_ROOT || path.join(os.homedir(), 'LuminaEvidence/fixtures')));
  const bdir = path.join(os.homedir(), 'LuminaEvidence/hostile/bases.noindex');
  if (!fs.existsSync(path.join(bdir, 'bases.json'))) spawnSync(path.join(BIN, 'hostile-ingest'), ['forge', bdir], { stdio: 'inherit' });
  const arw = (date, ori = 1) => {
    const b = fs.readFileSync(path.join(bdir, 'b0-head.ARW')), d = Buffer.from(b);
    const dt = d.indexOf('2026:09:08 10:00:00'); d.write(date, dt, 'latin1'); d.writeUInt16LE(ori, IFD0 + 2 + 12 + 8); return d;
  };
  const fresh = d => { fs.rmSync(d, { recursive: true, force: true }); fs.mkdirSync(d, { recursive: true }); fs.writeFileSync(path.join(d, '.metadata_never_index'), ''); return d; };
  // Names: 255 bytes, emoji, RTL override, markup, a newline, NFD and NFC twins, a trailing dot.
  const names = fresh(path.join(root, 'hostile-names'));
  const long = 'L'.repeat(255 - '.ARW'.length) + '.ARW';
  const list = [
    ['DSC00001.ARW', 'plain'], [long, '255 bytes'], ['📷 ceremony 🔥.ARW', 'emoji'], ['‮gpj.ARW', 'RTL override'],
    ['<img src=x onerror=alert(1)>.ARW', 'markup'], ['line\nbreak.ARW', 'newline'], ['Café.ARW', 'NFD'], ['Café.ARW', 'NFC'],
    ['trailing.dot..ARW', 'dots'], ["quote'\"&amp;.ARW", 'quotes'], ['%2e%2e%2fescape.ARW', 'percent'], ['javascript:alert(1).ARW', 'scheme'],
  ];
  const made = [];
  list.forEach(([n, why], i) => { try { fs.writeFileSync(path.join(names, n), arw(`2026:09:08 10:${String(i).padStart(2, '0')}:00`)); made.push({ name: n, why, ok: true }); } catch (e) { made.push({ name: n, why, ok: false, err: e.code }); } });
  // NFD and NFC on APFS: the same name or two files? Recorded, the scenario reads it.
  made.push({ nfdNfcFiles: fs.readdirSync(names).filter(f => f.normalize('NFC') === 'Café.ARW').length });
  // A sidecar for the markup name, so its merge path runs too.
  fs.writeFileSync(path.join(names, '<img src=x onerror=alert(1)>.xmp'), hostileXmps()['lightroom']);
  // XMP: 500 MB sparse, not UTF-8, entities, 10,000 nested elements, script text; each beside a RAW.
  const x = fresh(path.join(root, 'hostile-xmp'));
  const X = hostileXmps();
  const xs = [['DSC00101', 'lightroom'], ['DSC00102', 'entities'], ['DSC00103', 'external-entity'], ['DSC00104', 'nested-10000'], ['DSC00105', 'script-in-fields'], ['DSC00106', 'rating-as-element']];
  xs.forEach(([s, k], i) => { fs.writeFileSync(path.join(x, s + '.ARW'), arw(`2026:09:08 11:0${i}:00`)); fs.writeFileSync(path.join(x, s + '.xmp'), X[k]); });
  fs.writeFileSync(path.join(x, 'DSC00107.ARW'), arw('2026:09:08 11:07:00'));
  fs.writeFileSync(path.join(x, 'DSC00107.xmp'), Buffer.concat([Buffer.from(X.lightroom.replace('xmp:Rating="2"', 'xmp:Rating="2" xmp:Label="Café"'), 'latin1'), Buffer.from([0xE9, 0xFF, 0xFE])]));   // Latin-1, not UTF-8
  fs.writeFileSync(path.join(x, 'DSC00108.ARW'), arw('2026:09:08 11:08:00'));
  const fd = fs.openSync(path.join(x, 'DSC00108.xmp'), 'w'); fs.ftruncateSync(fd, 500 * 1024 * 1024); fs.closeSync(fd);                                                // 500 MB, sparse
  fs.writeFileSync(path.join(root, 'hostile-fixtures.json'), JSON.stringify({ names: made, xmp: xs.map(([s, k]) => ({ stem: s, kind: k })).concat([{ stem: 'DSC00107', kind: 'latin-1' }, { stem: 'DSC00108', kind: '500 MB sparse' }]) }, null, 1));
  console.log(`fixtures in ${root}: hostile-names (${made.filter(m => m.ok).length} files), hostile-xmp (8 RAW + sidecar)`);
  console.log(made);
}

const modes = { ingest, decode, xmp, fixtures };
if (!modes[mode]) { console.error('usage: fuzz.mjs ingest|decode|xmp|fixtures [--seed N] [--n N] [--out DIR]'); process.exit(2); }
await modes[mode]();
