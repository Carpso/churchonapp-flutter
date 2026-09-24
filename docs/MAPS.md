# Reusing the Church On App maps in other projects

This documents how to reuse the map stack **in its current state** (2026-09-24).
`church_map.dart` is still an in-app widget (not a published package), but the
**basemap and all map assets are independent HTTP resources** that any project or
stack can consume today.

---

## 1. What is reusable right now

### Basemap (vector PMTiles, self-hosted on R2)

| Region | URL | Zoom | Notes |
|---|---|---|---|
| Southern Africa (ZM, ZW, MW, MZ) | `https://maps.churchonapp.com/region-zm-zw-mw-mz.pmtiles` | 0–15 | 1433 MB, the base archive |
| Lusaka / Ndola / Kitwe / Livingstone / Harare / Bulawayo | `https://maps.churchonapp.com/tiles/<city>-z13-19.pmtiles` | 13–19 | high-detail, built on demand |

The old `zambia.pmtiles` (612 MB) and `zimbabwe.pmtiles` (310 MB) were **deleted**
— use `region-zm-zw-mw-mz.pmtiles`, which supersedes both.

- Format: **PMTiles v3**, `tile_type = 1` (**vector / MVT**), internal + tile
  compression = gzip.
- Source schema: **Protomaps Basemap v4.13.6** — layers:
  `boundaries, buildings, earth, landcover, landuse, places, pois, roads, water`.
- Bucket: `church-on-app-maps` · custom domain `maps.churchonapp.com`
- **CORS: `*`** (with `Range` allowed) → usable from any origin, including browsers.
- `tiles/latest.json` lists every live source (url, bbox, zoom range, bytes,
  dated rollback URL) — read it if your client wants to discover sources
  dynamically instead of hardcoding them.

### Map assets (label fonts + POI sprites)

| Asset | URL |
|---|---|
| Glyphs (fonts) | `https://maps.churchonapp.com/map-assets/fonts/{fontstack}/{range}.pbf` |
| Sprites | `https://maps.churchonapp.com/map-assets/sprites/v4/light` (`.json` + `.png`, plus `@2x`) |

- Fontstacks provided: `Noto Sans Regular`, `Noto Sans Medium`, `Noto Sans Italic`
- Ranges provided (Latin + Latin-Extended + Greek): `0-255, 256-511, 512-767, 768-1023`
- Same bucket, same domain, CORS `*`.

### Routing + geocoding endpoints

- Routing: configurable via `OSRM_BASE_URL` (defaults to the public OSRM demo).
- Geocoding: `GEOCODING_BASE_URL` (self-hosted, takes precedence) → Nominatim →
  Photon fallback, with a 7-day local cache.

---

## 2. Consuming it from a NON-Flutter project (JS/React/Vue, etc.)

Vector PMTiles are standard — no Church On App code needed:

```js
// npm i maplibre-gl pmtiles
import maplibregl from 'maplibre-gl';
import { Protocol } from 'pmtiles';

const protocol = new Protocol();
maplibregl.addProtocol('pmtiles', protocol.tile);

const map = new maplibregl.Map({
  container: 'map',
  style: 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json', // or your own
  center: [28.3228, -15.3875],
  zoom: 12,
});

map.on('load', () => {
  map.addSource('coa', {
    type: 'vector',
    url: 'pmtiles://https://maps.churchonapp.com/region-zm-zw-mw-mz.pmtiles',
  });
  // Point the style's `glyphs` at the self-hosted fonts if you style with the
  // Protomaps v4 layers:
  //   "glyphs": "https://maps.churchonapp.com/map-assets/fonts/{fontstack}/{range}.pbf",
  //   "sprite": "https://maps.churchonapp.com/map-assets/sprites/v4/light",
});
```

> If you keep the stock Protomaps v4 theme you can also use the public
> `protomaps.github.io/basemaps-assets` glyphs; the self-hosted copies above
> exist so the app has no third-party dependency.

---

## 3. Consuming it from another FRAMEWORK project (React Native, etc.)

The basemap is just an HTTP PMTiles URL — any PMTiles-capable renderer works
(MapLibre Native, Mapbox GL with a PMTiles plugin, a custom `pmtiles` client…).
There is nothing Church-On-App-specific about the tile data.

---

## 4. Consuming it from another FLUTTER project

