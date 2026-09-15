import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';

class FollowService {
  final SupabaseClient _client;
  FollowService(this._client);

  Future<bool> isFollowing(String userId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return false;
    final res = await _client.from('user_follows').select('id').eq('follower_id', me).eq('following_id', userId).maybeSingle();
    return res != null;
  }

  Future<bool> toggleFollow(String userId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw Exception("Not authenticated");
    final existing = await _client.from('user_follows').select('id').eq('follower_id', me).eq('following_id', userId).maybeSingle();
    if (existing != null) {
      await _client.from('user_follows').delete().eq('follower_id', me).eq('following_id', userId);
      return false;
    } else {
      await _client.from('user_follows').insert({'follower_id': me, 'following_id': userId});
      // Notify the followed user (Facebook/TikTok-style "X started following
      // you"). Writes the in-app notification row AND fires a device push.
      _notifyNewFollower(userId);
      return true;
    }
  }

  /// Fire-and-forget: tell `userId` that someone started following them.
  Future<void> _notifyNewFollower(String userId) async {
    try {
      final me = _client.auth.currentUser;
      if (me == null || me.id == userId) return;
      final myName = (me.userMetadata?['full_name'] ??
              me.userMetadata?['name'] ??
              me.email ??
              'Someone')
          .toString();
      await _client.functions.invoke('push-notifications', body: {
        'userId': userId,
        'title': 'New follower',
        'body': '$myName started following you',
        'type': 'follow',
        'referenceId': me.id,
      });
    } catch (e) {
      debugPrint('follow notify failed (non-fatal): $e');
    }
  }

  Future<Map<String, int>> getFollowCounts(String userId) async {
    final followers = await _client.from('user_follows').select('id').eq('following_id', userId);
    final following = await _client.from('user_follows').select('id').eq('follower_id', userId);
    return {'followers': (followers as List).length, 'following': (following as List).length};
  }

  /// People who follow [userId] (with their profile rows).
  Future<List<Map<String, dynamic>>> fetchFollowers(String userId) async {
    final rows = await _client
        .from('user_follows')
        .select('follower_id')
        .eq('following_id', userId);
    return _profilesFor(
        (rows as List).map((r) => r['follower_id'].toString()).toList());
  }

  /// People [userId] follows (with their profile rows).
  Future<List<Map<String, dynamic>>> fetchFollowing(String userId) async {
    final rows = await _client
        .from('user_follows')
        .select('following_id')
        .eq('follower_id', userId);
    return _profilesFor(
        (rows as List).map((r) => r['following_id'].toString()).toList());
  }

  /// Two-step lookup (avoids depending on an FK constraint name).
  Future<List<Map<String, dynamic>>> _profilesFor(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final rows = await _client
          .from('profiles')
          .select('id, full_name, avatar_url, role, tenant_id')
          .inFilter('id', ids);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('follow profiles lookup failed: $e');
      return [];
    }
  }
}

final followServiceProvider = Provider<FollowService>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return FollowService(client);
});
