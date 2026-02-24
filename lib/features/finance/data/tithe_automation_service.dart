import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/services/sms_service.dart';

class TitheAutomationService {
  final SupabaseClient _client;
  final Ref _ref;

  TitheAutomationService(this._client, this._ref);

  /// Scans for members who haven't tithed in the current month and sends a gentle reminder.
  Future<void> sendMonthlyReminders() async {
    final now = DateTime.now();
    final currentPeriod = "${_getMonthName(now.month)} ${now.year}";

    // 1. Get all members with phone numbers
    final profiles = await _client
        .from('profiles')
        .select('id, full_name, phone_number')
        .not('phone_number', 'is', null);

    final smsService = _ref.read(smsServiceProvider);

    for (var profile in profiles) {
      final userId = profile['id'];
      
      // 2. Check if they have a record for this period
      final existing = await _client
          .from('tithe_records')
          .select('id')
          .eq('user_id', userId)
          .eq('period', currentPeriod)
          .maybeSingle();

      if (existing == null) {
        // 3. Send gentle reminder
        final name = profile['full_name'];
        final phone = profile['phone_number'];
        final message = "Peace be with you $name. As we conclude $currentPeriod, this is a gentle reminder to honor your Kingdom Tithe. God bless your faithfulness! - Church On App";
        
        await smsService.sendLogisticsAlert(phoneNumber: phone, message: message);
        
        // Log the reminder in notifications too
        await _client.from('notifications').insert({
          'user_id': userId,
          'title': 'Stewardship Reminder',
          'body': 'A gentle reminder to honor your tithing for $currentPeriod.',
          'is_read': false,
        });
      }
    }
  }

  String _getMonthName(int month) {
    const months = [
      "Jan", "Feb", "Mar", "Apr", "May", "Jun", 
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ];
    return months[month - 1];
  }
}

final titheAutomationServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return TitheAutomationService(client, ref);
});
