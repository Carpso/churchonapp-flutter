import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlatformSettings {
  final double silverFee;
  final double goldFee;
  final double churchFee;

  PlatformSettings({
    required this.silverFee,
    required this.goldFee,
    required this.churchFee,
  });

  factory PlatformSettings.fromList(List<dynamic> list) {
    double silver = 50.0;
    double gold = 150.0;
    double church = 1500.0;

    for (var row in list) {
      if (row is Map) {
        final key = row['key'];
        final val = double.tryParse(row['value']?.toString() ?? '');
        if (val != null) {
          if (key == 'silver_subscription_fee') silver = val;
          if (key == 'gold_subscription_fee') gold = val;
          if (key == 'church_subscription_fee') church = val;
        }
      }
    }

    return PlatformSettings(
      silverFee: silver,
      goldFee: gold,
      churchFee: church,
    );
  }
}

class PlatformSettingsService {
  final SupabaseClient _client;
  PlatformSettingsService(this._client);

  Future<PlatformSettings> fetchSettings() async {
    try {
      final data = await _client.from('platform_settings').select();
      return PlatformSettings.fromList(data);
    } catch (e) {
      debugPrint('Error fetching platform settings: $e');
      return PlatformSettings(silverFee: 50.0, goldFee: 150.0, churchFee: 1500.0);
    }
  }

  Future<void> updateSettings({
    required double silverFee,
    required double goldFee,
    required double churchFee,
  }) async {
    try {
      await _client.from('platform_settings').upsert([
        {'key': 'silver_subscription_fee', 'value': silverFee.toString()},
        {'key': 'gold_subscription_fee', 'value': goldFee.toString()},
        {'key': 'church_subscription_fee', 'value': churchFee.toString()},
      ]);
    } catch (e) {
      debugPrint('Error updating platform settings: $e');
      rethrow;
    }
  }
}

final platformSettingsServiceProvider = Provider((ref) {
  final client = Supabase.instance.client;
  return PlatformSettingsService(client);
});

final platformSettingsProvider = FutureProvider<PlatformSettings>((ref) async {
  return ref.watch(platformSettingsServiceProvider).fetchSettings();
});
