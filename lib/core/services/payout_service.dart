import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PayoutService {
  final SupabaseClient _client;

  PayoutService(this._client);

  /// Sends a payout via the lipila-payout Edge Function.
  ///
  /// WARNING: [amount] must ALREADY be netted via `FeeConfig.payoutNet()`
  /// (deducts Lipila's 1.5% disbursement fee + COA's payout fee, min K3).
  /// Never pass a raw payout amount — the recipient would be short-changed.
  Future<void> requestPayout({
    required String accountNumber,
    required double amount,
    String? narration,
    String? referenceId,
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) throw Exception("Not authenticated");

    const functionUrl = 'lipila-payout';

    final response = await _client.functions.invoke(
      functionUrl,
      method: HttpMethod.post,
      body: {
        'accountNumber': accountNumber,
        'amount': amount,
        'narration': narration,
        'referenceId': referenceId,
      },
    );

    if (response.status != 200) {
      throw Exception("Payout failed with status ${response.status}");
    }
  }
}

final payoutServiceProvider = Provider((ref) {
  return PayoutService(Supabase.instance.client);
});
