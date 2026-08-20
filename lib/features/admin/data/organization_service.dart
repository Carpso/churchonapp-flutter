import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:church_on_app/core/services/supabase_service.dart';
import 'package:church_on_app/core/services/tenant_service.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class Organization {
  final String id;
  final String name;
  final String code;
  final String? logoUrl;
  final String? bishopId;
  final String? secretaryId;
  final String? treasurerId;

  Organization({
    required this.id,
    required this.name,
    required this.code,
    this.logoUrl,
    this.bishopId,
    this.secretaryId,
    this.treasurerId,
  });

  factory Organization.fromMap(Map<String, dynamic> map) {
    return Organization(
      id: map['id'],
      name: map['name'],
      code: map['code'] ?? '',
      logoUrl: map['logo_url'],
      bishopId: map['bishop_id'],
      secretaryId: map['secretary_id'],
      treasurerId: map['treasurer_id'],
    );
  }
}

class HierarchyNode {
  final String id;
  final String organizationId;
  final String levelId;
  final String? parentNodeId;
  final String name;
  final String? tenantId;
  final String? leaderUserId;
  final Map<String, dynamic> metadata;

  HierarchyNode({
    required this.id,
    required this.organizationId,
    required this.levelId,
    this.parentNodeId,
    required this.name,
    this.tenantId,
    this.leaderUserId,
    this.metadata = const {},
  });

  factory HierarchyNode.fromMap(Map<String, dynamic> map) {
    return HierarchyNode(
      id: map['id'],
      organizationId: map['organization_id'],
      levelId: map['level_id'],
      parentNodeId: map['parent_node_id'],
      name: map['name'],
      tenantId: map['tenant_id'],
      leaderUserId: map['leader_user_id'],
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
    );
  }
}

class HierarchicalReport {
  final String id;
  final String organizationId;
  final String nodeId;
  final String authorId;
  final String reportType;
  final String title;
  final Map<String, dynamic> content;
  final String status;
  final int currentLevelRank;
  final List<dynamic> approvalChain;
  final DateTime createdAt;

  HierarchicalReport({
    required this.id,
    required this.organizationId,
    required this.nodeId,
    required this.authorId,
    required this.reportType,
    required this.title,
    required this.content,
    required this.status,
    required this.currentLevelRank,
    this.approvalChain = const [],
    required this.createdAt,
  });

