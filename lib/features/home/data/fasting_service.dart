import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class UserFast {
  final String id;
  final String fastType;
  final int durationDays;
  final int durationHours;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String status;

  UserFast({
    required this.id,
    required this.fastType,
    required this.durationDays,
    int? durationHours,
    required this.startedAt,
    this.completedAt,
    required this.status,
  }) : durationHours = durationHours ?? (durationDays * 24);

  factory UserFast.fromMap(Map<String, dynamic> map) {
    final days = int.tryParse(map['duration_days']?.toString() ?? '3') ?? 3;
    final hours = int.tryParse(map['duration_hours']?.toString() ?? '') ?? (days * 24);
    return UserFast(
      id: map['id']?.toString() ?? '',
      fastType: map['fast_type']?.toString() ?? 'Daniel Fast',
      durationDays: days,
      durationHours: hours,
      startedAt: DateTime.parse(map['started_at']),
      completedAt: map['completed_at'] != null ? DateTime.tryParse(map['completed_at'].toString()) : null,
      status: map['status']?.toString() ?? 'active',
    );
  }

  DateTime get endTime => startedAt.add(Duration(hours: durationHours));
  DateTime get startTime => startedAt;
  bool get isActive => status == 'active' && DateTime.now().isBefore(endTime);
  bool get isCurrentlyActive => isActive;
  List<String> get blockedApps => const ['social_media', 'entertainment'];

  double get percentComplete {
    final total = endTime.difference(startedAt).inSeconds;
    if (total <= 0) return 1.0;
    final elapsed = DateTime.now().difference(startedAt).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }
}

class FastingService {
  final SupabaseClient _client;

  FastingService(this._client);

  static const Map<String, String> techFastLabels = {
    'social_media': 'Social Media Fast',
    'entertainment': 'Entertainment Fast',
    'news': 'News & Media Fast',
    'all_tech': 'Complete Tech Fast',
  };

  static const Map<String, String> appCategoryLabels = techFastLabels;

  Future<UserFast?> getActiveFast() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final data = await _client
        .from('user_fasts')
        .select()
        .eq('user_id', user.id)
        .eq('status', 'active')
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (data == null) return null;
    final fast = UserFast.fromMap(data);
    if (fast.isActive) return fast;

    await _client.from('user_fasts').update({'status': 'completed', 'completed_at': DateTime.now().toIso8601String()}).eq('id', fast.id);
    return null;
  }

  Future<UserFast> startFast(String fastType, int durationDays, {int? durationHours}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    final hours = durationHours ?? (durationDays * 24);

    // Auto-complete any existing active fasts to prevent stale state
    await _client
        .from('user_fasts')
        .update({'status': 'completed', 'completed_at': DateTime.now().toIso8601String()})
        .eq('user_id', user.id)
        .eq('status', 'active');

    final data = await _client.from('user_fasts').insert({
      'user_id': user.id,
      'fast_type': fastType,
      'duration_days': durationDays,
      'started_at': DateTime.now().toIso8601String(),
      'status': 'active',
    }).select().single();

    final fastMap = Map<String, dynamic>.from(data);
    fastMap['duration_hours'] = hours;
    return UserFast.fromMap(fastMap);
  }

  Future<void> endFast(String fastId) async {
    await _client.from('user_fasts').update({
      'status': 'completed',
      'completed_at': DateTime.now().toIso8601String(),
    }).eq('id', fastId);
  }

  Future<List<UserFast>> getHistory() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    final data = await _client
        .from('user_fasts')
        .select()
        .eq('user_id', user.id)
        .order('started_at', ascending: false)
        .limit(20);

    return (data as List).map((map) => UserFast.fromMap(map)).toList();
  }

  Future<void> endTechFast(String fastId) => endFast(fastId);
}

typedef FastSchedule = UserFast;

final fastingServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return FastingService(client);
});

final activeFastProvider = FutureProvider<UserFast?>((ref) {
  return ref.watch(fastingServiceProvider).getActiveFast();
});

final activeTechFastProvider = activeFastProvider;

final fastHistoryProvider = FutureProvider<List<UserFast>>((ref) {
  return ref.watch(fastingServiceProvider).getHistory();
});

final techFastHistoryProvider = fastHistoryProvider;
