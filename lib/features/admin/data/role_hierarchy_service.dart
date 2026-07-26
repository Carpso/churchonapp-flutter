import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoleApproval {
  final String id;
  final String? tenantId;
  final String userId;
  final String roleName;
  final String? assignedBy;
  final String status;
  final DateTime? approvedAt;
  final DateTime createdAt;
  final String? userFullName;
  final String? userEmail;
  final String? tenantName;

  RoleApproval({
    required this.id,
    this.tenantId,
    required this.userId,
    required this.roleName,
    this.assignedBy,
    this.status = 'pending',
    this.approvedAt,
    required this.createdAt,
    this.userFullName,
    this.userEmail,
    this.tenantName,
  });

  factory RoleApproval.fromMap(Map<String, dynamic> map, {Map<String, dynamic>? profile, Map<String, dynamic>? church}) {
    return RoleApproval(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String?,
      userId: map['user_id'] as String,
      roleName: map['role_name'] as String,
      assignedBy: map['assigned_by'] as String?,
      status: map['status'] as String? ?? 'pending',
      approvedAt: map['approved_at'] != null ? DateTime.parse(map['approved_at'] as String) : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      userFullName: profile?['full_name'] as String?,
      userEmail: profile?['email'] as String?,
      tenantName: church?['name'] as String?,
    );
  }
}

class TenantRole {
  final String id;
  final String? tenantId;
  final String roleName;
  final String? displayName;
  final String? description;
  final bool isSystemRole;
  final String? createdBy;

  TenantRole({
    required this.id,
    this.tenantId,
    required this.roleName,
    this.displayName,
    this.description,
    this.isSystemRole = false,
    this.createdBy,
  });

  factory TenantRole.fromMap(Map<String, dynamic> map) {
    return TenantRole(
      id: map['id'] as String,
      tenantId: map['tenant_id'] as String?,
      roleName: map['role_name'] as String,
      displayName: map['display_name'] as String?,
      description: map['description'] as String?,
      isSystemRole: map['is_system_role'] as bool? ?? false,
      createdBy: map['created_by'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'tenant_id': tenantId,
    'role_name': roleName,
    'display_name': displayName,
    'description': description,
    'is_system_role': isSystemRole,
    'created_by': createdBy,
  };
}

class RoleHierarchyService {
  final SupabaseService _supabase;

  RoleHierarchyService(this._supabase);

  Future<List<RoleApproval>> getPendingApprovals() async {
    final result = await _supabase.client
        .from('role_assignments')
        .select('*, profiles!inner(full_name, email), churches!left(name)')
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return (result as List).map((e) {
      final profile = e['profiles'] as Map<String, dynamic>?;
      final church = e['churches'] as Map<String, dynamic>?;
      return RoleApproval.fromMap(e, profile: profile, church: church);
    }).toList();
  }

  Future<List<RoleApproval>> getUserAssignments(String userId) async {
    final result = await _supabase.client
        .from('role_assignments')
        .select('*, churches!left(name)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (result as List).map((e) {
      final church = e['churches'] as Map<String, dynamic>?;
      return RoleApproval.fromMap(e, church: church);
    }).toList();
  }

  Future<void> assignRole({
    required String userId,
    required String roleName,
    String? tenantId,
  }) async {
    final currentUser = _supabase.client.auth.currentUser!;
    await _supabase.client.from('role_assignments').insert({
      'user_id': userId,
      'role_name': roleName,
      'tenant_id': tenantId,
      'assigned_by': currentUser.id,
      'status': 'pending',
    });
    // Notify superadmins and employees about new role request
    final admins = await _supabase
        .client
        .from('profiles')
        .select('id')
        .inFilter('role', ['superadmin', 'employee']);
    if (admins != null) {
      for (final admin in admins as List) {
        if (admin is Map && admin['id'] != null) {
          await _supabase.client.from('notifications').insert({
            'user_id': admin['id'],
            'title': 'New Role Request',
            'body': '$roleName assignment pending approval for user $userId${tenantId != null ? ' in tenant $tenantId' : ''}',
            'type': 'role_approval',
            'reference_id': userId,
          });
        }
      }
    }
  }

  Future<void> approveRole(String assignmentId) async {
    await _supabase.client.from('role_assignments').update({
      'status': 'approved',
      'approved_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', assignmentId);

    final assignment = await _supabase.client
        .from('role_assignments')
        .select('user_id, role_name')
        .eq('id', assignmentId)
        .single();
    await _supabase.client.from('profiles').update({
      'role': assignment['role_name'],
    }).eq('id', assignment['user_id']);
  }

  Future<void> rejectRole(String assignmentId, {String? reason}) async {
    await _supabase.client.from('role_assignments').update({
      'status': 'rejected',
      'rejected_at': DateTime.now().toUtc().toIso8601String(),
      'rejection_reason': reason,
    }).eq('id', assignmentId);
  }

  Future<List<TenantRole>> getTenantRoles(String? tenantId) async {
    if (tenantId == null) return [];
    final result = await _supabase.client
        .from('tenant_roles')
        .select('id, tenant_id, role_name, display_name, description, is_system_role, created_by')
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false);
    return (result as List).map((e) => TenantRole.fromMap(e)).toList();
  }

  Future<List<TenantRole>> getSystemRoles() async {
    final result = await _supabase.client
        .from('tenant_roles')
        .select('id, tenant_id, role_name, display_name, description, is_system_role, created_by')
        .eq('is_system_role', true)
        .order('role_name', ascending: true);
    return (result as List).map((e) => TenantRole.fromMap(e)).toList();
  }

  Future<void> createTenantRole(TenantRole role) async {
    await _supabase.client.from('tenant_roles').insert(role.toMap());
  }

  Future<void> deleteTenantRole(String roleId) async {
    await _supabase.client.from('tenant_roles').delete().eq('id', roleId);
  }

  Future<void> elevateRole({
    required String userId,
    required String roleName,
    String? tenantId,
  }) async {
    final currentUser = _supabase.client.auth.currentUser!;
    await _supabase.client.from('role_assignments').insert({
      'user_id': userId,
      'role_name': roleName,
      'tenant_id': tenantId,
      'assigned_by': currentUser.id,
      'status': 'approved',
      'approved_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _supabase.client.from('profiles').update({
      'role': roleName,
    }).eq('id', userId);
  }
}

final roleHierarchyServiceProvider = Provider<RoleHierarchyService>((ref) {
  final supabase = ref.read(supabaseServiceProvider);
  return RoleHierarchyService(supabase);
});

final pendingRoleApprovalsProvider = FutureProvider<List<RoleApproval>>((ref) async {
  return ref.read(roleHierarchyServiceProvider).getPendingApprovals();
});
