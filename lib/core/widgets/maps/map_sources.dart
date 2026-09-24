import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One PMTiles archive the basemap may switch to.
///
/// [buildMapSourceTable] builds the table; [resolveMapSource] picks the archive
/// for a camera centre + zoom. The default source is the whole-world z0–15
/// archive (`MAPS_ZAMBIA_URL`), which always matches, so a centre outside every
/// named region over-zooms it instead of going blank.
@immutable
class MapSourceRegion {
  const MapSourceRegion({
    required this.name,
    required this.url,
    required this.minLat,
    required this.minLng,
    required this.maxLat,
    required this.maxLng,
    required this.minZoom,
    required this.maxZoom,
    this.isBase = false,
  });

  /// Diagnostic name (e.g. `'lusaka'`, `'base'`).
  final String name;

  /// Absolute archive URL (typically `https://maps.churchonapp.com/...`).
  final String url;

  final double minLat;
  final double minLng;
  final double maxLat;
  final double maxLng;

  /// Inclusive lowest/highest zoom this archive is built for. Past [maxZoom]
  /// the layer over-zooms (raster) — see `VectorTileLayer.maximumZoom`.
  final int minZoom;
  final int maxZoom;

  /// The fallback source: world bbox, used when nothing else matches.
  final bool isBase;

  bool contains(double lat, double lng) =>
      lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;

  /// Zoom range the archive covers. The `+ 1` lets a source whose max is 15
  /// still serve the z16 boundary frame while a city file takes over at 16.
  bool acceptsZoom(double zoom) => zoom >= minZoom && zoom <= maxZoom + 1;

  /// Square degrees — smaller wins when several regions match.
  double get area => (maxLat - minLat) * (maxLng - minLng);

  @override
  String toString() =>
      'MapSourceRegion($name z$minZoom-$maxZoom [$minLat,$minLng,$maxLat,$maxLng])';
}

/// World extent of the base source.
const double _worldSouth = -90;
const double _worldWest = -180;
const double _worldNorth = 90;
const double _worldEast = 180;

/// Zimbabwe country extent — used when `MAPS_ZIMBABWE_URL` is a separate
/// archive (older deployments). The current regional archive already covers it,
/// so this is skipped when the URL matches the primary.
const MapSourceRegion _zimbabweRegion = MapSourceRegion(
  name: 'zimbabwe',
  url: '',
  minLat: -22.42,
  minLng: 25.24,
  maxLat: -15.61,
  maxLng: 33.07,
  minZoom: 0,
  maxZoom: 15,
);

/// Builds the source table the basemap switches between.
///
/// * [primaryUrl] — base archive (`MAPS_ZAMBIA_URL`). Required; empty means no
///   vector basemap.
/// * [zimbabweUrl] — `MAPS_ZIMBABWE_URL`; skipped when empty or equal to
///   [primaryUrl].
/// * [extraJson] — raw `MAPS_EXTRA_SOURCES`: a JSON array of
///   `{"name": "...", "bbox": [south, west, north, east], "minZoom": n,
///   "maxZoom": n, "url": "..."}`. `min_zoom`/`max_zoom`/`minzoom`/`maxzoom`
///   accepted as aliases; entries with a missing/non-numeric field are dropped
///   with a `debugPrint` so a typo can never blank the map.
///
/// Duplicate URLs collapse onto their first entry, so `_providerCache` never
/// opens the same archive twice under different names.
List<MapSourceRegion> buildMapSourceTable({
  required String primaryUrl,
  String zimbabweUrl = '',
  String? extraJson,
  int baseMaxZoom = 15,
}) {
  final base = primaryUrl.trim();
  final out = <MapSourceRegion>[];
  final seen = <String>{};

  if (base.isNotEmpty) {
    out.add(MapSourceRegion(
      name: 'base',
      url: base,
      minLat: _worldSouth,
      minLng: _worldWest,
      maxLat: _worldNorth,
      maxLng: _worldEast,
      minZoom: 0,
      maxZoom: baseMaxZoom,
      isBase: true,
    ));
    seen.add(base);
  }

  final zim = zimbabweUrl.trim();
  if (zim.isNotEmpty && zim != base && seen.add(zim)) {
    out.add(MapSourceRegion(
      name: _zimbabweRegion.name,
      url: zim,
      minLat: _zimbabweRegion.minLat,
      minLng: _zimbabweRegion.minLng,
      maxLat: _zimbabweRegion.maxLat,
      maxLng: _zimbabweRegion.maxLng,
      minZoom: _zimbabweRegion.minZoom,
      maxZoom: _zimbabweRegion.maxZoom,
    ));
  }

  out.addAll(_parseExtraSources(extraJson, seen));
  return out;
}

