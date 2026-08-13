import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bible_books.dart';
import 'bible_audio_r2.dart';

class BiblePodcastEpisode {
  final String id;
  final String title;
  final String book;
  final String duration;
  final String thumbnailUrl;
  final String audioUrl;
  final String? description;
  final bool hasAudio;

  BiblePodcastEpisode({
    required this.id,
    required this.title,
    required this.book,
    required this.duration,
    required this.thumbnailUrl,
    required this.audioUrl,
    this.description,
    this.hasAudio = false,
  });
}

class BiblePodcastService {
  BiblePodcastService();

  // Books with LibriVox dramatized recordings
  static const _booksWithAudio = {
    'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy',
    'Joshua', 'Judges', 'Ruth', '1 Samuel', '2 Samuel',
    '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles',
    'Ezra', 'Nehemiah', 'Esther', 'Job', 'Psalms', 'Proverbs',
    'Ecclesiastes', 'Song of Solomon', 'Isaiah', 'Jeremiah',
    'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel',
    'Amos', 'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk',
    'Zephaniah', 'Haggai', 'Zechariah', 'Malachi',
    'Matthew', 'Mark', 'Luke', 'John', 'Acts', 'Romans',
    '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians',
    'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians',
    '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews',
    'James', '1 Peter', '2 Peter', '1 John', '2 John', '3 John',
    'Jude', 'Revelation',
  };

  String? _getAudioUrl(String bookName) => kjvR2BookUrl(bookName);

  bool _hasAudio(String book) => _booksWithAudio.contains(book);

  static const _bookSubtitles = {
    'Genesis': 'The Beginning of All Things', 'Exodus': 'The Great Deliverance',
    'Leviticus': 'Holiness and Law', 'Numbers': 'Wandering in the Wilderness',
    'Deuteronomy': 'The Law Repeated', 'Joshua': 'Possessing the Land',
    'Judges': 'Cycles of Deliverance', 'Ruth': 'A Story of Redemption',
    'Psalms': 'Songs of the Heart', 'Proverbs': 'Wisdom for Life',
    'Matthew': 'The Promised King', 'John': 'The Word Made Flesh',
    'Acts': 'The Church Empowered', 'Romans': 'The Power of the Gospel',
    'Revelation': 'The Ultimate Victory',
  };

  List<BiblePodcastEpisode> getAllEpisodes() {
    return bibleBooks.asMap().entries.map((entry) {
      final index = entry.key;
      final book = entry.value;
      final subtitle = _bookSubtitles[book] ?? 'Deep Dive into the Word';
      final available = _hasAudio(book);

      return BiblePodcastEpisode(
        id: 'ep_${index + 1}',
        title: available ? '$book — Dramatized Audio' : '$book: $subtitle',
        book: book,
        duration: available ? '~${3 + (index % 15)}:00' : 'TTS Only',
        thumbnailUrl: '', // Placeholder — Bible book art coming soon
        audioUrl: available ? (_getAudioUrl(book) ?? '') : '',
        description: available
            ? 'Dramatized reading of the Book of $book by LibriVox volunteers. Chapter-by-chapter audio narration with character voices.'
            : 'Audio recording not yet available for $book. Use Text-to-Speech (Read Aloud) or stream chapter audio from the Bible reader.',
        hasAudio: available,
      );
    }).toList();
  }
}

final biblePodcastProvider = Provider((ref) {
  return BiblePodcastService().getAllEpisodes();
});
