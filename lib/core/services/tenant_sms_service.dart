import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TenantSmsService {
  final SupabaseClient _client;

  TenantSmsService(this._client);

  Future<int> getBalance(String tenantId) async {
    try {
      final data = await _client.rpc('get_tenant_balance', params: {'p_tenant_id': tenantId});
      return (data as int?) ?? 0;
    } catch (e) {
      debugPrint('Error fetching SMS balance: $e');
      return 0;
    }
  }

  Future<bool> sendBroadcast({
    required String tenantId,
    required List<String> phoneNumbers,
    required String message,
    String? audienceLabel,
  }) async {
    try {
      final result = await _client.functions.invoke(
        'send-sms',
        method: HttpMethod.post,
        body: {
          'tenant_id': tenantId,
          'phone_numbers': phoneNumbers,
          'message': message,
          'audience_label': audienceLabel ?? 'all',
        },
      );
      final data = result.data as Map<String, dynamic>?;
      return data?['success'] == true;
    } catch (e) {
      debugPrint('Error sending SMS broadcast: $e');
      return false;
    }
  }

  Future<bool> buyCredits({
    required String tenantId,
    required int credits,
    required double amountKwacha,
    required String paymentRef,
  }) async {
    try {
      await _client.functions.invoke(
        'buy-sms-credits',
        method: HttpMethod.post,
        body: {
          'tenant_id': tenantId,
          'credits': credits,
          'amount_kwacha': amountKwacha,
          'payment_ref': paymentRef,
        },
      );
      return true;
    } catch (e) {
      debugPrint('Error buying SMS credits: $e');
      return false;
    }
  }
}

final tenantSmsServiceProvider = Provider((ref) {
  return TenantSmsService(Supabase.instance.client);
});

final smsBalanceProvider = FutureProvider.family<int, String>((ref, tenantId) async {
  return ref.watch(tenantSmsServiceProvider).getBalance(tenantId);
});