  factory HierarchicalReport.fromMap(Map<String, dynamic> map) {
    return HierarchicalReport(
      id: map['id'],
      organizationId: map['organization_id'],
      nodeId: map['node_id'],
      authorId: map['author_id'],
      reportType: map['report_type'],
      title: map['title'] ?? 'Untitled Report',
      content: Map<String, dynamic>.from(map['content'] ?? {}),
      status: map['status'] ?? 'draft',
      currentLevelRank: map['current_level_rank'] ?? 4,
      approvalChain: List<dynamic>.from(map['approval_chain'] ?? []),
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}

class OrganizationService {
  final SupabaseClient _client;
  OrganizationService(this._client);

  Future<Organization?> getOrganizationByBishop(String bishopId) async {
    final data = await _client
        .from('organizations')
        .select('id, name, code, logo_url, bishop_id, secretary_id, treasurer_id')
        .eq('bishop_id', bishopId)
        .maybeSingle();
    return data != null ? Organization.fromMap(data) : null;
  }

  Future<List<HierarchyNode>> getOrganizationNodes(String orgId) async {
    final res = await _client
        .from('hierarchy_nodes')
        .select()
        .eq('organization_id', orgId)
        .order('name');
    return (res as List).map((e) => HierarchyNode.fromMap(e)).toList();
  }

  Future<List<HierarchyNode>> getChildrenNodes(String parentNodeId) async {
    final res = await _client
        .from('hierarchy_nodes')
        .select()
        .eq('parent_node_id', parentNodeId)
        .order('name');
    return (res as List).map((e) => HierarchyNode.fromMap(e)).toList();
  }

  Future<void> submitHierarchicalReport({
    required String orgId,
    required String nodeId,
    required String type,
    required String title,
    required Map<String, dynamic> content,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    await _client.from('hierarchical_reports').insert({
      'organization_id': orgId,
      'node_id': nodeId,
      'author_id': user.id,
      'report_type': type,
      'title': title,
      'content': content,
      'status': 'pending_local_approval',
    });
  }

  Future<void> approveReport(String reportId, int nextRank, String signOffNote) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    final report = await _client.from('hierarchical_reports').select('approval_chain, status').eq('id', reportId).single();
    final chain = List<dynamic>.from(report['approval_chain'] ?? []);
    chain.add({
      'user_id': user.id,
      'action': 'approved',
      'note': signOffNote,
      'at': DateTime.now().toIso8601String(),
    });

    String newStatus = 'pending_regional_review';
    if (nextRank == 1) newStatus = 'approved_hq';

    await _client.from('hierarchical_reports').update({
      'status': newStatus,
      'current_level_rank': nextRank,
      'approval_chain': chain,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', reportId);
  }

  Stream<List<HierarchicalReport>> streamReportsForOversight(String orgId) {
    return _client
        .from('hierarchical_reports')
        .stream(primaryKey: ['id'])
        .eq('organization_id', orgId)
        .order('created_at', ascending: false)
        .map((data) => data.map((e) => HierarchicalReport.fromMap(e)).toList());
  }

  Stream<List<Tenant>> streamLinkedChurches(String orgId) {
    return _client
        .from('churches')
        .stream(primaryKey: ['id'])
        .eq('organization_id', orgId)
        .map((data) => data.map((map) => Tenant.fromMap(map)).toList());
  }

  Future<void> submitPastorReport({
    required String pastorId,
    required String orgId,
    required String content,
    required Map<String, dynamic> stats,
  }) async {
    await _client.from('pastor_reports').insert({
      'pastor_id': pastorId,
      'organization_id': orgId,
      'content': content,
      'aggregated_stats': stats,
      'status': 'pending', // pending, reviewed by secretary, seen by bishop
    });
  }

  Stream<List<Map<String, dynamic>>> streamPastorReports(String orgId) {
    return _client
        .from('pastor_reports')
        .stream(primaryKey: ['id'])
        .eq('organization_id', orgId)
        .order('created_at', ascending: false);
  }

  Future<Map<String, dynamic>> getOrganizationStats(String orgId) async {
    final res = await _client.rpc('get_organization_stats', params: {'p_org_id': orgId});
    return (res as Map<String, dynamic>?) ?? {
      'members': 0,
      'branches': 0,
      'monthly_giving': 0,
      'active_streams': 0,
    };
  }

  Future<Map<String, dynamic>> getNodeAggregatedStats(String nodeId) async {
    final res = await _client.rpc('get_node_aggregated_stats', params: {'p_node_id': nodeId});
    return (res as Map<String, dynamic>?) ?? {
      'branches': 0,
      'attendance': 0,
      'giving': 0,
    };
  }

  /// Single server-side call replacing the unbounded IN-clause missions scan.
  Future<List<Map<String, dynamic>>> getOrganizationMissions(String orgId, {int limit = 50, String status = 'all'}) async {
    try {
      final res = await _client.rpc('get_organization_missions', params: {
        'p_org_id': orgId,
        'p_limit': limit,
        'p_status': status,
      });
      return List<Map<String, dynamic>>.from(res as List? ?? []);
    } catch (e, s) {
      debugPrint('getOrganizationMissions error: $e');
      debugPrint(s.toString());
      return [];
    }
  }

  /// Single server-side call returning per-branch member counts for an org.
  /// Replaces the unbounded `profiles.select('tenant_id')` scan in the
  /// apostle dashboard with one grouped aggregate.
  Future<List<Map<String, dynamic>>> getOrganizationChurchMemberCounts(String orgId) async {
    try {
      final res = await _client.rpc('get_organization_church_member_counts', params: {'p_org_id': orgId});
      return List<Map<String, dynamic>>.from(res as List? ?? []);
    } catch (e, s) {
      debugPrint('getOrganizationChurchMemberCounts error: $e');
      debugPrint(s.toString());
      return [];
    }
  }

/// Single server-side call replacing separate attendance/profile/transaction scans.
  Future<Map<String, dynamic>> getChurchMonthlyStats(String tenantId) async {
    final res = await _client.rpc('get_church_monthly_stats', params: {'p_tenant_id': tenantId});
    return (res as Map<String, dynamic>?) ?? {
      'attendance_mtd': 0,
      'attendance_previous': 0,
      'tithes_mtd': 0,
      'members': 0,
    };
  }

  /// Monthly settled-giving trend (oldest first) for an org — powers the
  /// bishop network giving chart.
  Future<List<Map<String, dynamic>>> getOrgGivingSeries(String orgId, {int months = 6}) async {
    try {
      final res = await _client.rpc('get_org_giving_series', params: {
        'p_org_id': orgId,
        'p_months': months,
      });
      return List<Map<String, dynamic>>.from(res as List? ?? []);
    } catch (e, s) {
      debugPrint('getOrgGivingSeries error: $e');
      debugPrint(s.toString());
      return [];
    }
  }

  /// Monthly settled-giving trend for a single church (finance dashboard).
  Future<List<Map<String, dynamic>>> getChurchGivingSeries(String tenantId, {int months = 6}) async {
    try {
      final res = await _client.rpc('get_church_giving_series', params: {
        'p_tenant_id': tenantId,
        'p_months': months,
      });
      return List<Map<String, dynamic>>.from(res as List? ?? []);
    } catch (e, s) {
      debugPrint('getChurchGivingSeries error: $e');
      debugPrint(s.toString());
      return [];
    }
  }

  /// Per-branch snapshot (members / attendance MTD / tithes MTD / service
  /// reports MTD) for the bishop's "All Branches" list — ONE RPC instead of
  /// N per-church calls.
  Future<List<Map<String, dynamic>>> getOrgBranchSnapshots(String orgId) async {
    try {
      final res = await _client.rpc('get_org_branch_snapshots', params: {'p_org_id': orgId});
      return List<Map<String, dynamic>>.from(res as List? ?? []);
    } catch (e, s) {
      debugPrint('getOrgBranchSnapshots error: $e');
      debugPrint(s.toString());
      return [];
    }
  }

  /// Link a church to this organization (org-leader or employee gated server-side).
  Future<void> linkChurchToOrg(String churchId, String orgId) async {
    await _client.rpc('link_church_to_org', params: {
      'p_church_id': churchId,
      'p_org_id': orgId,
    });
  }

  /// Unlink a church from its organization (org-leader or employee gated server-side).
  Future<void> unlinkChurchFromOrg(String churchId) async {
    await _client.rpc('unlink_church_from_org', params: {'p_church_id': churchId});
  }

  /// Platform-wide revenue (transactions + wallet fees) — superadmin/COA only.
  Future<Map<String, dynamic>> getPlatformRevenueSummary({int months = 6}) async {
    try {
      final res = await _client.rpc('get_platform_revenue_summary', params: {'p_months': months});
      return (res as Map<String, dynamic>?) ?? {'total_revenue': 0, 'series': []};
    } catch (e, s) {
      debugPrint('getPlatformRevenueSummary error: $e');
      debugPrint(s.toString());
      return {'total_revenue': 0, 'series': []};
    }
  }

  /// Rider lifetime summary (completed trips / fare / distance / active ride).
  Future<Map<String, dynamic>> getRiderSummary(String userId) async {
    try {
      final res = await _client.rpc('get_rider_summary', params: {'p_user_id': userId});
      return (res as Map<String, dynamic>?) ?? {
        'completed_trips': 0,
        'total_fare': 0,
        'total_distance_km': 0,
        'active_ride': null,
      };
    } catch (e, s) {
      debugPrint('getRiderSummary error: $e');
      debugPrint(s.toString());
      return {'completed_trips': 0, 'total_fare': 0, 'total_distance_km': 0, 'active_ride': null};
    }
  }
}

final organizationServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return OrganizationService(client);
});

/// Aggregated stats for a single hierarchy node (a presbytery / region).
/// Falls back to a zero-valued map instead of throwing on empty data.
final nodeAggregatedStatsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, nodeId) async {
  final svc = ref.watch(organizationServiceProvider);
  try {
    return await svc.getNodeAggregatedStats(nodeId);
  } catch (e) {
    debugPrint('get_node_aggregated_stats failed for $nodeId: $e');
    return {'branches': 0, 'attendance': 0, 'giving': 0};
  }
});

