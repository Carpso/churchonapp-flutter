import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class SmsService {
  final SupabaseClient _client;

  SmsService(this._client);

  /// Sends a mission-critical SMS alert for logistics.
  /// In a production environment, this would call a gateway like Twilio, Bulksms.com, or AfricasTalking.
  Future<void> sendLogisticsAlert({
    required String phoneNumber,
    required String message,
  }) async {
    // 1. Mock the external API call
    print("LOGISTICS SMS -> To: $phoneNumber | Msg: $message");
    
    // 2. Log the SMS in our private VPS audit trail for sovereignty
    await _client.from('sms_logs').insert({
      'phone_number': phoneNumber,
      'message': message,
      'type': 'logistics_alert',
      'status': 'sent_mock',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Specialized alert for Driver/Rider matching
  Future<void> sendMissionMatchedAlert(String phoneNumber, String missionType, String partnerName) async {
    final msg = "KINGDOM ALERT: Your $missionType has been accepted by $partnerName. Open Church On App to track live!";
    await sendLogisticsAlert(phoneNumber: phoneNumber, message: msg);
  }

  /// Critical safety alert
  Future<void> sendSafetyAlert(String phoneNumber, String driverName, String plateNumber) async {
    final msg = "SAFETY ALERT: Your Kingdom Driver $driverName (Vehicle: $plateNumber) has arrived. Please verify before boarding.";
    await sendLogisticsAlert(phoneNumber: phoneNumber, message: msg);
  }
}

final smsServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return SmsService(client);
});

