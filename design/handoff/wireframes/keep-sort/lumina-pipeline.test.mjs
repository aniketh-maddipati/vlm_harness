// node lumina-pipeline.test.mjs — Rec.709 maths, the .cube, the FCPXML stringout and the package.
import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, writeFileSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import P from './lumina-pipeline.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const near = (a, b, tol, msg) => assert.ok(Math.abs(a - b) <= tol, (msg || '') + ` ${a} vs ${b} (±${tol})`);
const has = cmd => { try { execFileSync('sh', ['-c', 'command -v ' + cmd]); return true; } catch { return false; } };

// ---------- S-Log3 curve: Sony's published reference points ----------
test('S-Log3: 18% grey ↔ code value 420 (0.41)', () => {
  near(P.linearToSlog3Cv(0.18) * 1023, 420, 1e-9); near(P.slog3CvToLinear(420 / 1023), 0.18, 1e-12);
});
test('S-Log3: 0% black ↔ 95 (0.093), 90% white ↔ 598 (0.584)', () => {
  near(P.linearToSlog3Cv(0) * 1023, 95, 1e-9); near(P.linearToSlog3Cv(0.9) * 1023, 598, 0.2);
  near(P.slog3CvToLinear(95 / 1023), 0, 1e-12);
});
test('S-Log3: curve is continuous at the break and round-trips', () => {
  const b = 171.2102946929 / 1023; near(P.slog3CvToLinear(b - 1e-9), P.slog3CvToLinear(b + 1e-9), 1e-7);
  for (const x of [-0.01, 0, 0.005, 0.01125, 0.18, 0.9, 5, 30]) near(P.slog3CvToLinear(P.linearToSlog3Cv(x)), x, 1e-9, 'x=' + x);
});
test('video range: legal 0–1 ↔ cv/1023', () => { near(P.legalToCv(0), 64 / 1023, 1e-12); near(P.legalToCv(1), 940 / 1023, 1e-12); near(P.cvToLegal(P.legalToCv(0.37)), 0.37, 1e-12); });

// ---------- gamut ----------
test('S-Gamut3.Cine → Rec.709 matrix matches Sony\'s published one, white preserved', () => {
  const sony = [[1.6269474097, -0.5401385389, -0.0868088708], [-0.1785155271, 1.4179409275, -0.2394254004], [-0.0444361150, -0.1959199662, 1.2403560812]];
  P.SG3C_TO_709.forEach((r, i) => { r.forEach((v, j) => near(v, sony[i][j], 5e-5, `m[${i}][${j}]`)); near(r[0] + r[1] + r[2], 1, 1e-9); });
});

// ---------- Rec.709 out ----------
test('Rec.709 OETF: 0.018 → 0.081, 1 → 1, inverse round-trips', () => {
  near(P.oetf709(0.018), 0.081, 1e-3); near(P.oetf709(0.18), 0.409, 1e-3); near(P.oetf709(1), 1, 1e-12);
  for (const v of [0, 0.05, 0.081, 0.4, 1]) near(P.oetf709(P.oetf709Inv(v)), v, 1e-12);
});
test('slog3ToRec709: reference points (neutral axis = Final Cut Sony LUT fit, SL3T)', () => {
  const grey = P.slog3ToRec709([420 / 1023, 420 / 1023, 420 / 1023], {input:'cv'});
  grey.forEach(v => near(v, 0.4879, 5e-4, '18% grey'));
  const black = P.slog3ToRec709([95 / 1023, 95 / 1023, 95 / 1023], {input:'cv'});
  black.forEach(v => near(v, 0.0256, 5e-4, '0% black'));
  const white = P.slog3ToRec709([598 / 1023, 598 / 1023, 598 / 1023], {input:'cv'});
  white.forEach(v => near(v, 0.8985, 5e-4, '90% white'));
  assert.deepEqual(P.slog3ToRec709([1, 1, 1]), [1, 1, 1], 'top of range clips to 1');
  assert.deepEqual(P.slog3ToRec709([0, 0, 0]), [0, 0, 0], 'bottom of range is 0');
  // legal-range input is the default: grey at (420-64)/876
  near(P.slog3ToRec709([(420 - 64) / 876, (420 - 64) / 876, (420 - 64) / 876])[1], 0.4879, 5e-4);
});
test('slog3ToRec709: monotonic on the neutral axis, greys stay neutral, saturated colours stay in 0–1', () => {
  let prev = -1; for (let i = 0; i <= 200; i++) { const v = i / 200, o = P.slog3ToRec709([v, v, v]); assert.ok(o[1] >= prev - 1e-12); prev = o[1]; near(o[0], o[1], 1e-9); near(o[2], o[1], 1e-9); }
  for (const c of [[0.8, 0.1, 0.1], [0.1, 0.8, 0.1], [0.1, 0.1, 0.8]]) P.slog3ToRec709(c).forEach(v => assert.ok(v >= 0 && v <= 1));
  const red = P.slog3ToRec709([0.6, 0.35, 0.35]); assert.ok(red[0] > red[1] && red[0] > red[2], 'a reddish log pixel stays red');
});

