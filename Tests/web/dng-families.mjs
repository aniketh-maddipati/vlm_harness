// Synthetic DNGs for the camera families TEST-PLAN.md names beyond iPhone / Pixel / Sony (dng-fixtures.mjs has
// those): Samsung phone and camera, Leica, DJI, Sony Xperia, and one with no Make / Model at all. Built in
// memory with dng-fixtures.mjs's TIFF writer and JPEG drawer; every preview is drawn flat 8×8 blocks, every raw
// stand-in bytes. No photo anywhere.
//
//   import {families} from './dng-families.mjs'
//   families() → [{id, name, bytes: Uint8Array, preview: Uint8Array|null, expect}]   (fresh bytes on every call)
//
// Layouts are from memory of exiftool dumps (no network to check); what is tested is phoneOf on Make / Model
// read through parseHead, so the layout only has to be a valid TIFF/DNG with a preview parseHead can find:
// - Samsung Expert RAW (samsung / SM-S918B, Galaxy S23 Ultra), little-endian, DNG 1.4: IFD0 the raw
//   (NewSubfileType 0, no SubIFDs), IFD1 (next-IFD chain) the JPEG preview as one strip (NewSubfileType 1).
//   Low confidence in the arrangement; it exercises the next-IFD path the other fixtures do not.
// - Samsung NX500 through Adobe DNG Converter (NX bodies write SRW natively), big-endian: IFD0 an RGB
//   thumbnail, SubIFD 0 the raw, SubIFD 1 the JPEG preview. Converter layout, medium-high confidence.
// - Leica Q2 (LEICA CAMERA AG / LEICA Q2), native DNG, little-endian: IFD0 a small uncompressed RGB thumbnail,
//   SubIFD 0 the raw, SubIFD 1 a JPEG preview. Medium-low confidence for the preview's place.
// - DJI Mini 3 Pro (DJI / FC3582), little-endian: IFD0 the raw (NewSubfileType 0), the preview through
//   JPEGInterchangeFormat in IFD1. Low confidence.
// - Sony Xperia 1 IV (SONY / XQ-DQ54, Photo Pro), little-endian: IFD0 the JPEG preview strip, SubIFD 0 the raw
//   (the Android DngCreator shape with a JPEG instead of its RGB thumbnail; see C4's pixel-rgb-thumb for that).
// - No make (no Make or Model tag), little-endian DNG: the "empty make → camera" case.
import { buildTiff, drawJpeg } from './dng-fixtures.mjs';

const T = { BYTE: 1, ASCII: 2, SHORT: 3, LONG: 4, RATIONAL: 5, SRATIONAL: 10 };
const strip = (nst, w, h, cmp, photometric, blob, spp = 1, bps = [8]) => [
  [0x00FE, T.LONG, [nst]], [0x0100, T.LONG, [w]], [0x0101, T.LONG, [h]], [0x0102, T.SHORT, bps], [0x0103, T.SHORT, [cmp]],
  [0x0106, T.SHORT, [photometric]], [0x0111, T.LONG, { blob }], [0x0115, T.SHORT, [spp]], [0x0116, T.LONG, [h]], [0x0117, T.LONG, { len: blob }]];
const camera = (make, model, orient) => [...(make !== null ? [[0x010F, T.ASCII, make]] : []), ...(model !== null ? [[0x0110, T.ASCII, model]] : []), [0x0112, T.SHORT, [orient]]];
const dng = (version, unique) => [[0xC612, T.BYTE, version], [0xC613, T.BYTE, [1, 4, 0, 0]], [0xC614, T.ASCII, unique]];
const exif = ({ date, exp, fnum, iso, fl, fl35, lens }) => ({ entries: [
  [0x829A, T.RATIONAL, [exp]], [0x829D, T.RATIONAL, [fnum]], [0x8827, T.SHORT, [iso]], [0x9003, T.ASCII, date],
  [0x9204, T.SRATIONAL, [[0, 1]]], [0x920A, T.RATIONAL, [fl]], ...(fl35 ? [[0xA405, T.SHORT, [fl35]]] : []), ...(lens ? [[0xA434, T.ASCII, lens]] : [])] });
const cfa = n => { const b = new Uint8Array(n); for (let i = 0; i < n; i++) b[i] = (i * 53) & 255; return b; };
const rawEntries = (blob, cmp = 1) => [...strip(0, 64, 48, cmp, 32803, blob, 1, [16]), [0x828D, T.SHORT, [2, 2]], [0x828E, T.BYTE, [0, 1, 1, 2]]];

function out(id, name, le, ifd0, blobs, preview, expect) {
  const { bytes, offsets } = buildTiff({ le, ifd0, blobs });
  return { id, name, bytes, preview, expect: { ...expect, preview: preview ? [offsets.preview, preview.length] : null } };
}

function samsungExpertRaw() {
  const date = '2026:09:13 09:02:11', preview = drawJpeg(64, 48, (x, y) => 40 + 18 * x + 9 * y);
  const ifd1 = { entries: strip(1, 64, 48, 7, 6, 'preview', 3, [8, 8, 8]) };
  const ifd0 = { entries: [...rawEntries('raw'), ...camera('samsung', 'SM-S918B', 1), [0x0131, T.ASCII, 'S918BXXU3BWK5'], ...dng([1, 4, 0, 0], 'samsung SM-S918B')],
    exif: exif({ date, exp: [1, 250], fnum: [170, 100], iso: 50, fl: [630, 100], fl35: 23 }), next: ifd1 };
  return out('samsung-expert-raw', '20260913_090211.dng', true, ifd0, { raw: cfa(64 * 48 * 2), preview }, preview,
    { make: 'samsung', model: 'SM-S918B', dng: true, orient: 1, date, fl35: 23, phone: true, short: 'Samsung SM-S918B', zoom: '1×', lens: '1× camera', fl: 6.3 });
}

