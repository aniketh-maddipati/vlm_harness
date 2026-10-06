// node Tests/core/v8-core.test.mjs
// The core cases CHANGES-v0.02 §9 asks for, on the shipped lumina-core-v4.js. Kept here, not in the
// handoff folder, because a sync replaces that folder; when a handoff brings its own copies of these
// cases, this file goes. Every TIFF is built in memory: no camera files in the repo.
import { createRequire } from 'node:module';
const LC = createRequire(import.meta.url)('../../design/handoff/lumina-cull/lumina-core-v4.js');

let bad = 0;
const eq = (n, a, b) => { const ok = JSON.stringify(a) === JSON.stringify(b); console.log(ok ? 'ok  ' : 'FAIL', n); if (!ok) { bad++; console.log(' got ', JSON.stringify(a), '\n want', JSON.stringify(b)); } };
const SIZE = 1 << 20;   // the file size parseHead checks piece offsets against

// A little-endian TIFF head. ifd(at, entries, next): entries are [tag, type, count, value]; a value
// that does not fit in 4 bytes is an offset the test writes itself with put16 / put32 / put8.
const head = () => { const u8 = new Uint8Array(4096), dv = new DataView(u8.buffer); u8.set([0x49, 0x49, 42, 0]); dv.setUint32(4, 8, true); return { u8, dv }; };
const ifd = ({ u8, dv }, at, entries, next = 0) => {
  dv.setUint16(at, entries.length, true);
  entries.forEach(([tag, type, cnt, v], i) => { const e = at + 2 + i * 12; dv.setUint16(e, tag, true); dv.setUint16(e + 2, type, true); dv.setUint32(e + 4, cnt, true); if (type === 3 && cnt === 1) dv.setUint16(e + 8, v, true); else dv.setUint32(e + 8, v, true); });
  dv.setUint32(at + 2 + entries.length * 12, next, true);
};
const put32 = ({ dv }, at, xs) => xs.forEach((x, i) => dv.setUint32(at + i * 4, x, true));

// ——— parseHead
eq('a head under 8 bytes → null', LC.parseHead(new Uint8Array(7), SIZE), null);

{ // a tiled JPEG preview (0x0144 / 0x0145), no 0x0201 → pvParts
  const t = head();
  ifd(t, 8, [[0x00FE, 4, 1, 1], [0x0100, 4, 1, 320], [0x0101, 4, 1, 240], [0x0103, 3, 1, 7], [0x0142, 4, 1, 256], [0x0143, 4, 1, 256], [0x0144, 4, 2, 400], [0x0145, 4, 2, 408]]);
  put32(t, 400, [10000, 12000]); put32(t, 408, [2000, 1800]);
  const m = LC.parseHead(t.u8, SIZE);
  eq('a tiled preview → pvParts', [m.preview, m.pvParts], [null, { parts: [[10000, 2000], [12000, 1800]], w: 320, h: 240, tw: 256, th: 256, tiled: true }]);
}
{ // a JPEG preview in several strips → pvParts
  const t = head();
  ifd(t, 8, [[0x00FE, 4, 1, 1], [0x0100, 4, 1, 320], [0x0101, 4, 1, 240], [0x0103, 3, 1, 7], [0x0111, 4, 2, 400], [0x0116, 4, 1, 120], [0x0117, 4, 2, 408]]);
  put32(t, 400, [10000, 12000]); put32(t, 408, [2000, 1800]);
  const m = LC.parseHead(t.u8, SIZE);
  eq('a multi-strip preview → pvParts', [m.preview, m.pvParts], [null, { parts: [[10000, 2000], [12000, 1800]], w: 320, h: 240, rps: 120, tiled: false }]);
}
{ // an uncompressed 8-bit RGB thumbnail (Android DngCreator IFD0) → pvRGB
  const t = head();
  ifd(t, 8, [[0x00FE, 4, 1, 1], [0x0100, 4, 1, 96], [0x0101, 4, 1, 64], [0x0102, 3, 1, 8], [0x0103, 3, 1, 1], [0x0106, 3, 1, 2], [0x0111, 4, 1, 10000], [0x0115, 3, 1, 3], [0x0117, 4, 1, 96 * 64 * 3]]);
  const m = LC.parseHead(t.u8, SIZE);
  eq('an RGB thumbnail → pvRGB', [m.preview, m.pvParts, m.pvRGB], [null, null, { parts: [[10000, 96 * 64 * 3]], w: 96, h: 64, spp: 3 }]);
}

// Sony MakerNote: IFD0 → 0x927C at `mo`, with or without the "SONY DSC " header (IFD at +12 or +0).
const sony = (entries, { header = true } = {}) => {
  const t = head(), mo = 200, at = header ? mo + 12 : mo;
  if (header) t.u8.set([...'SONY DSC '].map(c => c.charCodeAt(0)), mo);
  ifd(t, 8, [[0x927C, 7, 512, mo]]);
  ifd(t, at, entries(t));
  return LC.parseHead(t.u8, SIZE);
};
eq('a MakerNote with the SONY header is read', sony(() => [[0xB04A, 3, 1, 3]]).seqImage, 3);
eq('a SONY-less MakerNote is read', sony(() => [[0xB04A, 3, 1, 3]], { header: false }).seqImage, 3);

