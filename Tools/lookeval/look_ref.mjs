// The page's own look maths (its LOOK-BEGIN … LOOK-END block), run on pixels from stdin, for the numpy port's parity check.
//   echo '{"rgb":[[r,g,b],…],"looks":[{…},…],"mode":0}' | node Tools/lookeval/look_ref.mjs
// Every look runs on every pixel through lkPreview(rgb, look, mode); out: {"out":[[[r,g,b],…] per look], "rows":…, "hues":…}.
import fs from 'node:fs';

const PAGE = new URL('../../design/handoff/lumina-skim/Lumina Skim v3.dc.html', import.meta.url);
const src = fs.readFileSync(PAGE, 'utf8');
const a = src.indexOf('// LOOK-BEGIN'), b = src.indexOf('// LOOK-END');
if (!(a > 0 && b > a)) throw new Error('the page has no look block');
const C = new Function('class Component {\n' + src.slice(a, b) + '\n}\nreturn Component;')();

const q = JSON.parse(fs.readFileSync(0, 'utf8'));
const out = (q.looks || []).map(L => q.rgb.map(p => C.lkPreview(p, L, q.mode || 0)));
process.stdout.write(JSON.stringify({out, rows: C.LK_ROWS, hues: C.LK_HUES, zones: C.LK_ZONES,
  ranges: Object.fromEntries((q.params || []).map(p => [p, C.lkRange(p)])),
  clean: (q.looks || []).map(L => Object.fromEntries(Object.entries(L).map(([p, v]) => [p, C.lkClean(p, v)])))}));
