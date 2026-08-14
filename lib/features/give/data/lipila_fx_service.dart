import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Live FX rates for USD <-> ZMW using the free open.er-api.com (no key).
///
/// Part of the shared Lipila payment integration so any project wiring Lipila
/// can reuse the same live exchange-rate logic. Callers can also supply a
/// custom base-currency to convert from any supported currency pair.
class LipilaFxService {
  static const String defaultBaseUrl = 'https://open.er-api.com/v6/latest';

  final String baseCurrency;
  final String targetCurrency;
  final String baseUrl;

  double _zmwPerTarget = 0;
  DateTime? _lastUpdated;
  double _fallbackRate = 18.0;

  LipilaFxService({
    this.baseCurrency = 'ZMW',
    this.targetCurrency = 'USD',
    this.baseUrl = defaultBaseUrl,
  });

  /// How many [baseCurrency] units equal 1 [targetCurrency] unit.
  double get ratePerUnit => _zmwPerTarget;

  bool get isRateLoaded => _zmwPerTarget > 0;

  DateTime? get lastUpdated => _lastUpdated;

  void setFallbackRate(double rate) => _fallbackRate = rate;

  /// Fetch the live rate. Cached for 1 minute to keep it fresh without spamming the API.
  /// Returns a Future&lt;double&gt;. Falls back if offline.
  Future<double> fetchRate({bool force = false}) async {
    if (!force &&
        _zmwPerTarget > 0 &&
        _lastUpdated != null &&
         DateTime.now().difference(_lastUpdated!).inMinutes < 1) {
      return _zmwPerTarget;
    }
    try {
      final uri = Uri.parse('$baseUrl/$baseCurrency');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        // response rates are "targetCurrency per 1 baseCurrency"
        final targetPerBase =
            (data['rates']?[targetCurrency] as num?)?.toDouble() ?? 0;
        if (targetPerBase > 0) {
          _zmwPerTarget = 1 / targetPerBase; // base units per 1 target unit
          _lastUpdated = DateTime.now();
          return _zmwPerTarget;
        }
      }
    } catch (e) {
      debugPrint('LipilaFxService: FX fetch error: $e');
    }
    if (_zmwPerTarget > 0) return _zmwPerTarget;
    return _fallbackRate;
  }

  /// Convert an amount in [baseCurrency] to [targetCurrency].
  double convert(double amountInBase, double rate) => amountInBase / rate;

  /// Convenience: async conversion (fetches rate if needed).
  Future<double> convertAsync(double amountInBase) async {
    final rate = await fetchRate();
    return convert(amountInBase, rate);
  }
}

final lipilaFxServiceProvider = Provider<LipilaFxService>((ref) {
  return LipilaFxService();
});

/// Reactive provider that emits the live ZMW->USD rate (base units per USD).
final zmwPerUsdProvider = FutureProvider<double>((ref) async {
  return ref.watch(lipilaFxServiceProvider).fetchRate();
});
