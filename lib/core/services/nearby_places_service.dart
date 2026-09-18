import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OSM categories the "Nearby" panel can search for.
enum NearbyCategory {
  fuel('fuel', 'Fuel'),
  restaurant('restaurant', 'Restaurant'),
  cafe('cafe', 'Cafe'),
  bank('bank', 'Bank / ATM'),
  hospital('hospital', 'Hospital / Pharmacy'),
  supermarket('supermarket', 'Supermarket / Shop'),
  hotel('hotel', 'Hotel'),
  church('church', 'Church'),
  police('police', 'Police'),
  busStation('bus_station', 'Bus stop'),
  parking('parking', 'Parking');

  final String key;
  final String label;

  const NearbyCategory(this.key, this.label);

  static NearbyCategory? fromKey(String? k) {
    if (k == null) return null;
    for (final c in NearbyCategory.values) {
      if (c.key == k) return c;
    }
    return null;
  }
}

/// A single nearby place returned by the Overpass search.
class NearbyPlace {
  final String id;
  final String name;
  final NearbyCategory category;
  final double lat;
  final double lng;
  final String? address;
  final double distanceKm;

  const NearbyPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    this.address,
    required this.distanceKm,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.key,
        'lat': lat,
        'lng': lng,
        'address': address,
        'distance_km': distanceKm,
      };

  factory NearbyPlace.fromJson(Map<String, dynamic> j) => NearbyPlace(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        category:
            NearbyCategory.fromKey(j['category']?.toString()) ?? NearbyCategory.restaurant,
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
        address: j['address']?.toString(),
        distanceKm: (j['distance_km'] as num?)?.toDouble() ?? 0,
      );
}

/// "Nearby places" search built on the OpenStreetMap Overpass API.
///
/// Why Overpass (and not the basemap): the self-hosted Protomaps basemap only
/// carries POIs that survive its low-zoom generalisation, and its sprite has a
/// limited icon set. Overpass gives the full OSM amenity/shop/tourism database
/// (fuel, banks, pharmacies, hotels, police...) for any radius, which the map
/// then renders as first-class markers.
///
/// Resilience: results are cached locally for 24 h, a bounded 8 s timeout is
/// applied to every request, and a mirrored fallback endpoint is used when the
/// primary host is slow/blocked — so a search can never hang the UI.
class NearbyPlacesService {
  NearbyPlacesService({http.Client? client}) : _http = client;

  final http.Client? _http;

  static const List<String> _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  static const Duration _timeout = Duration(seconds: 8);
  static const String _ua = 'ChurchOnApp/1.0 (churchonapp.com)';

  static const String _cacheKey = 'nearby_places_cache_v1';
  static const Duration _ttl = Duration(hours: 24);
  static const int _maxCacheEntries = 30;

  /// Overpass clauses per category.
  static const Map<NearbyCategory, List<String>> _clauses = {
    NearbyCategory.fuel: [r'nwr["amenity"="fuel"]'],
    NearbyCategory.restaurant: [r'nwr["amenity"="restaurant"]'],
    NearbyCategory.cafe: [r'nwr["amenity"="cafe"]'],
    NearbyCategory.bank: [r'nwr["amenity"~"^(bank|atm)$"]'],
    NearbyCategory.hospital: [
      r'nwr["amenity"~"^(hospital|clinic|doctors|pharmacy)$"]'
    ],
    NearbyCategory.supermarket: [
      r'nwr["shop"~"^(supermarket|convenience|greengrocer|bakery|butcher|general|grocery)$"]'
    ],
    NearbyCategory.hotel: [r'nwr["tourism"~"^(hotel|guest_house|hostel|motel)$"]'],
    NearbyCategory.church: [r'nwr["amenity"="place_of_worship"]'],
    NearbyCategory.police: [r'nwr["amenity"="police"]'],
    NearbyCategory.busStation: [
      r'nwr["highway"="bus_stop"]',
      r'nwr["amenity"="bus_station"]'
    ],
    NearbyCategory.parking: [r'nwr["amenity"="parking"]'],
  };

  /// Builds the Overpass QL query. Exposed for tests/inspection.
  static String buildQuery({
    required double lat,
    required double lng,
    required double radiusMeters,
    NearbyCategory? category,
    int limit = 80,
  }) {
    final cats = category == null ? NearbyCategory.values : [category];
    final around =
        '${radiusMeters.round()},${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    final parts = <String>[];
    for (final c in cats) {
      for (final clause in _clauses[c]!) {
        parts.add('$clause(around:$around);');
      }
    }
    return '[out:json][timeout:8];(${parts.join()});out center $limit;';
  }

  /// Searches around [lat]/[lng]; returns places sorted by distance.
  Future<List<NearbyPlace>> search({
    required double lat,
    required double lng,
    double radiusMeters = 2000,
    NearbyCategory? category,
  }) async {
    final cacheKey = _cacheKeyFor(lat, lng, radiusMeters, category);
    final cached = await _readCache(cacheKey);
    if (cached != null) return cached;

    final query = buildQuery(
      lat: lat,
      lng: lng,
      radiusMeters: radiusMeters,
      category: category,
    );

    for (final endpoint in _endpoints) {
      final body = await _post(endpoint, query);
      if (body == null) continue;
      final places = _parse(body, lat, lng, category);
      if (places.isNotEmpty) {
        await _writeCache(cacheKey, places);
        return places;
      }
      // A valid but empty response is still worth caching.
      await _writeCache(cacheKey, const []);
      return const [];
    }
    return const [];
  }

