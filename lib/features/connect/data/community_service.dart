import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/providers/profile_provider.dart';

class CommunityService {
  final SupabaseClient _client;

  CommunityService(this._client);

  /// Fetch communities with their nested groups, filtered by tenant.
  Future<List<Map<String, dynamic>>> fetchCommunities({String? tenantId}) async {
    try {
      final List<Map<String, dynamic>> communitiesRes;
      final List<Map<String, dynamic>> groupsRes;

      if (tenantId != null && tenantId.isNotEmpty) {
        communitiesRes = List<Map<String, dynamic>>.from(await _client
            .from('community_communities')
            .select()
            .eq('tenant_id', tenantId)
            .order('sort_order'));

        groupsRes = List<Map<String, dynamic>>.from(await _client
            .from('community_groups')
            .select()
            .or('tenant_id.eq.$tenantId,is_public.is.true,tenant_id.is.null')
            .order('sort_order'));
      } else {
        communitiesRes = List<Map<String, dynamic>>.from(await _client
            .from('community_communities')
            .select()
            .order('sort_order'));

        groupsRes = List<Map<String, dynamic>>.from(await _client
            .from('community_groups')
            .select()
            .order('sort_order'));
      }

      final allGroups = List<Map<String, dynamic>>.from(groupsRes);

      final List<Map<String, dynamic>> result = [];
      for (final community in communitiesRes) {
        final communityGroups = allGroups
            .where((g) => g['community_id'] == community['id'])
            .map((g) => {
                  'id': g['id'],
                  'title': g['title'] ?? '',
                  'subtitle': g['subtitle'] ?? '',
                  'image': g['image_url'] ?? '',
                  'groupId': g['group_identifier'] ?? '',
                  'isAnnouncement': g['is_announcement'] ?? false,
                  'isPublic': g['is_public'] ?? true,
                  'count': g['member_count'] ?? 0,
                  'tenantId': g['tenant_id'],
                })
            .toList();
        result.add({
          'name': community['name'] ?? '',
          'description': community['description'] ?? '',
          'banner': community['banner_url'] ?? '',
          'avatar': community['avatar_url'] ?? '',
          'groups': communityGroups,
        });
      }
      return result;
    } catch (e) {
      debugPrint('[CommunityService] fetchCommunities error: $e');
      return [];
    }
  }

  /// Fetch groups directly (flattened) for the communities screen
  Future<List<Map<String, dynamic>>> fetchGroups({String? tenantId}) async {
    try {
      var query = _client.from('community_groups').select();
      if (tenantId != null && tenantId.isNotEmpty) {
        query = query.or('tenant_id.eq.$tenantId,is_public.is.true,tenant_id.is.null');
      }
      final res = await query.order('sort_order');
      return List<Map<String, dynamic>>.from(res).map((g) => {
        'id': g['id'],
        'title': g['title'] ?? '',
        'subtitle': g['subtitle'] ?? '',
        'image': g['image_url'] ?? '',
        'groupId': g['group_identifier'] ?? '',
        'isAnnouncement': g['is_announcement'] ?? false,
        'isPublic': g['is_public'] ?? true,
        'count': g['member_count'] ?? 0,
        'tenantId': g['tenant_id'],
      }).toList();
    } catch (e) {
      debugPrint('[CommunityService] fetchGroups error: $e');
      return [];
    }
  }

  /// Check if the current user has joined a group
  Future<bool> isMember(String groupId) async {
    final user = _client.auth.currentUser;
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
      final profile = await _client
          .from('profiles')
          .select('id, full_name, tenant_id, avatar_url')
          .eq('id', user.id)
          .single();
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
        'user_name': profile['full_name'] ?? 'Member',
        'avatar_url': profile['avatar_url'],
        'tenant_id': profile['tenant_id'],
      });
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
      return true;
    } catch (e) {
      debugPrint('[CommunityService] leaveGroup error: $e');
      return false;
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
