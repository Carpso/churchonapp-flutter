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
  final String? organizationId;
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
    this.organizationId,
    this.isVerified = false,
    this.walletId,
    this.membershipId,
    this.dateOfBirth,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id']?.toString() ?? '',
      name:
          (map['full_name'] ?? map['name'] ?? map['displayName'] ?? 'Believer')
              .toString(),
      role: (map['role'] ?? map['user_role'] ?? 'member').toString(),
      coins: int.tryParse(map['coins']?.toString() ?? '0') ?? 0,
      streakCount: int.tryParse(map['streak_count']?.toString() ?? '0') ?? 0,
      lastReadAt: map['last_read_at'] != null
          ? DateTime.tryParse(map['last_read_at'].toString())
          : null,
      isWorkMode: map['is_work_mode'] == true,
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      balanceCc: (map['balance_cc'] as num?)?.toDouble() ?? 0.0,
      balanceZmw: (map['balance_zmw'] as num?)?.toDouble() ?? 0.0,
      phoneNumber: map['phone_number']?.toString() ?? map['phone']?.toString(),
      avatarUrl: map['avatar_url']?.toString() ?? map['avatar']?.toString(),
      tenantId: map['tenant_id']?.toString(),
      organizationId: map['organization_id']?.toString(),
      isVerified: map['is_verified'] == true,
      walletId: map['wallet_id']?.toString(),
      membershipId: map['membership_id']?.toString(),
      dateOfBirth: map['date_of_birth'] != null
          ? DateTime.tryParse(map['date_of_birth'].toString())
          : null,
    );
  }

  bool get isSuperadmin => role == 'superadmin';
  bool get isEmployee => role == 'coa_employee' || role == 'superadmin';
  bool get isBishopOrHigher =>
      role == 'bishop' || role == 'apostle' || role == 'superadmin' || role == 'coa_employee';
  bool get isPastorOrHigher =>
      isBishopOrHigher || role == 'pastor' || role == 'prophet' || role == 'general_secretary';
  bool get isAdminOrHigher =>
      isPastorOrHigher ||
      role == 'admin' ||
      role == 'leader' ||
      (role.endsWith('_employee') && role != 'coa_employee');
  bool get isTenantAdmin => isAdminOrHigher;
  bool get isLedgerManager =>
      isAdminOrHigher || role == 'usher' || role == 'treasurer';
  bool get isOnboardingOfficer =>
      isSuperadmin || role == 'coa_employee' || role == 'bishop';
  bool get isBishop => role == 'bishop' || role == 'apostle';
  bool get isPastor => role == 'pastor';
  bool get isUsher => role == 'usher';
  bool get isBookshopOwner =>
      role == 'bookshop_owner' || role == 'store_manager' || role == 'vendor';
  bool get isStoreManager =>
      role == 'store_manager' || role == 'bookshop_owner';
  bool get isBookshopStaff => [
    'bookshop_owner',
    'store_manager',
    'assistant',
    'cashier',
  ].contains(role);
  bool get isLeadershipTeam =>
      isAdminOrHigher || role == 'leader' || role == 'department_leader';
  bool get isPraiseTeam =>
      role == 'praise_team_leader' ||
      role == 'worship_leader' ||
      role == 'praise_team_member';
  bool get isWorshipLeader =>
      role == 'worship_leader' || role == 'praise_team_leader';
  bool get isExecutiveOffice =>
      isBishop ||
      role == 'general_secretary' ||
      role == 'general_treasurer' ||
      isSuperadmin;
  bool get canWork => role == 'driver' || role == 'rider';
  bool get isBirthdayToday =>
      dateOfBirth != null &&
      dateOfBirth!.month == DateTime.now().month &&
      dateOfBirth!.day == DateTime.now().day;
  int get age =>
      dateOfBirth == null ? 0 : DateTime.now().year - dateOfBirth!.year;
}

class ProfileNotifier extends Notifier<AsyncValue<UserProfile?>> {
  int _fetchSeq = 0;

