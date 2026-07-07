import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/weather_service.dart';
import '../../data/weather_model.dart';
import '../../data/logistics_service.dart';
import '../../data/logistics_model.dart';

final weatherServiceProvider = Provider<WeatherService>((ref) => WeatherService());

final logisticsServiceProvider = Provider<LogisticsService>((ref) => LogisticsService(Supabase.instance.client));

final weatherDataProvider = FutureProvider.autoDispose<WeatherData>((ref) async {
  final service = ref.watch(weatherServiceProvider);
  return service.fetchWeather();
});

final busesProvider = FutureProvider.autoDispose<List<BusInfo>>((ref) async {
  final service = ref.watch(logisticsServiceProvider);
  return service.getBuses();
});

final trafficAlertsProvider = FutureProvider.autoDispose<List<TrafficAlert>>((ref) async {
  final service = ref.watch(logisticsServiceProvider);
  return service.getTrafficAlerts();
});

final parkingZonesProvider = FutureProvider.autoDispose<List<ParkingZone>>((ref) async {
  final service = ref.watch(logisticsServiceProvider);
  return service.getParkingZones();
});

final quickRoutesProvider = FutureProvider.autoDispose<List<QuickRoute>>((ref) async {
  final service = ref.watch(logisticsServiceProvider);
  return service.getQuickRoutes();
});

class WeatherRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state++;
}

final weatherRefreshProvider = NotifierProvider<WeatherRefreshNotifier, int>(WeatherRefreshNotifier.new);

final refreshableWeatherProvider = FutureProvider.autoDispose<WeatherData>((ref) async {
  ref.watch(weatherRefreshProvider);
  final service = ref.watch(weatherServiceProvider);
  return service.fetchWeather();
});

final refreshableBusesProvider = FutureProvider.autoDispose<List<BusInfo>>((ref) async {
  ref.watch(weatherRefreshProvider);
  final service = ref.watch(logisticsServiceProvider);
  return service.getBuses();
});

final refreshableTrafficAlertsProvider = FutureProvider.autoDispose<List<TrafficAlert>>((ref) async {
  ref.watch(weatherRefreshProvider);
  final service = ref.watch(logisticsServiceProvider);
  return service.getTrafficAlerts();
});

final refreshableParkingZonesProvider = FutureProvider.autoDispose<List<ParkingZone>>((ref) async {
  ref.watch(weatherRefreshProvider);
  final service = ref.watch(logisticsServiceProvider);
  return service.getParkingZones();
});

final refreshableQuickRoutesProvider = FutureProvider.autoDispose<List<QuickRoute>>((ref) async {
  ref.watch(weatherRefreshProvider);
  final service = ref.watch(logisticsServiceProvider);
  return service.getQuickRoutes();
});
