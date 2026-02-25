import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';

class UserProfile {
  final String id;
  final String name;
  final String? role; // 'member', 'driver', 'rider', 'writer', 'usher', 'admin', 'pastor', 'bishop', 'superadmin', 'employee'
  final int coins;
  final bool isWorkMode;
  final double? lat;
  final double? lng;
  final double? balanceCc;
  final double? balanceZmw;
  final String? phoneNumber;
  final String? avatarUrl;

  UserProfile({
    required this.id,
    required this.name,
    this.role = 'member',
    this.coins = 0,
    this.isWorkMode = false,
    this.lat,
    this.lng,
    this.balanceCc = 0.0,
    this.balanceZmw = 0.0,
    this.phoneNumber,
    this.avatarUrl,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'],
      name: map['full_name'] ?? 'Believer',
      role: map['role'] ?? 'member',
      coins: map['coins'] ?? 0,
      isWorkMode: map['is_work_mode'] ?? false,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      balanceCc: (map['balance_cc'] as num?)?.toDouble() ?? 0.0,
      balanceZmw: (map['balance_zmw'] as num?)?.toDouble() ?? 0.0,
      phoneNumber: map['phone_number'],
      avatarUrl: map['avatar_url'],
    );
  }

  bool get isSuperadmin => role == 'superadmin';
  bool get isEmployee => role == 'employee' || role == 'superadmin';
  bool get isAdminOrHigher => role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'superadmin';
  
  // High-level access for financial reports
  bool get isLedgerManager => isAdminOrHigher || role == 'usher' || role == 'employee';
  
  // Access for onboarding new churches/users
  bool get isOnboardingOfficer => isSuperadmin || role == 'employee' || role == 'bishop';

  // Bishop's Office / General Conference
  bool get isBishop => role == 'bishop';
  bool get isGeneralSecretary => role == 'general_secretary';
  bool get isGeneralTreasurer => role == 'general_treasurer';
  bool get isElder => role == 'elder';
  
  // Bishop or his executive office (Secretaries/Treasurers at org level)
  bool get isExecutiveOffice => isBishop || isGeneralSecretary || isGeneralTreasurer || isSuperadmin;

  // Leadership Team (Pastors + Elders + Executives)
  bool get isLeadershipTeam => isExecutiveOffice || role == 'pastor' || role == 'elder';

  // Drivers and Riders
  bool get canWork => role == 'driver' || role == 'rider';
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
      var res = await _client
          .from('profiles')
          .select()
          .eq('id', auth.user!.id)
          .maybeSingle();
      
      final userEmail = auth.user!.email;
      const superadminEmail = 'superadmingosomzkay7@churchonapp.com';
      
      if (res == null) {
        // Create profile if missing
        final newProfile = {
          'id': auth.user!.id,
          'full_name': auth.user!.userMetadata?['full_name'] ?? 'Believer',
          'role': userEmail == superadminEmail ? 'superadmin' : 'member',
          'coins': 500,
        };
        await _client.from('profiles').insert(newProfile);
        res = newProfile;
      } else if (userEmail == superadminEmail && res['role'] != 'superadmin') {
        // Force superadmin role for this email
        await _client.from('profiles').update({'role': 'superadmin'}).eq('id', auth.user!.id);
        res['role'] = 'superadmin';
      }
      
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

  Future<void> toggleWorkMode() async {
    final profile = state.value;
    if (profile == null) return;

    final newMode = !profile.isWorkMode;
    await _client.from('profiles').update({'is_work_mode': newMode}).eq('id', profile.id);
    _init();
  }

  Future<void> addCoins(int amount) async {
    final profile = state.value;
    if (profile == null) return;

    await _client.from('profiles').update({'coins': profile.coins + amount}).eq('id', profile.id);
    _init();
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, AsyncValue<UserProfile?>>(() {
  return ProfileNotifier();
});

