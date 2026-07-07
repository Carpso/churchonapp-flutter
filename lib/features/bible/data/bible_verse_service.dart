import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:church_on_app/core/services/supabase_service.dart';

class DailyBibleVerse {
  final String id;
  final String reference;
  final String text;
  final DateTime createdAt;

  DailyBibleVerse({
    required this.id,
    required this.reference,
    required this.text,
    required this.createdAt,
  });

  factory DailyBibleVerse.fromMap(Map<String, dynamic> map) {
    return DailyBibleVerse(
      id: map['id']?.toString() ?? '',
      reference: map['reference'] ?? map['media_url'] ?? 'Scripture',
      text: map['text'] ?? map['content'] ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
    );
  }
}

class BibleVerseService {
  final SupabaseClient _client;
  BibleVerseService(this._client);

  Future<DailyBibleVerse> fetchLatestVerse() async {
    try {
      // 1. Try fetching from daily_bible_verses table
      final response = await _client
          .from('daily_bible_verses')
          .select()
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        return DailyBibleVerse.fromMap(response);
      }
    } catch (e) {
      // Use debugPrint for development-only logging
      debugPrint('Querying daily_bible_verses failed, falling back: $e');
      debugPrint(e.toString());
    }

    try {
      // 2. Fallback: fetch from social_posts with category 'daily_verse'
      final response = await _client
          .from('social_posts')
          .select()
          .eq('category', 'daily_verse')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        return DailyBibleVerse.fromMap(response);
      }
    } catch (e, s) {
      debugPrint('Querying fallback social_posts failed: $e');
      debugPrint(s.toString());
    }

    // 3. Last fallback: return a default beautiful verse
    return DailyBibleVerse(
      id: 'default',
      reference: 'Jeremiah 29:11',
      text:
          'For I know the thoughts that I think toward you, saith the Lord, thoughts of peace, and not of evil, to give you an expected end.',
      createdAt: DateTime.now(),
    );
  }

  Future<void> postDailyVerse({
    required String reference,
    required String text,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Try to insert into daily_bible_verses
      await _client.from('daily_bible_verses').insert({
        'reference': reference,
        'text': text,
        'posted_by': user.id,
      });
      debugPrint('Successfully posted to daily_bible_verses');
    } catch (e, s) {
      debugPrint('Posting to daily_bible_verses failed, falling back: $e');
      debugPrint(s.toString());
      // 2. Fallback: insert into social_posts table with category = 'daily_verse'
      await _client.from('social_posts').insert({
        'user_id': user.id,
        'content': text,
        // Storing reference in a field named 'media_url' can be confusing.
        // A better approach would be to have a dedicated 'reference' field or use metadata.
        // For now, we'll keep it but acknowledge it's not ideal.
        'media_url': reference,
        'category': 'daily_verse',
      });
      debugPrint('Successfully posted to fallback social_posts');
    }
  }
}

final bibleVerseServiceProvider = Provider((ref) {
  final client = ref.watch(supabaseServiceProvider).client;
  return BibleVerseService(client);
});

final dailyBibleVerseProvider = FutureProvider<DailyBibleVerse>((ref) async {
  return ref.watch(bibleVerseServiceProvider).fetchLatestVerse();
});
