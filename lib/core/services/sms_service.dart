import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class SmsService {
  final SupabaseClient _client;

  SmsService(this._client);

  /// Sends a mission-critical SMS alert via the send-sms Edge Function (Africa's Talking).
  Future<void> sendLogisticsAlert({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        debugPrint('SmsService: Not authenticated');
        return;
      }

      // Resolve tenant_id from the user's profile
      final profile = await _client
          .from('profiles')
          .select('tenant_id')
          .eq('id', user.id)
          .maybeSingle();
      final tenantId = profile?['tenant_id'] as String?;
      if (tenantId == null) {
        debugPrint('SmsService: No tenant_id found for user');
        return;
      }

      // Send SMS via Edge Function (expects tenant_id + phone_numbers array)
      await _client.functions.invoke('send-sms', body: {
        'tenant_id': tenantId,
        'phone_numbers': [phoneNumber],
        'message': message,
      });

      // Log in our audit trail
      await _client.from('sms_logs').insert({
        'phone_number': phoneNumber,
        'message': message,
        'type': 'logistics_alert',
        'status': 'sent',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('SmsService: Failed to send SMS: $e');
      // Still log failed attempts
      await _client.from('sms_logs').insert({
        'phone_number': phoneNumber,
        'message': message,
        'type': 'logistics_alert',
        'status': 'failed',
        'error': e.toString(),
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Specialized alert for Driver/Rider matching
  Future<void> sendMissionMatchedAlert(String phoneNumber, String missionType, String partnerName) async {
    final msg = "ALERT: Your $missionType has been accepted by $partnerName. Open Church On App to track live!";
    await sendLogisticsAlert(phoneNumber: phoneNumber, message: msg);
  }

  /// Critical safety alert
  Future<void> sendSafetyAlert(String phoneNumber, String driverName, String plateNumber) async {
    final msg = "SAFETY ALERT: Your Driver $driverName (Vehicle: $plateNumber) has arrived. Please verify before boarding.";
    await sendLogisticsAlert(phoneNumber: phoneNumber, message: msg);
  }
}

final smsServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return SmsService(client);
});

