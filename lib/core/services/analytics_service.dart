import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lightweight client-side analytics — every event lands in `app_events`
/// (RLS: users insert their own rows; only superadmin/coa_employee read).
/// Fire-and-forget: failures never surface to the user.
class AnalyticsService {
  AnalyticsService(this._client);
  final SupabaseClient _client;

  Future<void> logEvent(
    String event, {
    Map<String, dynamic> properties = const {},
    String? tenantId,
  }) async {
    try {
      final user = _client.auth.currentUser;
      await _client.from('app_events').insert({
        'event': event,
        'user_id': user?.id,
        'tenant_id': tenantId ?? user?.userMetadata?['tenant_id']?.toString(),
        'properties': properties,
      });
    } catch (_) {
      // Analytics must never break the user flow.
    }
  }
}

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService(Supabase.instance.client);
});
