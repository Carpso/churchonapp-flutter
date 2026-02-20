import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';

class UserProfile {
  final String id;
  final String name;
  final String? role; // 'member', 'driver', 'admin', 'pastor'
  final int coins;

  UserProfile({
    required this.id,
    required this.name,
    this.role = 'member',
    this.coins = 0,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'],
      name: map['full_name'] ?? 'Believer',
      role: map['role'] ?? 'member',
      coins: map['coins'] ?? 0,
    );
  }
}

class ProfileNotifier extends Notifier<AsyncValue<UserProfile?>> {
  @override
  AsyncValue<UserProfile?> build() {
    _init();
    return const AsyncValue.loading();
  }

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> _init() async {
    final auth = ref.watch(authProvider);
    if (auth.user == null) {
      state = const AsyncValue.data(null);
      return;
    }

    try {
      final res = await _client
          .from('profiles')
          .select()
          .eq('id', auth.user!.id)
          .single();
      state = AsyncValue.data(UserProfile.fromMap(res));
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> updateRole(String newRole) async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    await _client.from('profiles').update({'role': newRole}).eq('id', user.id);
    _init();
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, AsyncValue<UserProfile?>>(() {
  return ProfileNotifier();
});
