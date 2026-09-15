import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class CommunityService {
  final SupabaseClient _client;

  CommunityService(this._client);

  /// Fetch communities with their nested groups.
  ///
  /// Church groups are **TENANT-ALIGNED**: only the caller's own church's
  /// communities/groups are returned. The cross-church / "global" experience
  /// lives in the church social feed (Connect), which has its own
  /// All / My Church / Friends filters.
  Future<List<Map<String, dynamic>>> fetchCommunities({String? tenantId}) async {
    try {
      if (tenantId == null || tenantId.isEmpty) return const [];

      final communitiesRes = List<Map<String, dynamic>>.from(await _client
          .from('community_communities')
          .select()
          .eq('tenant_id', tenantId)
          .order('sort_order'));

      final groupsRes = List<Map<String, dynamic>>.from(await _client
          .from('community_groups')
          .select()
          .eq('tenant_id', tenantId)
          .order('sort_order'));

      final allGroups = List<Map<String, dynamic>>.from(groupsRes);

      final List<Map<String, dynamic>> result = [];
      for (final community in communitiesRes) {
        final communityGroups = allGroups
            .where((g) => g['community_id'] == community['id'])
            .map((g) => {
                  'id': g['id'],
                  'communityId': g['community_id'],
                  'title': g['title'] ?? '',
                  'subtitle': g['subtitle'] ?? '',
                  'image': g['image_url'] ?? '',
                  'groupId': g['group_identifier'] ?? '',
                  'isAnnouncement': g['is_announcement'] ?? false,
                  'isPublic': g['is_public'] ?? true,
                  'count': g['member_count'] ?? 0,
                  'tenantId': g['tenant_id'],
                  'createdBy': g['created_by'],
                })
            .toList();
        result.add({
          'id': community['id'],
          'name': community['name'] ?? '',
          'description': community['description'] ?? '',
          'banner': community['banner_url'] ?? '',
          'avatar': community['avatar_url'] ?? '',
          'isPublic': community['is_public'] ?? false,
          'tenantId': community['tenant_id'],
          'createdBy': community['created_by'],
          'groups': communityGroups,
        });
      }
      return result;
    } catch (e) {
      debugPrint('[CommunityService] fetchCommunities error: $e');
      return [];
    }
  }

  /// Fetch groups directly (flattened) for the communities screen.
  /// TENANT-ALIGNED — only the caller's own church's groups.
  Future<List<Map<String, dynamic>>> fetchGroups({String? tenantId}) async {
    try {
      if (tenantId == null || tenantId.isEmpty) return const [];
      final res = await _client
          .from('community_groups')
          .select()
          .eq('tenant_id', tenantId)
          .order('sort_order');
      return List<Map<String, dynamic>>.from(res).map((g) => {
        'id': g['id'],
        'communityId': g['community_id'],
        'title': g['title'] ?? '',
        'subtitle': g['subtitle'] ?? '',
        'image': g['image_url'] ?? '',
        'groupId': g['group_identifier'] ?? '',
        'isAnnouncement': g['is_announcement'] ?? false,
        'isPublic': g['is_public'] ?? true,
        'count': g['member_count'] ?? 0,
        'tenantId': g['tenant_id'],
        'createdBy': g['created_by'],
      }).toList();
    } catch (e) {
      debugPrint('[CommunityService] fetchGroups error: $e');
      return [];
    }
  }

  // ── Create / edit ─────────────────────────────────────────────────────────

  Future<String?> _myTenantId() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final p = await _client
          .from('profiles')
          .select('tenant_id')
          .eq('id', user.id)
          .maybeSingle();
      return p?['tenant_id']?.toString();
    } catch (e) {
      debugPrint('[CommunityService] tenant lookup failed: $e');
      return null;
    }
  }

  /// Create a community in the caller's own church. Returns the new id.
  Future<String?> createCommunity({
    required String name,
    String? description,
    bool isPublic = true,
  }) async {
    final user = _client.auth.currentUser;
    final tenantId = await _myTenantId();
    if (user == null || tenantId == null) return null;
    final res = await _client
        .from('community_communities')
        .insert({
          'name': name,
          'description': description,
          'is_public': isPublic,
          'tenant_id': tenantId,
          'created_by': user.id,
          'sort_order': 99,
        })
        .select('id')
        .maybeSingle();
    return res?['id']?.toString();
  }

  Future<void> updateCommunity(
    String id, {
    String? name,
    String? description,
    bool? isPublic,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (description != null) patch['description'] = description;
    if (isPublic != null) patch['is_public'] = isPublic;
    if (patch.isEmpty) return;
    await _client.from('community_communities').update(patch).eq('id', id);
  }

  Future<void> deleteCommunity(String id) async {
    await _client.from('community_communities').delete().eq('id', id);
  }

  /// Create a group inside a community. Uses the community's tenant so the
  /// row stays church-aligned even if the caller's profile is out of sync.
  Future<String?> createGroup({
    required String communityId,
    required String title,
    String? subtitle,
    bool isAnnouncement = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    String? tenantId = await _myTenantId();
    try {
      final c = await _client
          .from('community_communities')
          .select('tenant_id')
          .eq('id', communityId)
          .maybeSingle();
      tenantId = c?['tenant_id']?.toString() ?? tenantId;
    } catch (_) {}
    final res = await _client
        .from('community_groups')
        .insert({
          'community_id': communityId,
          'title': title,
          'subtitle': subtitle,
          'group_identifier':
              'grp-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
          'is_announcement': isAnnouncement,
          'is_public': true,
          'tenant_id': tenantId,
          'created_by': user.id,
          'sort_order': 99,
        })
        .select('id')
        .maybeSingle();
    return res?['id']?.toString();
  }

  Future<void> updateGroup(
    String id, {
    String? title,
    String? subtitle,
    bool? isAnnouncement,
  }) async {
    final patch = <String, dynamic>{};
    if (title != null) patch['title'] = title;
    if (subtitle != null) patch['subtitle'] = subtitle;
    if (isAnnouncement != null) patch['is_announcement'] = isAnnouncement;
    if (patch.isEmpty) return;
    await _client.from('community_groups').update(patch).eq('id', id);
  }

  Future<void> deleteGroup(String id) async {
    await _client.from('community_groups').delete().eq('id', id);
  }

  /// Check if the current user has joined a group
  Future<bool> isMember(String groupId) async {    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final existing = await _client
          .from('community_group_members')
          .select('id')
          .eq('group_id', groupId)
          .eq('user_id', user.id)
          .maybeSingle();
      return existing != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> joinGroup(String groupId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final existing = await _client
          .from('community_group_members')
          .select('id')
          .eq('group_id', groupId)
          .eq('user_id', user.id)
          .maybeSingle();
      if (existing != null) return true;
      await _client.from('community_group_members').insert({
        'group_id': groupId,
        'user_id': user.id,
      });
      await _bumpMemberCount(groupId, 1);
      return true;
    } catch (e) {
      debugPrint('[CommunityService] joinGroup error: $e');
      return false;
    }
  }

  Future<bool> leaveGroup(String groupId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      await _client
          .from('community_group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', user.id);
      await _bumpMemberCount(groupId, -1);
      return true;
    } catch (e) {
      debugPrint('[CommunityService] leaveGroup error: $e');
      return false;
    }
  }

  Future<void> _bumpMemberCount(String groupId, int delta) async {
    try {
      await _client.rpc('bump_group_member_count', params: {
        'p_group_id': groupId,
        'p_delta': delta,
      });
    } catch (e) {
      debugPrint('[CommunityService] member count bump failed: $e');
    }
  }
}

final communityServiceProvider = Provider<CommunityService>((ref) {
  return CommunityService(Supabase.instance.client);
});

final communitiesStreamProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.read(communityServiceProvider);
  String? tenantId;
    try {
      final profile = ref.read(profileProvider).value;
      tenantId = profile?.tenantId;
    } catch (e) {
      debugPrint('Error reading profile for communities: $e');
    }
    return service.fetchCommunities(tenantId: tenantId);
});

final communityGroupsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final service = ref.read(communityServiceProvider);
  String? tenantId;
    try {
      final profile = ref.read(profileProvider).value;
      tenantId = profile?.tenantId;
    } catch (e) {
      debugPrint('Error reading profile for groups: $e');
    }
    return service.fetchGroups(tenantId: tenantId);
});
