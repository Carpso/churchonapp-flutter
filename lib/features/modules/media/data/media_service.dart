import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class KingdomVideo {
  final String id;
  final String title;
  final String? description;
  final String videoUrl;
  final String? thumbnailUrl;
  final int views;
  final int likes;
  final String? speaker;
  final String? churchName;
  final DateTime createdAt;
  final int amenCount;
  final int commentsCount;
  final int shareCount;
  final String? userAvatar;
  final String? userId;
  final String? userName;
  final List<String> likedBy;

  KingdomVideo({
    required this.id,
    required this.title,
    this.description,
    required this.videoUrl,
    this.thumbnailUrl,
    this.views = 0,
    this.likes = 0,
    this.speaker,
    this.churchName,
    required this.createdAt,
    this.amenCount = 0,
    this.commentsCount = 0,
    this.shareCount = 0,
    this.userAvatar,
    this.userId,
    this.userName,
    this.likedBy = const [],
  });

  factory KingdomVideo.fromMap(Map<String, dynamic> map) {
    return KingdomVideo(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? map['caption'] ?? 'Untitled Klip',
      description: map['description'] ?? map['caption'],
      videoUrl: map['video_url'] ?? map['url'] ?? '',
      thumbnailUrl: map['thumbnail_url'],
      views: map['views'] ?? 0,
      likes: map['likes'] ?? 0,
      speaker: map['speaker'] ?? map['user_name'] ?? map['author'],
      churchName: map['church_name'],
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      amenCount: map['amen_count'] ?? map['likes'] ?? 0,
      commentsCount: map['comments_count'] ?? 0,
      shareCount: map['share_count'] ?? 0,
      userAvatar: map['user_avatar'] ?? map['avatar'],
      userId: map['user_id']?.toString(),
      userName: map['user_name'] ?? map['author'],
      likedBy: map['liked_by'] != null ? List<String>.from(map['liked_by']) : [],
    );
  }
}

class KlipComment {
  final String id;
  final String klipId;
  final String userId;
  final String content;
  final DateTime createdAt;
  final String? userName;
  final String? userAvatar;

  KlipComment({
    required this.id,
    required this.klipId,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.userName,
    this.userAvatar,
  });

  factory KlipComment.fromMap(Map<String, dynamic> map) {
    return KlipComment(
      id: map['id']?.toString() ?? '',
      klipId: map['klip_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      content: map['content'] ?? '',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
      userName: map['profiles'] is Map ? map['profiles']['full_name'] : map['user_name'],
      userAvatar: map['profiles'] is Map ? map['profiles']['avatar_url'] : map['user_avatar'],
    );
  }
}

class KingdomFlyer {
  final String id;
  final String? name;
  final String? url;
  final String? createdBy;
  final DateTime createdAt;

  KingdomFlyer({
    required this.id,
    this.name,
    this.url,
    this.createdBy,
    required this.createdAt,
  });

