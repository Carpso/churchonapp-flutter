import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/connectivity_util.dart';

/// One person's attendance, captured while offline.
@immutable
class OfflineAttendanceRecord {
  /// Client-generated key. Makes replay idempotent, so a retry after a partial
  /// network failure can never double-count a person.
  final String localId;
  final String userId;
  final String tenantId;
  final String serviceDate;

  /// Matches the DB default and the app's existing vocabulary.
  final String serviceType;
  final DateTime checkedInAt;
  final String? checkedInBy;
  final String? notes;
  final int attempts;

  const OfflineAttendanceRecord({
    required this.localId,
    required this.userId,
    required this.tenantId,
    required this.serviceDate,
    this.serviceType = 'Sunday Service',
    required this.checkedInAt,
    this.checkedInBy,
    this.notes,
    this.attempts = 0,
  });

  /// `yyyy-MM-dd`, which is what the `service_date DATE` column expects.
  static String formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'local_id': localId,
        'user_id': userId,
        'tenant_id': tenantId,
        'service_date': serviceDate,
        'service_type': serviceType,
        'checked_in_at': checkedInAt.toIso8601String(),
        'checked_in_by': checkedInBy,
        'notes': notes,
        'attempts': attempts,
      };

  factory OfflineAttendanceRecord.fromJson(Map<String, dynamic> json) {
    return OfflineAttendanceRecord(
      localId: json['local_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      serviceDate: json['service_date']?.toString() ?? '',
      serviceType: json['service_type']?.toString() ?? 'Sunday Service',
      checkedInAt:
          DateTime.tryParse(json['checked_in_at']?.toString() ?? '') ??
              DateTime.now(),
      checkedInBy: json['checked_in_by']?.toString(),
      notes: json['notes']?.toString(),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    );
  }

  /// Identity used for dedupe: a person can only be marked present once per
  /// service, which is also the table's UNIQUE constraint
  /// (user_id, tenant_id, service_date, service_type).
  String get dedupeKey =>
      '$userId|$tenantId|$serviceDate|${serviceType.toLowerCase()}';

  OfflineAttendanceRecord withAttempts(int n) => OfflineAttendanceRecord(
        localId: localId,
        userId: userId,
        tenantId: tenantId,
        serviceDate: serviceDate,
        serviceType: serviceType,
        checkedInAt: checkedInAt,
        checkedInBy: checkedInBy,
        notes: notes,
        attempts: n,
      );
}

/// Durable offline queue for attendance.
///
/// ## Why this exists
///
/// Attendance is the one number every pastor is judged on, and it is recorded
/// in the least connected environment in the whole product: a Sunday service in
/// a rural or peri-urban Zambian church, often with one bar of signal behind
/// the person doing the counting. Everything else in the app degrades to a
/// "you are offline" banner, so a pastor who cannot check members in has no
/// way to record who actually turned up.
///
/// Mirrors `OfflineGivingQueue` so both behave identically: same storage, same
/// bounded retries, same drop-after-N policy.
///
/// ## Replay safety
///
/// `member_attendance` has UNIQUE (user_id, tenant_id, service_date,
/// service_type). Replay uses an upsert on that constraint, so a record that
/// actually landed before a timeout is absorbed rather than duplicated, and a
/// genuinely new one is inserted. Retrying is therefore always safe.
class OfflineAttendanceQueue {
  static const String _queueKey = 'offline_attendance_queue';
  static const int _maxRetries = 5;

  /// Bounded so a long offline stretch (a whole weekend with no signal)
  /// cannot grow SharedPreferences without limit.
  static const int _maxQueueLength = 400;

  final SupabaseClient _client;
  OfflineAttendanceQueue(this._client);

