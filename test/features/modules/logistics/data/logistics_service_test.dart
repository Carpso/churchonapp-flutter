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

    test('returns cached buses when offline', () async {
      SharedPreferences.setMockInitialValues({
        'logistics_buses': '[{"id":"c1","name":"Cached Bus","route":"Route A","eta":"5 mins","nextStop":"Stop 1"}]',
      });
      final buses = await service.getBuses();
      expect(buses.length, 1);
      expect(buses.first.name, 'Cached Bus');
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

    test('returns cached traffic alerts when offline', () async {
      SharedPreferences.setMockInitialValues({
        'logistics_traffic': '[{"road":"Test Rd","description":"Clear","status":"Clear","severity":"low"}]',
      });
      final alerts = await service.getTrafficAlerts();
      expect(alerts.length, 1);
      expect(alerts.first.road, 'Test Rd');
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

    test('returns cached routes when offline', () async {
      SharedPreferences.setMockInitialValues({
        'logistics_routes': '[{"title":"Test Route","time":"10 min","via":"Via Main Rd","iconName":"home"}]',
      });
      final routes = await service.getQuickRoutes();
      expect(routes.length, 1);
      expect(routes.first.title, 'Test Route');
    });
  });
}
