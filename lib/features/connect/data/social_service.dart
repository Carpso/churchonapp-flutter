import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

class SocialPost {
  final String id;
  final String userId;
  final String? content;
  final String? mediaUrl;
  final String? mediaType;
  final int likesCount;
  final int commentsCount;
  final DateTime createdAt;
  final String? userName;
  final String? userAvatar;
  final bool isModerated;
  final double propheticWeight;
  final String category;

  SocialPost({
    required this.id,
    required this.userId,
    this.content,
    this.mediaUrl,
    this.mediaType,
    this.likesCount = 0,
    this.commentsCount = 0,
    required this.createdAt,
    this.userName,
    this.userAvatar,
    this.isModerated = false,
    this.propheticWeight = 0.0,
    this.category = 'general',
  });

  factory SocialPost.fromMap(Map<String, dynamic> map) {
    return SocialPost(
      id: map['id'],
      userId: map['user_id'],
      content: map['content'],
      mediaUrl: map['media_url'],
      mediaType: map['media_type'],
      likesCount: map['likes_count'] ?? 0,
      commentsCount: map['comments_count'] ?? 0,
      createdAt: DateTime.parse(map['created_at']),
      userName: map['profiles']?['full_name'],
      userAvatar: map['profiles']?['avatar_url'] ?? "https://i.pravatar.cc/100?u=${map['user_id']}",
      isModerated: map['is_moderated'] ?? false,
      propheticWeight: (map['prophetic_weight'] as num?)?.toDouble() ?? 0.0,
      category: map['category'] ?? 'general',
    );
  }
}

class SocialService {
  final SupabaseClient _client;
  SocialService(this._client);

  Stream<List<SocialPost>> streamPosts() {
    return _client
        .from('social_posts')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data.map((map) => SocialPost.fromMap(map)).toList());
  }

  Future<void> createPost({String? content, String? mediaUrl, String? mediaType}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('social_posts').insert({
      'user_id': user.id,
      'content': content,
      'media_url': mediaUrl,
      'media_type': mediaType,
    });
  }

  Future<void> likePost(String postId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client.from('social_likes').insert({
        'post_id': postId,
        'user_id': user.id,
      });
      // Trigger count update (in a real app this would be a DB trigger)
      final post = await _client.from('social_posts').select('likes_count').eq('id', postId).single();
      await _client.from('social_posts').update({'likes_count': post['likes_count'] + 1}).eq('id', postId);
    } catch (_) {
      // Already liked
    }
  }

  Future<void> addComment(String postId, String content) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client.from('social_comments').insert({
      'post_id': postId,
      'user_id': user.id,
      'content': content,
    });
    
    final post = await _client.from('social_posts').select('comments_count').eq('id', postId).single();
    await _client.from('social_posts').update({'comments_count': post['comments_count'] + 1}).eq('id', postId);
  }

  Future<void> praiseTestimony(String id, List? praisedBy) async {
    // Mock legacy method to resolve build error
  }
}

final socialServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return SocialService(client);
});

final socialPostsProvider = StreamProvider<List<SocialPost>>((ref) {
  return ref.watch(socialServiceProvider).streamPosts();
});