  @override
  AsyncValue<UserProfile?> build() {
    final auth = ref.watch(authProvider);
    // Watch tenant so we re-fetch profile and re-derive roles when context changes
    ref.watch(currentTenantProvider);

    final user = auth.user;
    if (user == null) {
      return const AsyncValue.data(null);
    }

    _fetchProfile(user.id, user.email);
    return const AsyncValue.loading();
  }

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> _fetchProfile(String userId, String? email) async {
    final seq = ++_fetchSeq;
    try {
      final res = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      Map<String, dynamic>? profileData;

      final selectedTenant = ref.read(currentTenantProvider);
      if (res == null) {
        final user = ref.read(authProvider).user;
        final metadata = user?.userMetadata;

        String country = 'Zambia';
        if (selectedTenant != null) {
          try {
            final church = await _client
                .from('churches')
                .select('country')
                .eq('tenant_id', selectedTenant.id)
                .maybeSingle();
            if (church != null && church['country'] != null) {
              country = church['country'].toString();
            }
          } catch (e) {
            debugPrint('Error fetching church country: $e');
          }
        }

        final codeGen = ref.read(codeGeneratorProvider);
        final walletId = await codeGen.generateWalletId(country);
        final membershipId = await codeGen.generateMembershipId(country);

        profileData = {
          'id': userId,
          'full_name':
              metadata?['full_name'] ?? metadata?['name'] ?? 'Believer',
          'role': 'member',
          'coins': 0,
          'is_work_mode': false,
          'avatar_url': metadata?['avatar_url'] ?? metadata?['picture'],
          if (selectedTenant != null) 'tenant_id': selectedTenant.id,
          'wallet_id': walletId,
          'membership_id': membershipId,
        };
        await _client.from('profiles').upsert(profileData);

        final iso = CodeGeneratorService.countryToISO(country);
        await codeGen.registerCode(
          codeType: 'wallet',
          codeValue: walletId,
          countryIso: iso,
          userId: userId,
        );
        await codeGen.registerCode(
          codeType: 'membership',
          codeValue: membershipId,
          countryIso: iso,
          userId: userId,
        );
      } else {
        // Use existing data, but ensure it's modifiable if we need to update it
        profileData = Map<String, dynamic>.from(res);

        // Sync local selected tenant with DB profile
        final dbTenantId = profileData['tenant_id']?.toString();

        if (dbTenantId != null &&
            dbTenantId.isNotEmpty &&
            (selectedTenant == null || selectedTenant.id != dbTenantId)) {
          try {
            final service = ref.read(tenantServiceProvider);
            final tenant = await service.getTenantById(dbTenantId);
            if (tenant != null) {
              await ref.read(currentTenantProvider.notifier).setTenant(tenant);
            }
          } catch (e) {
            debugPrint('Error syncing tenant from DB profile: $e');
          }
        } else if (selectedTenant != null && dbTenantId != selectedTenant.id) {
          try {
            await _client
                .from('profiles')
                .update({
                  'tenant_id': selectedTenant.id,
                  'organization_id': selectedTenant.organizationId,
                })
                .eq('id', userId);
            profileData['tenant_id'] = selectedTenant.id;
            profileData['organization_id'] = selectedTenant.organizationId;
          } catch (e) {
            debugPrint('Error updating profile tenant_id in sync: $e');
          }
        }

        // DERIVE ROLE FROM role_assignments FOR CURRENT TENANT
        // This ensures a user's role is scoped to their current tenant.
        // If Pastor John switches from Tenant1 to Tenant2, his role is
        // recalculated from Tenant2's role_assignments, not carried over.
        final effectiveTenantId = selectedTenant?.id ?? profileData['tenant_id']?.toString();
        // role_assignments.tenant_id is a uuid column — only query it with valid
        // UUIDs, otherwise PostgREST returns 400 and kills the whole profile.
        final isUuidTenant = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(effectiveTenantId ?? '');
        // Platform-level roles (superadmin / coa_employee) are global — they
        // must NEVER be overridden or demoted by tenant-scoped role_assignments.
        final isPlatformRole =
            profileData['role'] == 'superadmin' ||
            profileData['role'] == 'coa_employee';
        if (!isPlatformRole &&
            effectiveTenantId != null &&
            effectiveTenantId.isNotEmpty &&
            isUuidTenant) {
          try {
            final assignment = await _client
                .from('role_assignments')
                .select('role_name')
                .eq('user_id', userId)
                .eq('tenant_id', effectiveTenantId)
                .eq('status', 'approved')
                .order('created_at', ascending: false)
                .maybeSingle();

            final assignedRole = assignment?['role_name'] as String?;
            if (assignedRole != null && assignedRole.isNotEmpty && assignedRole != profileData['role']) {
              // Role from role_assignments differs from cached profiles.role
              // Update the cache to stay in sync
              profileData['role'] = assignedRole;
              try {
                await _client
                    .from('profiles')
                    .update({'role': assignedRole})
                    .eq('id', userId);
              } catch (e) {
                debugPrint('Error syncing role cache: $e');
              }
            } else if (assignedRole == null) {
              // No approved role_assignments row for this tenant. role_assignments
              // only ever GRANTS/confirms a role — it must NOT wipe a role that
              // was already set directly on profiles.role (legacy role-onboarding,
              // church-registration, or COA assignment flows). Demoting those
              // users to 'member' here is what broke "Pastor dashboard not
              // showing" — a pastor without a matching role_assignments row was
              // silently rewritten to 'member' on every profile fetch.
              // Only a truly empty role falls back to 'member'.
              final currentRole = profileData['role'] as String?;
              if (currentRole == null || currentRole.isEmpty) {
                profileData['role'] = 'member';
                try {
                  await _client
                      .from('profiles')
                      .update({'role': 'member'})
                      .eq('id', userId);
                } catch (e) {
                  debugPrint('Error resetting role to member: $e');
                }
              }
            }
          } catch (e) {
            debugPrint('Error deriving role from role_assignments: $e');
          }
        }
      }

      if (seq == _fetchSeq) {
        state = AsyncValue.data(UserProfile.fromMap(profileData));
      }
    } catch (e, st) {
      debugPrint("ProfileNotifier Error: $e");
      debugPrint("PROFILE FETCH ERROR: $e\n$st");
      if (seq == _fetchSeq) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> updateRole(String userId, String newRole) async {
    final currentUser = ref.read(authProvider).user;
    if (currentUser == null) return;
    final profile = state.value;
    if (profile == null) return;
    if (!profile.isSuperadmin && !profile.isEmployee) {
      throw Exception("Only superadmins and COA employees can change roles");
    }
    await _client.from('profiles').update({'role': newRole}).eq('id', userId);
    ref.invalidateSelf();
  }

  Future<void> toggleWorkMode() async {
    final profile = state.value;
    if (profile == null) return;
    await _client
        .from('profiles')
        .update({'is_work_mode': !profile.isWorkMode})
        .eq('id', profile.id);
    ref.invalidateSelf();
  }

  Future<void> addCoins(int amount) async {
    final profile = state.value;
    if (profile == null) return;
    await _client
        .from('profiles')
        .update({'coins': (profile.coins) + amount})
        .eq('id', profile.id);
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
        final lastReadDate = DateTime(
          lastRead.year,
          lastRead.month,
          lastRead.day,
        );
        final difference = today.difference(lastReadDate).inDays;

        if (difference == 1) {
          await _client
              .from('profiles')
              .update({
                'streak_count': profile.streakCount + 1,
                'last_read_at': now.toIso8601String(),
              })
              .eq('id', profile.id);
        } else if (difference > 1) {
          await _client
              .from('profiles')
              .update({
                'streak_count': 1,
                'last_read_at': now.toIso8601String(),
              })
              .eq('id', profile.id);
        }
      } else {
        await _client
            .from('profiles')
            .update({'streak_count': 1, 'last_read_at': now.toIso8601String()})
            .eq('id', profile.id);
      }
      ref.invalidateSelf();
    } catch (e) {
      debugPrint("Error updating reading streak: $e");
    }
  }
}

final profileProvider =
    NotifierProvider<ProfileNotifier, AsyncValue<UserProfile?>>(
      ProfileNotifier.new,
    );
