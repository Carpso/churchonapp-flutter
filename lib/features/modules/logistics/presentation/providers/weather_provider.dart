import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/weather_service.dart';
import '../../data/weather_model.dart';
import '../../data/logistics_service.dart';
import '../../data/logistics_model.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

final weatherServiceProvider = Provider<WeatherService>((ref) => WeatherService());

final logisticsServiceProvider = Provider<LogisticsService>((ref) => LogisticsService(Supabase.instance.client));

/// The city the user has explicitly chosen, or null meaning "use my exact
/// current location".
///
/// WHY NULL IS THE DEFAULT
///   This used to default to `cityPresets.first` (Lusaka), so the temperature
///   chip showed Lusaka weather to EVERYONE regardless of where they actually
///   were. A member in Ndola, or in Harare, or anywhere in between saw a
///   temperature for a city they were not in. Defaulting to null means the chip
///   reflects the user's real position, and the preset list becomes an
///   explicit opt-in for "show me another city" rather than a silent default.
///   Persisted, because flipping the app back to a wrong city on every launch
///   would be worse than the original bug.
class SelectedCityNotifier extends Notifier<CityPreset?> {
  static const _key = 'weather_selected_city';

  @override
  CityPreset? build() {
    final name = _prefs?.getString(_key);
    if (name == null || name.isEmpty) return null; // -> exact location
    for (final c in WeatherService.cityPresets) {
      if (c.name == name) return c;
    }
    return null;
  }

  SharedPreferences? get _prefs => _prefsInstance;

  static SharedPreferences? _prefsInstance;

/// Hand the notifier its [SharedPreferences] at startup so an explicitly
  /// chosen city survives a cold start.
  ///
  /// Called from `_initNotifications` in `main.dart`. It was previously
  /// documented as "already done by the notification service bootstrap" —
  /// nothing called it, so `_prefs` was always null and `selectCity` silently
  /// wrote nothing.
  static void attachPrefs(SharedPreferences prefs) =>
      _prefsInstance = prefs;

  Future<void> selectCity(CityPreset preset) async {
    state = preset;
    try {
      await _prefsInstance?.setString(_key, preset.name);
    } catch (_) {}
  }

  /// Back to the user's real position.
  Future<void> useExactLocation() async {
    state = null;
    try {
      await _prefsInstance?.remove(_key);
    } catch (_) {}
  }
}

final selectedCityPresetProvider =
    NotifierProvider<SelectedCityNotifier, CityPreset?>(SelectedCityNotifier.new);

/// The user's real position, for weather that is actually about where they are.
///
/// Resolution order (cheapest and most reliable first):
///   1. `profiles.lat/lng` — already synced by the location tracker, no
///      permission prompt and no GPS radio wake-up.
///   2. Device GPS — only when the profile has no fix yet.
///
/// Never blocks: on failure it returns null and the caller falls back to the
/// user's chosen city (or Lusaka), so weather is never empty.
final exactWeatherLocationProvider = FutureProvider.autoDispose<
    ({double latitude, double longitude, String source})?>((ref) async {
  // 1. Profile coordinates.
  try {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('lat, lng')
          .eq('id', uid)
          .maybeSingle();
      final lat = (row?['lat'] as num?)?.toDouble();
      final lng = (row?['lng'] as num?)?.toDouble();
      // Reject the (0,0)/unset placeholder the profile defaults to.
      if (lat != null && lng != null && (lat != 0 || lng != 0)) {
        return (latitude: lat, longitude: lng, source: 'profile');
      }
    }
  } catch (_) {
    // fall through to GPS
  }

  // 2. Device GPS.
  try {
    final granted = await Geolocator.isLocationServiceEnabled();
    if (granted) {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
        if (pos.latitude != 0 || pos.longitude != 0) {
          return (latitude: pos.latitude, longitude: pos.longitude, source: 'gps');
        }
      }
    }
  } catch (_) {
    // Permission denied / GPS unavailable / timeout -> caller falls back.
  }
  return null;
});

/// Realtime-ish weather feed for the home top-bar chip.
///
/// Emits immediately, then re-fetches every 10 minutes while the home screen
/// is visible (autoDispose drops the timer when the chip unmounts). The emoji
/// and temperature therefore track live Open-Meteo `current` conditions —
/// rain starting mid-session flips ☀️ → 🌧️ without leaving the screen.
/// Also re-emits when the selected city changes.
final weatherDataProvider = StreamProvider.autoDispose<WeatherData>((ref) async* {
  final service = ref.watch(weatherServiceProvider);
  // Explicitly chosen city, or null = follow the user's real position.
  final city = ref.watch(selectedCityPresetProvider);
  // Only awaited when no city was chosen, so picking a city never waits on GPS.
  final exact = city == null ? await ref.watch(exactWeatherLocationProvider.future) : null;

  Future<WeatherData> fetch() {
    if (city != null) {
      return service.fetchWeather(
        latitude: city.latitude,
        longitude: city.longitude,
        locationName: city.name,
      );
    }
    if (exact != null) {
      return service.fetchWeather(
        latitude: exact.latitude,
        longitude: exact.longitude,
        // No reverse-geocoding round-trip: the chip is a few pixels wide, so a
        // coordinate label would be noise. The weather map screen still names
        // the city when the user asks for it.
        locationName: 'Your location',
      );
    }
    // No fix and no choice: Lusaka keeps the chip populated rather than blank.
    final fallback = WeatherService.cityPresets.first;
    return service.fetchWeather(
      latitude: fallback.latitude,
      longitude: fallback.longitude,
      locationName: fallback.name,
    );
  }

  // First reading right away.
  yield await fetch();

  // Periodic refresh �?" 10 min keeps us inside Open-Meteo's free-tier comfort
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

/// Pull-to-refresh variant of [weatherDataProvider]. Must follow the SAME rule
/// or a refresh would silently snap the chip back to a hardcoded city.
final refreshableWeatherProvider = FutureProvider.autoDispose<WeatherData>((ref) async {
  ref.watch(weatherRefreshProvider);
  final service = ref.watch(weatherServiceProvider);
  final city = ref.watch(selectedCityPresetProvider);
  if (city != null) {
    return service.fetchWeather(
      latitude: city.latitude,
      longitude: city.longitude,
      locationName: city.name,
    );
  }
  final exact = await ref.watch(exactWeatherLocationProvider.future);
  if (exact != null) {
    return service.fetchWeather(
      latitude: exact.latitude,
      longitude: exact.longitude,
      locationName: 'Your location',
    );
  }
  final fallback = WeatherService.cityPresets.first;
  return service.fetchWeather(
    latitude: fallback.latitude,
    longitude: fallback.longitude,
    locationName: fallback.name,
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
