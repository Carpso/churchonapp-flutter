import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Generic remote configuration read from the `platform_settings` table.
///
/// Lets COA adjust feature values (coin rewards, fares, durations, prizes,
/// subscription terms...) without shipping an app update — change the
/// `value` in Supabase and the next app launch picks it up.
class RemoteConfig {
  final Map<String, String> _values;

  const RemoteConfig([this._values = const {}]);

  factory RemoteConfig.fromRows(List<dynamic> rows) {
    final map = <String, String>{};
    for (final row in rows) {
      if (row is Map) {
        final key = row['key']?.toString();
        final value = row['value']?.toString() ?? '';
        if (key != null && key.isNotEmpty) map[key] = value;
      }
    }
    return RemoteConfig(map);
  }

  bool has(String key) => _values[key] != null && _values[key]!.isNotEmpty;

  String getString(String key, String fallback) {
    final v = _values[key];
    return (v == null || v.isEmpty) ? fallback : v;
  }

  int getInt(String key, int fallback) {
    final v = _values[key];
    if (v == null || v.isEmpty) return fallback;
    return int.tryParse(v) ?? fallback;
  }

  double getDouble(String key, double fallback) {
    final v = _values[key];
    if (v == null || v.isEmpty) return fallback;
    return double.tryParse(v) ?? fallback;
  }

  bool getBool(String key, bool fallback) {
    final v = _values[key]?.toLowerCase();
    if (v == null || v.isEmpty) return fallback;
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
    return fallback;
  }

  /// Duration in whole seconds (e.g. `72000` = 20 hours).
  Duration getDuration(String key, Duration fallback) {
    final v = _values[key];
    if (v == null || v.isEmpty) return fallback;
    final secs = int.tryParse(v);
    return secs == null ? fallback : Duration(seconds: secs);
  }

  /// Comma-separated numeric list, e.g. `"5,10,20,30"`.
  List<double> getDoubleList(String key, List<double> fallback) {
    final v = _values[key];
    if (v == null || v.isEmpty) return fallback;
    final parsed = v
        .split(',')
        .map((e) => double.tryParse(e.trim()))
        .whereType<double>()
        .toList();
    return parsed.isEmpty ? fallback : parsed;
  }

  /// Comma-separated integer list, e.g. `"100,250,500"`.
  List<int> getIntList(String key, List<int> fallback) {
    final v = _values[key];
    if (v == null || v.isEmpty) return fallback;
    final parsed = v
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
    return parsed.isEmpty ? fallback : parsed;
  }

  // ── Domain helpers ───────────────────────────────────────────────────

  /// Length of the free trial granted to a new church (30 days default).
  int get trialDurationDays => getInt('subscription_trial_days', 30);

  /// Length of a paid subscription renewal (365 days default).
  int get renewalDurationDays => getInt('subscription_renewal_days', 365);

  /// Length of the free Platinum upgrade after onboarding (30 days default).
  int get platinumPromoDays => getInt('platinum_promo_days', 30);

  @override
  String toString() => 'RemoteConfig(${_values.length} keys)';
}

/// Loads ALL `platform_settings` rows into a typed map. Safe to `ref.watch`;
/// call `ref.invalidate(remoteConfigProvider)` to refresh after the admin
/// panel changes a value.
final remoteConfigProvider = FutureProvider<RemoteConfig>((ref) async {
  try {
    final rows = await Supabase.instance.client
        .from('platform_settings')
        .select('key, value');
    return RemoteConfig.fromRows(rows);
  } catch (e) {
    debugPrint('Error fetching remote config: $e');
    return const RemoteConfig();
  }
});

/// Synchronous access for providers/services — falls back to local defaults
/// while the remote config has not loaded yet.
RemoteConfig currentRemoteConfig(Ref ref) =>
    ref.read(remoteConfigProvider).value ?? const RemoteConfig();

/// Synchronous access for widgets (`WidgetRef`) — Riverpod 3 keeps `Ref`
/// (providers) and `WidgetRef` (widgets) in separate hierarchies.
RemoteConfig widgetRemoteConfig(WidgetRef ref) =>
    ref.read(remoteConfigProvider).value ?? const RemoteConfig();