  Future<String?> _post(String endpoint, String query) async {
    try {
      final client = _http ?? http.Client();
      try {
        final res = await client
            .post(
              Uri.parse(endpoint),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'User-Agent': _ua,
                'Accept': 'application/json',
              },
              body: {'data': query},
            )
            .timeout(_timeout);
        if (res.statusCode != 200) return null;
        return res.body;
      } finally {
        if (_http == null) client.close();
      }
    } catch (e) {
      debugPrint('nearby_places: $endpoint failed (non-fatal): $e');
      return null;
    }
  }

  static List<NearbyPlace> _parse(
    String body,
    double originLat,
    double originLng,
    NearbyCategory? requested,
  ) {
    final out = <NearbyPlace>[];
    try {
      final decoded = jsonDecode(body);
      final elements =
          (decoded is Map ? decoded['elements'] : null) as List? ?? const [];
      for (final raw in elements) {
        if (raw is! Map) continue;
        final tags = (raw['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
        final center = raw['center'];
        final lat = (raw['lat'] as num?)?.toDouble() ??
            (center is Map ? (center['lat'] as num?)?.toDouble() : null);
        final lng = (raw['lon'] as num?)?.toDouble() ??
            (center is Map ? (center['lon'] as num?)?.toDouble() : null);
        if (lat == null || lng == null) continue;

        final name =
            (tags['name:en'] ?? tags['name'])?.toString().trim() ?? '';
        if (name.isEmpty) continue; // unnamed POIs are not useful to a user

        final category = _classify(tags) ?? requested;
        if (category == null) continue;

        out.add(NearbyPlace(
          id: '${raw['type'] ?? 'node'}/${raw['id'] ?? ''}',
          name: name,
          category: category,
          lat: lat,
          lng: lng,
          address: _address(tags),
          distanceKm: const Distance().as(
            LengthUnit.Kilometer,
            LatLng(originLat, originLng),
            LatLng(lat, lng),
          ),
        ));
      }
    } catch (e) {
      debugPrint('nearby_places: parse failed (non-fatal): $e');
      return const [];
    }
    out.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return out;
  }

  static NearbyCategory? _classify(Map<String, dynamic> tags) {
    final amenity = tags['amenity']?.toString();
    final shop = tags['shop']?.toString();
    final tourism = tags['tourism']?.toString();
    final highway = tags['highway']?.toString();

    if (amenity == 'fuel') return NearbyCategory.fuel;
    if (amenity == 'restaurant') return NearbyCategory.restaurant;
    if (amenity == 'cafe') return NearbyCategory.cafe;
    if (amenity == 'bank' || amenity == 'atm') return NearbyCategory.bank;
    if (amenity == 'hospital' ||
        amenity == 'clinic' ||
        amenity == 'doctors' ||
        amenity == 'pharmacy') {
      return NearbyCategory.hospital;
    }
    if (amenity == 'place_of_worship') return NearbyCategory.church;
    if (amenity == 'police') return NearbyCategory.police;
    if (amenity == 'bus_station' || highway == 'bus_stop') {
      return NearbyCategory.busStation;
    }
    if (amenity == 'parking') return NearbyCategory.parking;
    if (tourism == 'hotel' ||
        tourism == 'guest_house' ||
        tourism == 'hostel' ||
        tourism == 'motel') {
      return NearbyCategory.hotel;
    }
    if (shop != null && shop.isNotEmpty) return NearbyCategory.supermarket;
    return null;
  }

  static String? _address(Map<String, dynamic> tags) {
    final parts = <String>[];
    final house = tags['addr:housenumber']?.toString().trim();
    final street = tags['addr:street']?.toString().trim();
    if (street != null && street.isNotEmpty) {
      parts.add([if (house != null && house.isNotEmpty) house, street].join(' '));
    }
    final suburb = tags['addr:suburb']?.toString().trim();
    if (suburb != null && suburb.isNotEmpty) parts.add(suburb);
    final city = tags['addr:city']?.toString().trim();
    if (city != null && city.isNotEmpty) parts.add(city);
    return parts.isEmpty ? null : parts.join(', ');
  }

  static String _cacheKeyFor(
    double lat,
    double lng,
    double radiusMeters,
    NearbyCategory? category,
  ) =>
      '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)},'
      '${radiusMeters.round()},${category?.key ?? 'all'}';

  static Future<List<NearbyPlace>?> _readCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final entry = map[key] as Map<String, dynamic>?;
      if (entry == null) return null;
      final at = DateTime.tryParse(entry['at']?.toString() ?? '');
      if (at == null || DateTime.now().difference(at) > _ttl) return null;
      final list = (entry['places'] as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((e) => NearbyPlace.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(
      String key, List<NearbyPlace> places) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      final map = (raw == null || raw.isEmpty)
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      map[key] = {
        'at': DateTime.now().toIso8601String(),
        'places': places.map((p) => p.toJson()).toList(),
      };
      if (map.length > _maxCacheEntries) {
        final keys = map.keys.take(map.length - _maxCacheEntries).toList();
        for (final k in keys) {
          map.remove(k);
        }
      }
      await prefs.setString(_cacheKey, jsonEncode(map));
    } catch (_) {}
  }
}

/// Family key: a Dart record (structural equality) so the same query reuses
/// one instance — never key a family with a Map/List (see AGENTS.md).
typedef NearbySearch = ({
  double lat,
  double lng,
  double radiusMeters,
  NearbyCategory? category,
});

final nearbyPlacesProvider =
    FutureProvider.family<List<NearbyPlace>, NearbySearch>((ref, q) async {
  return NearbyPlacesService().search(
    lat: q.lat,
    lng: q.lng,
    radiusMeters: q.radiusMeters,
    category: q.category,
  );
});