class BishopCommandHubStats {
  final int branches;
  final int members;
  final int activeStreams;
  final double monthlyGiving;
  final int networkAttendance;
  final List<HierarchyNode> presbyteries;

  const BishopCommandHubStats({
    required this.branches,
    required this.members,
    required this.activeStreams,
    required this.monthlyGiving,
    required this.networkAttendance,
    required this.presbyteries,
  });
}

/// Bishop Command Hub aggregate: pulls org-wide stats via `get_organization_stats`
/// and per-presbytery totals via `get_node_aggregated_stats`. The active scope
/// (the bishop's `organization_id`) is resolved from the profile so the RPCs are
/// never called with a hardcoded id.
final bishopCommandHubStatsProvider = FutureProvider<BishopCommandHubStats>((ref) async {
  final profile = ref.watch(profileProvider).value;
  final orgId = profile?.organizationId;
  final orgSvc = ref.watch(organizationServiceProvider);

  // GLOBAL EXECUTIVE MODE: org-wide stats via server-side RPCs
  if (orgId != null && orgId.isNotEmpty) {
    final orgStats = await orgSvc.getOrganizationStats(orgId);

    final nodes = await orgSvc.getOrganizationNodes(orgId);
    final presbyteries = nodes.where((n) => n.parentNodeId == null).toList();

    int networkAttendance = 0;
    for (final node in presbyteries) {
      try {
        final nodeStats = await orgSvc.getNodeAggregatedStats(node.id);
        networkAttendance += (nodeStats['attendance'] as num?)?.toInt() ?? 0;
      } catch (e) {
        debugPrint('Failed aggregating node ${node.id}: $e');
      }
    }

    return BishopCommandHubStats(
      branches: (orgStats['branches'] as num?)?.toInt() ?? 0,
      members: (orgStats['members'] as num?)?.toInt() ?? 0,
      activeStreams: (orgStats['active_streams'] as num?)?.toInt() ?? 0,
      monthlyGiving: (orgStats['monthly_giving'] as num?)?.toDouble() ?? 0,
      networkAttendance: networkAttendance,
      presbyteries: presbyteries,
    );
  }

  // LOCAL BISHOP MODE: single-tenant oversight when no org is assigned yet
  final tenantId = profile?.tenantId;
  if (tenantId == null || tenantId.isEmpty) {
    throw Exception("No church or organization assigned to this bishop account.");
  }

  final stats = await orgSvc.getChurchMonthlyStats(tenantId);
  return BishopCommandHubStats(
    branches: 1,
    members: (stats['members'] as num?)?.toInt() ?? 0,
    activeStreams: 0,
    monthlyGiving: (stats['tithes_mtd'] as num?)?.toDouble() ?? 0,
    networkAttendance: (stats['attendance_mtd'] as num?)?.toInt() ?? 0,
    presbyteries: const [],
  );
});

/// Live stream of branches linked to the bishop's organization.
final bishopLinkedChurchesProvider = StreamProvider.family<List<Tenant>, String>((ref, orgId) {
  return ref.watch(organizationServiceProvider).streamLinkedChurches(orgId);
});