// ---------- .cube ----------
test('buildCube: header, size³ rows, red fastest, values in 0–1', () => {
  for (const n of [2, 17, 33]) {
    const t = P.buildCube(n), L = t.trim().split('\n'), rows = L.filter(l => /^[\d.]+ [\d.]+ [\d.]+$/.test(l));
    assert.ok(L.includes('LUT_3D_SIZE ' + n)); assert.ok(L.includes('DOMAIN_MIN 0.0 0.0 0.0')); assert.ok(L.includes('DOMAIN_MAX 1.0 1.0 1.0'));
    assert.equal(rows.length, n ** 3);
    rows.forEach(r => r.split(' ').forEach(v => assert.ok(+v >= 0 && +v <= 1 && /^\d\.\d{6}$/.test(v))));
    assert.deepEqual(rows[0].split(' ').map(Number), P.slog3ToRec709([0, 0, 0]).map(v => +v.toFixed(6)));
    assert.deepEqual(rows[1].split(' ').map(Number), P.slog3ToRec709([1 / (n - 1), 0, 0]).map(v => +v.toFixed(6)), 'second row steps red');
    assert.deepEqual(rows[n].split(' ').map(Number), P.slog3ToRec709([0, 1 / (n - 1), 0]).map(v => +v.toFixed(6)), 'row n steps green');
  }
  assert.ok(P.buildCube().includes('LUT_3D_SIZE 33'));
});

// ---------- gamma ----------
test('gammaOf: Sony sidecar, profile, wireframe flags', () => {
  const xml = '<NonRealTimeMeta><AcquisitionRecord><Group name="CameraUnitMetadataSet"><Item name="CaptureGammaEquation" value="s-log3-cine"/><Item name="CaptureColorPrimaries" value="S-Gamut3.Cine"/></Group></AcquisitionRecord></NonRealTimeMeta>';
  assert.deepEqual(P.readSonyXml(xml), {captureGammaEquation:'s-log3-cine', captureColorPrimaries:'S-Gamut3.Cine'});
  let g = P.gammaOf({name:'C4815', sidecar:xml}); assert.equal(g.kind, 'log'); assert.equal(g.gamma, 'S-Log3'); assert.equal(g.primaries, 'S-Gamut3.Cine'); assert.equal(g.source, 'sidecar'); assert.equal(g.fcpLut, P.FCP_SONY_SLOG3);
  g = P.gammaOf({sidecar:'<x captureGammaEquation="rec709"/>'}); assert.equal(g.kind, '709'); assert.equal(g.fcpLut, null);
  g = P.gammaOf({sidecar:{captureGammaEquation:'s-log2', captureColorPrimaries:'s-gamut3'}}); assert.equal(g.gamma, 'S-Log2'); assert.equal(g.fcpLut, null);
  g = P.gammaOf({profile:{gamma:'S-Log3', primaries:'S-Gamut3'}}); assert.equal(g.kind, 'log'); assert.equal(g.fcpLut, null, 'S-Gamut3 (not .Cine) has no known Final Cut name');
  assert.equal(P.gammaOf({src:'card', log:true}).fcpLut, P.FCP_SONY_SLOG3);
  assert.equal(P.gammaOf({src:'drone', log:true}).gamma, 'D-Log'); assert.equal(P.gammaOf({src:'drone', log:true}).fcpLut, null);
  assert.equal(P.gammaOf({src:'phone', log:false}).kind, '709'); assert.equal(P.gammaOf({}).kind, '709');
});

