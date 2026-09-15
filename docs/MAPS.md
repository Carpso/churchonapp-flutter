# Reusing the Church On App maps in other projects

This documents how to reuse the map stack **in its current state** (2026-09-15).
`church_map.dart` is still an in-app widget (not a published package), but the
**basemap and all map assets are independent HTTP resources** that any project or
stack can consume today.

---

## 1. What is reusable right now

### Basemap (vector PMTiles, self-hosted on R2)

| Region | URL |
|---|---|
| Zambia | `https://maps.churchonapp.com/zambia.pmtiles` (612 MB) |
| Zimbabwe | `https://maps.churchonapp.com/zimbabwe.pmtiles` (310 MB) |

- Format: **PMTiles v3**, `tile_type = 1` (**vector / MVT**), zoom **0–15**,
  internal + tile compression = gzip.
- Source schema: **Protomaps Basemap v4.13.6** — layers:
  `boundaries, buildings, earth, landcover, landuse, places, pois, roads, water`.
- Bucket: `church-on-app-maps` · custom domain `maps.churchonapp.com`
- **CORS: `*`** (with `Range` allowed) → usable from any origin, including browsers.

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
    url: 'pmtiles://https://maps.churchonapp.com/zambia.pmtiles',
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

Set the env keys: `MAPS_ZAMBIA_URL`, `MAPS_ZIMBABWE_URL`, `OSRM_BASE_URL`,
`GEOCODING_BASE_URL`.

**To turn it into a real package later** (`coa_maps`): move the widget + generated
theme + assets into `packages/coa_maps`, add a `path:` dependency, and update
imports. That has not been done on purpose (a large, risky refactor).

---

## 5. Regenerating the theme / assets

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

## 6. Notes / constraints

- Basemap max zoom is **15**; the app lets the user zoom to 18 and the layer
  over-zooms.
- Glyph ranges are Latin only; other scripts need their ranges uploaded too.
- `media.churchonapp.com` (`choa-sermons-vault`) is **public**, CORS restricted to
  the app origins. `choa-kyc-vault` is **private** (no domain, signed reads only).
- Map tiles are cached to disk for 90 days / 250 MB in the app, so previously
  viewed areas work offline.
