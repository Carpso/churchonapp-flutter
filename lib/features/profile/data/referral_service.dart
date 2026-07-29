import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/services/code_generator_service.dart';

class ReferralStats {
  final int invited;
  final int verified;
  final int pendingVerification;
  final int totalCoinsEarned;

  ReferralStats({
    required this.invited,
    required this.verified,
    required this.pendingVerification,
    required this.totalCoinsEarned,
  });

  factory ReferralStats.empty() => ReferralStats(invited: 0, verified: 0, pendingVerification: 0, totalCoinsEarned: 0);
}

class ReferralRecord {
  final String id;
  final String refereeId;
  final String? refereeName;
  final String? refereeEmail;
  final String status;
  final bool rewardClaimed;
  final DateTime createdAt;

  ReferralRecord({
    required this.id,
    required this.refereeId,
    this.refereeName,
    this.refereeEmail,
    required this.status,
    required this.rewardClaimed,
    required this.createdAt,
  });

  factory ReferralRecord.fromMap(Map<String, dynamic> map) {
    return ReferralRecord(
      id: map['id'] as String,
      refereeId: map['referee_id'] as String,
      refereeName: map['referee']?['full_name'] as String?,
      refereeEmail: map['referee']?['email'] as String?,
      status: (map['status'] as String?) ?? 'pending',
      rewardClaimed: (map['reward_claimed'] as bool?) ?? false,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class ReferralService {
  final SupabaseClient _client;
  final CodeGeneratorService _codeGenerator;

  ReferralService(this._client, this._codeGenerator);

  static const int referralCoins = 100;

  Future<String> getReferralCode() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    final res = await _client
        .from('profiles')
        .select('referral_code, tenant_id')
        .eq('id', user.id)
        .maybeSingle();

    if (res != null && res['referral_code'] != null && (res['referral_code'] as String).isNotEmpty) {
      return res['referral_code'] as String;
    }

    String country = 'Zambia';
    final tenantId = res?['tenant_id'] as String?;
    if (tenantId != null) {
      final church = await _client.from('churches').select('country').eq('tenant_id', tenantId).maybeSingle();
      if (church != null && church['country'] != null) {
        country = church['country'].toString();
      }
    }

    final code = await _codeGenerator.generateReferralCode(country);
    await _client.from('profiles').update({'referral_code': code}).eq('id', user.id);

    final iso = CodeGeneratorService.countryToISO(country);
    await _codeGenerator.registerCode(
      codeType: 'referral',
      codeValue: code,
      countryIso: iso,
      userId: user.id,
    );

    return code;
  }

  Future<ReferralStats> getStats() async {
    final user = _client.auth.currentUser;
    if (user == null) return ReferralStats.empty();

    try {
      final referrals = await _client
          .from('referrals')
          .select('status, reward_claimed')
          .eq('referrer_id', user.id);

      final list = referrals as List;
      final invited = list.length;
      final verified = list.where((r) => r['status'] == 'completed').length;
      final pendingVerification = list.where((r) => r['status'] == 'pending').length;
      final totalCoinsEarned = verified * referralCoins;

      return ReferralStats(
        invited: invited,
        verified: verified,
        pendingVerification: pendingVerification,
        totalCoinsEarned: totalCoinsEarned,
      );
    } catch (e) {
      debugPrint("getStats error: $e");
      return ReferralStats.empty();
    }
  }

  Future<List<ReferralRecord>> getReferralHistory() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final referrals = await _client
          .from('referrals')
          .select('id, referee_id, status, reward_claimed, created_at, referee:profiles!referee_id(full_name, email)')
          .eq('referrer_id', user.id)
          .order('created_at', ascending: false);

      final list = referrals as List;
      return list.map((r) => ReferralRecord.fromMap(r)).toList();
    } catch (e) {
      debugPrint("getReferralHistory error: $e");
      return [];
    }
  }

  Future<void> recordReferral(String referralCode, String newUserId) async {
    if (referralCode.isEmpty) return;

    final referrer = await _client
        .from('profiles')
        .select('id')
        .eq('referral_code', referralCode)
        .maybeSingle();

    if (referrer == null) return;
    if (referrer['id'] == newUserId) return;

    final existing = await _client
        .from('referrals')
        .select('id')
        .eq('referrer_id', referrer['id'])
        .eq('referee_id', newUserId)
        .maybeSingle();

    if (existing != null) return;

    await _client.from('referrals').insert({
      'referrer_id': referrer['id'],
      'referee_id': newUserId,
      'status': 'completed',
      'reward_claimed': true,
    });

    await _client.rpc('add_coins', params: {
      'user_id': referrer['id'],
      'amount': referralCoins,
    });
  }
}

final referralServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  final codeGenerator = ref.watch(codeGeneratorProvider);
  return ReferralService(client, codeGenerator);
});

final referralCodeProvider = FutureProvider<String>((ref) {
  return ref.watch(referralServiceProvider).getReferralCode();
});

final referralStatsProvider = FutureProvider<ReferralStats>((ref) {
  return ref.watch(referralServiceProvider).getStats();
});

final referralHistoryProvider = FutureProvider<List<ReferralRecord>>((ref) {
  return ref.watch(referralServiceProvider).getReferralHistory();
});
