import 'dart:io';
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
  });

  factory KingdomVideo.fromMap(Map<String, dynamic> map) {
    return KingdomVideo(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      videoUrl: map['video_url'],
      thumbnailUrl: map['thumbnail_url'],
      views: map['views'] ?? 0,
      likes: map['likes'] ?? 0,
      speaker: map['speaker'],
      churchName: map['church_name'],
      createdAt: DateTime.parse(map['created_at']),
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
      id: map['id'],
      name: map['name'],
      url: map['url'],
      createdBy: map['created_by']?.toString(),
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}

class MediaService {
  final SupabaseClient _client;

  MediaService(this._client);

  Stream<List<KingdomVideo>> getVideosStream() {
    return _client
        .from('videos')
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
    // In real app, we would use an RPC or increment. 
    // For now we just do a raw update for demonstration.
    try {
      final res = await _client.from('videos').select('views').eq('id', id).single();
      final currentViews = res['views'] as int;
      await _client.from('videos').update({'views': currentViews + 1}).eq('id', id);
    } catch (_) {}
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
    } catch (_) {}
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

    // Seed Videos (Kingdom Klips)
    final videos = [
      {
        'title': 'The Power of Prayer',
        'description': 'Pastor John explains the necessity of prayer in the life of a believer.',
        'video_url': 'https://assets.mixkit.co/videos/preview/mixkit-pastor-preaching-at-a-church-service-34538-large.mp4',
        'thumbnail_url': 'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800&q=80',
        'speaker': 'Pastor John',
        'church_name': 'Grace Assemblies'
      },
      {
        'title': 'Kingdom Worship 2024',
        'description': 'Highlights from the national worship night.',
        'video_url': 'https://assets.mixkit.co/videos/preview/mixkit-group-of-friends-partying-happily-4640-large.mp4',
        'thumbnail_url': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=800&q=80',
        'speaker': 'Worship Team',
        'church_name': 'Zion Gates'
      }
    ];

    for (var v in videos) {
      await _client.from('videos').upsert(v, onConflict: 'video_url');
    }

    // Seed Flyers
    final flyers = [
      {
        'name': 'Sunday Celebration',
        'url': 'https://images.unsplash.com/photo-1517457373958-b7bdd4587205?w=800&q=80',
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