// ---------- FCPXML ----------
const CLIPS = [
  {id:'P01', name:'IMG_2041', src:'phone', log:false, dur:8.2, t:'2026-10-12T09:14:02'},
  {id:'C01', name:'C4815', src:'card', log:true, dur:11.2, t:'2026-10-12T11:02:00'},
  {id:'C02', name:'C4816', src:'card', log:true, dur:10.8, t:'2026-10-12T11:02:22'},
  {id:'S01', name:'C4401', src:'ssd', log:true, dur:18.0, t:'2026-10-12T11:08:00'}, // 6 min fast → 11:02:00 + shift
  {id:'T01', name:'B0012', src:'t7b', log:true, dur:12.6, t:'2026-10-12T11:40:10'}, // 1 h slow → 12:40:10
  {id:'C05', name:'C4866', src:'card', log:true, dur:9.4, t:'2026-10-12T12:40:05'},
  {id:'D01', name:'DJI_0012', src:'drone', log:true, dur:22.0, t:'2026-10-12T10:03:10'},
  {id:'C08', name:'C4958', src:'card', log:false, dur:8.0, t:'2026-10-12T14:22:00'},
  {id:'X01', name:'R&D <test> "q"', src:'card', log:true, dur:5, t:'2026-10-12T15:00:00'},
];
const SHIFT = {ssd:-360, t7b:3600, t7c:50};
const H = {name:'Dump-Day1', clips:CLIPS, keeps:['C05', 'T01', 'S01', 'C02', 'P01', 'D01', 'C08', 'X01'], shift:SHIFT, rec709:true};
const spine = t => [...t.matchAll(/<spine>([\s\S]*?)<\/spine>/g)][0][1];
const spineClips = t => [...spine(t).matchAll(/<asset-clip ([^>]*)\/>/g)].map(m => Object.fromEntries([...m[1].matchAll(/(\w+)="([^"]*)"/g)].map(a => [a[1], a[2]])));
const assets = t => Object.fromEntries([...t.matchAll(/<asset ([^>]*)>\s*<media-rep [^>]*src="([^"]*)"/g)].map(m => { const a = Object.fromEntries([...m[1].matchAll(/(\w+)="([^"]*)"/g)].map(x => [x[1], x[2]])); a.src = m[2]; return [a.id, a]; }));
const rat = s => { if (s === '0s') return 0; const m = /^(\d+)\/(\d+)s$/.exec(s) || /^(\d+)s$/.exec(s); assert.ok(m, 'rational time: ' + s); return m[2] ? +m[1] / +m[2] : +m[1]; };

