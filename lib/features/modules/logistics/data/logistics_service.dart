import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'logistics_model.dart';

/// Static fleet/road data for a church.
///
/// IMPORTANT — this used to return HARDCODED Lusaka fixtures (a bus on Great
/// East Road, "Cairo Rd: Heavy traffic", four invented parking zones) any
/// time a query came back empty. That made the map look populated while
/// showing fiction, which is worse than an empty map. Every method now returns
/// an honest empty list and logs why. Live positions come from
/// `MapLiveService` / `get_live_bus_positions`.
class LogisticsService {
  final SupabaseClient _client;

  LogisticsService(this._client);

  Future<List<BusInfo>> getBuses({String? tenantId}) async {
    if (tenantId != null && tenantId.isNotEmpty) {
      try {
        final data = await _client
            .from('church_buses')
            .select()
            .eq('tenant_id', tenantId)
            .limit(50);
        if (data.isNotEmpty) return _mapBuses(data);
      } catch (e) {
        debugPrint('getBuses failed (returning empty, no fixtures): $e');
      }
    } else {
      // Platform-wide view (COA / superadmin).
      try {
        final data = await _client.from('church_buses').select().limit(50);
        if (data.isNotEmpty) return _mapBuses(data);
      } catch (e) {
        debugPrint('getBuses failed (returning empty, no fixtures): $e');
      }
    }
    return const [];
  }

  List<BusInfo> _mapBuses(List data) => data.map((b) {
        final stopsRaw = (b['stops'] as List?)?.map((s) {
          final sp = s as Map<String, dynamic>;
          return BusStop(
            name: sp['name']?.toString() ?? 'Stop',
            position: LatLng(
              (sp['lat'] as num?)?.toDouble() ?? 0,
              (sp['lng'] as num?)?.toDouble() ?? 0,
            ),
          );
        }).toList() ??
            const <BusStop>[];
        final pathRaw = (b['path'] as List?)?.map((p) {
          final pp = p as Map<String, dynamic>;
          return LatLng(
            (pp['lat'] as num?)?.toDouble() ?? 0,
            (pp['lng'] as num?)?.toDouble() ?? 0,
          );
        }).toList() ??
            const <LatLng>[];
        final currentLat = (b['current_lat'] as num?)?.toDouble();
        final currentLng = (b['current_lng'] as num?)?.toDouble();

        return BusInfo(
          id: b['id']?.toString() ?? '',
          name: b['name']?.toString() ?? 'Bus',
          route: b['route']?.toString() ?? '',
          eta: b['eta']?.toString() ?? '--',
          nextStop: b['next_stop']?.toString() ?? '--',
          stops: stopsRaw,
          path: pathRaw,
          currentPosition: (currentLat != null && currentLng != null)
              ? LatLng(currentLat, currentLng)
              : null,
          lastUpdatedAt: b['updated_at'] != null
              ? DateTime.tryParse(b['updated_at'].toString())
              : null,
          driverName: b['driver_name']?.toString(),
          driverPhone: b['driver_phone']?.toString(),
        );
      }).toList();

  Future<List<TrafficAlert>> getTrafficAlerts() async {
    try {
      final data = await _client
          .from('traffic_alerts')
          .select('road, description, status, severity')
          .order('created_at', ascending: false)
          .limit(20);
      if (data.isNotEmpty) {
        return data
            .map((t) => TrafficAlert(
                  road: t['road']?.toString() ?? '',
                  description: t['description']?.toString() ?? '',
                  status: t['status']?.toString() ?? 'Reported',
                  severity: t['severity']?.toString() ?? 'low',
                ))
            .toList();
      }
    } catch (e) {
      debugPrint('getTrafficAlerts failed (returning empty, no fixtures): $e');
    }
    return const [];
  }

  Future<List<ParkingZone>> getParkingZones() async {
    try {
      final data = await _client
          .from('parking_zones')
          .select('name, available, total')
          .limit(20);
      if (data.isNotEmpty) {
        return data
            .map((p) => ParkingZone(
                  name: p['name']?.toString() ?? '',
                  available: (p['available'] as num?)?.toInt() ?? 0,
                  total: (p['total'] as num?)?.toInt() ?? 0,
                ))
            .toList();
      }
    } catch (e) {
      debugPrint('getParkingZones failed (returning empty, no fixtures): $e');
    }
    return const [];
  }

  Future<List<QuickRoute>> getQuickRoutes() async {
    try {
      final data = await _client
          .from('quick_routes')
          .select('title, time, via, icon')
          .limit(20);
      if (data.isNotEmpty) {
        return data
            .map((r) => QuickRoute(
                  title: r['title']?.toString() ?? '',
                  time: r['time']?.toString() ?? '',
                  via: r['via']?.toString() ?? '',
                  iconName: r['icon']?.toString() ?? 'home',
                ))
            .toList();
      }
    } catch (e) {
      debugPrint('getQuickRoutes failed (returning empty, no fixtures): $e');
    }
    return const [];
  }
}
