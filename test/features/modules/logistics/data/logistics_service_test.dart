import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_on_app/features/modules/logistics/data/logistics_service.dart';
import '../../../../test_mocks.dart';

/// WHY THESE TESTS LOOK THE WAY THEY DO
///
///   This file previously asserted that a failed query returns hard-coded
///   Lusaka fixtures (`Bus #4`, `bus-1`, canned traffic/parking/routes). That
///   was the behaviour that made the Logistics screens show invented buses and
///   parking in cities that have none — data that looked real but was not.
///
///   The 2026-08-18 Logistics Command rewrite removed the fixtures: these
///   getters now read the real `church_buses` / `traffic_alerts` /
///   `parking_zones` / `quick_routes` tables and return an EMPTY list on
///   failure. Showing nothing is correct; showing a fabricated bus is not.
///
///   So the contract asserted here is: real rows are mapped through, and a
///   failure yields an empty list rather than invented data. `empty means
///   unknown` is now a guarantee, not an accident.
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
    test('returns an empty list when the query fails (no fixtures)', () async {
      when(() => mockClient.from('church_buses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(10)).thenThrow(Exception('db error'));

      final buses = await service.getBuses();

      expect(
        buses,
        isEmpty,
        reason: 'A failed query must not surface invented buses.',
      );
    });

    test('does not serve a stale offline cache of removed fixtures', () async {
      SharedPreferences.setMockInitialValues({
        'logistics_buses': '[{"id":"bus-1","name":"Bus #4"}]',
      });
      when(() => mockClient.from('church_buses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(10)).thenThrow(Exception('offline'));

      final buses = await service.getBuses();

      expect(
        buses,
        isEmpty,
        reason: 'The SharedPreferences fixture cache was removed on purpose; '
            'a seeded cache must not resurrect deleted fake data.',
      );
    });
  });

  group('getTrafficAlerts', () {
    test('returns an empty list when the query fails (no fixtures)', () async {
      when(() => mockClient.from('traffic_alerts'))
          .thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order(any(), ascending: any(named: 'ascending')))
          .thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(any())).thenThrow(Exception('db error'));

      expect(await service.getTrafficAlerts(), isEmpty);
    });
  });

  group('getParkingZones', () {
    test('returns an empty list when the query fails (no fixtures)', () async {
      when(() => mockClient.from('parking_zones')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(any())).thenThrow(Exception('db error'));

      expect(await service.getParkingZones(), isEmpty);
    });
  });

  group('getQuickRoutes', () {
    test('returns an empty list when the query fails (no fixtures)', () async {
      when(() => mockClient.from('quick_routes')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(any())).thenThrow(Exception('db error'));

      expect(await service.getQuickRoutes(), isEmpty);
    });
  });
}
