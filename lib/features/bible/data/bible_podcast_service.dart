import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bible_books.dart';
import '../../../core/services/r2_service.dart';

class BiblePodcastEpisode {
  final String id;
  final String title;
  final String book;
  final String duration;
  final String thumbnailUrl;
  final String audioUrl;
  final String? description;

  BiblePodcastEpisode({
    required this.id,
    required this.title,
    required this.book,
    required this.duration,
    required this.thumbnailUrl,
    required this.audioUrl,
    this.description,
  });
}

class BiblePodcastService {
  BiblePodcastService();

  final SupabaseClient _supabase = Supabase.instance.client;

  final List<String> _thumbnails = [
    '',
    '',
    '',
    '',
    '',
  ];

  final Map<String, String> _bookSubtitles = {
    'Genesis': 'The Beginning of All Things',
    'Exodus': 'The Great Deliverance',
    'Leviticus': 'Holiness and Law',
    'Numbers': 'Wandering in the Wilderness',
    'Deuteronomy': 'The Law Repeated',
    'Joshua': 'Possessing the Land',
    'Judges': 'Cycles of Deliverance',
    'Ruth': 'A Story of Redemption',
    'Psalms': 'Songs of the Heart',
    'Proverbs': 'Wisdom for Life',
    'Matthew': 'The Promised King',
    'John': 'The Word Made Flesh',
    'Acts': 'The Church Empowered',
    'Romans': 'The Power of the Gospel',
    'Revelation': 'The Ultimate Victory',
  };

  String _getAudioUrl(String bookName, int index) {
    final slug = bookName.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return 'https://${R2Service.publicDomain}/bible-audio/$slug.wav';
  }

  List<BiblePodcastEpisode> getAllEpisodes() {
    return bibleBooks.asMap().entries.map((entry) {
      final index = entry.key;
      final book = entry.value;
      final subtitle = _bookSubtitles[book] ?? 'Deep Dive into the Word';

      final audioUrl = _getAudioUrl(book, index);
      return BiblePodcastEpisode(
        id: 'ep_${index + 1}',
        title: '$book: $subtitle',
        book: book,
        duration: '${15 + (index % 45)}:00',
        thumbnailUrl: _thumbnails[index % _thumbnails.length],
        audioUrl: audioUrl,
        description: 'Explore the profound truths and historical context of the Book of $book in this comprehensive audio study.',
      );
    }).toList();
  }

  Future<String> generateDramatizedContent(String bookName) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'dramatized_$bookName';
    final cached = prefs.getString(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    try {
      final response = await _supabase.functions.invoke(
        'kael-ai',
        body: {
          'action': 'dramatize',
          'prompt': 'Create a dramatic, cinematic narration script for the Book of $bookName from the Bible. Include vivid scene descriptions, character emotions, and atmospheric details. Format as a spoken-word script suitable for audio drama.',
        },
      );

      final content = response.data?['response'] ?? response.data?['content'] ?? response.data?['text'] ?? '';
      if (content is String && content.isNotEmpty) {
        await prefs.setString(cacheKey, content);
        return content;
      }
      return '';
    } catch (e) {
      return '';
    }
  }
}

final biblePodcastProvider = Provider((ref) {
  return BiblePodcastService().getAllEpisodes();
});
