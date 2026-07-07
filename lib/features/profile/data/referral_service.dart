import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class ReferralStats {
  final int invited;
  final int pendingVerification;
  final int coinsEarned;

  ReferralStats({required this.invited, required this.pendingVerification, required this.coinsEarned});

  factory ReferralStats.empty() => ReferralStats(invited: 0, pendingVerification: 0, coinsEarned: 0);
}

class ReferralService {
  final SupabaseClient _client;

  ReferralService(this._client);

  Future<String> getReferralCode() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    final res = await _client.from('profiles').select('referral_code').eq('id', user.id).maybeSingle();
    if (res != null && res['referral_code'] != null) return res['referral_code'] as String;

    final code = "COA-${user.id.substring(0, 8).toUpperCase()}";
    await _client.from('profiles').update({'referral_code': code}).eq('id', user.id);
    return code;
  }

  Future<ReferralStats> getStats() async {
    final user = _client.auth.currentUser;
    if (user == null) return ReferralStats.empty();

    try {
      final referrals = await _client.from('referrals').select().eq('referrer_id', user.id);
      final list = referrals as List;
      final invited = list.length;
      final pendingVerification = list.where((r) => r['status'] == 'pending').length;
      final coinsEarned = list.where((r) => r['reward_claimed'] == true).length * 100;
      return ReferralStats(invited: invited, pendingVerification: pendingVerification, coinsEarned: coinsEarned);
    } catch (_) {
      return ReferralStats.empty();
    }
  }

  Future<void> recordReferral(String referralCode, String newUserId) async {
    final referrer = await _client.from('profiles').select('id').eq('referral_code', referralCode).maybeSingle();
    if (referrer == null) return;

    await _client.from('referrals').insert({
      'referrer_id': referrer['id'],
      'referee_id': newUserId,
      'status': 'pending',
      'reward_claimed': false,
    });
  }

  Future<void> claimReward(String referralId) async {
    final referral = await _client.from('referrals').select('referrer_id').eq('id', referralId).single();
    final referrerId = referral['referrer_id'];

    final profile = await _client.from('profiles').select('coins').eq('id', referrerId).single();
    final currentCoins = (profile['coins'] as num?)?.toInt() ?? 0;
    await _client.from('profiles').update({'coins': currentCoins + 100}).eq('id', referrerId);

    await _client.from('referrals').update({'status': 'completed', 'reward_claimed': true}).eq('id', referralId);
  }
}

final referralServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return ReferralService(client);
});

final referralCodeProvider = FutureProvider<String>((ref) {
  return ref.watch(referralServiceProvider).getReferralCode();
});

final referralStatsProvider = FutureProvider<ReferralStats>((ref) {
  return ref.watch(referralServiceProvider).getStats();
});