test('stringout: kept only, in axis order (file time + per-source shift)', () => {
  const ids = P.stringoutClips(H).map(c => c.id);
  assert.deepEqual(ids, ['P01', 'D01', 'S01', 'C02', 'C05', 'T01', 'C08', 'X01']);
  assert.ok(!ids.includes('C01'), 'not kept stays out');
  // S01 lands at 11:02:00 (before C02); without the shift it sorts after C02 at 11:08, and T01 before C05
  assert.deepEqual(P.stringoutClips({...H, shift:{}}).map(c => c.id), ['P01', 'D01', 'C02', 'S01', 'T01', 'C05', 'C08', 'X01']);
  const x = P.buildFcpxml(H), A = assets(x.text), names = spineClips(x.text).map(c => A[c.ref].name);
  assert.deepEqual(names, ['IMG_2041', 'DJI_0012', 'C4401', 'C4816', 'C4866', 'B0012', 'C4958', 'R&amp;D &lt;test&gt; &quot;q&quot;']);
});
test('FCPXML: version 1.10, one project, rational times, gapless spine on timeline frames', () => {
  const x = P.buildFcpxml(H), t = x.text;
  assert.match(t, /<fcpxml version="1\.10">/); assert.equal((t.match(/<project /g) || []).length, 1); assert.equal((t.match(/<sequence /g) || []).length, 1);
  assert.equal(x.n, 8);
  const seqFmt = /<sequence format="(r\d+)" duration="([^"]+)"/.exec(t), fm = new RegExp('<format id="' + seqFmt[1] + '" name="(\\w+)" frameDuration="([^"]+)"').exec(t);
  assert.equal(fm[1], 'FFVideoFormat3840x2160p2398', 'timeline uses the format most keeps share, a named one'); const fd = rat(fm[2]);
  let at = 0;
  for (const c of spineClips(t)) {
    near(rat(c.offset), at, 1e-12, 'gapless'); const d = rat(c.duration);
    near(d / fd, Math.round(d / fd), 1e-9, 'whole timeline frames'); at += d;
  }
  near(rat(seqFmt[2]), at, 1e-12, 'sequence duration = sum');
  for (const m of t.matchAll(/(?:duration|offset|start|frameDuration)="([^"]+)"/g)) assert.match(m[1], /^(0s|\d+\/\d+s)$/);
  // a clip is never longer than its file
  const A = assets(t); for (const id in A) assert.ok(rat(A[id].duration) <= CLIPS.find(c => c.name.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;') === A[id].name).dur + 1e-9);
  // 8.2 s at 29.97 = 245 frames (floor), phone format 1001/30000
  assert.equal(A.a1.duration, 245 * 1001 + '/30000s');
});
test('FCPXML: file:// URLs from placeholder paths, escaped', () => {
  const A = assets(P.buildFcpxml(H).text), src = Object.values(A).map(a => a.src);
  assert.ok(src.includes('file:///Volumes/T7/Road%20trip/Clips/A-cam/C4401.MP4'));
  assert.ok(src.includes('file:///Volumes/T7/Road%20trip/Clips/B-cam/B0012.MP4'));
  assert.ok(src.includes('file:///Volumes/iPhone/DCIM/100APPLE/IMG_2041.MOV'));
  assert.ok(src.includes('file:///Volumes/Untitled/PRIVATE/M4ROOT/CLIP/R%26D%20%3Ctest%3E%20%22q%22.MP4'), 'each path part URL-encoded');
  src.forEach(s => assert.match(s, /^file:\/\/\/Volumes\/[^ <>"]+$/));
});
test('FCPXML: Sony Log clips carry Final Cut\'s camera LUT; 709 and D-Log do not; the switch turns it off', () => {
  const x = P.buildFcpxml(H), A = assets(x.text), by = n => Object.values(A).find(a => a.name === n);
  for (const n of ['C4816', 'C4401', 'C4866', 'B0012']) assert.equal(by(n).customLUTOverride, P.FCP_SONY_SLOG3, n);
  for (const n of ['IMG_2041', 'C4958', 'DJI_0012']) assert.equal(by(n).customLUTOverride, undefined, n);
  assert.equal(x.log, 6); assert.equal(x.lut, 5);
  const off = P.buildFcpxml({...H, rec709:false}); assert.ok(!off.text.includes('customLUTOverride')); assert.equal(off.lut, 0);
});
test('FCPXML: well-formed (xmllint) and valid against the 1.10 subset DTD', {skip:!has('xmllint') && 'xmllint not installed'}, () => {
  const dir = mkdtempSync(join(tmpdir(), 'lp-')), f = join(dir, 'x.fcpxml');
  for (const h of [H, {...H, rec709:false}, {...H, keeps:['C02']}]) {
    writeFileSync(f, P.buildFcpxml(h).text);
    execFileSync('xmllint', ['--noout', f]);
    const dtd = join(HERE, 'fcpxml-1.10-subset.dtd'); if (existsSync(dtd)) execFileSync('xmllint', ['--noout', '--dtdvalid', dtd, f]);
  }
});
test('FCPXML: nothing kept → no project, still well-formed', () => {
  const x = P.buildFcpxml({...H, keeps:[]}); assert.equal(x.n, 0); assert.ok(!x.text.includes('<project'));
  assert.equal(P.summaryLine({...H, keeps:[]}), 'Final Cut · nothing kept yet');
});
test('summary line', () => {
  assert.equal(P.summaryLine(H), 'Final Cut · 8 clips · Log → Rec.709 LUT applied · 1 Log as shot');
  assert.equal(P.summaryLine({...H, rec709:false}), 'Final Cut · 8 clips · Log left as shot');
  assert.equal(P.summaryLine({...H, keeps:['C02', 'S01']}), 'Final Cut · 2 clips · Log → Rec.709 LUT applied');
  assert.equal(P.summaryLine({...H, keeps:['P01']}), 'Final Cut · 1 clip · all Rec.709');
});

// ---------- package ----------
test('buildPackage: .fcpxml + .cube + README; zip opens', () => {
  const p = P.buildPackage(H);
  assert.deepEqual(p.files.map(f => f.name), ['Dump-Day1 stringout.fcpxml', P.CUBE_NAME, 'README.txt']);
  assert.equal(p.files[0].text, P.buildFcpxml(H).text); assert.ok(p.files[1].text.includes('LUT_3D_SIZE 33'));
  assert.match(p.files[2].text, /placeholders/); assert.match(p.files[2].text, /Relink Files/); assert.match(p.files[2].text, /Camera LUT/);
  const z = P.zipStore(p.files, p.name);
  assert.equal(P.crc32(new TextEncoder().encode('123456789')), 0xCBF43926);
  if (has('unzip')) {
    const dir = mkdtempSync(join(tmpdir(), 'lpz-')), f = join(dir, 'p.zip'); writeFileSync(f, z);
    const out = execFileSync('unzip', ['-t', f]).toString(); assert.match(out, /No errors detected/);
    const ls = execFileSync('unzip', ['-Z1', f]).toString().trim().split('\n'); assert.deepEqual(ls, p.files.map(x => p.name + '/' + x.name));
    assert.equal(execFileSync('unzip', ['-p', f, p.name + '/README.txt']).toString(), p.files[2].text);
  }
});
