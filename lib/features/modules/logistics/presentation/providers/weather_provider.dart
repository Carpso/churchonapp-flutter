import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/weather_service.dart';
import '../../data/weather_model.dart';
import '../../data/logistics_service.dart';
import '../../data/logistics_model.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

final weatherServiceProvider = Provider<WeatherService>((ref) => WeatherService());

final logisticsServiceProvider = Provider<LogisticsService>((ref) => LogisticsService(Supabase.instance.client));

class SelectedCityNotifier extends Notifier<CityPreset> {
  @override
  CityPreset build() => WeatherService.cityPresets.first;

  void selectCity(CityPreset preset) {
    state = preset;
  }
}

final selectedCityPresetProvider = NotifierProvider<SelectedCityNotifier, CityPreset>(SelectedCityNotifier.new);

/// Realtime-ish weather feed for the home top-bar chip.
///
/// Emits immediately, then re-fetches every 10 minutes while the home screen
/// is visible (autoDispose drops the timer when the chip unmounts). The emoji
/// and temperature therefore track live Open-Meteo `current` conditions —
/// rain starting mid-session flips ☀️ → 🌧️ without leaving the screen.
/// Also re-emits when the selected city changes.
final weatherDataProvider = StreamProvider.autoDispose<WeatherData>((ref) async* {
  final service = ref.watch(weatherServiceProvider);
  final city = ref.watch(selectedCityPresetProvider);

  Future<WeatherData> fetch() => service.fetchWeather(
        latitude: city.latitude,
        longitude: city.longitude,
        locationName: city.name,
      );

  // First reading right away.
  yield await fetch();

  // Periodic refresh — 10 min keeps us inside Open-Meteo's free-tier comfort
  // zone (their current-conditions update cadence is ~15 min upstream).
  yield* Stream<void>.periodic(const Duration(minutes: 10))
      .asyncMap((_) => fetch());
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
  final city = ref.watch(selectedCityPresetProvider);
  return service.fetchWeather(
    latitude: city.latitude,
    longitude: city.longitude,
    locationName: city.name,
  );
});

final refreshableBusesProvider = FutureProvider.autoDispose<List<BusInfo>>((ref) async {
  ref.watch(weatherRefreshProvider);
  final service = ref.watch(logisticsServiceProvider);
  final tenant = ref.watch(currentTenantProvider);
  return service.getBuses(tenantId: tenant?.id);
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
