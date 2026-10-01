import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One user's weather-alert settings.
///
/// The same shape is stored in `public.weather_alert_preferences`. All alerting
/// logic (thresholds, quiet hours, once-per-day dedupe) is evaluated
/// server-side by the `weather-alerts` Edge Function, so a client that is
/// closed, backgrounded or on a dead network still gets warned.
class WeatherAlertPrefs {
  const WeatherAlertPrefs({
    this.enabled = false,
    this.maxTempC,
    this.minTempC,
    this.rainProbabilityPct,
    this.maxWindKph,
    this.quietStartHour = 0,
    this.quietEndHour = 6,
    this.timezone = 'Africa/Lusaka',
    this.lat,
    this.lng,
    this.locationLabel,
  });

  final bool enabled;
  final double? maxTempC;
  final double? minTempC;
  final double? rainProbabilityPct;
  final double? maxWindKph;

  /// Never alert inside [quietStartHour, quietEndHour). Enforced server-side.
  final int quietStartHour;
  final int quietEndHour;

  /// IANA zone, so "quiet hours" means the user's wall clock, not UTC.
  final String timezone;

  final double? lat;
  final double? lng;
  final String? locationLabel;

  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId,
        'enabled': enabled,
        'max_temp_c': maxTempC,
        'min_temp_c': minTempC,
        'rain_probability_pct': rainProbabilityPct,
        'max_wind_kph': maxWindKph,
        'quiet_start_hour': quietStartHour,
        'quiet_end_hour': quietEndHour,
        'timezone': timezone,
        'lat': lat,
        'lng': lng,
        'location_label': locationLabel,
      };

  factory WeatherAlertPrefs.fromMap(Map<String, dynamic> m) =>
      WeatherAlertPrefs(
        enabled: m['enabled'] == true,
        maxTempC: (m['max_temp_c'] as num?)?.toDouble(),
        minTempC: (m['min_temp_c'] as num?)?.toDouble(),
        rainProbabilityPct: (m['rain_probability_pct'] as num?)?.toDouble(),
        maxWindKph: (m['max_wind_kph'] as num?)?.toDouble(),
        quietStartHour: (m['quiet_start_hour'] as num?)?.toInt() ?? 0,
        quietEndHour: (m['quiet_end_hour'] as num?)?.toInt() ?? 6,
        timezone: m['timezone']?.toString() ?? 'Africa/Lusaka',
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        locationLabel: m['location_label']?.toString(),
      );
}

class WeatherAlertService {
  static const _columns =
      'enabled, max_temp_c, min_temp_c, rain_probability_pct, max_wind_kph, '
      'quiet_start_hour, quiet_end_hour, timezone, lat, lng, location_label';

  SupabaseClient get _client => Supabase.instance.client;

  /// Returns null when the user has never opened/saved this screen, which is
  /// the same as "not opted in".
  Future<WeatherAlertPrefs?> load() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      final res = await _client
          .from('weather_alert_preferences')
          .select(_columns)
          .eq('user_id', uid)
          .maybeSingle();
      if (res == null) return null;
      return WeatherAlertPrefs.fromMap(Map<String, dynamic>.from(res));
    } catch (e) {
      debugPrint('[WeatherAlerts] load failed: $e');
      return null;
    }
  }

  Future<bool> save(WeatherAlertPrefs prefs) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return false;
      await _client
          .from('weather_alert_preferences')
          .upsert(prefs.toRow(uid), onConflict: 'user_id');
      return true;
    } catch (e) {
      debugPrint('[WeatherAlerts] save failed: $e');
      return false;
    }
  }

  /// Turns alerts off. Kept separate from [save] so a one-tap opt-out is
  /// possible from notification settings without touching thresholds.
  Future<bool> disable() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return false;
      await _client
          .from('weather_alert_preferences')
          .update({'enabled': false})
          .eq('user_id', uid);
      return true;
    } catch (e) {
      debugPrint('[WeatherAlerts] disable failed: $e');
      return false;
    }
  }
}
