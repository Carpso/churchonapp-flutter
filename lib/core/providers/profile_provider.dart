import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';

class UserProfile {
  final String id;
  final String name;
  final String role;
  final int coins;
  final int streakCount;
  final DateTime? lastReadAt;
  final bool isWorkMode;
  final double lat;
  final double lng;
  final double balanceCc;
  final double balanceZmw;
  final String? phoneNumber;
  final String? avatarUrl;
  final String? tenantId;
  final bool isVerified;

  UserProfile({
    required this.id,
    required this.name,
    this.role = 'member',
    this.coins = 0,
    this.streakCount = 0,
    this.lastReadAt,
    this.isWorkMode = false,
    this.lat = 0.0,
    this.lng = 0.0,
    this.balanceCc = 0.0,
    this.balanceZmw = 0.0,
    this.phoneNumber,
    this.avatarUrl,
    this.tenantId,
    this.isVerified = false,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id']?.toString() ?? '',
      name: (map['full_name'] ?? map['name'] ?? map['displayName'] ?? 'Believer').toString(),
      role: (map['role'] ?? map['user_role'] ?? 'member').toString(),
      coins: int.tryParse(map['coins']?.toString() ?? '0') ?? 0,
      streakCount: int.tryParse(map['streak_count']?.toString() ?? '0') ?? 0,
      lastReadAt: map['last_read_at'] != null ? DateTime.tryParse(map['last_read_at'].toString()) : null,
      isWorkMode: map['is_work_mode'] == true,
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      balanceCc: (map['balance_cc'] as num?)?.toDouble() ?? 0.0,
      balanceZmw: (map['balance_zmw'] as num?)?.toDouble() ?? 0.0,
      phoneNumber: map['phone_number']?.toString() ?? map['phone']?.toString(),
      avatarUrl: map['avatar_url']?.toString() ?? map['avatar']?.toString(),
      tenantId: map['tenant_id']?.toString(),
      isVerified: map['is_verified'] == true,
    );
  }

  bool get isSuperadmin => role == 'superadmin';
  bool get isEmployee => role == 'employee' || role == 'superadmin';
  bool get isAdminOrHigher => role == 'admin' || role == 'pastor' || role == 'bishop' || role == 'superadmin' || role == 'prophet' || role == 'apostle';
  bool get isLedgerManager => isAdminOrHigher || role == 'usher' || role == 'employee';
  bool get isOnboardingOfficer => isSuperadmin || role == 'employee' || role == 'bishop';
  bool get isBishop => role == 'bishop';
  bool get isPastor => role == 'pastor';
  bool get isUsher => role == 'usher';
  bool get isLeadershipTeam => isAdminOrHigher || role == 'leader';
  bool get isExecutiveOffice => isBishop || role == 'general_secretary' || role == 'general_treasurer' || isSuperadmin;
  bool get canWork => role == 'driver' || role == 'rider';
}

class ProfileNotifier extends Notifier<AsyncValue<UserProfile?>> {
  @override
  AsyncValue<UserProfile?> build() {
    final auth = ref.watch(authProvider);
    if (auth.user == null) return const AsyncValue.data(null);
    
    _fetchProfile(auth.user!.id, auth.user!.email);
    return const AsyncValue.loading();
  }

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> _fetchProfile(String userId, String? email) async {
    try {
      final res = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      
      const superadminEmail = 'superadmingosomzkay7@churchonapp.com';
      Map<String, dynamic>? profileData;

      final selectedTenant = ref.read(currentTenantProvider);
      if (res == null) {
        // Fallback: Create new profile client-side if database trigger didn't run or failed
        final user = ref.read(authProvider).user;
        final metadata = user?.userMetadata;
        profileData = {
          'id': userId,
          'full_name': metadata?['full_name'] ?? metadata?['name'] ?? 'Believer',
          'role': email == superadminEmail ? 'superadmin' : 'member',
          'coins': 500,
          'is_work_mode': false,
          'avatar_url': metadata?['avatar_url'] ?? metadata?['picture'],
          if (selectedTenant != null) 'tenant_id': selectedTenant.id,
        };
        await _client.from('profiles').insert(profileData);
      } else {
        // Use existing data, but ensure it's modifiable if we need to update it
        profileData = Map<String, dynamic>.from(res);
        
        // Auto-upgrade superadmin if matching email
        if (email == superadminEmail && profileData['role'] != 'superadmin') {
          await _client.from('profiles').update({'role': 'superadmin'}).eq('id', userId);
          profileData['role'] = 'superadmin';
        }

        // Sync local selected tenant with DB profile
        final dbTenantId = profileData['tenant_id'];
        if (dbTenantId != null && (selectedTenant == null || selectedTenant.id != dbTenantId)) {
          final service = ref.read(tenantServiceProvider);
          final tenant = await service.getTenantById(dbTenantId);
          if (tenant != null) {
            await ref.read(currentTenantProvider.notifier).setTenant(tenant);
          }
        } else if (selectedTenant != null && dbTenantId != selectedTenant.id) {
          await _client.from('profiles').update({'tenant_id': selectedTenant.id}).eq('id', userId);
          profileData['tenant_id'] = selectedTenant.id;
        }
      }
      
      state = AsyncValue.data(UserProfile.fromMap(profileData));
    } catch (e, st) {
      debugPrint("ProfileNotifier Error: $e");
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateRole(String userId, String newRole) async {
    final currentUser = ref.read(authProvider).user;
    if (currentUser == null) return;
    final profile = state.value;
    if (profile == null) return;
    if (!profile.isSuperadmin && !profile.isEmployee) {
      throw Exception("Only superadmins and employees can change roles");
    }
    await _client.from('profiles').update({'role': newRole}).eq('id', userId);
    ref.invalidateSelf();
  }

  Future<void> toggleWorkMode() async {
    final profile = state.value;
    if (profile == null) return;
    await _client.from('profiles').update({'is_work_mode': !profile.isWorkMode}).eq('id', profile.id);
    ref.invalidateSelf();
  }

  Future<void> addCoins(int amount) async {
    final profile = state.value;
    if (profile == null) return;
    await _client.from('profiles').update({'coins': (profile.coins) + amount}).eq('id', profile.id);
    ref.invalidateSelf();
  }

  Future<void> updateReadingStreak() async {
    final profile = state.value;
    if (profile == null) return;

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      if (profile.lastReadAt != null) {
        final lastRead = profile.lastReadAt!.toLocal();
        final lastReadDate = DateTime(lastRead.year, lastRead.month, lastRead.day);
        final difference = today.difference(lastReadDate).inDays;

        if (difference == 1) {
          await _client.from('profiles').update({
            'streak_count': profile.streakCount + 1,
            'last_read_at': now.toIso8601String(),
          }).eq('id', profile.id);
          ref.invalidateSelf();
        } else if (difference > 1) {
          await _client.from('profiles').update({
            'streak_count': 1,
            'last_read_at': now.toIso8601String(),
          }).eq('id', profile.id);
          ref.invalidateSelf();
        }
      } else {
        await _client.from('profiles').update({
          'streak_count': 1,
          'last_read_at': now.toIso8601String(),
        }).eq('id', profile.id);
        ref.invalidateSelf();
      }
    } catch (e) {
      debugPrint("Error updating reading streak: $e");
    }
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, AsyncValue<UserProfile?>>(ProfileNotifier.new);
