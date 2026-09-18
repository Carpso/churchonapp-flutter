import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:church_on_app/core/config/env.dart';

/// A single turn-by-turn maneuver parsed from an OSRM route step.
///
/// [type]/[modifier] mirror OSRM's maneuver vocabulary (`turn` + `left`,
/// `roundabout` + `exit`, `arrive`, ...). [geometry] is the step's own
/// LineString so a navigation controller can locate the maneuver.
class RouteStep {
  final String type;
  final String? modifier;
  final String? name;
  final String? ref;
  final double distanceMetres;
  final int durationSeconds;
  final List<LatLng> geometry;
  final String mode;
  final double? bearingBefore;
  final double? bearingAfter;
  final int? exitNumber;

  const RouteStep({
    required this.type,
    this.modifier,
    this.name,
    this.ref,
    required this.distanceMetres,
    required this.durationSeconds,
    this.geometry = const [],
    this.mode = 'driving',
    this.bearingBefore,
    this.bearingAfter,
    this.exitNumber,
  });

  /// Best available road label for instruction text (name, else ref).
  String? get roadLabel {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final r = ref?.trim();
    if (r != null && r.isNotEmpty) return r;
    return null;
  }

  LatLng? get startPoint => geometry.isNotEmpty ? geometry.first : null;
  LatLng? get endPoint => geometry.isNotEmpty ? geometry.last : null;
}

class RouteResult {
  final List<LatLng> points;
  final double distanceMetres;
  final int durationSeconds;
  final List<RouteStep> steps;

  /// True when OSRM could not be reached and this is a straight-line estimate.
  /// The UI must NEVER present fake guidance for a fallback route.
  final bool isFallback;

  const RouteResult({
    required this.points,
    required this.distanceMetres,
    required this.durationSeconds,
    this.steps = const [],
    this.isFallback = false,
  });

  /// Whether real turn-by-turn maneuvers are available.
  bool get hasGuidance => !isFallback && steps.isNotEmpty;

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

/// Fetches a real turn-by-turn road route (OSRM) between two points, including
/// per-maneuver steps, and returns the geometry as a polyline. Falls back to a
/// straight line when routing is unavailable so the map never breaks — the
/// fallback is marked [RouteResult.isFallback] so callers can disable guidance.
///
/// The endpoint is configurable via `OSRM_BASE_URL` (see [Env.osrmBaseUrl]) —
/// switch to a self-hosted OSRM/Valhalla instance before volume grows, since
/// the public demo server is rate-limited.
class RouteService {
  static String get _osrmBase => Env.osrmBaseUrl;

  /// [via] adds a mandatory waypoint between [from] and [to] (e.g. driver →
  /// pickup → destination), so the maneuvers stay accurate across phases.
  static Future<RouteResult> fetchRoute({
    required LatLng from,
    required LatLng to,
    LatLng? via,
  }) async {
    try {
      final coords = via == null
          ? '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
          : '${from.longitude},${from.latitude};'
              '${via.longitude},${via.latitude};'
              '${to.longitude},${to.latitude}';
      final uri = Uri.parse(
        '$_osrmBase/$coords'
        '?overview=full&geometries=geojson&steps=true&annotations=true',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return _straightLine(from, to, via);

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return _straightLine(from, to, via);
      final route = routes.first as Map<String, dynamic>;
      final points = _parseLineString(route['geometry'] as Map?);
      if (points.isEmpty) return _straightLine(from, to, via);

      final dist = (route['distance'] as num?)?.toDouble() ?? 0.0;
      final dur = (route['duration'] as num?)?.toInt() ?? 0;
      final steps = _parseSteps(route['legs'] as List?);

      return RouteResult(
        points: points,
        distanceMetres: dist,
        durationSeconds: dur,
        steps: steps,
      );
    } catch (e) {
      debugPrint('RouteService: OSRM failed, using straight line: $e');
      return _straightLine(from, to, via);
    }
  }

  /// Parse a GeoJSON LineString geometry into LatLng points.
  static List<LatLng> _parseLineString(Map? geometry) {
    if (geometry == null) return const [];
    final coords = geometry['coordinates'] as List?;
    if (coords == null || coords.isEmpty) return const [];
    final out = <LatLng>[];
    for (final c in coords) {
      if (c is! List || c.length < 2) continue;
      final lon = (c[0] as num?)?.toDouble();
      final lat = (c[1] as num?)?.toDouble();
      if (lon == null || lat == null) continue;
      out.add(LatLng(lat, lon));
    }
    return out;
  }

  /// Parse OSRM `legs[].steps[]` into typed [RouteStep]s, skipping malformed
  /// entries rather than throwing.
  static List<RouteStep> _parseSteps(List? legs) {
    if (legs == null) return const [];
    final steps = <RouteStep>[];
    for (final leg in legs) {
      if (leg is! Map) continue;
      final legSteps = leg['steps'] as List?;
      if (legSteps == null) continue;
      for (final raw in legSteps) {
        if (raw is! Map) continue;
        final maneuver = raw['maneuver'];
        final man = maneuver is Map ? maneuver : const <String, dynamic>{};
        steps.add(RouteStep(
          type: (man['type'] as String?) ?? 'continue',
          modifier: man['modifier'] as String?,
          name: raw['name'] as String?,
          ref: raw['ref'] as String?,
          distanceMetres: (raw['distance'] as num?)?.toDouble() ?? 0.0,
          durationSeconds:
              ((raw['duration'] as num?)?.toDouble() ?? 0.0).round(),
          geometry: _parseLineString(raw['geometry'] as Map?),
          mode: (raw['mode'] as String?) ?? 'driving',
          bearingBefore: (man['bearing_before'] as num?)?.toDouble(),
          bearingAfter: (man['bearing_after'] as num?)?.toDouble(),
          exitNumber: (man['exit'] as num?)?.toInt(),
        ));
      }
    }
    return steps;
  }

  static RouteResult _straightLine(LatLng from, LatLng to, [LatLng? via]) {
    final pts = via == null ? [from, to] : [from, via, to];
    double dist = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      dist += const Distance()(pts[i], pts[i + 1]);
    }
    // Rough ETA at 25 km/h city speed — never presented as real guidance.
    final dur = (dist / 25 * 3600).round();
    return RouteResult(
      points: pts,
      distanceMetres: dist,
      durationSeconds: dur,
      isFallback: true,
    );
  }
}