List<MapSourceRegion> _parseExtraSources(String? json, Set<String> seen) {
  if (json == null || json.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) {
      debugPrint('[map-sources] MAPS_EXTRA_SOURCES is not a JSON array');
      return const [];
    }
    final out = <MapSourceRegion>[];
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final name = '${map['name'] ?? map['id'] ?? ''}'.trim();
      final url = '${map['url'] ?? ''}'.trim();
      final bbox = map['bbox'] ?? map['bounds'];
      if (name.isEmpty || url.isEmpty) {
        debugPrint('[map-sources] skipping entry without name/url: $raw');
        continue;
      }
      if (bbox is! List || bbox.length != 4) {
        debugPrint('[map-sources] "$name": bbox must be [s,w,n,e]');
        continue;
      }
      double at(int i) {
        final v = bbox[i];
        if (v is num) return v.toDouble();
        return double.tryParse('$v') ?? double.nan;
      }

      final south = at(0), west = at(1), north = at(2), east = at(3);
      if (![south, west, north, east].every((v) => v.isFinite)) {
        debugPrint('[map-sources] "$name": non-numeric bbox $bbox');
        continue;
      }
      if (south > north || west > east) {
        debugPrint('[map-sources] "$name": inverted bbox $bbox');
        continue;
      }
      if (!seen.add(url)) continue;
      out.add(MapSourceRegion(
        name: name,
        url: url,
        minLat: south,
        minLng: west,
        maxLat: north,
        maxLng: east,
        minZoom: _intOr(map, const ['minZoom', 'min_zoom', 'minzoom'], 13)
            .clamp(0, 22),
        maxZoom: _intOr(map, const ['maxZoom', 'max_zoom', 'maxzoom'], 19)
            .clamp(0, 22),
      ));
    }
    return out;
  } catch (e) {
    debugPrint('[map-sources] failed to parse MAPS_EXTRA_SOURCES: $e');
    return const [];
  }
}

int _intOr(Map<String, dynamic> map, List<String> keys, int fallback) {
  for (final k in keys) {
    final v = map[k];
    if (v == null) continue;
    final n = v is num ? v.toInt() : int.tryParse('$v');
    if (n != null) return n;
  }
  return fallback;
}

/// Picks the source for [center] at [zoom].
///
/// 1. Regions whose bbox contains the centre **and** whose zoom range covers
///    [zoom], smallest bbox first (a city beats its country).
/// 2. The base source (world bbox) — always matches when configured.
/// 3. `null` when the table is empty (no archive configured).
MapSourceRegion? resolveMapSource(
  List<MapSourceRegion> table,
  MapLatLng center,
  double zoom,
) {
  MapSourceRegion? best;
  for (final r in table) {
    if (!r.contains(center.latitude, center.longitude)) continue;
    if (!r.acceptsZoom(zoom)) continue;
    if (best == null || r.area < best.area) best = r;
  }
  if (best != null) return best;
  for (final r in table) {
    if (r.isBase) return r;
  }
  return table.isEmpty ? null : table.first;
}

/// Plain lat/lng pair so the resolver has no `latlong2` dependency.
class MapLatLng {
  const MapLatLng(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}
