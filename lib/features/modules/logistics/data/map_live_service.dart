import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'map_live_models.dart';

/// Live map + streaming audience data.
///
/// EVERY method returns real data or an honest empty list. The previous
/// `LogisticsService` substituted hardcoded Lusaka fixtures (a bus on Cairo Rd,
/// "Heavy traffic", four fake parking zones) whenever a query came back empty,
/// so the map looked populated while showing fiction. That is gone —
/// [trafficSourceNote] tells the UI to explain WHY a layer is empty.
class MapLiveService {
  MapLiveService(this._client);

  final SupabaseClient _client;

  // ── Stream audience ──────────────────────────────────────────────────────

  /// Who is watching right now, and how many. The studio uses the full list;
  /// the viewer asks for the count only.
  Future<StreamAudience> getStreamAudience(
    String streamId, {
    bool includeWatchers = true,
  }) async {
    try {
      final res = await _client.rpc('get_stream_audience', params: {
        'p_stream_id': streamId,
        'p_include_watchers': includeWatchers,
      });
      return StreamAudience.fromJson(
          (res as Map<String, dynamic>?) ?? const {});
    } catch (e) {
      debugPrint('getStreamAudience failed: $e');
      return StreamAudience.empty;
    }
  }

  // ── Buses ────────────────────────────────────────────────────────────────

