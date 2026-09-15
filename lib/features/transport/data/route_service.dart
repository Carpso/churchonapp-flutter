import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:church_on_app/core/config/env.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceMetres;
  final int durationSeconds;

  const RouteResult({
    required this.points,
    required this.distanceMetres,
    required this.durationSeconds,
  });

  String get etaText {
    final m = durationSeconds ~/ 60;
    if (m < 1) return 'Arriving now';
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final rem = m % 60;
    return '$h hr ${rem > 0 ? '$rem min' : ''}'.trim();
  }

  String get distanceText {
    if (distanceMetres < 1000) return '${distanceMetres.round()} m';
    return '${(distanceMetres / 1000).toStringAsFixed(1)} km';
  }
}

/// Fetches a real turn-by-turn road route (OSRM) between two points and returns
/// the geometry as a polyline. Falls back to a straight line when routing is
/// unavailable so the map never breaks.
///
/// The endpoint is configurable via `OSRM_BASE_URL` (see [Env.osrmBaseUrl]) —
/// switch to a self-hosted OSRM/Valhalla instance before volume grows, since
/// the public demo server is rate-limited.
class RouteService {
  static String get _osrmBase => Env.osrmBaseUrl;

  static Future<RouteResult> fetchRoute({
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
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final coords = geometry?['coordinates'] as List?;
      if (coords == null || coords.isEmpty) return _straightLine(from, to);

      final points = coords
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      final dist = (route['distance'] as num?)?.toDouble() ?? 0.0;
      final dur = (route['duration'] as num?)?.toInt() ?? 0;

      return RouteResult(points: points, distanceMetres: dist, durationSeconds: dur);
    } catch (e) {
      debugPrint('RouteService: OSRM failed, using straight line: $e');
      return _straightLine(from, to);
    }
  }

  static RouteResult _straightLine(LatLng from, LatLng to) {
    final dist = Distance()(from, to);
    final dur = (dist / 25 * 3600).round(); // rough ETA at 25 km/h city speed
    return RouteResult(points: [from, to], distanceMetres: dist, durationSeconds: dur);
  }
}