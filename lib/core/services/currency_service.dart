import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Live FX rates for USD <-> ZMW using the free open.er-api.com (no key).
class CurrencyService {
  static const _baseUrl = 'https://open.er-api.com/v6/latest/ZMW';

  double _zmwPerUsd = 0;
  DateTime? _lastUpdated;

  /// Fetch the latest ZMW->USD rate (cached for 10 min to be polite to the API).
  Future<double> fetchZmwPerUsd({bool force = false}) async {
    if (!force &&
        _zmwPerUsd > 0 &&
        _lastUpdated != null &&
        DateTime.now().difference(_lastUpdated!).inMinutes < 10) {
      return _zmwPerUsd;
    }
    try {
      final res = await http
          .get(Uri.parse(_baseUrl))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final usdPerZmw = (data['rates']?['USD'] as num?)?.toDouble() ?? 0;
        if (usdPerZmw > 0) {
          _zmwPerUsd = 1 / usdPerZmw;
          _lastUpdated = DateTime.now();
          return _zmwPerUsd;
        }
      }
    } catch (e) {
      debugPrint('CurrencyService: FX fetch error: $e');
    }
    // Fallback: last known rate or a reasonable floor.
    if (_zmwPerUsd > 0) return _zmwPerUsd;
    return 18.0;
  }

  double zmwToUsd(double zmw) => zmw / _zmwPerUsd;
}

final currencyServiceProvider = Provider<CurrencyService>((ref) {
  return CurrencyService();
});

/// Reactive provider: emits the live ZMW->USD rate.
final zmwPerUsdProvider = FutureProvider<double>((ref) async {
  return ref.watch(currencyServiceProvider).fetchZmwPerUsd();
});
