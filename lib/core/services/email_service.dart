import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EmailService {
  final SupabaseClient _client;

  EmailService(this._client);

  Future<bool> sendSecurityAlert({
    required String recipientEmail,
    required String userName,
    required String eventType,
    required String details,
    String? ipAddress,
  }) async {
    try {
      final result = await _client.functions.invoke('send-email', body: {
        'type': 'security_alert',
        'to': recipientEmail,
        'userName': userName,
        'eventType': eventType,
        'details': details,
        'ipAddress': ipAddress,
      });

      return result.data != null && result.data['success'] == true;
    } catch (e) {
      debugPrint('EmailService: sendSecurityAlert error: $e');
      return false;
    }
  }

  Future<bool> sendWelcomeEmail({
    required String recipientEmail,
    required String userName,
    String? churchName,
  }) async {
    try {
      final result = await _client.functions.invoke('send-email', body: {
        'type': 'welcome',
        'to': recipientEmail,
        'userName': userName,
        'churchName': churchName,
      });

      return result.data != null && result.data['success'] == true;
    } catch (e) {
      debugPrint('EmailService: sendWelcomeEmail error: $e');
      return false;
    }
  }

  Future<bool> sendPaymentReceipt({
    required String recipientEmail,
    required String userName,
    required double amount,
    required String paymentType,
    required String reference,
    String? churchName,
  }) async {
    try {
      final result = await _client.functions.invoke('send-email', body: {
        'type': 'payment_receipt',
        'to': recipientEmail,
        'userName': userName,
        'amount': amount.toStringAsFixed(2),
        'paymentType': paymentType,
        'reference': reference,
        'churchName': churchName,
      });

      return result.data != null && result.data['success'] == true;
    } catch (e) {
      debugPrint('EmailService: sendPaymentReceipt error: $e');
      return false;
    }
  }

  Future<bool> sendChurchApproval({
    required String recipientEmail,
    required String churchName,
    required bool isApproved,
    String? rejectionReason,
  }) async {
    try {
      final result = await _client.functions.invoke('send-email', body: {
        'type': 'church_approval',
        'to': recipientEmail,
        'churchName': churchName,
        'isApproved': isApproved,
        'rejectionReason': rejectionReason,
      });

      return result.data != null && result.data['success'] == true;
    } catch (e) {
      debugPrint('EmailService: sendChurchApproval error: $e');
      return false;
    }
  }

  Future<bool> sendEventConfirmation({
    required String recipientEmail,
    required String userName,
    required String eventName,
    required String eventDate,
    String? eventLocation,
  }) async {
    try {
      final result = await _client.functions.invoke('send-email', body: {
        'type': 'event_confirmation',
        'to': recipientEmail,
        'userName': userName,
        'eventName': eventName,
        'eventDate': eventDate,
        'eventLocation': eventLocation,
      });

      return result.data != null && result.data['success'] == true;
    } catch (e) {
      debugPrint('EmailService: sendEventConfirmation error: $e');
      return false;
    }
  }

  Future<bool> sendSubscriptionWarning({
    required String recipientEmail,
    required String churchName,
    required int daysRemaining,
  }) async {
    try {
      final result = await _client.functions.invoke('send-email', body: {
        'type': 'subscription_warning',
        'to': recipientEmail,
        'churchName': churchName,
        'daysRemaining': daysRemaining,
      });

      return result.data != null && result.data['success'] == true;
    } catch (e) {
      debugPrint('EmailService: sendSubscriptionWarning error: $e');
      return false;
    }
  }
}

final emailServiceProvider = Provider<EmailService>((ref) {
  return EmailService(Supabase.instance.client);
});
