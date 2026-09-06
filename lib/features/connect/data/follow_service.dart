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
      return true;
    }
  }

  Future<Map<String, int>> getFollowCounts(String userId) async {
    final followers = await _client.from('user_follows').select('id').eq('following_id', userId);
    final following = await _client.from('user_follows').select('id').eq('follower_id', userId);
    return {'followers': (followers as List).length, 'following': (following as List).length};
  }
}

final followServiceProvider = Provider<FollowService>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return FollowService(client);
});
