import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/features/modules/logistics/presentation/providers/weather_provider.dart';
import 'package:church_on_app/features/modules/logistics/data/logistics_service.dart';
import 'package:church_on_app/features/modules/logistics/data/logistics_model.dart';
import 'package:church_on_app/features/modules/logistics/data/weather_service.dart';
import 'package:mocktail/mocktail.dart';

class MockLogisticsService extends Mock implements LogisticsService {}

class MockWeatherService extends Mock implements WeatherService {}

void main() {
  late MockLogisticsService mockLogisticsService;
  // ignore: unused_local_variable
  late MockWeatherService mockWeatherService;

  setUp(() {
    mockLogisticsService = MockLogisticsService();
    mockWeatherService = MockWeatherService();
  });

  test('busesProvider fetches and returns bus list', () async {
    when(() => mockLogisticsService.getBuses()).thenAnswer((_) async => [
          BusInfo(id: '1', name: 'Bus 1', route: 'Route A', eta: '5 min', nextStop: 'Stop 1'),
        ]);

    final container = ProviderContainer(
      overrides: [
        logisticsServiceProvider.overrideWith((ref) => mockLogisticsService),
      ],
    );
    final buses = await container.read(busesProvider.future);
    expect(buses.length, 1);
    expect(buses.first.name, 'Bus 1');
    container.dispose();
  });

  test('trafficAlertsProvider returns alerts', () async {
    when(() => mockLogisticsService.getTrafficAlerts()).thenAnswer((_) async => [
          TrafficAlert(road: 'Great East Road', description: 'Accident near town', status: 'active', severity: 'high'),
        ]);

    final container = ProviderContainer(
      overrides: [
        logisticsServiceProvider.overrideWith((ref) => mockLogisticsService),
      ],
    );
    final alerts = await container.read(trafficAlertsProvider.future);
    expect(alerts.length, 1);
    expect(alerts.first.road, contains('Great East'));
    container.dispose();
  });

  test('parkingZonesProvider returns zones', () async {
    when(() => mockLogisticsService.getParkingZones()).thenAnswer((_) async => [
          ParkingZone(name: 'Zone A', available: 20, total: 50),
        ]);

    final container = ProviderContainer(
      overrides: [
        logisticsServiceProvider.overrideWith((ref) => mockLogisticsService),
      ],
    );
    final zones = await container.read(parkingZonesProvider.future);
    expect(zones.length, 1);
    expect(zones.first.name, 'Zone A');
    container.dispose();
  });

  test('quickRoutesProvider returns routes', () async {
    when(() => mockLogisticsService.getQuickRoutes()).thenAnswer((_) async => [
          QuickRoute(title: 'Route 1', time: '15 min', via: 'Main Road'),
        ]);

    final container = ProviderContainer(
      overrides: [
        logisticsServiceProvider.overrideWith((ref) => mockLogisticsService),
      ],
    );
    final routes = await container.read(quickRoutesProvider.future);
    expect(routes.length, 1);
    expect(routes.first.title, 'Route 1');
    container.dispose();
  });
}
