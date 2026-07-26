import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/services/code_generator_service.dart';

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
  final String? walletId;
  final String? membershipId;
  final DateTime? dateOfBirth;

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
    this.walletId,
    this.membershipId,
    this.dateOfBirth,
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
      walletId: map['wallet_id']?.toString(),
      membershipId: map['membership_id']?.toString(),
      dateOfBirth: map['date_of_birth'] != null ? DateTime.tryParse(map['date_of_birth'].toString()) : null,
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
  bool get isBookshopOwner => role == 'bookshop_owner' || role == 'store_manager' || role == 'vendor';
  bool get isStoreManager => role == 'store_manager' || role == 'bookshop_owner';
  bool get isBookshopStaff => ['bookshop_owner', 'store_manager', 'assistant', 'cashier'].contains(role);
  bool get isLeadershipTeam => isAdminOrHigher || role == 'leader' || role == 'department_leader';
  bool get isPraiseTeam => role == 'praise_team_leader' || role == 'worship_leader' || role == 'praise_team_member';
  bool get isWorshipLeader => role == 'worship_leader' || role == 'praise_team_leader';
  bool get isExecutiveOffice => isBishop || role == 'general_secretary' || role == 'general_treasurer' || isSuperadmin;
  bool get canWork => role == 'driver' || role == 'rider';
  bool get isBirthdayToday => dateOfBirth != null && dateOfBirth!.month == DateTime.now().month && dateOfBirth!.day == DateTime.now().day;
  int get age => dateOfBirth == null ? 0 : DateTime.now().year - dateOfBirth!.year;
}

class ProfileNotifier extends Notifier<AsyncValue<UserProfile?>> {
  Future<void>? _fetchFuture;

  @override
  AsyncValue<UserProfile?> build() {
    final auth = ref.watch(authProvider);
    if (auth.user == null) {
      _fetchFuture = null;
      return const AsyncValue.data(null);
    }

    _fetchFuture ??= _fetchProfile(auth.user!.id, auth.user!.email);
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
        final user = ref.read(authProvider).user;
        final metadata = user?.userMetadata;

        String country = 'Zambia';
        if (selectedTenant != null) {
          final church = await _client.from('churches').select('country').eq('tenant_id', selectedTenant.id).maybeSingle();
          if (church != null && church['country'] != null) {
            country = church['country'].toString();
          }
        }

        final codeGen = ref.read(codeGeneratorProvider);
        final walletId = await codeGen.generateWalletId(country);
        final membershipId = await codeGen.generateMembershipId(country);

        profileData = {
          'id': userId,
          'full_name': metadata?['full_name'] ?? metadata?['name'] ?? 'Believer',
          'role': email == superadminEmail ? 'superadmin' : 'member',
          'coins': 0,
          'is_work_mode': false,
          'avatar_url': metadata?['avatar_url'] ?? metadata?['picture'],
          if (selectedTenant != null) 'tenant_id': selectedTenant.id,
          'wallet_id': walletId,
          'membership_id': membershipId,
        };
        await _client.from('profiles').insert(profileData);

        final iso = CodeGeneratorService.countryToISO(country);
        await codeGen.registerCode(codeType: 'wallet', codeValue: walletId, countryIso: iso, userId: userId);
        await codeGen.registerCode(codeType: 'membership', codeValue: membershipId, countryIso: iso, userId: userId);
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
    _fetchFuture = null;
    ref.invalidateSelf();
  }

  Future<void> toggleWorkMode() async {
    final profile = state.value;
    if (profile == null) return;
    await _client.from('profiles').update({'is_work_mode': !profile.isWorkMode}).eq('id', profile.id);
    _fetchFuture = null;
    ref.invalidateSelf();
  }

  Future<void> addCoins(int amount) async {
    final profile = state.value;
    if (profile == null) return;
    await _client.from('profiles').update({'coins': (profile.coins) + amount}).eq('id', profile.id);
    _fetchFuture = null;
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
        } else if (difference > 1) {
          await _client.from('profiles').update({
            'streak_count': 1,
            'last_read_at': now.toIso8601String(),
          }).eq('id', profile.id);
        }
      } else {
        await _client.from('profiles').update({
          'streak_count': 1,
          'last_read_at': now.toIso8601String(),
        }).eq('id', profile.id);
      }
      _fetchFuture = null;
      ref.invalidateSelf();
    } catch (e) {
      debugPrint("Error updating reading streak: $e");
    }
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, AsyncValue<UserProfile?>>(ProfileNotifier.new);
