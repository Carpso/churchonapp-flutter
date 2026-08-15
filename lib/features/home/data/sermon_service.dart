import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Sermon {
  final String id;
  final String title;
  final String preacher;
  final String thumbnailUrl;
  final String videoUrl;
  final String audioUrl;
  final bool isLive;
  final int viewerCount;
  final int amenCount;
  final int insightCount;
  final String category;
  final int? durationMinutes;
  final String? transcript;
  final String? aiSummary;
  final DateTime createdAt;

  Sermon({
    required this.id,
    required this.title,
    required this.preacher,
    required this.thumbnailUrl,
    required this.videoUrl,
    this.audioUrl = '',
    this.isLive = false,
    this.viewerCount = 0,
    this.amenCount = 0,
    this.insightCount = 0,
    this.category = 'General',
    this.durationMinutes,
    this.transcript,
    this.aiSummary,
    required this.createdAt,
  });

  factory Sermon.fromMap(Map<String, dynamic> map) {
    return Sermon(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? 'Untitled Sermon',
      preacher: map['preacher'] ?? 'Unknown Preacher',
      thumbnailUrl: map['thumbnail_url'] ?? '',
      videoUrl: map['video_url'] ?? '',
      audioUrl: map['audio_url'] ?? '',
      isLive: map['is_live'] ?? false,
      viewerCount: map['viewer_count'] ?? 0,
      amenCount: (map['amen_count'] as num?)?.toInt() ?? 0,
      insightCount: (map['insight_count'] as num?)?.toInt() ?? 0,
      category: map['category'] ?? 'General',
      durationMinutes: map['duration_minutes'] as int?,
      transcript: map['transcript'],
      aiSummary: map['ai_summary'],
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class SermonService {
  final SupabaseClient _client;
  SermonService(this._client);

  Future<List<Sermon>> fetchLatestSermons({
    int offset = 0,
    int limit = 10,
    String? category,
  }) async {
    try {
      final hasCategory = category != null && category.isNotEmpty;
      final response = hasCategory
          ? await _client
              .from('sermons')
              .select()
              .eq('category', category)
              .order('created_at', ascending: false)
              .range(offset, offset + limit - 1)
          : await _client
              .from('sermons')
              .select()
              .order('created_at', ascending: false)
              .range(offset, offset + limit - 1);

      return (response as List).map((s) => Sermon.fromMap(s)).toList();
    } catch (e) {
      debugPrint('Failed to fetch sermons: $e');
      return [];
    }
  }

  Future<List<String>> fetchCategories() async {
    try {
      final response = await _client
          .from('sermons')
          .select('category')
          .limit(300);
      final categories = (response as List)
          .map((r) => (r['category'] ?? '').toString())
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      return categories;
    } catch (e) {
      debugPrint('Failed to fetch sermon categories: $e');
      return const [];
    }
  }

  Future<void> reactToSermon(String sermonId, String type, {String? content}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      debugPrint('SermonService: No authenticated user');
      throw Exception('You must be logged in to react to sermons');
    }

    // Get user's tenant/church info for proper scoping
    String? tenantId;
    String? churchId;
    try {
      final profile = await _client.from('profiles').select('tenant_id, church_id').eq('id', user.id).maybeSingle();
      if (profile != null) {
        tenantId = profile['tenant_id'] as String?;
        churchId = profile['church_id'] as String?;
      }
    } catch (e) {
      debugPrint('SermonService: Could not fetch user tenant/church: $e');
    }

    // "Amen" is a toggle — one reaction per user per sermon so the count
    // reflects distinct worshippers, not taps. Tapping again removes it.
    if (type == 'amen') {
      final existing = await _client
          .from('sermon_reactions')
          .select('id')
          .eq('sermon_id', sermonId)
          .eq('user_id', user.id)
          .eq('reaction_type', 'amen')
          .maybeSingle();
      if (existing != null) {
        await _client.from('sermon_reactions').delete().eq('id', existing['id']);
        return;
      }
    }

    await _client.from('sermon_reactions').insert({
      'sermon_id': sermonId,
      'user_id': user.id,
      'reaction_type': type,
      'content': content,
      'tenant_id': tenantId,
      'church_id': churchId,
    });
  }

  Future<bool> hasUserReacted(String sermonId, String type) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final existing = await _client
          .from('sermon_reactions')
          .select('id')
          .eq('sermon_id', sermonId)
          .eq('user_id', user.id)
          .eq('reaction_type', type)
          .maybeSingle();
      return existing != null;
    } catch (e) {
      debugPrint('SermonService: hasUserReacted error: $e');
      return false;
    }
  }

  Stream<List<Map<String, dynamic>>> streamSermonInsights(String sermonId) {
    return _client
        .from('sermon_reactions')
        .stream(primaryKey: ['id'])
        .eq('sermon_id', sermonId)
        .order('created_at', ascending: false)
        .map((data) => data.where((e) => e['reaction_type'] == 'discuss').toList());
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
      final response = await _client
          .from('sermons')
          .select()
          .or('title.ilike.%$query%,preacher.ilike.%$query%')
          .order('created_at', ascending: false);
      return (response as List).map((s) => Sermon.fromMap(s)).toList();
    }
  }
}

final sermonServiceProvider = Provider((ref) => SermonService(Supabase.instance.client));

final latestSermonsProvider = FutureProvider<List<Sermon>>((ref) async {
  return ref.watch(sermonServiceProvider).fetchLatestSermons();
});

final sermonInsightsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, sermonId) {
  return ref.watch(sermonServiceProvider).streamSermonInsights(sermonId);
});

