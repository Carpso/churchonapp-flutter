import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/code_generator_service.dart';
import 'tithe_models.dart';

class TitheService {
  final SupabaseClient _client;
  final CodeGeneratorService _codeGenerator;
  TitheService(this._client, this._codeGenerator);

  Future<TitheCard?> getTitheCard(String tenantId, String userId) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final card = await _client
          .from('tithe_cards')
          .select()
          .eq('tenant_id', tenantId)
          .eq('user_id', userId)
          .maybeSingle();

      if (card == null) return null;

      final records = await _client
          .from('tithe_records')
          .select()
          .eq('user_id', userId)
          .eq('tenant_id', tenantId)
          .order('given_at', ascending: false)
          .limit(10);

      final titheRecords = (records as List?)?.map((r) => TitheRecord.fromMap(r)).toList() ?? [];
      return TitheCard.fromMap(card, recentTithes: titheRecords);
    } catch (e) {
      debugPrint('TitheService.getTitheCard error: $e');
      return null;
    }
  }

  Future<List<TitheRecord>> getTitheHistory(String userId, {int limit = 20}) async {
    final records = await _client
        .from('tithe_records')
        .select()
        .eq('user_id', userId)
        .order('given_at', ascending: false)
        .limit(limit);

    return (records as List).map((r) => TitheRecord.fromMap(r)).toList();
  }

  Future<List<TitheRecord>> getTitheHistoryByTenant(String tenantId, String userId, {int limit = 20}) async {
    final records = await _client
        .from('tithe_records')
        .select()
        .eq('user_id', userId)
        .eq('tenant_id', tenantId)
        .order('given_at', ascending: false)
        .limit(limit);

    return (records as List).map((r) => TitheRecord.fromMap(r)).toList();
  }

  Future<String> getMemberId(String tenantId, String userId) async {
    final existing = await _client
        .from('tithe_cards')
        .select('member_id')
        .eq('tenant_id', tenantId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) return existing['member_id'].toString();

    final church = await _client
        .from('churches')
        .select('slug, country')
        .eq('tenant_id', tenantId)
        .maybeSingle();

    final country = (church?['country']?.toString() ?? 'Zambia');
    final memberId = await _codeGenerator.generateTitheCardNumber(country);

    final iso = CodeGeneratorService.countryToISO(country);
    await _codeGenerator.registerCode(
      codeType: 'tithe_card',
      codeValue: memberId,
      countryIso: iso,
      userId: userId,
      metadata: {'tenant_id': tenantId},
    );

    return memberId;
  }

  Future<void> giveTithe(double amount, String paymentMethod, {bool isAnonymous = false}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    String? tenantId;
    try {
      final profile = await _client.from('profiles').select('tenant_id').eq('id', user.id).maybeSingle();
      tenantId = profile?['tenant_id']?.toString();
    } catch (_) {}

    await _client.from('tithe_records').insert({
      'user_id': user.id,
      if (tenantId != null) 'tenant_id': tenantId,
      'amount': amount,
      'payment_method': paymentMethod,
      'is_anonymous': isAnonymous,
    });
  }

  Future<List<TitheRecord>> getTitheHistoryFiltered(
    String userId, {
    DateTime? startDate,
    DateTime? endDate,
    double? minAmount,
    double? maxAmount,
  }) async {
    final records = await _client.rpc('get_filtered_tithe_records', params: {
      'p_user_id': userId,
      if (startDate != null) 'p_start_date': startDate.toIso8601String(),
      if (endDate != null) 'p_end_date': endDate.toIso8601String(),
      if (minAmount != null) 'p_min_amount': minAmount,
      if (maxAmount != null) 'p_max_amount': maxAmount,
    });
    return (records as List).map((r) => TitheRecord.fromMap(r)).toList();
  }
}

final titheServiceProvider = Provider<TitheService>((ref) {
  final codeGenerator = ref.watch(codeGeneratorProvider);
  return TitheService(Supabase.instance.client, codeGenerator);
});