`church_map.dart` is **not yet a package**. To reuse the *widget* today, copy:

```
lib/core/widgets/church_map.dart                       # the widget
lib/core/widgets/maps/protomaps_light_v4_layers.dart   # generated theme (6.7k lines)
lib/core/services/geocoding_service.dart               # address search chain
lib/core/config/app_constants.dart                     # brand colours
```

and add these dependencies (see this repo's `pubspec.yaml`):

```
flutter_map, vector_map_tiles, vector_map_tiles_pmtiles,
latlong2, geolocator, geocoding, image_picker, shared_preferences,
http, flutter_riverpod, supabase_flutter, lucide_icons, flutter_dotenv, cached_network_image
```

Set the env keys: `MAPS_ZAMBIA_URL`, `MAPS_ZIMBABWE_URL`, `MAPS_EXTRA_SOURCES`,
`OSRM_BASE_URL`, `GEOCODING_BASE_URL`.

Copy the source-switching helper too — it is pure Dart, no Supabase/riverpod:

```
lib/core/widgets/maps/map_sources.dart   # MapSourceRegion + build/resolve helpers
```

**To turn it into a real package later** (`coa_maps`): move the widget + generated
theme + assets into `packages/coa_maps`, add a `path:` dependency, and update
imports. That has not been done on purpose (a large, risky refactor).

---

## 5. Building high-detail city tiles

The z0–15 regional archive cannot show building footprints. For city detail
(z13–19) build a clipped archive per metro:

```powershell
# Windows — all countries + all cities
.\scripts\map\build-city-tiles.ps1

# Just Lusaka and Harare
.\scripts\map\build-city-tiles.ps1 -Cities lusaka,harare

# Country-only rebuild, no uploads
.\scripts\map\build-city-tiles.ps1 -Countries zambia,zimbabwe -SkipUpload

# Force a rebuild of outputs that already exist
.\scripts\map\build-city-tiles.ps1 -Cities lusaka -Force
```

```bash
# Linux/macOS VM
./scripts/map/build-city-tiles.sh --countries zambia --cities lusaka
```

| Switch | Meaning |
|---|---|
| `-Countries all` / `-Cities all` | every id in `scripts/map/metros.json` |
| `-Scratch D:\mapbuild` | where PBFs + `.pmtiles` land (default `D:\mapbuild`) |
| `-SkipDownload` | reuse PBFs already on disk |
| `-SkipUpload` | build only; nothing touches R2 |
| `-Force` | rebuild an output that already exists (planetiler cannot resume) |
| `-UseDocker` | run planetiler in `ghcr.io/onthegomap/planetiler` |
| `-OnlyFetchWays` | offline, geometry-only input (smaller, faster) |
| `-DateStamp 20260924` | override the snapshot date in the key |

What it does:

1. Downloads `<country>-latest.osm.pbf` from Geofabrik (once — cached).
2. Runs Planetiler `--area/--bounds/--minzoom/--maxzoom/--output` to a `.pmtiles`.
3. Uploads to R2 via `r2-put.mjs` (S3 SigV4 — `wrangler r2 object put` crashes
   on Windows for files this size; the dashboard caps at 300 MB anyway).
4. Copies each build to a **stable key** (`tiles/lusaka-z13-19.pmtiles`) and a
   **dated snapshot** (`tiles/lusaka-z13-19/20260924.pmtiles`).
5. Writes `<Scratch>/build-report.json`.

Publish the manifest + schedule a refresh:

```powershell
.\scripts\map\refresh-maps.ps1                    # build + manifest + upload
.\scripts\map\refresh-maps.ps1 -SkipBuild         # manifest/upload only
.\scripts\map\refresh-maps.ps1 -Cities lusaka     # one city
```

```bash
./scripts/map/refresh-maps.sh --cities lusaka
```

`refresh-maps.ps1` prints the `schtasks` line; `refresh-maps.sh` prints the cron
line. Weekly Sunday 03:00 is the suggested cadence.

**Rollback:** the manifest records a `dated` URL per source. Repoint
`MAPS_EXTRA_SOURCES` (or `MAPS_ZAMBIA_URL`) at a previous
`tiles/<name>/<yyyyMMdd>.pmtiles` and redeploy — no rebuild needed.

### Enabling the city sources in the app

After the first upload, uncomment `MAPS_EXTRA_SOURCES` in `.env`:

```
MAPS_EXTRA_SOURCES=[{"name":"lusaka","bbox":[-15.78,27.66,-15.02,28.62],"minZoom":16,"maxZoom":19,"url":"https://maps.churchonapp.com/tiles/lusaka-z13-19.pmtiles"}, ...]
```

`bbox` is `[south, west, north, east]`. `build-city-tiles.ps1 -Report` writes the
exact lines to paste (also in `build-report.json`).

### How the app picks a source

`lib/core/widgets/maps/map_sources.dart`:

- `buildMapSourceTable(primaryUrl, zimbabweUrl, extraJson)` — world base
  (z0–15) + optional Zimbabwe + every entry in `MAPS_EXTRA_SOURCES`.
- `resolveMapSource(table, center, zoom)` — smallest bbox that **contains the
  centre** and **covers the zoom**; falls back to the world base.
- `church_map.dart` re-resolves on camera movement, keys the `VectorTileLayer`
  on the URL (no stale tiles), and sets `maximumZoom` from the active source
  (15 → 19 inside a city).
- A city archive that fails to open **silently falls back to the base**; only a
  base failure shows the RETRY chip.
- A caller passing `ChurchMap.pmtilesUrl` explicitly pins that single archive —
  no switching.

---

## 6. Routing this as a *rental* service (per-tenant billing)

R2 is a dumb, cheap blob store. It serves tiles; it cannot meter them. The
split you need to sell basemaps to other apps:

| Concern | Where it runs | Why |
|---|---|---|
| Tile storage | **R2** (`church-on-app-maps`) | egress-free, cheap, CORS `*` |
| Per-tenant API keys, rate limits, usage metering, billing | **Cloudflare Worker** in front of the tiles | R2 has no auth/quotas; Workers can count requests per key |
| Routing (OSRM / Valhalla) | **Cloudflare Containers** or a small VM | needs compute + a routing graph in memory |
| Geocoding (Photon / Nominatim) | **Cloudflare Containers** or a small VM | same — needs compute |
| Live traffic | **paid feed or your own drivers** | there is no free global real-time traffic feed |

Minimal Worker shape:

```
GET /t/<tenant_key>/<source>.pmtiles   →  look up tenant, bump KV/D1 counter,
                                          check quota, then `env.BUCKET.get()`
```

Serve the manifest (`tiles/latest.json`) unauthenticated so clients can discover
sources before they have a key; gate the `.pmtiles` objects themselves.

Pricing intuition: R2 storage is ~$0.015/GB-month and **egress is free**, so a
1.5 GB archive is ≈ $0.03/month to hold. Your margin comes entirely from the
metering layer, not the storage.

---

## 7. Regenerating the theme / assets

The v4 light theme is held locally (`maps/protomaps_light_v4_layers.dart`)
because `ProtomapsThemes.lightV4()` hardcodes its glyph URL and does not expose
it. Regenerate by copying the `themeLight` array out of:

```
vector_map_tiles_pmtiles/lib/src/themes/v4/light.dart
```

The font/sprites files come from
`https://protomaps.github.io/basemaps-assets/` and are uploaded to the
`church-on-app-maps` bucket under `map-assets/`.

> **Gotcha:** `wrangler r2 object put|get` default to a LOCAL simulator — always
> pass `--remote` to touch real R2.

---

## 8. Notes / constraints

- Basemap max zoom is **15** for the regional archive; city archives go to
  **19**. The app sets `VectorTileLayer.maximumZoom` from whichever source is
  active and lets the layer over-zoom past a source's top zoom.
- **Planetiler cannot resume a partial run** — a killed build restarts from
  scratch. The scripts skip outputs that already exist, so re-running after a
  crash continues from the last *completed* source (`-Force`/`--force` rebuilds).
- Glyph ranges are Latin only; other scripts need their ranges uploaded too.
- `media.churchonapp.com` (`choa-sermons-vault`) is **public**, CORS restricted to
  the app origins. `choa-kyc-vault` is **private** (no domain, signed reads only).
- Map tiles are cached to disk for 90 days / 250 MB in the app, so previously
  viewed areas work offline.
- Live traffic needs a paid feed — there is no free global real-time traffic
  source. The app falls back to crowd-sourced driver-speed segments.
