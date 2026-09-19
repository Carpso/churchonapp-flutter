import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

/// Quick reactions allowed on a story (must match the server CHECK/RPC).
const List<String> kStoryReactions = ['❤️', '🙏', '🔥', '😂', '👏'];

/// Maximum story lifetime = 1 year (server clamps to the same cap).
const int kStoryMaxHours = 8760;

/// A selectable story lifetime.
class StoryDurationOption {
  final int hours;
  final String label;
  const StoryDurationOption(this.hours, this.label);
}

const List<StoryDurationOption> kStoryDurationOptions = [
  StoryDurationOption(24, '24 hours'),
  StoryDurationOption(24 * 7, '1 week'),
  StoryDurationOption(24 * 30, '1 month'),
];

/// Server-backed helpers for stories: durations, reactions, archive, highlights.
class StoryService {
  final SupabaseClient _client;
  StoryService(this._client);

  String? get _uid => _client.auth.currentUser?.id;

  // ── Durations ─────────────────────────────────────────────────────────────
  /// Clamp to the allowed window (client mirror of the server cap).
  int normalizeHours(int hours) => hours.clamp(1, kStoryMaxHours).toInt();

  Future<DateTime?> setExpiry(String storyId, int hours) async {
    final res = await _client.rpc('set_story_expiry', params: {
      'p_story_id': storyId,
      'p_hours': normalizeHours(hours),
    });
    if (res == null) return null;
    return DateTime.tryParse(res.toString());
  }

  // ── Reactions ─────────────────────────────────────────────────────────────
  /// Toggle my reaction on a story. Returns `{my_reaction: String?, count: int}`.
  Future<Map<String, dynamic>> reactToStory(
      String storyId, String reaction) async {
    final res = await _client.rpc('react_to_story', params: {
      'p_story_id': storyId,
      'p_reaction': reaction,
    });
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'my_reaction': null, 'count': 0};
  }

  /// My current reaction on a story, or null.
  Future<String?> myReaction(String storyId) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final row = await _client
          .from('social_story_reactions')
          .select('reaction')
          .eq('story_id', storyId)
          .eq('user_id', uid)
          .maybeSingle();
      return row?['reaction']?.toString();
    } catch (e) {
      debugPrint('my reaction fetch failed: $e');
      return null;
    }
  }

  Future<Map<String, int>> reactionSummary(String storyId) async {
    try {
      final rows = await _client.rpc('story_reaction_summary', params: {
        'p_story_id': storyId,
      });
      final out = <String, int>{};
      for (final r in (rows as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        out[m['reaction'].toString()] = (m['cnt'] as num?)?.toInt() ?? 0;
      }
      return out;
    } catch (e) {
      debugPrint('story reaction summary failed: $e');
      return {};
    }
  }

  // ── Archive ───────────────────────────────────────────────────────────────
  /// The poster's own stories (including expired ones), newest first.
  Future<List<Map<String, dynamic>>> fetchArchive() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _client
          .from('social_stories')
          .select('id, user_id, tenant_id, media_url, media_type, caption, '
              'thumbnail_url, created_at, expires_at, duration_hours, '
              'view_count, is_archived')
          .eq('user_id', uid)
          .eq('is_archived', true)
          .order('created_at', ascending: false)
          .limit(200);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('story archive fetch failed: $e');
      return [];
    }
  }

  Future<void> setArchived(String storyId, bool archived) async {
    await _client.rpc('set_story_archived', params: {
      'p_story_id': storyId,
      'p_archived': archived,
    });
  }

  /// Delete one of my own stories (RLS covers ownership).
  Future<void> deleteStory(String storyId) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _client
        .from('social_stories')
        .delete()
        .eq('id', storyId)
        .eq('user_id', uid);
  }

  /// Re-share an archived story: a fresh row with the same media + new lifetime.
  Future<void> reshare(
    Map<String, dynamic> source, {
    required int hours,
    String? caption,
    bool? isPublic,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not authenticated');
    await _client.from('social_stories').insert({
      'user_id': uid,
      'tenant_id': source['tenant_id'],
      'media_url': source['media_url'],
      'media_type': source['media_type'] ?? 'image',
      'thumbnail_url': source['thumbnail_url'],
      'caption': caption ?? source['caption'],
      'is_public': isPublic ?? false,
      'duration_hours': normalizeHours(hours),
    });
  }

  // ── Highlights ────────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchHighlights({String? userId}) async {
    final uid = userId ?? _uid;
    if (uid == null) return [];
    try {
      final rows = await _client
          .from('story_highlights')
          .select('id, user_id, title, cover_url, created_at, updated_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('story highlights fetch failed: $e');
      return [];
    }
  }

  /// Stories inside a highlight (works even for expired saved stories).
  Future<List<Map<String, dynamic>>> fetchHighlightStories(
      String highlightId) async {
    try {
      final rows = await _client.rpc('highlight_stories', params: {
        'p_highlight_id': highlightId,
      });
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('highlight stories fetch failed: $e');
      return [];
    }
  }

  Future<String?> createHighlight({
    required String title,
    String? coverUrl,
    List<String> storyIds = const [],
  }) async {
    final res = await _client.rpc('create_story_highlight', params: {
      'p_title': title,
      'p_cover_url': coverUrl,
      'p_story_ids': storyIds,
    });
    return res?.toString();
  }

  Future<void> updateHighlight(
    String highlightId, {
    required String title,
    String? coverUrl,
  }) async {
    await _client.rpc('update_story_highlight', params: {
      'p_highlight_id': highlightId,
      'p_title': title,
      'p_cover_url': coverUrl,
    });
  }

  Future<void> deleteHighlight(String highlightId) async {
    await _client.rpc('delete_story_highlight', params: {
      'p_highlight_id': highlightId,
    });
  }

  Future<void> addToHighlight(String highlightId, String storyId) async {
    await _client.rpc('add_story_to_highlight', params: {
      'p_highlight_id': highlightId,
      'p_story_id': storyId,
    });
  }

  Future<void> removeFromHighlight(String highlightId, String storyId) async {
    await _client.rpc('remove_story_from_highlight', params: {
      'p_highlight_id': highlightId,
      'p_story_id': storyId,
    });
  }
}

final storyServiceProvider = Provider<StoryService>((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return StoryService(client);
});

/// The signed-in user's story archive.
final storyArchiveProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(storyServiceProvider).fetchArchive();
});

/// A user's highlights (defaults to the signed-in user).
final storyHighlightsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>((ref, userId) {
  return ref.watch(storyServiceProvider).fetchHighlights(userId: userId);
});

/// Aggregate reactions for one story.
final storyReactionSummaryProvider = FutureProvider.autoDispose
    .family<Map<String, int>, String>((ref, storyId) {
  return ref.watch(storyServiceProvider).reactionSummary(storyId);
});
