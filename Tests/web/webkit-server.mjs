// The native side of the WebKit sandbox (Tests/web/webkit.py): serves the page as SetsSchemeHandler
// serves it (page files, vendor, /media/head and /media/preview), answers the page's native calls
// with the same stand-in for SetsBridge the Chromium harness uses, and gives the in-page tests a
// control endpoint (make a shoot, pick a folder, pull a card, read a file).
//
//   node Tests/web/webkit-server.mjs <port> <workdir>
import http from 'http';
import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';
import { pw, WEB, VENDOR, Bridge, makeJpegs, makeShoot, makeBigJpegs, makeBigShoot, strictQuery } from './lib.mjs';

const port = +(process.argv[2] || 8765), work = path.resolve(process.argv[3] || '/tmp/lumina-webkit');
fs.mkdirSync(work, { recursive: true });
const ORIGIN = `http://127.0.0.1:${port}`;
let bridge = new Bridge();

// Synthetic ARWs need JPEG previews: made once with Chromium's canvas, then reused.
const jpegDir = path.join(work, 'jpegs');
if (!fs.existsSync(jpegDir) || fs.readdirSync(jpegDir).length < 12) {
  fs.mkdirSync(jpegDir, { recursive: true });
  const b = await pw.chromium.launch();
  (await makeJpegs(b, 12)).forEach((j, i) => fs.writeFileSync(path.join(jpegDir, i + '.jpg'), j));
  await b.close();
}
const jpegs = fs.readdirSync(jpegDir).sort((a, b) => parseInt(a) - parseInt(b)).map(f => fs.readFileSync(path.join(jpegDir, f)));

// SetsIngest.thumb's stand-in: one GdkPixbuf helper process, requests answered in order.
const helper = spawn('/usr/bin/python3.12', [path.join(path.dirname(new URL(import.meta.url).pathname), 'thumb-helper.py')], { stdio: ['pipe', 'pipe', 'inherit'] });
const waiting = []; let pending = Buffer.alloc(0);
helper.stdout.on('data', d => {
  pending = Buffer.concat([pending, d]);
  while (pending.length >= 8) {
    const n = Number(pending.readBigUInt64BE(0)); if (pending.length < 8 + n) break;
    const b = pending.subarray(8, 8 + n); pending = pending.subarray(8 + n); waiting.shift()(n ? Buffer.from(b) : null);
  }
});
const thumb = (f, q) => new Promise(res => { waiting.push(res); helper.stdin.write(JSON.stringify({ f, o: q.o, l: q.l, ori: q.ori || 1 }) + '\n'); });

const body = req => new Promise(res => { let d = ''; req.on('data', c => d += c); req.on('end', () => res(d)); });
const json = (res, v, code = 200) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(v === undefined ? null : v)); };

const ctl = async (op, a) => {
  switch (op) {
    case 'reset': bridge = new Bridge(); return true;
    case 'resources': return Object.fromEntries(Object.entries(VENDOR).map(([k, v]) => [k, v.replace('http://lumina.test', ORIGIN)]));
    case 'shoot': {   // { name, others: [], sidecars: {} } → folder path
      const dir = path.join(work, 'shoots', a.name);
      makeShoot(dir, jpegs, { others: a.others || [], sidecars: a.sidecars || {} });
      return dir;
    }
    case 'bigshoot': {   // { name, n } → folder of n camera-sized synthetic ARWs
      const bj = path.join(work, 'jpegs-big');
      if (!fs.existsSync(bj) || fs.readdirSync(bj).length < 24) {
        fs.mkdirSync(bj, { recursive: true });
        const b = await pw.chromium.launch();
        (await makeBigJpegs(b, 24)).forEach((j, i) => fs.writeFileSync(path.join(bj, i + '.jpg'), j));
        await b.close();
      }
      const big = fs.readdirSync(bj).sort((a, b) => parseInt(a) - parseInt(b)).map(f => fs.readFileSync(path.join(bj, f)));
      const dir = path.join(work, 'shoots', a.name);
      makeBigShoot(dir, big, a.n || 400);
      return dir;
    }
    case 'folder': { const dir = path.join(work, 'shoots', a.name); fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true }); for (const n of a.files || []) fs.writeFileSync(path.join(dir, n), 'x'); return dir; }
    case 'pick': bridge.pending = a.path; return true;
    case 'deny': bridge.denied = a.path || null; return true;
    case 'gone': if (a.on) bridge.gone.add(a.name); else bridge.gone.delete(a.name); return true;
    case 'ls': return fs.existsSync(a.path) ? fs.readdirSync(a.path).sort() : null;
    case 'read': return fs.existsSync(a.path) ? fs.readFileSync(a.path, 'utf8') : null;
    case 'state': return { calls: bridge.calls, sessions: bridge.sessions, index: bridge.index, prefs: bridge.prefs, revealed: bridge.revealed, kicked: bridge.kicked || 0, readyMsg: bridge.readyMsg || null, canvas: bridge.canvas, renders: bridge.renders, bodies: bridge.bodies || null };
    case 'takeKick': { const k = bridge.kicked || 0; bridge.kicked = 0; return k; }
    default: throw new Error('unknown ctl ' + op);
  }
};

http.createServer(async (req, res) => {
  try {
    const u = new URL(req.url, ORIGIN), p = decodeURIComponent(u.pathname.slice(1));
    if (req.method === 'POST' && p === 'native') return json(res, await bridge.handle(JSON.parse(await body(req))));
    if (req.method === 'POST' && p === 'ctl') { const m = JSON.parse(await body(req)); return json(res, await ctl(m.op, m)); }
    if (p.startsWith('render/')) {
      // The Edit preview (image path): what lumina://render answers.
      const rel = p.slice(7), q = strictQuery(u);
      if (!bridge.resolve(rel)) { res.writeHead(404); return res.end('not in an opened folder'); }
      const r = await bridge.render(rel, q);
      res.writeHead(r.status, { 'content-type': r.contentType || 'text/plain' }); return res.end(r.body);
    }
    if (p.startsWith('media/')) {
      const q = strictQuery(u), f = bridge.resolve(q.p || ''), [n] = (q.p || '').split('/');
      if (bridge.gone.has(n)) { res.writeHead(410); return res.end('card removed'); }
      if (!f || !fs.existsSync(f)) { res.writeHead(404); return res.end('not in an opened folder'); }
      if (p === 'media/thumb') {
        const t = await thumb(f, q);
        if (!t) { res.writeHead(422); return res.end('preview doesn\'t decode'); }
        res.writeHead(200, { 'content-type': 'image/jpeg' }); return res.end(t);
      }
      if (p !== 'media/head' && p !== 'media/preview') { res.writeHead(404); return res.end('unknown media'); }
      const b = fs.readFileSync(f), out = p === 'media/head' ? b.subarray(0, 262144) : b.subarray(+q.o, +q.o + +q.l);
      res.writeHead(200, { 'content-type': p === 'media/head' ? 'application/octet-stream' : 'image/jpeg' }); return res.end(out);
    }
    const file = p.startsWith('vendor/') ? path.join(WEB, p.slice(7)) : path.join(WEB, p);
    if (!p || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'content-type': file.endsWith('.html') ? 'text/html; charset=utf-8' : 'text/javascript; charset=utf-8' });
    res.end(fs.readFileSync(file));
  } catch (e) { json(res, { error: String(e) }, 500); }
}).listen(port, '127.0.0.1', () => console.log('ready ' + ORIGIN));
process.on('SIGTERM', () => { helper.kill(); process.exit(0); });
