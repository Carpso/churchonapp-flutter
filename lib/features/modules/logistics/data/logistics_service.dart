import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'logistics_model.dart';

class LogisticsService {
  final SupabaseClient _client;

  LogisticsService(this._client);

  Future<List<BusInfo>> getBuses() async {
    try {
      final data = await _client.from('church_buses').select().limit(10);
      if (data.isNotEmpty) {
        return data.map((b) {
          final stopsRaw = (b['stops'] as List?)?.map((s) {
            final sp = s as Map<String, dynamic>;
            return BusStop(
              name: sp['name']?.toString() ?? 'Stop',
              position: LatLng(
                (sp['lat'] as num?)?.toDouble() ?? -15.385,
                (sp['lng'] as num?)?.toDouble() ?? 28.320,
              ),
            );
          }).toList() ?? [];
          final pathRaw = (b['path'] as List?)?.map((p) {
            final pp = p as Map<String, dynamic>;
            return LatLng(
              (pp['lat'] as num?)?.toDouble() ?? -15.385,
              (pp['lng'] as num?)?.toDouble() ?? 28.320,
            );
          }).toList() ?? [];

          return BusInfo(
            id: b['id']?.toString() ?? '',
            name: b['name']?.toString() ?? 'Bus',
            route: b['route']?.toString() ?? '',
            eta: b['eta']?.toString() ?? '--',
            nextStop: b['next_stop']?.toString() ?? '--',
            stops: stopsRaw,
            path: pathRaw,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Failed to fetch buses, using defaults: $e');
    }
    return _defaultBuses();
  }

  List<BusInfo> _defaultBuses() => [
    BusInfo(
      id: 'bus-1',
      name: 'Bus #4',
      route: 'Great East Road',
      eta: '2 mins',
      nextStop: 'Stop B',
      stops: [
        BusStop(name: 'Stop A', position: const LatLng(-15.3850, 28.3200)),
        BusStop(name: 'Stop B', position: const LatLng(-15.3900, 28.3250)),
        BusStop(name: 'Stop C', position: const LatLng(-15.3950, 28.3300)),
      ],
      path: [
        const LatLng(-15.3850, 28.3200),
        const LatLng(-15.3870, 28.3220),
        const LatLng(-15.3900, 28.3250),
        const LatLng(-15.3930, 28.3280),
        const LatLng(-15.3950, 28.3300),
      ],
    ),
  ];

  Future<List<TrafficAlert>> getTrafficAlerts() async {
    try {
      final data = await _client.from('traffic_alerts').select().limit(20);
      if (data.isNotEmpty) {
        return data.map((t) => TrafficAlert(
          road: t['road']?.toString() ?? '',
          description: t['description']?.toString() ?? '',
          status: t['status']?.toString() ?? 'Moderate',
          severity: t['severity']?.toString() ?? 'medium',
        )).toList();
      }
    } catch (e) {
      debugPrint('Failed to fetch traffic alerts, using defaults: $e');
    }
    return _defaultTrafficAlerts();
  }

  List<TrafficAlert> _defaultTrafficAlerts() => [
    TrafficAlert(road: 'Cairo Rd', description: 'Cairo Road: Heavy traffic — Use Los Angeles Blvd', status: 'Heavy', severity: 'high'),
    TrafficAlert(road: 'Great East', description: 'Great East Road: Moderate — Expect 10 min delay', status: 'Moderate', severity: 'medium'),
    TrafficAlert(road: 'Kafue Rd', description: 'Kafue Road: Clear — All lanes open', status: 'Clear', severity: 'low'),
  ];

  Future<List<ParkingZone>> getParkingZones() async {
    try {
      final data = await _client.from('parking_zones').select().limit(20);
      if (data.isNotEmpty) {
        return data.map((p) => ParkingZone(
          name: p['name']?.toString() ?? '',
          available: (p['available'] as num?)?.toInt() ?? 0,
          total: (p['total'] as num?)?.toInt() ?? 0,
        )).toList();
      }
    } catch (e) {
      debugPrint('Failed to fetch parking zones, using defaults: $e');
    }
    return _defaultParkingZones();
  }

  List<ParkingZone> _defaultParkingZones() => [
    ParkingZone(name: 'Zone A - Main Church', available: 12, total: 50),
    ParkingZone(name: 'Zone B - Overflow', available: 35, total: 40),
    ParkingZone(name: 'Zone C - VIP/Pastoral', available: 2, total: 10),
    ParkingZone(name: 'Zone D - Street Parking', available: 0, total: 20),
  ];

  Future<List<QuickRoute>> getQuickRoutes() async {
    try {
      final data = await _client.from('quick_routes').select().limit(20);
      if (data.isNotEmpty) {
        return data.map((r) => QuickRoute(
          title: r['title']?.toString() ?? '',
          time: r['time']?.toString() ?? '',
          via: r['via']?.toString() ?? '',
          iconName: r['icon']?.toString() ?? 'home',
        )).toList();
      }
    } catch (e) {
      debugPrint('Failed to fetch quick routes, using defaults: $e');
    }
    return _defaultQuickRoutes();
  }

  List<QuickRoute> _defaultQuickRoutes() => [
    QuickRoute(title: 'Home → Church', time: '12 min', via: 'Via Great East Rd', iconName: 'home'),
    QuickRoute(title: 'Church → Mall', time: '8 min', via: 'Via Addis Ababa Dr', iconName: 'shoppingBag'),
    QuickRoute(title: 'Church → Airport', time: '25 min', via: 'Via Airport Rd', iconName: 'plane'),
  ];
}
