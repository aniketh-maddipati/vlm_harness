// Skim's look reference (the page's LOOK-BEGIN … LOOK-END block, as Tests/web/skim-look.test.mjs runs it)
// applied to a raw float image, for Tools/parity/skim_parity.py. Measures only; never edits Skim.
//
//   node Tools/parity/skim_look.mjs <job.json>
//
// job.json: {"width": W, "height": H, "input": "in.f32", "looks": [{"look": {ev: 1, …}, "out": "o.f32"}, …]}
// Images are float32 display-referred RGB 0…1, row-major, interleaved (H × W × 3).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const PAGE = process.env.SKIM_PAGE || path.join(ROOT, 'design/handoff/lumina-skim/Lumina Skim v3.dc.html');
const src = fs.readFileSync(PAGE, 'utf8');
const a = src.indexOf('// LOOK-BEGIN'), b = src.indexOf('// LOOK-END');
if (!(a > 0 && b > a)) throw new Error('no LOOK-BEGIN … LOOK-END block in ' + PAGE);
const C = new Function('class Component {\n' + src.slice(a, b) + '\n}\nreturn Component;')();

const job = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const dir = path.dirname(process.argv[2]);
const at = p => path.isAbsolute(p) ? p : path.join(dir, p);
const buf = fs.readFileSync(at(job.input));
const input = new Float32Array(buf.buffer, buf.byteOffset, buf.byteLength / 4);
if (input.length !== job.width * job.height * 3) throw new Error('input size');
for (const it of job.looks) {
  const u = C.lkU(it.look), out = new Float32Array(input.length);
  for (let i = 0; i < input.length; i += 3) {
    const px = C.lkPx([input[i], input[i + 1], input[i + 2]], u);
    out[i] = px[0]; out[i + 1] = px[1]; out[i + 2] = px[2];
  }
  fs.writeFileSync(at(it.out), Buffer.from(out.buffer));
}
console.log(JSON.stringify({page: path.relative(ROOT, PAGE), looks: job.looks.length}));
