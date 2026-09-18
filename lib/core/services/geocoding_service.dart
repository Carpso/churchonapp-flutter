import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GeoPoint {
  final double lat;
  final double lng;
  final String label;
  const GeoPoint({required this.lat, required this.lng, required this.label});
}

/// Address ⇄ coordinate lookup with a FALLBACK CHAIN and a local cache.
///
/// Why: the app previously called OpenStreetMap **Nominatim** directly from
/// every client. Nominatim's usage policy forbids heavy application traffic and
/// has no SLA, so at volume address search silently starts failing (or the
/// provider blocks the app). This service:
///   1. serves repeated queries from a 7-day local cache (no network),
///   2. tries Nominatim,
///   3. falls back to Photon (`photon.komoot.io`) when Nominatim is slow/blocked.
///
/// For production scale, self-host Photon/Nominatim (or use a paid provider)
/// and set `GEOCODING_BASE_URL` — see AGENTS.md.
class GeocodingService {
  static const _cacheKey = 'geocode_cache_v2';
  static const _ttl = Duration(days: 7);

  /// Optional self-hosted / paid forward-geocoding endpoint. When set it is
  /// tried FIRST. Expected response: Nominatim-compatible JSON array.
  static const String _overrideBase = String.fromEnvironment('GEOCODING_BASE_URL');

  static Future<GeoPoint?> forward(String query) async {
    final q = query.trim();
    if (q.isEmpty) return null;

    final cached = await _readCache(q);
    if (cached != null) return cached;

    GeoPoint? hit;
    if (_overrideBase.isNotEmpty) {
      hit = await _nominatimLike(_overrideBase, q);
    }
    hit ??= await _nominatimLike(
        'https://nominatim.openstreetmap.org', q, withCountry: 'Zambia');
    hit ??= await _photon(q);

    if (hit != null) await _writeCache(q, hit);
    return hit;
  }

  /// Reverse geocode a coordinate into a human place NAME (not "lat,lng").
  ///
  /// The `geocoding` plugin needs a Google API key on web, so reverse lookups
  /// silently fell back to raw coordinates there. Fallback chain:
  /// cache → self-hosted (if set) → Nominatim → Photon.
  static Future<String?> reverse(double lat, double lng) async {
    final key = 'rev:${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    final cached = await _readCache(key);
    if (cached != null && cached.label.trim().isNotEmpty) return cached.label;

    String? label;
    if (_overrideBase.isNotEmpty) {
      label = await _nominatimReverse(_overrideBase, lat, lng);
    }
    label ??=
        await _nominatimReverse('https://nominatim.openstreetmap.org', lat, lng);
    label ??= await _photonReverse(lat, lng);

    if (label != null && label.trim().isNotEmpty) {
      await _writeCache(key, GeoPoint(lat: lat, lng: lng, label: label));
      return label;
    }
    return null;
  }

  static const _ua = 'ChurchOnApp/1.0 (churchonapp.com)';

  static Future<String?> _nominatimReverse(
      String base, double lat, double lng) async {
    try {
      final uri = Uri.https(base, '/reverse', {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'format': 'jsonv2',
        'addressdetails': '1',
        'zoom': '18',
      });
      final res = await http.get(uri, headers: {'User-Agent': _ua}).timeout(
            const Duration(seconds: 8),
          );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! Map) return null;
      final addr = data['address'];
      if (addr is Map) {
        final parts = <String>[
          for (final k in ['amenity', 'building', 'shop', 'road', 'suburb', 'city', 'town'])
            if ((addr[k]?.toString().trim().isNotEmpty ?? false))
              addr[k].toString().trim(),
        ];
        if (parts.isNotEmpty) return parts.take(3).join(', ');
      }
      final display = data['display_name']?.toString();
      if (display != null && display.isNotEmpty) {
        return display.split(',').take(3).join(',').trim();
      }
    } catch (e) {
      debugPrint('geocoding reverse failed: $e');
    }
    return null;
  }

  static Future<String?> _photonReverse(double lat, double lng) async {
    try {
      final uri = Uri.https('photon.komoot.io', '/reverse', {
        'lat': lat.toString(),
        'lon': lng.toString(),
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final features = data['features'];
      if (features is List && features.isNotEmpty) {
        final props = (features.first as Map)['properties'];
        if (props is Map) {
          final parts = <String>[
            for (final k in ['name', 'street', 'city'])
              if ((props[k]?.toString().trim().isNotEmpty ?? false))
                props[k].toString().trim(),
          ];
          if (parts.isNotEmpty) return parts.take(3).join(', ');
        }
      }
    } catch (e) {
      debugPrint('photon reverse failed: $e');
    }
    return null;
  }

  /// Nominatim-shaped `/search` endpoint.
  static Future<GeoPoint?> _nominatimLike(String base, String q,
      {String? withCountry}) async {
    try {
      final uri = Uri.https(base, '/search', {
        'q': withCountry != null ? '$q, $withCountry' : q,
        'format': 'json',
        'limit': '1',
      });
      final res = await http.get(uri, headers: {
        'User-Agent': 'ChurchOnApp/1.0 (church management app)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      if (data is! List || data.isEmpty) return null;
      final first = data.first as Map<String, dynamic>;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lng = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lng == null) return null;
      return GeoPoint(
        lat: lat,
        lng: lng,
        label: first['display_name']?.toString() ?? q,
      );
    } catch (e) {
      debugPrint('GeocodingService: $base failed (non-fatal): $e');
      return null;
    }
  }

  /// Photon (Komoot) fallback — different response shape.
  static Future<GeoPoint?> _photon(String q) async {
    try {
      final uri = Uri.parse(
          'https://photon.komoot.io/api/?q=${Uri.encodeQueryComponent(q)}&limit=1');
      final res = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final features = body['features'] as List?;
      if (features == null || features.isEmpty) return null;
      final f = features.first as Map<String, dynamic>;
      final geom = f['geometry'] as Map<String, dynamic>?;
      final coords = geom?['coordinates'] as List?;
      if (coords == null || coords.length < 2) return null;
      final props = (f['properties'] as Map?)?.cast<String, dynamic>() ?? {};
      final name = [props['name'], props['city'], props['country']]
          .where((s) => s != null && s.toString().trim().isNotEmpty)
          .join(', ');
      return GeoPoint(
        lat: (coords[1] as num).toDouble(),
        lng: (coords[0] as num).toDouble(),
        label: name.isEmpty ? q : name,
      );
    } catch (e) {
      debugPrint('GeocodingService: photon failed (non-fatal): $e');
      return null;
    }
  }

  static Future<GeoPoint?> _readCache(String q) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final entry = map[q.toLowerCase()] as Map<String, dynamic>?;
      if (entry == null) return null;
      final at = DateTime.tryParse(entry['at']?.toString() ?? '');
      if (at == null || DateTime.now().difference(at) > _ttl) return null;
      return GeoPoint(
        lat: (entry['lat'] as num).toDouble(),
        lng: (entry['lng'] as num).toDouble(),
        label: entry['label']?.toString() ?? q,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(String q, GeoPoint p) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      final map = (raw == null || raw.isEmpty)
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      map[q.toLowerCase()] = {
        'lat': p.lat,
        'lng': p.lng,
        'label': p.label,
        'at': DateTime.now().toIso8601String(),
      };
      // Keep the cache bounded.
      if (map.length > 200) {
        final keys = map.keys.take(map.length - 200).toList();
        for (final k in keys) {
          map.remove(k);
        }
      }
      await prefs.setString(_cacheKey, jsonEncode(map));
    } catch (_) {}
  }
}