  Future<List<LiveBus>> getLiveBuses(String tenantId) async {
    if (tenantId.isEmpty) return const [];
    try {
      final res = await _client.rpc('get_live_bus_positions', params: {
        'p_tenant_id': tenantId,
      });
      return ((res as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(LiveBus.fromJson)
          .toList();
    } catch (e) {
      debugPrint('getLiveBuses failed: $e');
      return const [];
    }
  }

  /// Post a GPS heartbeat for a bus and mirror it onto the bus row so any
  /// client still reading `church_buses` sees the newest position too.
  Future<void> reportBusPosition({
    required String busId,
    required String tenantId,
    required double lat,
    required double lng,
    double? heading,
    double? speedKmh,
  }) async {
    final me = _client.auth.currentUser?.id;
    await _client.from('bus_locations').insert({
      'bus_id': busId,
      'tenant_id': tenantId,
      'lat': lat,
      'lng': lng,
      if (heading != null) 'heading': heading,
      if (speedKmh != null) 'speed_kmh': speedKmh,
      'recorded_by': me,
    });
    // Best-effort mirror; a failure here must not break the heartbeat.
    try {
      await _client.from('church_buses').update({
        'current_lat': lat,
        'current_lng': lng,
        if (heading != null) 'heading': heading,
        if (speedKmh != null) 'speed_kmh': speedKmh,
        'last_ping_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', busId);
    } catch (e) {
      debugPrint('bus mirror failed (non-fatal): $e');
    }
    // Housekeeping: keep only the recent history per bus.
    try {
      await _client
          .rpc('prune_bus_locations', params: {'p_bus_id': busId});
    } catch (_) {
      // optional; a growing table is not fatal
    }
  }

  // ── Traffic ──────────────────────────────────────────────────────────────

  /// Crowd-sourced road conditions around a point. Cells with fewer than two
  /// recent samples come back `unknown`, never "clear".
  Future<List<MapTrafficSegment>> getTrafficSegments(
    LatLng center, {
    double radiusDeg = 0.02,
    int minutes = 30,
  }) async {
    try {
      final res = await _client.rpc('get_traffic_segments', params: {
        'p_lat': center.latitude,
        'p_lng': center.longitude,
        'p_radius_deg': radiusDeg,
        'p_minutes': minutes,
      });
      return ((res as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(MapTrafficSegment.fromJson)
          .toList();
    } catch (e) {
      debugPrint('getTrafficSegments failed: $e');
      return const [];
    }
  }

  Future<List<TrafficIncident>> getIncidents(String tenantId) async {
    if (tenantId.isEmpty) return const [];
    try {
      final res = await _client
          .from('traffic_alerts')
          .select('id, road, description, status, severity, lat, lng,'
              ' radius_m, created_at')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false)
          .limit(50);
      return (res as List)
          .map((e) => TrafficIncident.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('getIncidents failed: $e');
      return const [];
    }
  }

  /// Report an incident — the human half of crowd-sourced traffic: our drivers
  /// contribute speed, our members contribute eyes.
  Future<void> reportIncident({
    required String tenantId,
    required String road,
    required String description,
    required String severity,
    double? lat,
    double? lng,
  }) async {
    await _client.from('traffic_alerts').insert({
      'tenant_id': tenantId,
      'road': road,
      'description': description,
      'severity': severity,
      'status': 'Reported',
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'reported_by': _client.auth.currentUser?.id,
      'expires_at':
          DateTime.now().add(const Duration(hours: 6)).toIso8601String(),
    });
  }

  /// Contribute our own GPS speed to the traffic model. Any signed-in driver,
  /// rider or bus feeds the next person's map.
  Future<void> contributeTrafficSample({
    required double lat,
    required double lng,
    required double speedKmh,
    String source = 'driver',
    double? heading,
    String? tenantId,
  }) async {
    try {
      await _client.from('traffic_samples').insert({
        'lat': lat,
        'lng': lng,
        'speed_kmh': speedKmh,
        'source': source,
        if (heading != null) 'heading': heading,
        if (tenantId != null) 'tenant_id': tenantId,
      });
    } catch (e) {
      debugPrint('traffic sample failed (non-fatal): $e');
    }
  }

  // ── Parking ──────────────────────────────────────────────────────────────

  Future<List<ParkingArea>> getParking(String tenantId) async {
    if (tenantId.isEmpty) return const [];
    try {
      final res = await _client
          .from('parking_zones')
          .select('id, name, available, total, lat, lng, zone_type,'
              ' fee_kwacha, updated_at')
          .eq('tenant_id', tenantId)
          .limit(100);
      return (res as List)
          .map((e) => ParkingArea.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('getParking failed: $e');
      return const [];
    }
  }

  Future<void> reportParking({
    required String tenantId,
    required String name,
    required int available,
    required int total,
    double? lat,
    double? lng,
    String? zoneType,
  }) async {
    await _client.from('parking_zones').upsert({
      'tenant_id': tenantId,
      'name': name,
      'available': available,
      'total': total,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (zoneType != null) 'zone_type': zoneType,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ── Quick routes ─────────────────────────────────────────────────────────

  Future<List<SavedQuickRoute>> getQuickRoutes(String tenantId) async {
    if (tenantId.isEmpty) return const [];
    try {
      final res = await _client
          .from('quick_routes')
          .select('id, title, time, via, icon, from_lat, from_lng, from_label,'
              ' to_lat, to_lng, to_label, sort_order')
          .eq('tenant_id', tenantId)
          .order('sort_order')
          .limit(50);
      return (res as List)
          .map((e) => SavedQuickRoute.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('getQuickRoutes failed: $e');
      return const [];
    }
  }

  Future<void> saveQuickRoute({
    required String tenantId,
    required String title,
    required LatLng from,
    required LatLng to,
    String? fromLabel,
    String? toLabel,
    String? via,
    String iconName = 'home',
  }) async {
    await _client.from('quick_routes').insert({
      'tenant_id': tenantId,
      'title': title,
      'from_lat': from.latitude,
      'from_lng': from.longitude,
      'to_lat': to.latitude,
      'to_lng': to.longitude,
      if (fromLabel != null) 'from_label': fromLabel,
      if (toLabel != null) 'to_label': toLabel,
      if (via != null) 'via': via,
      'icon': iconName,
      'created_by': _client.auth.currentUser?.id,
    });
  }

  /// Traffic is crowd-sourced, not a purchased feed. Surfaced in the UI so
  /// nobody mistakes "no data" for "clear roads".
  static const bool isCrowdSourced = true;
  static const String trafficSourceNote =
      'Traffic is crowd-sourced from Church On App drivers, riders and buses. '
      'Roads with no recent reports are shown as UNKNOWN, never as clear.';
}

final mapLiveServiceProvider =
    Provider<MapLiveService>((ref) => MapLiveService(Supabase.instance.client));

// ── Providers (top-level so any screen can watch / invalidate them) ─────────

/// Studio audience: count AND who is watching.
final streamAudienceProvider =
    FutureProvider.autoDispose.family<StreamAudience, String>((ref, streamId) {
  return ref.watch(mapLiveServiceProvider).getStreamAudience(streamId);
});

/// Count only — cheap enough for the viewer to poll every ~15 seconds.
final viewerCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, streamId) async {
  final a = await ref
      .watch(mapLiveServiceProvider)
      .getStreamAudience(streamId, includeWatchers: false);
  return a.viewersNow;
});

final liveBusesProvider =
    FutureProvider.autoDispose.family<List<LiveBus>, String>((ref, tenantId) {
  return ref.watch(mapLiveServiceProvider).getLiveBuses(tenantId);
});

final trafficSegmentsProvider =
    FutureProvider.autoDispose.family<List<MapTrafficSegment>, LatLng>(
        (ref, center) {
  return ref.watch(mapLiveServiceProvider).getTrafficSegments(center);
});

final incidentsProvider =
    FutureProvider.autoDispose.family<List<TrafficIncident>, String>(
        (ref, tenantId) {
  return ref.watch(mapLiveServiceProvider).getIncidents(tenantId);
});

final parkingProvider =
    FutureProvider.autoDispose.family<List<ParkingArea>, String>(
        (ref, tenantId) {
  return ref.watch(mapLiveServiceProvider).getParking(tenantId);
});

final quickRoutesProvider =
    FutureProvider.autoDispose.family<List<SavedQuickRoute>, String>(
        (ref, tenantId) {
  return ref.watch(mapLiveServiceProvider).getQuickRoutes(tenantId);
});
