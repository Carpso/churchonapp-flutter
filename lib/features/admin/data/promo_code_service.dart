import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A trackable promo code (migration `20261206_promo_codes.sql`).
///
/// `kind` is one of: cc | quiz_pass | subscription_discount | event_entry.
class PromoCode {
  final String id;
  final String code;
  final String kind;
  final double value;
  final String? description;
  final int? maxUses;
  final int perUserLimit;
  final int usedCount;
  final DateTime? expiresAt;
  final bool active;
  final DateTime createdAt;
  final int redemptions;
  final int uniqueUsers;

  const PromoCode({
    required this.id,
    required this.code,
    this.kind = 'cc',
    this.value = 0,
    this.description,
    this.maxUses,
    this.perUserLimit = 1,
    this.usedCount = 0,
    this.expiresAt,
    this.active = true,
    required this.createdAt,
    this.redemptions = 0,
    this.uniqueUsers = 0,
  });

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isExhausted => maxUses != null && usedCount >= maxUses!;

  String get kindLabel {
    switch (kind) {
      case 'cc':
        return 'Church Coins';
      case 'quiz_pass':
        return 'Quiz pass';
      case 'subscription_discount':
        return 'Subscription discount';
      case 'event_entry':
        return 'Event entry';
      default:
        return kind;
    }
  }

  factory PromoCode.fromMap(Map<String, dynamic> m) => PromoCode(
        id: m['id'].toString(),
        code: (m['code'] ?? '').toString(),
        kind: (m['kind'] ?? 'cc').toString(),
        value: (m['value'] as num?)?.toDouble() ?? 0,
        description: m['description']?.toString(),
        maxUses: (m['max_uses'] as num?)?.toInt(),
        perUserLimit: (m['per_user_limit'] as num?)?.toInt() ?? 1,
        usedCount: (m['used_count'] as num?)?.toInt() ?? 0,
        expiresAt: m['expires_at'] != null
            ? DateTime.tryParse(m['expires_at'].toString())
            : null,
        active: m['active'] != false,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
        redemptions: (m['redemptions'] as num?)?.toInt() ?? 0,
        uniqueUsers: (m['unique_users'] as num?)?.toInt() ?? 0,
      );
}

class PromoRedemption {
  final String id;
  final String code;
  final String userId;
  final String? fullName;
  final String? awardedBy;
  final DateTime? redeemedAt;
  final Map<String, dynamic> context;

  const PromoRedemption({
    required this.id,
    required this.code,
    required this.userId,
    this.fullName,
    this.awardedBy,
    this.redeemedAt,
    this.context = const {},
  });

  factory PromoRedemption.fromMap(Map<String, dynamic> m) => PromoRedemption(
        id: m['id'].toString(),
        code: (m['code'] ?? '').toString(),
        userId: m['user_id'].toString(),
        fullName: m['full_name']?.toString(),
        awardedBy: m['awarded_by']?.toString(),
        redeemedAt: m['redeemed_at'] != null
            ? DateTime.tryParse(m['redeemed_at'].toString())
            : null,
        context: m['context'] is Map
            ? Map<String, dynamic>.from(m['context'] as Map)
            : const {},
      );
}

class PromoCodeService {
  final SupabaseClient _client;
  PromoCodeService(this._client);

  List<Map<String, dynamic>> _asList(dynamic res) {
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<List<PromoCode>> listPromoCodes({bool onlyActive = false}) async {
    final res = await _client.rpc('list_promo_codes',
        params: {'p_only_active': onlyActive});
    return _asList(res).map(PromoCode.fromMap).toList();
  }

  Future<List<PromoRedemption>> listRedemptions({String? code}) async {
    final res = await _client.rpc('list_promo_code_redemptions',
        params: {'p_code': code});
    return _asList(res).map(PromoRedemption.fromMap).toList();
  }

  Future<String?> createPromoCode({
    String? code,
    required String kind,
    required double value,
    String? description,
    int? maxUses,
    int perUserLimit = 1,
    DateTime? expiresAt,
  }) async {
    final res = await _client.rpc('create_promo_code', params: {
      'p_code': code,
      'p_kind': kind,
      'p_value': value,
      'p_description': description,
      'p_max_uses': maxUses,
      'p_per_user_limit': perUserLimit,
      'p_expires_at': expiresAt?.toIso8601String(),
    });
    final map = res is Map ? Map<String, dynamic>.from(res) : null;
    return map?['code']?.toString();
  }

  Future<Map<String, dynamic>> awardToUser({
    required String userId,
    required String code,
  }) async {
    final res = await _client.rpc('award_promo_code', params: {
      'p_user_id': userId,
      'p_code': code,
      'p_context': {'source': 'staff'},
    });
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> redeem(String code, {String? eventId}) async {
    final res = await _client.rpc('redeem_promo_code', params: {
      'p_code': code,
      'p_context': eventId == null ? <String, dynamic>{} : {'event_id': eventId},
    });
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  Future<void> setActive(String id, bool active) async {
    await _client
        .rpc('set_promo_code_active', params: {'p_promo_id': id, 'p_active': active});
  }

  /// Searchable user list for the award picker (staff can read all profiles).
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      var q = _client
          .from('profiles')
          .select('id, full_name, email, tenant_id, avatar_url');
      if (query.trim().isNotEmpty) {
        q = q.or('full_name.ilike.%$query%,email.ilike.%$query%');
      }
      final rows = await q.order('full_name').limit(30);
      return _asList(rows);
    } catch (e) {
      debugPrint('searchUsers failed: $e');
      return [];
    }
  }
}

final promoCodeServiceProvider = Provider<PromoCodeService>((ref) {
  return PromoCodeService(Supabase.instance.client);
});

final promoCodesProvider = FutureProvider<List<PromoCode>>((ref) async {
  return ref.watch(promoCodeServiceProvider).listPromoCodes();
});
