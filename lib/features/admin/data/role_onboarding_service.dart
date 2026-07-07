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
      id: map['id'] as String,
      userId: map['user_id'] as String,
      role: map['role'] as String,
      step: map['step'] as int? ?? 1,
      totalSteps: map['total_steps'] as int? ?? 3,
      isCompleted: map['is_completed'] as bool? ?? false,
      metadata: map['metadata'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class RoleOnboardingService {
  final SupabaseService _supabase;

  RoleOnboardingService(this._supabase);

  Future<RoleOnboarding?> getOnboardingStatus(String role) async {
    final userId = _supabase.client.auth.currentUser!.id;
    final result = await _supabase.client
        .from('role_onboarding')
        .select('*')
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
    final userId = _supabase.client.auth.currentUser!.id;
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
