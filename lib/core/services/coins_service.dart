import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';

class CoinsService {
  final SupabaseClient _client;

  CoinsService(this._client);

  static const _dailyCollectKey = 'last_daily_coin_collect';
  static const int _dailyCoins = 25;
  static const int _streakBonus = 50;
  static const int _attendanceCoins = 50;
  static const int _referralCoins = 100;
  static const Duration _collectCooldown = Duration(hours: 20);

  Future<bool> canCollectDaily() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_dailyCollectKey);
    if (last == null) return true;
    final lastTime = DateTime.parse(last);
    return DateTime.now().difference(lastTime) >= _collectCooldown;
  }

  Future<int> collectDailyCoins() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    final canCollect = await canCollectDaily();
    if (!canCollect) return 0;

    await _client.rpc('add_coins', params: {
      'user_id': user.id,
      'amount': _dailyCoins,
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyCollectKey, DateTime.now().toIso8601String());

    return _dailyCoins;
  }

  Future<bool> hasCollectedToday() async {
    final can = await canCollectDaily();
    return !can;
  }

  Future<int> addAttendanceCoins() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    await _client.rpc('add_coins', params: {
      'user_id': user.id,
      'amount': _attendanceCoins,
    });

    return _attendanceCoins;
  }

  Future<int> addStreakBonus(int streakCount) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    final bonus = streakCount * _streakBonus;
    if (bonus <= 0) return 0;

    await _client.rpc('add_coins', params: {
      'user_id': user.id,
      'amount': bonus,
    });

    return bonus;
  }

  Future<int> addReferralCoins() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    await _client.rpc('add_coins', params: {
      'user_id': user.id,
      'amount': _referralCoins,
    });

    return _referralCoins;
  }

  Future<int> addAppOpenStreakCoins(int consecutiveDays) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    if (consecutiveDays <= 0) return 0;

    int coins = 0;
    if (consecutiveDays == 1) {
      coins = 5;
    } else if (consecutiveDays <= 6) {
      coins = 10;
    } else if (consecutiveDays <= 13) {
      coins = 20;
    } else {
      coins = 30;
    }

    await _client.rpc('add_coins', params: {
      'user_id': user.id,
      'amount': coins,
    });

    return coins;
  }

  Future<void> redeemAtBookshop({
    required int coinAmount,
    required String bookshopId,
    required String description,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    await _client.rpc('redeem_coins_atomic', params: {
      'p_user_id': user.id,
      'p_amount': coinAmount,
      'p_redemption_type': 'bookshop',
      'p_partner_id': bookshopId,
      'p_description': description,
    });
  }

  Future<void> redeemAtMerchStore({
    required int coinAmount,
    required String itemId,
    required String description,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    await _client.rpc('redeem_coins_atomic', params: {
      'p_user_id': user.id,
      'p_amount': coinAmount,
      'p_redemption_type': 'merch_store',
      'p_partner_id': itemId,
      'p_description': description,
    });
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
}

final coinsServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return CoinsService(client);
});

final canCollectDailyProvider = FutureProvider<bool>((ref) {
  return ref.watch(coinsServiceProvider).canCollectDaily();
});
