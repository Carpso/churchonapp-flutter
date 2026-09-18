import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/remote_config.dart';

/// Traffic severity for a segment.
enum TrafficLevel { slow, medium, fast }

/// A short (~200 m) aggregated traffic segment.
///
/// [points] is deliberately a coarse, grid-snapped two-point line: no driver
/// identity is ever carried and positions are coarsened so an individual GPS
/// trail cannot be reconstructed from the overlay.
class TrafficSegment {
  final List<LatLng> points;
  final double avgSpeedKmh;
  final TrafficLevel level;
  final int sampleCount;

  const TrafficSegment({
    required this.points,
    required this.avgSpeedKmh,
    required this.level,
    this.sampleCount = 1,
  });

  LatLng get midpoint => points.length >= 2
      ? LatLng(
          (points.first.latitude + points.last.latitude) / 2,
          (points.first.longitude + points.last.longitude) / 2,
        )
      : points.first;
}

/// Bounding box for a visible map view (Dart record ⇒ value equality, so it is
/// safe as a Riverpod family key).
typedef TrafficBounds = ({
  double minLat,
  double maxLat,
  double minLng,
  double maxLng,
});

/// Crowd-sourced live traffic derived ONLY from data we own: recent
/// `driver_locations` GPS heartbeats (with speed) from the last 15 minutes.
///
/// Each heartbeat is classified against a free-flow baseline
/// (`ride_avg_city_speed_kmh` remote config, default 25 km/h) and snapped to a
/// ~200 m grid so callers get anonymous, coarse speed segments. No driver id is
/// selected from the database and no identity is exposed.
class TrafficService {
  TrafficService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// ~200 m at the equator (1° latitude ≈ 111 km).
  static const double cellDegrees = 0.0018;

  static const Duration _window = Duration(minutes: 15);
  static const int _maxRows = 500;

  Future<List<TrafficSegment>> fetchSegments(
    TrafficBounds bounds, {
    double baselineKmh = 25,
  }) async {
    final baseline = baselineKmh > 0 ? baselineKmh : 25.0;
    try {
      final since = DateTime.now()
          .toUtc()
          .subtract(_window)
          .toIso8601String();
      final rows = await _client
          .from('driver_locations')
          // NOTE: deliberately NO driver_id — only aggregate speed data.
          .select('lat,lng,speed,updated_at')
          .gte('updated_at', since)
          .gte('lat', bounds.minLat)
          .lte('lat', bounds.maxLat)
          .gte('lng', bounds.minLng)
          .lte('lng', bounds.maxLng)
          .limit(_maxRows);
      return buildSegments(
        rows
            .map((r) => (r as Map).cast<String, dynamic>())
            .toList(growable: false),
        baseline,
      );
    } catch (e) {
      debugPrint('traffic: fetch failed (non-fatal): $e');
      return const [];
    }
  }

  /// Pure grouping logic (unit-testable): snap heartbeats to a ~200 m grid,
  /// derive each cell's average speed, then link adjacent cells into short
  /// segments. Cells without a speed sample are dropped (never guess).
  static List<TrafficSegment> buildSegments(
    List<Map<String, dynamic>> rows,
    double baselineKmh,
  ) {
    if (rows.isEmpty) return const [];
    final baseline = baselineKmh > 0 ? baselineKmh : 25.0;

    final cells = <String, _TrafficCell>{};
    for (final r in rows) {
      final lat = (r['lat'] as num?)?.toDouble();
      final lng = (r['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final gy = (lat / cellDegrees).floor();
      final gx = (lng / cellDegrees).floor();
      final key = '$gy:$gx';
      cells.putIfAbsent(key, () => _TrafficCell(gy, gx)).add(
            (r['speed'] as num?)?.toDouble(),
          );
    }
    final usable = cells.values.where((c) => c.hasSpeed).toList();
    if (usable.isEmpty) return const [];

    const neighbours = [(1, 0), (0, 1)];
    final segments = <TrafficSegment>[];
    for (final cell in usable) {
      for (final n in neighbours) {
        final nb = cells['${cell.gy + n.$1}:${cell.gx + n.$2}'];
        if (nb == null || !nb.hasSpeed) continue;
        final a = _level(cell.avgSpeed, baseline);
        final b = _level(nb.avgSpeed, baseline);
        segments.add(TrafficSegment(
          points: [cell.centre, nb.centre],
          avgSpeedKmh: (cell.avgSpeed + nb.avgSpeed) / 2,
          level: _severity(a) >= _severity(b) ? a : b,
          sampleCount: cell.count + nb.count,
        ));
      }
    }

    // Isolated cells still get a short stub so a lone heartbeat is visible.
    for (final cell in usable) {
      final linked = neighbours.any((n) {
        final p = cells['${cell.gy + n.$1}:${cell.gx + n.$2}'];
        final m = cells['${cell.gy - n.$1}:${cell.gx - n.$2}'];
        return (p?.hasSpeed ?? false) || (m?.hasSpeed ?? false);
      });
      if (linked) continue;
      final c = cell.centre;
      segments.add(TrafficSegment(
        points: [c, LatLng(c.latitude, c.longitude + cellDegrees * 0.6)],
        avgSpeedKmh: cell.avgSpeed,
        level: _level(cell.avgSpeed, baseline),
        sampleCount: cell.count,
      ));
    }
    return segments;
  }

  static TrafficLevel _level(double speedKmh, double baseline) {
    final ratio = speedKmh / baseline;
    if (ratio < 0.45) return TrafficLevel.slow;
    if (ratio < 0.80) return TrafficLevel.medium;
    return TrafficLevel.fast;
  }

  static int _severity(TrafficLevel level) {
    switch (level) {
      case TrafficLevel.slow:
        return 2;
      case TrafficLevel.medium:
        return 1;
      case TrafficLevel.fast:
        return 0;
    }
  }
}

class _TrafficCell {
  final int gy;
  final int gx;
  double _speedSum = 0;
  int _speedCount = 0;
  int count = 0;

  _TrafficCell(this.gy, this.gx);

  void add(double? speedKmh) {
    count++;
    if (speedKmh != null && speedKmh.isFinite && speedKmh >= 0) {
      _speedSum += speedKmh;
      _speedCount++;
    }
  }

  bool get hasSpeed => _speedCount > 0;

  double get avgSpeed => _speedCount == 0 ? 0 : _speedSum / _speedCount;

  /// Grid-snapped centre (coarsened ~200 m) — never the raw GPS point.
  LatLng get centre => LatLng(
        (gy + 0.5) * TrafficService.cellDegrees,
        (gx + 0.5) * TrafficService.cellDegrees,
      );
}

/// Aggregated traffic for the visible bounds. Baseline comes from remote config
/// (`ride_avg_city_speed_kmh`, default 25 km/h).
final trafficOverlayProvider =
    FutureProvider.family<List<TrafficSegment>, TrafficBounds>((ref, bounds) {
  final baseline =
      currentRemoteConfig(ref).getDouble('ride_avg_city_speed_kmh', 25);
  return TrafficService().fetchSegments(bounds, baselineKmh: baseline);
});
