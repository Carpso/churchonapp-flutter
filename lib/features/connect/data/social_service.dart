import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

class SocialPost {
  final String id;
  final String userId;
  final String? content;
  final String? mediaUrl;
  final List<String> images; // Multi-image support
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
    this.images = const [],
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
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      content: map['content'] ?? '',
      mediaUrl: map['media_url'],
      images: map['images'] != null ? List<String>.from(map['images']) : [],
      mediaType: map['media_type'],
      likesCount: map['likes_count'] ?? 0,
      commentsCount: map['comments_count'] ?? 0,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
      userName: map['profiles'] is Map ? map['profiles']['full_name'] : 'Kingdom Member',
      userAvatar: map['profiles'] is Map ? map['profiles']['avatar_url'] : "https://i.pravatar.cc/100?u=${map['user_id']}",
      isModerated: map['is_moderated'] ?? false,
      propheticWeight: (map['prophetic_weight'] as num?)?.toDouble() ?? 0.0,
      category: map['category'] ?? 'general',
    );
  }
}

class SocialComment {
  final String id;
  final String postId;
  final String userId;
  final String content;
  final DateTime createdAt;
  final String? userName;
  final String? userAvatar;

  SocialComment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.userName,
    this.userAvatar,
  });

  factory SocialComment.fromMap(Map<String, dynamic> map) {
    return SocialComment(
      id: map['id']?.toString() ?? '',
      postId: map['post_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      content: map['content'] ?? '',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
      userName: map['profiles'] is Map ? map['profiles']['full_name'] : 'Member',
      userAvatar: map['profiles'] is Map ? map['profiles']['avatar_url'] : null,
    );
  }
}

class SocialService {
  final SupabaseClient _client;
  SocialService(this._client);

  Future<List<SocialPost>> fetchPosts({String? tenantId}) async {
    try {
      var query = _client
          .from('social_posts')
          .select('*, profiles(full_name, avatar_url, role)');

      if (tenantId != null) {
        query = query.eq('tenant_id', tenantId);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(50);
      return (response as List).map((map) => SocialPost.fromMap(map)).toList();
    } catch (e) {
      debugPrint("social_service: Error fetching social posts: $e");
      return [];
    }
  }

  Future<void> createPost({String? content, String? mediaUrl, List<String>? images, String? mediaType}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception("User not authenticated");

    final profile = await _client
        .from('profiles')
        .select('tenant_id')
        .eq('id', user.id)
        .maybeSingle();

    await _client.from('social_posts').insert({
      'user_id': user.id,
      'content': content,
      'media_url': mediaUrl,
      'images': images ?? [],
      'media_type': mediaType,
      'tenant_id': profile?['tenant_id'],
    });
  }

  /// Returns true if user has liked the post, false otherwise
  Future<bool> hasLiked(String postId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final res = await _client
          .from('social_likes')
          .select('id')
          .eq('post_id', postId)
          .eq('user_id', user.id)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }

  /// Toggle like — inserts if not liked, deletes if already liked. Returns new liked state.
  Future<bool> toggleLike(String postId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    try {
      final existing = await _client
          .from('social_likes')
          .select('id')
          .eq('post_id', postId)
          .eq('user_id', user.id)
          .maybeSingle();

      final post = await _client
          .from('social_posts')
          .select('likes_count')
          .eq('id', postId)
          .single();
      final currentCount = (post['likes_count'] as int?) ?? 0;

      if (existing != null) {
        // Already liked — remove like
        await _client.from('social_likes').delete()
            .eq('post_id', postId)
            .eq('user_id', user.id);
        await _client.from('social_posts')
            .update({'likes_count': (currentCount - 1).clamp(0, 999999)})
            .eq('id', postId);
        return false;
      } else {
        // Not liked — add like
        await _client.from('social_likes').insert({
          'post_id': postId,
          'user_id': user.id,
        });
        await _client.from('social_posts')
            .update({'likes_count': (currentCount + 1).clamp(0, 999999)})
            .eq('id', postId);
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  Future<List<SocialComment>> fetchComments(String postId) async {
    try {
      final res = await _client
          .from('social_comments')
          .select('*, profiles(full_name, avatar_url)')
          .eq('post_id', postId)
          .order('created_at', ascending: true)
          .limit(50);
      return (res as List).map((m) => SocialComment.fromMap(m)).toList();
    } catch (e) {
      debugPrint("social_service: Error fetching comments: $e");
      return [];
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
    final currentComments = (post['comments_count'] as int?) ?? 0;
    await _client.from('social_posts').update({'comments_count': (currentComments + 1).clamp(0, 999999)}).eq('id', postId);
  }

  Future<void> praiseTestimony(String id, List? praisedBy) async {
    // Mock legacy method to resolve build error
  }
}

final socialServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return SocialService(client);
});

enum SocialFeedFilter { all, church, friends }

class SocialFilterNotifier extends Notifier<SocialFeedFilter> {
  @override
  SocialFeedFilter build() => SocialFeedFilter.all;

  void setFilter(SocialFeedFilter filter) => state = filter;
}

final socialFilterProvider = NotifierProvider<SocialFilterNotifier, SocialFeedFilter>(SocialFilterNotifier.new);

final socialPostsProvider = StreamProvider<List<SocialPost>>((ref) async* {
  final service = ref.watch(socialServiceProvider);
  final filter = ref.watch(socialFilterProvider);
  final client = Supabase.instance.client;

  final userId = client.auth.currentUser?.id;
  String? tenantId;
  if (filter == SocialFeedFilter.church || filter == SocialFeedFilter.friends) {
    if (userId != null) {
      final profileRes = await client
          .from('profiles')
          .select('tenant_id')
          .eq('id', userId)
          .maybeSingle();
      tenantId = profileRes?['tenant_id']?.toString();
    }
  }

  if (filter == SocialFeedFilter.friends && tenantId != null && userId != null) {
    final friendsRes = await client
        .from('profiles')
        .select('id')
        .eq('tenant_id', tenantId)
        .neq('id', userId);
    final friendIds = (friendsRes as List).map((m) => m['id'].toString()).toList();
    if (friendIds.isEmpty) {
      yield [];
      return;
    }
    final allPosts = await service.fetchPosts(tenantId: tenantId);
    yield allPosts.where((p) => friendIds.contains(p.userId)).toList();
    await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
      final refreshed = await service.fetchPosts(tenantId: tenantId);
      yield refreshed.where((p) => friendIds.contains(p.userId)).toList();
    }
  } else {
    yield await service.fetchPosts(tenantId: tenantId);
    await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
      yield await service.fetchPosts(tenantId: tenantId);
    }
  }
});
