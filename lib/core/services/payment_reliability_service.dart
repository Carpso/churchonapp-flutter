import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Payment reliability service for Church On App
/// Handles retry queues, background verification, and connection-aware polling
/// Critical for Zambian internet conditions
class PaymentReliabilityService {
  final SupabaseClient _client;

  PaymentReliabilityService(this._client);

  /// Queue a payment for retry if it fails
  Future<void> queuePaymentForRetry({
    required String referenceId,
    required double amount,
    required String recipientPhone,
    required String method,
    Map<String, dynamic>? metadata,
  }) async {
    await _client.from('payment_retry_queue').insert({
      'reference_id': referenceId,
      'amount': amount,
      'recipient_phone': recipientPhone,
      'method': method,
      'metadata': metadata ?? {},
      'status': 'pending',
      'attempts': 0,
      'max_attempts': 5,
      'next_retry_at': DateTime.now().toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Process retry queue - called periodically
  Future<void> processRetryQueue() async {
    final pendingPayments = await _client
        .from('payment_retry_queue')
        .select()
        .eq('status', 'pending')
        .lte('next_retry_at', DateTime.now().toIso8601String())
        .lt('attempts', 5)
        .order('created_at');

    for (final payment in pendingPayments) {
      final referenceId = payment['reference_id'];

      if (payment['id'] == null || referenceId == null) {
        continue;
      }
      await _retryPayment(payment);
    }
  }

  /// Retry a single payment
  Future<void> _retryPayment(Map<String, dynamic> payment) async {
    final referenceId = payment['reference_id'];
    final attempts = payment['attempts'] ?? 0;

    try {
      // Update attempt count
      await _client
          .from('payment_retry_queue')
        .update({
          'attempts': attempts + 1,
          'last_attempt_at': DateTime.now().toIso8601String(),
        })
        .eq('id', payment['id']);

      // Check if payment was confirmed via webhook
      final localTx = await _client
          .from('transactions')
          .select('status')
          .eq('reference', referenceId)
          .maybeSingle();

      if (localTx != null) {
        final status = (localTx['status'] ?? '').toString().toLowerCase();
        if (status == 'completed' || status == 'settled' || status == 'success') {
          // Payment confirmed - mark as resolved
          await _client
              .from('payment_retry_queue')
              .update({'status': 'resolved'})
              .eq('id', payment['id']);
          return;
        } else if (status == 'failed' || status == 'cancelled') {
          // Payment failed - mark as failed
          await _client
              .from('payment_retry_queue')
              .update({'status': 'failed'})
              .eq('id', payment['id']);
          return;
        }
      }

      // Check Lipila API status
      final statusResponse = await _client.functions.invoke(
        'lipila-collect',
        body: {
          'action': 'status',
          'reference': referenceId,
        },
      );

      if (statusResponse.data != null && statusResponse.data is Map) {
        final statusData = statusResponse.data as Map;
        final data = statusData['data'] is Map ? statusData['data'] as Map : null;
        final nestedData = data?['data'] is Map ? data!['data'] as Map : null;
        final String status = (nestedData?['status'] ?? data?['status'] ?? '').toString().toLowerCase();

        if (status == 'successful' || status == 'paid' || status == 'completed' || status == 'settled') {
          await _client
              .from('payment_retry_queue')
              .update({'status': 'resolved'})
              .eq('id', payment['id']);
          return;
        }
      }

      // Schedule next retry with exponential backoff
      final nextRetry = DateTime.now().add(Duration(minutes: 5 * (1 << attempts)));
      await _client
          .from('payment_retry_queue')
          .update({
            'next_retry_at': nextRetry.toIso8601String(),
          })
          .eq('id', payment['id']);

    } catch (e) {
      debugPrint('Payment retry failed for $referenceId: $e');

      // Schedule next retry
      final nextRetry = DateTime.now().add(Duration(minutes: 5 * (1 << attempts)));
      await _client
          .from('payment_retry_queue')
          .update({
            'next_retry_at': nextRetry.toIso8601String(),
          })
          .eq('id', payment['id']);
    }
  }

  /// Background verification - check all pending payments
  Future<void> verifyPendingPayments() async {
    final pending = await _client
        .from('payment_retry_queue')
        .select('reference_id')
        .eq('status', 'pending');

    for (final payment in pending) {
      final referenceId = payment['reference_id'];

      // Check local DB
      final localTx = await _client
          .from('transactions')
          .select('status')
          .eq('reference', referenceId)
          .maybeSingle();

      if (localTx != null) {
        final status = (localTx['status'] ?? '').toString().toLowerCase();
        if (status == 'completed' || status == 'settled' || status == 'success') {
          await _client
              .from('payment_retry_queue')
              .update({'status': 'resolved'})
              .eq('reference_id', referenceId);
        }
      }
    }
  }

  /// Get user's pending payments
  Future<List<Map<String, dynamic>>> getMyPendingPayments() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final result = await _client
        .from('payment_retry_queue')
        .select()
        .eq('user_id', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  /// Cancel a pending payment
  Future<void> cancelPayment(String paymentId) async {
    await _client
        .from('payment_retry_queue')
        .update({'status': 'cancelled'})
        .eq('id', paymentId);
  }
}

/// Connection-aware polling helper
class ConnectionAwarePoller {
  final Connectivity _connectivity = Connectivity();
  Timer? _timer;
  bool _isOnline = true;

  /// Start monitoring connection
  void startMonitoring(void Function() onOnline, void Function() onOffline) {
    _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = result.any((r) => r != ConnectivityResult.none);

      if (!wasOnline && _isOnline) {
        onOnline();
      } else if (wasOnline && !_isOnline) {
        onOffline();
      }
    });
  }

  /// Get polling interval based on connection quality
  Duration getPollingInterval() {
    if (_isOnline) {
      return Duration(seconds: 4); // Fast polling when online
    } else {
      return Duration(seconds: 30); // Slow polling when offline
    }
  }

  bool get isOnline => _isOnline;

  void dispose() {
    _timer?.cancel();
  }
}

/// Payment status widget that shows real-time updates
class PaymentStatusTracker extends StatefulWidget {
  final String referenceId;
  final Widget Function(VerificationStatus status) builder;

  const PaymentStatusTracker({
    super.key,
    required this.referenceId,
    required this.builder,
  });

  @override
  State<PaymentStatusTracker> createState() => _PaymentStatusTrackerState();
}

class _PaymentStatusTrackerState extends State<PaymentStatusTracker> {
  VerificationStatus _status = VerificationStatus.checking;
  Timer? _timer;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  void _startTracking() {
    _timer = Timer.periodic(Duration(seconds: 4), (_) => _checkStatus());
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    _attempts++;

    try {
      // Check local DB first
      final localTx = await Supabase.instance.client
          .from('transactions')
          .select('status')
          .eq('reference', widget.referenceId)
          .maybeSingle();

      if (localTx != null) {
        final status = (localTx['status'] ?? '').toString().toLowerCase();
        if (status == 'completed' || status == 'settled' || status == 'success') {
          setState(() => _status = VerificationStatus.confirmed);
          _timer?.cancel();
          return;
        } else if (status == 'failed' || status == 'cancelled') {
          setState(() => _status = VerificationStatus.failed);
          _timer?.cancel();
          return;
        }
      }

      // Check Lipila API
      final statusResponse = await Supabase.instance.client.functions.invoke(
        'lipila-collect',
        body: {
          'action': 'status',
          'reference': widget.referenceId,
        },
      );

      if (statusResponse.data != null && statusResponse.data is Map) {
        final statusData = statusResponse.data as Map;
        final data = statusData['data'] is Map ? statusData['data'] as Map : null;
        final nestedData = data?['data'] is Map ? data!['data'] as Map : null;
        final String status = (nestedData?['status'] ?? data?['status'] ?? '').toString().toLowerCase();

        if (status == 'successful' || status == 'paid' || status == 'completed' || status == 'settled') {
          setState(() => _status = VerificationStatus.confirmed);
          _timer?.cancel();
          return;
        } else if (status == 'failed' || status == 'cancelled' || status == 'rejected') {
          setState(() => _status = VerificationStatus.failed);
          _timer?.cancel();
          return;
        }
      }

      // Still processing
      if (_attempts > 60) {
        setState(() => _status = VerificationStatus.timeout);
        _timer?.cancel();
      }
    } catch (e) {
      debugPrint('Payment status check failed: $e');
      // Continue retrying
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_status);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

enum VerificationStatus {
  checking,
  pending,
  confirmed,
  failed,
  timeout,
  cancelled,
}
