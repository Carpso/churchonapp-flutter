import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_service.dart';

String _resolveSocialName(dynamic profiles, dynamic userId) {
  if (profiles is Map) {
    final name = profiles['full_name'] ?? profiles['username'];
    if (name != null && name.toString().trim().isNotEmpty) {
      return name.toString().trim();
    }
  }
  final uid = userId?.toString() ?? '';
  if (uid.length >= 6) return 'User ${uid.substring(0, 6).toUpperCase()}';
  return 'User';
}

class SocialPost {
  final String id;
  final String userId;
  final String? content;
  final String? mediaUrl;
  final List<String> images;
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
      userName: _resolveSocialName(map['profiles'], map['user_id']),
      userAvatar: map['profiles'] is Map ? map['profiles']['avatar_url'] : null,
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
      userName: _resolveSocialName(map['profiles'], map['user_id']),
      userAvatar: map['profiles'] is Map ? map['profiles']['avatar_url'] : null,
    );
  }
}

class SocialService {
  final SupabaseClient _client;
  SocialService(this._client);

  Future<List<SocialPost>> fetchPosts({String? tenantId, int limit = 15, int offset = 0}) async {
    try {
      var query = _client
          .from('social_posts')
          .select('*, profiles(full_name, avatar_url, role)');

      if (tenantId != null && tenantId.isNotEmpty) {
        // Cast to text for comparison since profiles.tenant_id is text but social_posts.tenant_id is uuid
        query = query.filter('tenant_id::text', 'eq', tenantId);
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return (response as List).map((map) => SocialPost.fromMap(map)).toList();
    } catch (e) {
      debugPrint("social_service: Error fetching social posts: $e");
      return [];
    }
  }

  Stream<List<SocialPost>> streamPosts({String? tenantId}) {
    final hasTenant = tenantId != null && tenantId.isNotEmpty;
    final stream = _client.from('social_posts').stream(primaryKey: ['id']);

    // Realtime streams do NOT support the `profiles(...)` join, so we fetch
    // author names/avatars separately and enrich each post.
    Stream<List<Map<String, dynamic>>> baseStream = stream;
    if (hasTenant) {
      baseStream = stream
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false)
          .limit(50);
    } else {
      baseStream = stream.order('created_at', ascending: false).limit(50);
    }

    return baseStream
        .asyncMap((data) async {
          final posts = (data as List).cast<Map<String, dynamic>>();
          final userIds = posts
              .map((p) => p['user_id']?.toString())
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet();
          final profiles = <String, Map<String, dynamic>>{};
          if (userIds.isNotEmpty) {
            try {
              final res = await _client
                  .from('profiles')
                  .select('id, full_name, avatar_url, role')
                  .inFilter('id', userIds.toList());
              for (final row in (res as List)) {
                final map = Map<String, dynamic>.from(row);
                profiles[map['id']?.toString() ?? ''] = map;
              }
            } catch (e) {
              debugPrint('social_service: profile enrich error: $e');
            }
          }
          return posts.map((map) {
            final enriched = Map<String, dynamic>.from(map);
            final pid = map['user_id']?.toString() ?? '';
            if (profiles.containsKey(pid)) {
              enriched['profiles'] = profiles[pid];
            }
            return SocialPost.fromMap(enriched);
          }).toList();
        })
        .handleError((error) {
      debugPrint('social_service: Stream error (${hasTenant ? "tenant" : "global"}): $error');
      return <SocialPost>[];
    });
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

      if (existing != null) {
        await _client.from('social_likes').delete()
            .eq('post_id', postId)
            .eq('user_id', user.id);
        return false;
      } else {
        await _client.from('social_likes').insert({
          'post_id': postId,
          'user_id': user.id,
        });
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  Future<List<SocialComment>> fetchComments(String postId, {int limit = 50}) async {
    try {
      final res = await _client
          .from('social_comments')
          .select('*, profiles(full_name, avatar_url)')
          .eq('post_id', postId)
          .order('created_at', ascending: true)
          .limit(limit);
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

    // Keep the post's comment counter in sync so counts show everywhere.
    try {
      final res = await _client
          .from('social_posts')
          .select('comments_count')
          .eq('id', postId)
          .maybeSingle();
      final current = (res?['comments_count'] as int?) ?? 0;
      await _client
          .from('social_posts')
          .update({'comments_count': current + 1})
          .eq('id', postId);
    } catch (e) {
      debugPrint("social_service: failed to increment comment count: $e");
    }
  }

  Future<List<SocialPost>> fetchUserPosts(String userId, {int limit = 50}) async {
    try {
      final res = await _client
          .from('social_posts')
          .select('*, profiles(full_name, avatar_url, role)')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (res as List).map((map) => SocialPost.fromMap(map)).toList();
    } catch (e) {
      debugPrint("social_service: Error fetching user posts: $e");
      return [];
    }
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

/// Posts provider with realtime updates
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
      debugPrint('social_posts_provider: filter=$filter, tenantId=$tenantId');
    }
  }

  // If user has no tenant_id for church/friends filter, yield empty
  if ((filter == SocialFeedFilter.church || filter == SocialFeedFilter.friends) &&
      (tenantId == null || tenantId.isEmpty)) {
    yield [];
    return;
  }

  if (filter == SocialFeedFilter.friends && tenantId != null && tenantId.isNotEmpty && userId != null) {
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
    yield* service.streamPosts(tenantId: tenantId).map(
      (posts) => posts.where((p) => friendIds.contains(p.userId)).toList(),
    );
  } else {
    yield* service.streamPosts(tenantId: tenantId).handleError((error) {
      debugPrint('socialPostsProvider: stream error for filter=$filter: $error');
      return <SocialPost>[];
    });
  }
});
