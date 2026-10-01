import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a map-growth point came from. The source is stored on every row so the
/// data can be weighted, audited, and deleted per-category if a user revokes
/// consent for one kind of collection.
enum MapGrowthSource {
  ride('ride'),
  delivery('delivery'),
  navigation('navigation'),
  placeReport('place_report'),
  pinSave('pin_save');

  const MapGrowthSource(this.wire);
  final String wire;
}

/// Records the user's OWN movement so the map improves as real usage is
/// observed, and reads back the aggregate heatmap for enrichment.
///
/// SCOPE — READ THIS BEFORE EXTENDING
///   This collects **only** movement the user performs *inside Church On App*:
///   Carpso rides and deliveries, in-app navigation, and places they explicitly
///   report or save. It records nothing about any other app.
///
///   It is NOT possible to collect a user's Yango / InDrive / Google Maps
///   location history: no API exposes another app's location data, and doing so
///   without consent would be both a privacy and a legal violation. If that
///   integration is ever wanted, the only legitimate route is a partnership API
///   plus explicit opt-in from the user.
///
///   `map_growth_samples` deliberately has NO client SELECT policy. The raw
///   trail is written by the user and readable only by the server; the client
///   sees the aggregated [heatMap] instead.
class MapGrowthService {
  static const _table = 'map_growth_samples';

  SupabaseClient get _client => Supabase.instance.client;

  /// Records one point. Fire-and-forget: map enrichment must never interfere
  /// with a ride or a turn-by-turn instruction, so a failure here is logged and
  /// dropped rather than surfaced to the user.
  Future<void> record({
    required double lat,
    required double lng,
    required MapGrowthSource source,
    double? speedKph,
    double? headingDeg,
    int? trafficLevel,
    String? tenantId,
  }) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;

      // Reject nonsense before it reaches the database (the table has CHECK
      // constraints, but a bad point would then throw a whole batch away).
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return;
      if (!lat.isFinite || !lng.isFinite) return;

      final now = DateTime.now();
      await _client.from(_table).insert({
        'user_id': uid,
        'tenant_id': tenantId,
        'lat': lat,
        'lng': lng,
        'source': source.wire,
        'speed_kph': speedKph,
        'heading_deg': headingDeg,
        'traffic_level': trafficLevel,
        'captured_local_date':
            '${now.year.toString().padLeft(4, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}',
      });
    } catch (e) {
      debugPrint('[MapGrowth] record failed (non-fatal): $e');
    }
  }

  /// Records a short breadcrumb trail with one call.
  ///
  /// Points are thinned to at most one per `minGapMeters` so a long drive does
  /// not write thousands of near-identical rows.
  Future<void> recordTrail({
    required List<({double lat, double lng, double? speedKph})> points,
    required MapGrowthSource source,
    String? tenantId,
    int minGapMeters = 40,
  }) async {
    if (points.length < 2) return;
    final kept = <({double lat, double lng, double? speedKph})>[];
    var last = points.first;
    for (final p in points.skip(1)) {
      if (_metersBetween(last.lat, last.lng, p.lat, p.lng) >= minGapMeters) {
        kept.add(p);
        last = p;
      }
    }
    for (final p in kept) {
      await record(
        lat: p.lat,
        lng: p.lng,
        speedKph: p.speedKph,
        source: source,
        tenantId: tenantId,
      );
    }
  }

  /// Aggregated corridors for map enrichment (never a raw trail).
  Future<List<MapGrowthCell>> heatMap({
    String? tenantId,
    int days = 30,
  }) async {
    try {
      final res = await _client.rpc('get_map_growth_heatmap', params: {
        'p_tenant_id': tenantId,
        'p_days': days,
      });
      if (res is! List) return const [];
      return res
          .whereType<Map>()
          .map((m) => MapGrowthCell(
                lat: (m['lat'] as num?)?.toDouble() ?? 0,
                lng: (m['lng'] as num?)?.toDouble() ?? 0,
                samples: (m['samples'] as num?)?.toInt() ?? 0,
                avgSpeedKph: (m['avg_speed_kph'] as num?)?.toDouble(),
              ))
          .where((c) => c.lat != 0 && c.lng != 0)
          .toList();
    } catch (e) {
      debugPrint('[MapGrowth] heatMap failed: $e');
      return const [];
    }
  }

  /// Great-circle distance in metres (haversine).
  static double _metersBetween(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        (math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.pow(math.sin(dLng / 2), 2));
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * 3.141592653589793 / 180.0;
}

class MapGrowthCell {
  const MapGrowthCell({
    required this.lat,
    required this.lng,
    required this.samples,
    this.avgSpeedKph,
  });

  final double lat;
  final double lng;
  final int samples;
  final double? avgSpeedKph;
}
