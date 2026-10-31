#!/usr/bin/env node
/**
 * Bake raster PNG tiles from a local TileServer GL instance into an R2-ready
 * tile tree.
 *
 * WHY THIS EXISTS
 *   The Flutter web build cannot render vector tiles at all - `executor_lib`
 *   branches only on `kDebugMode`, so a release web build takes the isolate
 *   `PoolExecutor` path and throws `Unsupported operation: ReceivePort`, hanging
 *   every tile job. The only way to give web a basemap is raster PNGs.
 *
 *   MapLibre Native (via tileserver-gl) is the only tool on this machine that
 *   can turn our Protomaps PMTiles into PNGs. This script crawls its
 *   `/styles/<style>/{z}/{x}/{y}.png` endpoint for a bbox/zoom range and writes
 *   a flat `{z}/{x}/{y}.png` tree ready for R2.
 *
 * SCOPE POLICY
 *   City bboxes are geographically disjoint, so one flat tree is safe: the
 *   regional archive supplies low zooms, cities add detail in their own areas.
 *   Bake z0-10 from the regional source and z11-16 per city. z16 for one city
 *   is ~24k tiles (~700 MB), so cap by zoom and let the operator extend.
 *
 * USAGE
 *   node bake-raster-tiles.mjs --server http://127.0.0.1:8100 \
 *     --style coa-light --bbox -15.78,27.66,-15.02,28.62 \
 *     --minzoom 13 --maxzoom 14 --out D:/mapbuild/raster/lusaka
 *
 *   Resume-safe: existing files are skipped, so re-running continues.
 */
import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';

const { values } = parseArgs({
  options: {
    server:  { type: 'string', default: 'http://127.0.0.1:8100' },
    style:   { type: 'string', default: 'coa-light' },
    bbox:    { type: 'string', required: true },   // south,west,north,east
    minzoom: { type: 'string', default: '11' },
    maxzoom: { type: 'string', default: '14' },
    out:     { type: 'string', required: true },
    limit:   { type: 'string', default: '0' },      // 0 = no cap
  },
});

const [south, west, north, east] = values.bbox.split(',').map(Number);
const zMin = Number(values.minzoom), zMax = Number(values.maxzoom);
const outRoot = path.resolve(values.out);
const cap = Number(values.limit);
fs.mkdirSync(outRoot, { recursive: true });

const lngToX = (lng, z) => Math.floor(((lng + 180) / 360) * 2 ** z);
const latToY = (lat, z) => {
  const r = (lat * Math.PI) / 180;
  return Math.floor(((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2) * 2 ** z);
};

let queued = 0, written = 0, skipped = 0, failed = 0;
const failures = [];

for (let z = zMin; z <= zMax; z++) {
  const x0 = lngToX(west, z), x1 = lngToX(east, z);
  const y0 = latToY(north, z), y1 = latToY(south, z);
  for (let x = x0; x <= x1; x++) {
    for (let y = y0; y <= y1; y++) {
      if (cap > 0 && queued >= cap) { console.log(`cap reached (${cap})`); process.exit(failed ? 2 : 0); }
      queued++;
      const dir = path.join(outRoot, String(z), String(x));
      const file = path.join(dir, `${y}.png`);
      if (fs.existsSync(file) && fs.statSync(file).size > 0) { skipped++; continue; }
      const url = `${values.server}/styles/${values.style}/${z}/${x}/${y}.png`;
      try {
        const res = await fetch(url, { signal: AbortSignal.timeout(60_000) });
        if (!res.ok) { failed++; failures.push(`${res.status} ${z}/${x}/${y}`); continue; }
        const buf = Buffer.from(await res.arrayBuffer());
        // A blank tile compresses to a few hundred bytes; keep it anyway so the
        // tree is complete, but flag suspiciously tiny ones.
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(file, buf);
        written++;
        if (written % 50 === 0) console.log(`  ${written} written, ${skipped} skipped, ${failed} failed`);
      } catch (e) {
        failed++; failures.push(`${e.message} ${z}/${x}/${y}`);
      }
    }
  }
}

console.log(`done: written=${written} skipped=${skipped} failed=${failed} queued=${queued}`);
if (failures.length) {
  console.log('first failures:');
  failures.slice(0, 10).forEach((f) => console.log('  ' + f));
  process.exit(2);
}