  bool _isProcessing = false;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Records attendance locally, then attempts an immediate sync so a device
  /// that merely blipped does not leave work pending.
  Future<bool> record({
    required String userId,
    required String tenantId,
    required DateTime serviceDate,
    String serviceType = 'Sunday Service',
    String? checkedInBy,
    String? notes,
  }) async {
    if (userId.isEmpty || tenantId.isEmpty) return false;

    final record = OfflineAttendanceRecord(
      localId: '${DateTime.now().microsecondsSinceEpoch}-$userId',
      userId: userId,
      tenantId: tenantId,
      serviceDate: OfflineAttendanceRecord.formatDate(serviceDate),
      serviceType: serviceType,
      checkedInAt: DateTime.now(),
      checkedInBy: checkedInBy,
      notes: notes,
    );

    final queue = await _readQueue();
    if (queue.any((r) => r.dedupeKey == record.dedupeKey)) {
      debugPrint('[OfflineAttendance] already queued for ${record.serviceDate}');
      return false;
    }
    queue.add(record);
    if (queue.length > _maxQueueLength) {
      queue.removeRange(0, queue.length - _maxQueueLength);
      debugPrint('[OfflineAttendance] queue trimmed to $_maxQueueLength');
    }
    await _writeQueue(queue);
    debugPrint(
        '[OfflineAttendance] queued ${record.userId} for ${record.serviceDate} (${queue.length} pending)');

    unawaited(sync());
    return true;
  }

  /// Replays everything pending. Safe to call repeatedly.
  Future<int> sync() async {
    if (_isProcessing) return 0;
    _isProcessing = true;
    var synced = 0;
    try {
      final queue = await _readQueue();
      if (queue.isEmpty) return 0;

      final remaining = <OfflineAttendanceRecord>[];
      for (final record in queue) {
        final ok = await _push(record);
        if (ok) {
          synced++;
        } else if (record.attempts + 1 >= _maxRetries) {
          // Give up rather than retry forever; the server is the source of
          // truth and a permanently failing record will not fix itself.
          debugPrint(
              '[OfflineAttendance] dropping ${record.userId} after $_maxRetries attempts');
        } else {
          remaining.add(record.withAttempts(record.attempts + 1));
        }
      }
      await _writeQueue(remaining);
      debugPrint(
          '[OfflineAttendance] synced $synced, ${remaining.length} remaining');
      return synced;
    } finally {
      _isProcessing = false;
    }
  }

  Future<bool> _push(OfflineAttendanceRecord record) async {
    try {
      // Upsert on the table's own UNIQUE constraint. `ignoreDuplicates` absorbs
      // the case where the row landed but the response was lost.
      await _client.from('member_attendance').upsert(
            {
              'user_id': record.userId,
              'tenant_id': record.tenantId,
              'service_date': record.serviceDate,
              'service_type': record.serviceType,
              'checked_in_at': record.checkedInAt.toUtc().toIso8601String(),
              'checked_in_by': record.checkedInBy,
              'notes': record.notes,
            },
            onConflict: 'user_id,tenant_id,service_date,service_type',
            ignoreDuplicates: true,
          );
      return true;
    } catch (e) {
      debugPrint(
          '[OfflineAttendance] retry ${record.attempts + 1} for ${record.userId}: $e');
      return false;
    }
  }

  /// Pending records, newest first. Drives the "N not yet synced" banner.
  Future<List<OfflineAttendanceRecord>> pending() async {
    final queue = await _readQueue();
    return queue.reversed.toList();
  }

  /// Total headcount recorded offline for one service - so the pastor sees a
  /// correct number immediately rather than an empty list.
  Future<int> pendingCountFor({
    required String tenantId,
    required DateTime serviceDate,
    String serviceType = 'Sunday Service',
  }) async {
    final date = OfflineAttendanceRecord.formatDate(serviceDate);
    final queue = await _readQueue();
    return queue
        .where((r) =>
            r.tenantId == tenantId &&
            r.serviceDate == date &&
            r.serviceType.toLowerCase() == serviceType.toLowerCase())
        .length;
  }

  /// Starts replay on every connectivity change. Idempotent.
  void startAutoSync() {
    _subscriptions.add(
      ConnectivityUtil.onConnectivityChanged.listen((online) {
        if (online) unawaited(sync());
      }),
    );
  }

  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
  }

  Future<List<OfflineAttendanceRecord>> _readQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_queueKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map)
            OfflineAttendanceRecord.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (e) {
      debugPrint('[OfflineAttendance] decode error: $e');
      return [];
    }
  }

  Future<void> _writeQueue(List<OfflineAttendanceRecord> queue) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _queueKey,
        jsonEncode([for (final r in queue) r.toJson()]),
      );
    } catch (e) {
      debugPrint('[OfflineAttendance] write failed (non-fatal): $e');
    }
  }
}