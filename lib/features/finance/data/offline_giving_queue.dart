import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Offline giving queue â€” records a giving intent locally when the device
/// has no connectivity and replays it (idempotently, server-side) once the
/// connection returns.
///
/// SECURITY: replay goes through `insert_transaction_idempotent` (SECURITY
/// DEFINER, auth.uid() = p_user_id, idempotent on the payment reference) and
/// `enqueue_payout_task` (server-side settlement engine). A replayed intent
/// can never double-create a transaction, and money movement is never trusted
/// to the client â€” the payout engine only disburses against confirmed
/// `coa_payments` anchors.
class OfflineGivingIntent {
  final String paymentRef;
  final String userId;
  final String? tenantId;
  final double amount;
  final String category;
  final String paymentMethod;
  final String? recipientPhone;
  final String? recipientName;
  final String? recipientRole;
  final DateTime queuedAt;

  OfflineGivingIntent({
    required this.paymentRef,
    required this.userId,
    required this.amount,
    required this.category,
    this.tenantId,
    this.paymentMethod = 'momo',
    this.recipientPhone,
    this.recipientName,
    this.recipientRole,
    DateTime? queuedAt,
  }) : queuedAt = queuedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'payment_ref': paymentRef,
        'user_id': userId,
        'tenant_id': tenantId,
        'amount': amount,
        'category': category,
        'payment_method': paymentMethod,
        'recipient_phone': recipientPhone,
        'recipient_name': recipientName,
        'recipient_role': recipientRole,
        'queued_at': queuedAt.toIso8601String(),
      };

  factory OfflineGivingIntent.fromJson(Map<String, dynamic> json) {
    return OfflineGivingIntent(
      paymentRef: json['payment_ref']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      category: json['category']?.toString() ?? 'giving',
      paymentMethod: json['payment_method']?.toString() ?? 'momo',
      recipientPhone: json['recipient_phone']?.toString(),
      recipientName: json['recipient_name']?.toString(),
      recipientRole: json['recipient_role']?.toString(),
      queuedAt: DateTime.tryParse(json['queued_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class OfflineGivingQueue {
  static const String _queueKey = 'offline_giving_queue';
  static const int _maxRetries = 5;

  final SupabaseClient _client;
  OfflineGivingQueue(this._client);

  bool _isProcessing = false;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Persist a giving intent locally for later replay.
  Future<void> enqueue(OfflineGivingIntent intent) async {
    final queue = await _readQueue();
    // Idempotency: never store the same payment ref twice.
    if (queue.any((i) => i.paymentRef == intent.paymentRef)) return;
    queue.add(intent);
    await _writeQueue(queue);
    debugPrint('OfflineGivingQueue: queued ${intent.paymentRef} (${queue.length} pending)');
  }

  /// Pending intents (newest first).
  Future<List<OfflineGivingIntent>> pending() async {
    final queue = await _readQueue();
    queue.sort((a, b) => b.queuedAt.compareTo(a.queuedAt));
    return queue;
  }

  /// Remove a specific intent (user cancelled or it synced).
  Future<void> remove(String paymentRef) async {
    final queue = await _readQueue();
    queue.removeWhere((i) => i.paymentRef == paymentRef);
    await _writeQueue(queue);
  }

  Future<int> count() async => (await _readQueue()).length;

  /// Replay the whole queue through the server-side idempotent RPCs.
  /// Retries with backoff per intent; items that keep failing stay queued.
  Future<int> syncNow() async {
    if (_isProcessing) return 0;
    _isProcessing = true;
    try {
      final queue = await _readQueue();
      if (queue.isEmpty) return 0;
      final user = _client.auth.currentUser;
      if (user == null) return 0;

      int synced = 0;
      final remaining = <OfflineGivingIntent>[];

      for (final intent in queue) {
        bool done = false;
        for (int attempt = 0; attempt <= _maxRetries && !done; attempt++) {
          try {
            await _client.rpc('insert_transaction_idempotent', params: {
              'p_idempotency_key': 'offline-gift-${intent.paymentRef}',
              'p_user_id': intent.userId,
              'p_tenant_id': intent.tenantId,
              'p_amount': intent.amount,
              'p_type': intent.category,
              'p_currency': 'ZMW',
              'p_payment_method': intent.paymentMethod,
              'p_payment_ref': intent.paymentRef,
              'p_description': 'Offline giving (${intent.category})',
              'p_platform_fee': 0,
            });

            // Server-side settlement: church receives the full amount.
            await _client.rpc('enqueue_payout_task', params: {
              'p_source': 'giving',
              'p_source_ref': null,
              'p_payment_ref': intent.paymentRef,
              'p_recipient_user_id': null,
              'p_recipient_phone': intent.recipientPhone ?? '',
              'p_gross_amount': intent.amount,
              'p_recipient_role': intent.recipientRole?.toLowerCase(),
            });

            done = true;
            synced++;
            debugPrint('OfflineGivingQueue: synced ${intent.paymentRef}');
          } catch (e) {
            debugPrint('OfflineGivingQueue: retry $attempt for ${intent.paymentRef}: $e');
            if (attempt < _maxRetries) {
              await Future.delayed(Duration(seconds: attempt * 3));
            }
          }
        }
        if (!done) remaining.add(intent);
      }

      await _writeQueue(remaining);
      debugPrint('OfflineGivingQueue: synced $synced, ${remaining.length} remaining');
      return synced;
    } finally {
      _isProcessing = false;
    }
  }

  /// Auto-sync whenever connectivity returns.
  void startAutoSync() {
    _subscriptions.add(Connectivity().onConnectivityChanged.listen((result) async {
      final isOnline = result.any((r) => r != ConnectivityResult.none);
      if (isOnline && await count() > 0) {
        await syncNow();
      }
    }));
  }

  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  Future<List<OfflineGivingIntent>> _readQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null) return [];
    try {
      final items = jsonDecode(raw) as List;
      return items
          .map((e) => OfflineGivingIntent.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('OfflineGivingQueue: decode error: $e');
      return [];
    }
  }

  Future<void> _writeQueue(List<OfflineGivingIntent> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(queue.map((i) => i.toJson()).toList()));
  }
}

final offlineGivingQueueProvider = Provider<OfflineGivingQueue>((ref) {
  final queue = OfflineGivingQueue(Supabase.instance.client);
  queue.startAutoSync();
  ref.onDispose(queue.dispose);
  return queue;
});

final offlineGivingPendingProvider = FutureProvider<List<OfflineGivingIntent>>((ref) async {
  return ref.watch(offlineGivingQueueProvider).pending();
});

final offlineGivingCountProvider = FutureProvider<int>((ref) async {
  return ref.watch(offlineGivingQueueProvider).count();
});
