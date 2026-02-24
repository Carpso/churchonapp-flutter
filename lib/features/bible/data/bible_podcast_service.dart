import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bible_books.dart';

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
  final List<String> _thumbnails = [
    "https://images.unsplash.com/photo-1504052434569-70ad5836ab65?w=500&q=80",
    "https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=500&q=80",
    "https://images.unsplash.com/photo-1512389142860-9c449e58a543?w=500&q=80",
    "https://images.unsplash.com/photo-1544427928-c49cdfebf4ad?w=500&q=80",
    "https://images.unsplash.com/photo-1516280440614-37939bbacd81?w=500&q=80"
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

  List<BiblePodcastEpisode> getAllEpisodes() {
    return bibleBooks.map((book) {
      final subtitle = _bookSubtitles[book] ?? 'Deep Dive into the Word';
      int index = bibleBooks.indexOf(book);
      
      return BiblePodcastEpisode(
        id: 'ep_${index + 1}',
        title: '$book: $subtitle',
        book: book,
        duration: '${15 + (index % 45)}:00',
        thumbnailUrl: _thumbnails[index % _thumbnails.length],
        audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-${(index % 10) + 1}.mp3',
        description: 'Explore the profound truths and historical context of the Book of $book in this comprehensive audio study.',
      );
    }).toList();
  }
}

final biblePodcastProvider = Provider((ref) => BiblePodcastService().getAllEpisodes());