function samsungNx() {
  const date = '2026:09:13 10:15:40', preview = drawJpeg(56, 40, (x, y) => 200 - 12 * x - 5 * y);
  const ifd0 = { entries: [...strip(1, 32, 21, 1, 2, 'thumb', 3, [8, 8, 8]), ...camera('SAMSUNG', 'NX500', 1), [0x0131, T.ASCII, 'Adobe DNG Converter 16.0'], ...dng([1, 4, 0, 0], 'Samsung NX500')],
    subs: [{ entries: rawEntries('raw') }, { entries: strip(1, 56, 40, 7, 6, 'preview', 3, [8, 8, 8]) }],
    exif: exif({ date, exp: [1, 320], fnum: [56, 10], iso: 200, fl: [300, 10], fl35: 46, lens: 'Samsung NX 30mm F2 Pancake' }) };
  return out('samsung-nx', 'SAM_0412.DNG', false, ifd0, { thumb: cfa(32 * 21 * 3), raw: cfa(64 * 48 * 2), preview }, preview,
    { make: 'SAMSUNG', model: 'NX500', dng: true, orient: 1, date, fl35: 46, phone: false, lens: 'Samsung NX 30mm F2 Pancake', fl: 30 });
}

function leica() {
  const date = '2026:09:13 11:40:05', preview = drawJpeg(64, 40, (x, y) => (x * 7 + y * 3) % 2 ? 180 : 70);
  const ifd0 = { entries: [...strip(1, 32, 20, 1, 2, 'thumb', 3, [8, 8, 8]), ...camera('LEICA CAMERA AG', 'LEICA Q2', 6), [0x0131, T.ASCII, '5.0.0'], ...dng([1, 4, 0, 0], 'LEICA Q2')],
    subs: [{ entries: rawEntries('raw') }, { entries: strip(1, 64, 40, 7, 6, 'preview', 3, [8, 8, 8]) }],
    exif: exif({ date, exp: [1, 125], fnum: [28, 10], iso: 100, fl: [28, 1], fl35: 28, lens: 'SUMMILUX 1:1.7/28 ASPH.' }) };
  return out('leica-q2', 'L1000123.DNG', true, ifd0, { thumb: cfa(32 * 20 * 3), raw: cfa(64 * 48 * 2), preview }, preview,
    { make: 'LEICA CAMERA AG', model: 'LEICA Q2', dng: true, orient: 6, date, fl35: 28, phone: false, lens: 'SUMMILUX 1:1.7/28 ASPH.', fl: 28 });
}

function dji() {
  const date = '2026:09:13 17:22:48', preview = drawJpeg(48, 32, (x, y) => 120 + 20 * ((x + y) % 4));
  const ifd1 = { entries: [[0x0103, T.SHORT, [6]], [0x0201, T.LONG, { blob: 'preview' }], [0x0202, T.LONG, { len: 'preview' }]] };
  const ifd0 = { entries: [...rawEntries('raw'), ...camera('DJI', 'FC3582', 1), [0x0131, T.ASCII, '10.01.04.15'], ...dng([1, 4, 0, 0], 'DJI FC3582')],
    exif: exif({ date, exp: [1, 800], fnum: [17, 10], iso: 100, fl: [672, 100], fl35: 24 }), next: ifd1 };
  return out('dji', 'DJI_0042.DNG', true, ifd0, { raw: cfa(64 * 48 * 2), preview }, preview,
    { make: 'DJI', model: 'FC3582', dng: true, orient: 1, date, fl35: 24, phone: false, lens: null, fl: 6.72 });
}

function xperia() {
  const date = '2026:09:13 18:05:59', preview = drawJpeg(64, 48, (x, y) => 220 - 22 * y - 4 * x);
  const ifd0 = { entries: [...strip(1, 64, 48, 7, 6, 'preview', 3, [8, 8, 8]), ...camera('SONY', 'XQ-DQ54', 1), ...dng([1, 4, 0, 0], 'Sony XQ-DQ54')],
    subs: [{ entries: rawEntries('raw') }],
    exif: exif({ date, exp: [1, 200], fnum: [23, 10], iso: 64, fl: [8500, 1000], fl35: 85 }) };
  return out('xperia', 'DSC_0007.DNG', true, ifd0, { preview, raw: cfa(64 * 48 * 2) }, preview,
    { make: 'SONY', model: 'XQ-DQ54', dng: true, orient: 1, date, fl35: 85, phone: true, short: 'Sony XQ-DQ54', zoom: '3×', lens: '3× camera', fl: 8.5 });
}

function noMake() {
  const date = '2026:09:13 19:00:00', preview = drawJpeg(48, 32, () => 128);
  const ifd0 = { entries: [...strip(1, 48, 32, 7, 6, 'preview', 3, [8, 8, 8]), ...camera(null, null, 1), ...dng([1, 4, 0, 0], 'unknown')],
    subs: [{ entries: rawEntries('raw') }],
    exif: exif({ date, exp: [1, 100], fnum: [40, 10], iso: 100, fl: [50, 1], fl35: 50 }) };
  return out('no-make', 'IMG_9999.DNG', true, ifd0, { preview, raw: cfa(64 * 48 * 2) }, preview,
    { make: null, model: null, dng: true, orient: 1, date, fl35: 50, phone: false, lens: null, fl: 50 });
}

export function families() { return [samsungExpertRaw(), samsungNx(), leica(), dji(), xperia(), noMake()]; }
