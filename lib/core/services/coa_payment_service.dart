import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'notification_service.dart';

class CoaPayment {
  final String id;
  final String userId;
  final String serviceType;
  final double amount;
  final String paymentRef;
  final String status;
  final DateTime createdAt;
  final String? approvedBy;
  final DateTime? approvedAt;

  CoaPayment({
    required this.id,
    required this.userId,
    required this.serviceType,
    required this.amount,
    required this.paymentRef,
    this.status = 'pending',
    required this.createdAt,
    this.approvedBy,
    this.approvedAt,
  });

  factory CoaPayment.fromMap(Map<String, dynamic> map) {
    return CoaPayment(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      serviceType: map['service_type']?.toString() ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      paymentRef: map['payment_ref']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      createdAt: DateTime.parse(map['created_at']?.toString() ?? DateTime.now().toIso8601String()),
      approvedBy: map['approved_by']?.toString(),
      approvedAt: map['approved_at'] != null ? DateTime.parse(map['approved_at'].toString()) : null,
    );
  }
}

class CoaPaymentService {
  final SupabaseClient _client;
  CoaPaymentService(this._client);

  Future<String?> submitPayment({
    required String serviceType,
    required double amount,
    required String paymentRef,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final res = await _client.from('coa_payments').insert({
        'user_id': user.id,
        'service_type': serviceType,
        'amount': amount,
        'payment_ref': paymentRef,
        'status': 'pending',
      }).select('id').single();
      return res['id']?.toString();
    } catch (e) {
      debugPrint('Error submitting COA payment: $e');
      return null;
    }
  }

  Future<List<CoaPayment>> getPendingPayments() async {
    try {
      final res = await _client
          .from('coa_payments')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      return (res as List).map((e) => CoaPayment.fromMap(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Error fetching pending COA payments: $e');
      return [];
    }
  }

  Future<bool> approvePayment(String paymentId, String approvedBy) async {
    try {
      // Fetch payment details before updating
      final payment = await _client.from('coa_payments').select('user_id, service_type, amount').eq('id', paymentId).maybeSingle();
      
      await _client.from('coa_payments').update({
        'status': 'approved',
        'approved_by': approvedBy,
        'approved_at': DateTime.now().toIso8601String(),
      }).eq('id', paymentId);

      // Notify the payer that their payment was approved
      if (payment != null && payment['user_id'] != null) {
        try {
          final notifService = NotificationService(_client);
          await notifService.sendNotification(
            userId: payment['user_id'] as String,
            title: 'Payment Approved!',
            body: 'Your ${payment['service_type']} payment of K${(payment['amount'] as num).toStringAsFixed(2)} has been approved. Service activated.',
            type: 'payment_approved',
            referenceId: paymentId,
            channelId: 'coa_payments',
          );
        } catch (e) {
          debugPrint('[CoaPaymentService] Approval notification failed: $e');
        }
      }
      return true;
    } catch (e) {
      debugPrint('Error approving COA payment: $e');
      return false;
    }
  }

  Future<bool> rejectPayment(String paymentId) async {
    try {
      // Fetch payment details before updating
      final payment = await _client.from('coa_payments').select('user_id, service_type, amount').eq('id', paymentId).maybeSingle();
      
      await _client.from('coa_payments').update({
        'status': 'rejected',
      }).eq('id', paymentId);

      // Notify the payer that their payment was rejected
      if (payment != null && payment['user_id'] != null) {
        try {
          final notifService = NotificationService(_client);
          await notifService.sendNotification(
            userId: payment['user_id'] as String,
            title: 'Payment Rejected',
            body: 'Your ${payment['service_type']} payment of K${(payment['amount'] as num).toStringAsFixed(2)} was not approved. Please contact support.',
            type: 'payment_rejected',
            referenceId: paymentId,
            channelId: 'coa_payments',
          );
        } catch (e) {
          debugPrint('[CoaPaymentService] Rejection notification failed: $e');
        }
      }
      return true;
    } catch (e) {
      debugPrint('Error rejecting COA payment: $e');
      return false;
    }
  }

  Stream<List<CoaPayment>> pendingPaymentsStream() {
    return _client
        .from('coa_payments')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .map((data) => data
            .map((e) => CoaPayment.fromMap(Map<String, dynamic>.from(e)))
            .toList());
  }
}

final coaPaymentServiceProvider = Provider((ref) {
  return CoaPaymentService(Supabase.instance.client);
});

final pendingCoaPaymentsProvider = FutureProvider<List<CoaPayment>>((ref) async {
  return ref.watch(coaPaymentServiceProvider).getPendingPayments();
});

final pendingCoaPaymentsStreamProvider = StreamProvider<List<CoaPayment>>((ref) {
  return ref.watch(coaPaymentServiceProvider).pendingPaymentsStream();
});
