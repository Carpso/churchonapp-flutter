import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Sermon {
  final String id;
  final String title;
  final String preacher;
  final String thumbnailUrl;
  final String videoUrl;
  final bool isLive;
  final int viewerCount;
  final String? transcript;
  final String? aiSummary;
  final DateTime createdAt;

  Sermon({
    required this.id,
    required this.title,
    required this.preacher,
    required this.thumbnailUrl,
    required this.videoUrl,
    this.isLive = false,
    this.viewerCount = 0,
    this.transcript,
    this.aiSummary,
    required this.createdAt,
  });

  factory Sermon.fromMap(Map<String, dynamic> map) {
    return Sermon(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? 'Untitled Sermon',
      preacher: map['preacher'] ?? 'Unknown Preacher',
      thumbnailUrl: map['thumbnail_url'] ?? 'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800&q=80',
      videoUrl: map['video_url'] ?? '',
      isLive: map['is_live'] ?? false,
      viewerCount: map['viewer_count'] ?? 0,
      transcript: map['transcript'],
      aiSummary: map['ai_summary'],
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class SermonService {
  final SupabaseClient _client;
  SermonService(this._client);

  Future<List<Sermon>> fetchLatestSermons() async {
    try {
      final response = await _client
          .from('sermons')
          .select()
          .order('created_at', ascending: false)
          .limit(10);
      
      return (response as List).map((s) => Sermon.fromMap(s)).toList();
    } catch (e) {
      // Fallback for prototype if table doesn't exist yet
      return [
        Sermon(
          id: '1',
          title: 'The Path to Faithful Stewardship',
          preacher: 'Pastor John Doe',
          thumbnailUrl: 'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800&q=80',
          videoUrl: 'https://assets.mixkit.co/videos/preview/mixkit-pastor-preaching-at-a-church-service-34538-large.mp4',
          createdAt: DateTime.now(),
        ),
        Sermon(
          id: '2',
          title: 'Grace Abounding',
          preacher: 'Pastor Hope',
          thumbnailUrl: 'https://images.unsplash.com/photo-1543165796-5426273ea430?w=800&q=80',
          videoUrl: 'https://assets.mixkit.co/videos/preview/mixkit-people-praying-in-a-church-34537-large.mp4',
          createdAt: DateTime.now(),
        ),
      ];
    }
  }

  Future<List<Sermon>> searchSermons(String query) async {
    try {
      final response = await _client
          .from('sermons')
          .select()
          .textSearch('fts', query, config: 'english')
          .order('created_at', ascending: false);
      
      return (response as List).map((s) => Sermon.fromMap(s)).toList();
    } catch (e) {
      // Fallback to simple ILIKE if FTS fails or isn't set up yet
      final response = await _client
          .from('sermons')
          .select()
          .or('title.ilike.%$query%,preacher.ilike.%$query%,transcript.ilike.%$query%')
          .order('created_at', ascending: false);
      return (response as List).map((s) => Sermon.fromMap(s)).toList();
    }
  }
}

final sermonServiceProvider = Provider((ref) => SermonService(Supabase.instance.client));

final latestSermonsProvider = FutureProvider<List<Sermon>>((ref) async {
  return ref.watch(sermonServiceProvider).fetchLatestSermons();
});
