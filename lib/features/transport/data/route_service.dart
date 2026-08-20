import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Fetches a real turn-by-turn road route (OSRM demo server, free, no key)
/// between two points and returns the geometry as a polyline. Falls back to a
/// straight line when routing is unavailable so the map never breaks.
class RouteService {
  static const _osrmBase =
      'https://router.project-osrm.org/route/v1/driving';

  static Future<List<LatLng>> fetchRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    try {
      final uri = Uri.parse(
        '$_osrmBase/${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson&steps=false',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return _straightLine(from, to);

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return _straightLine(from, to);
      final geometry = (routes.first as Map<String, dynamic>)['geometry']
          as Map<String, dynamic>?;
      final coords = geometry?['coordinates'] as List?;
      if (coords == null || coords.isEmpty) return _straightLine(from, to);

      return coords
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
    } catch (e) {
      debugPrint('RouteService: OSRM failed, using straight line: $e');
      return _straightLine(from, to);
    }
  }

  static List<LatLng> _straightLine(LatLng from, LatLng to) => [from, to];
}