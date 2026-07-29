import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoleOnboarding {
  final String id;
  final String userId;
  final String role;
  final int step;
  final int totalSteps;
  final bool isCompleted;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  RoleOnboarding({
    required this.id,
    required this.userId,
    required this.role,
    this.step = 1,
    this.totalSteps = 3,
    this.isCompleted = false,
    this.metadata = const {},
    required this.createdAt,
  });

  factory RoleOnboarding.fromMap(Map<String, dynamic> map) {
    return RoleOnboarding(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      role: map['role']?.toString() ?? 'member',
      step: (map['step'] as int?) ?? 1,
      totalSteps: (map['total_steps'] as int?) ?? 3,
      isCompleted: map['is_completed'] == true,
      metadata: (map['metadata'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : {},
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class RoleOnboardingService {
  final SupabaseService _supabase;

  RoleOnboardingService(this._supabase);

  Future<RoleOnboarding?> getOnboardingStatus(String role) async {
    final user = _supabase.client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");
    final userId = user.id;
    final result = await _supabase.client
        .from('role_onboarding')
        .select(
          'id, user_id, role, step, total_steps, is_completed, metadata, created_at',
        )
        .eq('user_id', userId)
        .eq('role', role)
        .maybeSingle();
    if (result == null) return null;
    return RoleOnboarding.fromMap(result);
  }

  Future<void> saveOrUpdate({
    required String role,
    required int step,
    required int totalSteps,
    bool isCompleted = false,
    Map<String, dynamic>? metadata,
  }) async {
    final user = _supabase.client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");
    final userId = user.id;
    await _supabase.client.from('role_onboarding').upsert({
      'user_id': userId,
      'role': role,
      'step': step,
      'total_steps': totalSteps,
      'is_completed': isCompleted,
      'metadata': metadata ?? {},
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> completeOnboarding(String role) async {
    await saveOrUpdate(role: role, step: 0, totalSteps: 0, isCompleted: true);
  }
}

final roleOnboardingServiceProvider = Provider<RoleOnboardingService>((ref) {
  final supabase = ref.read(supabaseServiceProvider);
  return RoleOnboardingService(supabase);
});