  factory KingdomFlyer.fromMap(Map<String, dynamic> map) {
    return KingdomFlyer(
      id: map['id']?.toString() ?? '',
      name: map['name'],
      url: map['url'],
      createdBy: map['created_by']?.toString(),
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class MediaService {
  final SupabaseClient _client;

  MediaService(this._client);

  String? get currentUserId => _client.auth.currentUser?.id;

  Stream<List<KingdomVideo>> getVideosStream() {
    return _client
        .from('klips')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data.map((map) => KingdomVideo.fromMap(map)).toList());
  }

  Stream<List<KingdomFlyer>> getFlyersStream() {
    return _client
        .from('flyers')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((data) => data.map((map) => KingdomFlyer.fromMap(map)).toList());
  }

  Future<void> logKlipView(String id) async {
    try {
      final res = await _client.from('klips').select('views').eq('id', id).single();
      final currentViews = (res['views'] as int?) ?? 0;
      await _client.from('klips').update({'views': currentViews + 1}).eq('id', id);
    } catch (e) {
      debugPrint('Failed to log klip view: $e');
    }
  }

  Future<int> toggleLike(String klipId) async {
    final user = _client.auth.currentUser;
    if (user == null) return 0;

    try {
      final res = await _client.from('klips').select('likes, liked_by').eq('id', klipId).single();
      final likedBy = (res['liked_by'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
      final currentLikes = (res['likes'] as int?) ?? 0;

      if (likedBy.contains(user.id)) {
        likedBy.remove(user.id);
        final newLikes = (currentLikes - 1).clamp(0, 999999);
        await _client.from('klips').update({'likes': newLikes, 'liked_by': likedBy}).eq('id', klipId);
        return newLikes;
      } else {
        likedBy.add(user.id);
        final newLikes = currentLikes + 1;
        await _client.from('klips').update({'likes': newLikes, 'liked_by': likedBy}).eq('id', klipId);
        return newLikes;
      }
    } catch (_) {
      try {
        final res = await _client.from('klips').select('amen_count').eq('id', klipId).single();
        final current = (res['amen_count'] as int?) ?? 0;
        await _client.from('klips').update({'amen_count': current + 1}).eq('id', klipId);
        return current + 1;
      } catch (e) {
        debugPrint('Failed to toggle like (fallback): $e');
      }
    }
    return 0;
  }

  Future<void> addComment(String klipId, String content) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client.from('klip_comments').insert({
        'klip_id': klipId,
        'user_id': user.id,
        'content': content,
      });

      final res = await _client.from('klips').select('comments_count').eq('id', klipId).single();
      final current = (res['comments_count'] as int?) ?? 0;
      await _client.from('klips').update({'comments_count': (current + 1).clamp(0, 999999)}).eq('id', klipId);
    } catch (_) {
      try {
        final res = await _client.from('klips').select('comments_count').eq('id', klipId).single();
        final current = (res['comments_count'] as int?) ?? 0;
        await _client.from('klips').update({'comments_count': (current + 1).clamp(0, 999999)}).eq('id', klipId);
      } catch (e) {
        debugPrint('Failed to update comments count (fallback): $e');
      }
    }
  }

  Stream<List<KlipComment>> getCommentsStream(String klipId) {
    return _client
        .from('klip_comments')
        .stream(primaryKey: ['id'])
        .eq('klip_id', klipId)
        .order('created_at', ascending: true)
        .map((data) => data.map((map) => KlipComment.fromMap(map)).toList());
  }

  Future<int> incrementShareCount(String klipId) async {
    try {
      final res = await _client.from('klips').select('share_count').eq('id', klipId).single();
      final current = (res['share_count'] as int?) ?? 0;
      final newCount = current + 1;
      await _client.from('klips').update({'share_count': newCount}).eq('id', klipId);
      return newCount;
    } catch (_) {
      return 0;
    }
  }

  Future<String?> downloadVideo(KingdomVideo video) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/sermon_${video.id}.mp4';
      final file = File(filePath);

      if (await file.exists()) return filePath;

      final response = await http.get(Uri.parse(video.videoUrl));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        
        final prefs = await SharedPreferences.getInstance();
        final downloaded = prefs.getStringList('downloaded_sermons') ?? [];
        if (!downloaded.contains(video.id)) {
          downloaded.add(video.id);
          await prefs.setStringList('downloaded_sermons', downloaded);
        }
        return filePath;
      }
    } catch (e) {
      debugPrint('Failed to download video: $e');
    }
    return null;
  }

  Future<bool> isDownloaded(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    final downloaded = prefs.getStringList('downloaded_sermons') ?? [];
    return downloaded.contains(videoId);
  }

  Future<String?> getLocalPath(String videoId) async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/sermon_$videoId.mp4';
    final file = File(filePath);
    return await file.exists() ? filePath : null;
  }

  Future<void> seedMedia() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    final klips = [
      {
        'title': 'The Power of Prayer',
        'description': 'Pastor John explains the necessity of prayer in the life of a believer.',
        'video_url': 'https://assets.mixkit.co/videos/preview/mixkit-pastor-preaching-at-a-church-service-34538-large.mp4',
        'thumbnail_url': '',
        'speaker': 'Pastor John',
        'church_name': 'Grace Assemblies',
        'user_id': user.id
      },
      {
        'title': 'Worship 2024',
        'description': 'Highlights from the national worship night.',
        'video_url': 'https://assets.mixkit.co/videos/preview/mixkit-group-of-friends-partying-happily-4640-large.mp4',
        'thumbnail_url': '',
        'speaker': 'Worship Team',
        'church_name': 'Zion Gates',
        'user_id': user.id
      }
    ];

    for (var k in klips) {
      await _client.from('klips').upsert(k, onConflict: 'video_url');
    }

    final flyers = [
      {
        'name': 'Sunday Celebration',
        'url': '',
        'created_by': 'Admin'
      }
    ];

    for (var f in flyers) {
      await _client.from('flyers').upsert(f, onConflict: 'url');
    }
  }
}

final mediaServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return MediaService(client);
});

final klipsStreamProvider = StreamProvider<List<KingdomVideo>>((ref) {
  return ref.watch(mediaServiceProvider).getVideosStream();
});

final flyersStreamProvider = StreamProvider<List<KingdomFlyer>>((ref) {
  return ref.watch(mediaServiceProvider).getFlyersStream();
});
