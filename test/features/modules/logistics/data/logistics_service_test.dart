import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_on_app/features/modules/logistics/data/logistics_service.dart';
import 'package:church_on_app/features/modules/logistics/data/logistics_model.dart';
import '../../../../test_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSupabaseClient mockClient;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late LogisticsService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    service = LogisticsService(mockClient);
    SharedPreferences.setMockInitialValues({});

    const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'check') {
        return ['none'];
      }
      return null;
    });
  });

  group('getBuses', () {
    test('returns default buses when supabase fails', () async {
      when(() => mockClient.from('church_buses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(10)).thenThrow(Exception('db error'));

      final buses = await service.getBuses();
      expect(buses.length, 1);
      expect(buses.first.name, 'Bus #4');
    });

    // NOTE: the SharedPreferences offline cache ('logistics_buses') was
    // removed in the 2026-08-18 Logistics Command rewrite on the real
    // `church_buses` table. Failure now falls straight to curated defaults.
    test('falls back to defaults on failure (no stale cache)', () async {
      when(() => mockClient.from('church_buses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(10)).thenThrow(Exception('offline'));

      final buses = await service.getBuses();
      expect(buses, isNotEmpty);
      expect(buses.first.id, 'bus-1');
    });

    test('default buses have valid structure', () async {
      when(() => mockClient.from('church_buses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(10)).thenThrow(Exception('error'));

      final buses = await service.getBuses();
      expect(buses.first.id, isNotEmpty);
      expect(buses.first.route, isNotEmpty);
      expect(buses.first.eta, isNotEmpty);
    });
  });

  group('getTrafficAlerts', () {
    test('returns default traffic alerts when supabase fails', () async {
      when(() => mockClient.from('traffic_alerts')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(20)).thenThrow(Exception('error'));

      final alerts = await service.getTrafficAlerts();
      expect(alerts.length, 3);
      expect(alerts.first.road, 'Cairo Rd');
    });

    // Offline cache removed — see getBuses note above.
    test('defaults cover severity tiers', () async {
      when(() => mockClient.from('traffic_alerts')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(20)).thenThrow(Exception('error'));

      final alerts = await service.getTrafficAlerts();
      final severities = alerts.map((a) => a.severity).toSet();
      expect(severities, containsAll(['high', 'medium', 'low']));
    });
  });

  group('getParkingZones', () {
    test('returns default parking zones when supabase fails', () async {
      when(() => mockClient.from('parking_zones')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(20)).thenThrow(Exception('error'));

      final zones = await service.getParkingZones();
      expect(zones.length, 4);
      expect(zones.first.name, 'Zone A - Main Church');
    });

    test('parking zone status is correctly computed', () {
      final fullZone = ParkingZone(name: 'Full', available: 0, total: 10);
      expect(fullZone.status, 'FULL');
      expect(fullZone.isFull, true);

      final lowZone = ParkingZone(name: 'Low', available: 3, total: 10);
      expect(lowZone.status, 'LOW');
      expect(lowZone.isLow, true);

      final openZone = ParkingZone(name: 'Open', available: 8, total: 10);
      expect(openZone.status, 'OPEN');
    });
  });

  group('getQuickRoutes', () {
    test('returns default routes when supabase fails', () async {
      when(() => mockClient.from('quick_routes')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(20)).thenThrow(Exception('error'));

      final routes = await service.getQuickRoutes();
      expect(routes.length, 3);
      expect(routes.first.title, 'Home → Church');
    });

    // Offline cache removed — see getBuses note above.
    test('default routes carry icon names for UI mapping', () async {
      when(() => mockClient.from('quick_routes')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(20)).thenThrow(Exception('error'));

      final routes = await service.getQuickRoutes();
      expect(routes.every((r) => r.iconName.isNotEmpty), isTrue);
    });
  });
}