// 0x9400, enciphered: Sony's cipher is c → c³ mod 249; the stored first byte names the layout.
const enc = c => (c * c * c) % 249;
const seq9400 = (index, length) => sony(t => {
  const p = 600, d = new Array(0x40).fill(0);
  d[0x12] = index; d[0x1E] = length; d[0x09] = 1;
  t.u8.set(d.map(enc), p); t.u8[p] = 0x23;
  return [[0x9400, 7, 0x40, p]];
});
eq('a single shot has seqImage null', seq9400(0, 1).seqImage, null);
eq('frame 3 of 5 has seqImage 3', [seq9400(2, 5).seqImage, seq9400(2, 5).seqLength], [3, 5]);

// ——— soft and blown (8g), through buildShoot
const shot = (i, sec, more = {}) => ({ name: 'DSC1' + String(i).padStart(4, '0') + '.ARW', path: 's/' + i, date: '2026:09:26 15:' + String(Math.floor(sec / 60)).padStart(2, '0') + ':' + String(sec % 60).padStart(2, '0'), exp: 0.001, fl: 50, ev: null, iso: 400, lens: 'FE 50mm', lum: 0.5, focus: 300, clip: 0, portrait: false, src: '', lg: '', ...more });
const flags = (input, key) => { const d = LC.buildShoot(input, {}); return d.order.map(id => d.byId[id][key]); };
const kindsOf = input => { const d = LC.buildShoot(input, {}); return d.order.map(id => d.byId[id].kind); };

{ const one = [shot(0, 0, { focus: 10 })];
  eq('a single has no soft', [kindsOf(one), flags(one, 'soft')], [['single'], [false]]); }
{ const burst = [0, 1, 2].map(i => shot(i, 0, { seqImage: i + 1, releaseMode2: 1, focus: [300, 100, 200][i] }));
  eq('a burst frame below 0.45× its sharpest is soft', [kindsOf(burst), flags(burst, 'soft')], [['burst', 'burst', 'burst'], [false, true, false]]); }
{ const br = [0, 1, 2].map(i => shot(i, 0, { seqImage: i + 1, releaseMode2: 2, clip: [0, 2, 30][i], ev: [-1, 0, 1][i] }));
  eq('a bracket is never blown', [kindsOf(br), flags(br, 'blown')], [['bracket', 'bracket', 'bracket'], [false, false, false]]); }
{ // five singles a few seconds apart, one row; the last at 6 % clip
  const row = clips => clips.map((c, i) => shot(i, i * 6, { clip: c, focus: 300 + i * 40 }));
  const lo = row([1, 1, 1, 1, 6]), hi = row([4, 4, 4, 4, 6]);
  eq('the singles row is one row of singles', [LC.buildShoot(lo, {}).M.length, kindsOf(lo)], [1, ['single', 'single', 'single', 'single', 'single']]);
  eq('a single at 6 % clip in a row with median 1 % is blown', flags(lo, 'blown')[4], true);
  eq('… in a row with median 4 % it isn\'t', flags(hi, 'blown')[4], false);
}

// ——— sidecars
{ const x = LC.freshXmp(3, null, null, 'Lumina pass 2');
  eq('freshXmp(…, "Lumina pass 2") has the dc:subject bag', /<dc:subject><rdf:Bag><rdf:li>Lumina pass 2<\/rdf:li><\/rdf:Bag><\/dc:subject>/.test(x), true);
  eq('… and the lr:hierarchicalSubject bag', /<lr:hierarchicalSubject><rdf:Bag><rdf:li>Lumina\|pass 2<\/rdf:li><\/rdf:Bag><\/lr:hierarchicalSubject>/.test(x), true); }
{ const old = '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmp:Rating="2">'
    + '<dc:subject><rdf:Bag><rdf:li>Lumina pass 1</rdf:li><rdf:li>Portfolio</rdf:li></rdf:Bag></dc:subject></rdf:Description></rdf:RDF></x:xmpmeta>';
  const x = LC.mergeXmp(old, 3, null, 'Lumina pass 2'), lis = [...x.matchAll(/<rdf:li>([^<]*)<\/rdf:li>/g)].map(m => m[1]);
  eq('mergeXmp replaces the old Lumina pass keyword and keeps the others', [lis.includes('Lumina pass 1'), lis.includes('Lumina pass 2'), lis.includes('Portfolio')], [false, true, true]);
  eq('… and sets the rating', /xmp:Rating="3"/.test(x), true); }

process.exit(bad ? 1 : 0);
