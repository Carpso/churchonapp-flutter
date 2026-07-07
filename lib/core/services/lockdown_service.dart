import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LockdownService {
  final SupabaseService _supabase;

  LockdownService(this._supabase);

  Future<bool> isSystemLocked() async {
    try {
      final result = await _supabase.client.rpc('is_system_locked');
      return result as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> toggleLockdown({required bool lock, required String message}) async {
    final user = _supabase.client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    await _supabase.client.from('system_lockdown').upsert({
      'is_locked': lock,
      'message': message,
      'locked_by': user.id,
      'locked_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String> getLockdownMessage() async {
    try {
      final result = await _supabase.client
          .from('system_lockdown')
          .select('message')
          .limit(1)
          .single();
      return result['message'] as String? ?? 'System is under maintenance.';
    } catch (_) {
      return 'System is under maintenance.';
    }
  }
}

final lockdownServiceProvider = Provider<LockdownService>((ref) {
  final supabase = ref.read(supabaseServiceProvider);
  return LockdownService(supabase);
});

final isSystemLockedProvider = FutureProvider<bool>((ref) async {
  final service = ref.read(lockdownServiceProvider);
  return service.isSystemLocked();
});
