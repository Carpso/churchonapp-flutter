import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/config/remote_config.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class CoinPackage {
  final int coins;
  final int priceKwacha;
  final String label;
  final String? bonus; // e.g. "20% bonus"

  const CoinPackage({
    required this.coins,
    required this.priceKwacha,
    required this.label,
    this.bonus,
  });

  double get pricePerCoin => priceKwacha / coins;
}

class CoinPurchaseResult {
  final bool success;
  final String? txId;
  final String? error;

  const CoinPurchaseResult({required this.success, this.txId, this.error});
}

class CoinPurchaseService {
  final SupabaseClient _client;

  CoinPurchaseService(this._client);

  static const List<CoinPackage> packages = [
    CoinPackage(coins: 100, priceKwacha: 10, label: "Starter"),
    CoinPackage(coins: 250, priceKwacha: 22, label: "Popular", bonus: "10% bonus"),
    CoinPackage(coins: 500, priceKwacha: 40, label: "Value", bonus: "20% bonus"),
    CoinPackage(coins: 1000, priceKwacha: 70, label: "Premium", bonus: "40% bonus"),
    CoinPackage(coins: 2500, priceKwacha: 150, label: "Champion", bonus: "50% bonus"),
  ];

  /// Packages read from remote config (`coin_package_coins` +
  /// `coin_package_prices_kwacha`, comma-separated lists) — COA can re-price
  /// or add tiers without an app update. Falls back to [packages] when the
  /// keys are missing or the lists don't align.
  static List<CoinPackage> packagesFrom(RemoteConfig rc) {
    const defaultCoins = [100, 250, 500, 1000, 2500];
    const defaultPrices = [10, 22, 40, 70, 150];
    const labels = ["Starter", "Popular", "Value", "Premium", "Champion"];
    const bonuses = [null, "10% bonus", "20% bonus", "40% bonus", "50% bonus"];

    final coins = rc.getIntList('coin_package_coins', defaultCoins);
    final prices = rc.getIntList('coin_package_prices_kwacha', defaultPrices);
    if (coins.isEmpty || prices.isEmpty || coins.length != prices.length) {
      return packages;
    }
    return [
      for (var i = 0; i < coins.length; i++)
        CoinPackage(
          coins: coins[i],
          priceKwacha: prices[i],
          label: i < labels.length ? labels[i] : "Package ${i + 1}",
          bonus: i < bonuses.length ? bonuses[i] : null,
        ),
    ];
  }

  Future<CoinPurchaseResult> purchaseCoins({
    required CoinPackage package,
    required String paymentRef,
    required String paymentMethod,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const CoinPurchaseResult(success: false, error: "Not authenticated");
    }

    try {
      await _client.from('coin_purchases').insert({
        'user_id': user.id,
        'coins_amount': package.coins,
        'price_kwacha': package.priceKwacha,
        'payment_ref': paymentRef,
        'payment_method': paymentMethod,
        'status': 'completed',
        'package_label': package.label,
      });

      await _client.rpc('add_coins', params: {
        'user_id': user.id,
        'amount': package.coins,
      });

      return CoinPurchaseResult(success: true, txId: paymentRef);
    } catch (e) {
      return CoinPurchaseResult(success: false, error: e.toString());
    }
  }

  Future<int> getCoins() async {
    final user = _client.auth.currentUser;
    if (user == null) return 0;

    final res = await _client
        .from('profiles')
        .select('coins')
        .eq('id', user.id)
        .maybeSingle();

    return (res?['coins'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> getPurchaseHistory() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final res = await _client
          .from('coin_purchases')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(20);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
  }
}

final coinPurchaseServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return CoinPurchaseService(client);
});
