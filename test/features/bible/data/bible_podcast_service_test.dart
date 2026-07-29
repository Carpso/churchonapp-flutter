
import 'package:flutter_test/flutter_test.dart';

import 'package:church_on_app/features/bible/data/bible_books.dart';

void main() {
  /* group('BiblePodcastEpisode', () {
    test('durationString formats correctly', () {
      final ep = BiblePodcastEpisode(
        id: 'test-1',
        title: 'Genesis 1',
        book: 'Genesis',
        duration: const Duration(minutes: 5, seconds: 30),
        thumbnailUrl: 'https://example.com/thumb.jpg',
        audioUrl: 'https://example.com/audio.mp3',
      );
      expect(ep.durationString, '05:30');
    });

    test('durationString handles zero duration', () {
      final ep = BiblePodcastEpisode(
        id: 'test-2',
        title: 'Test',
        book: 'Genesis',
        duration: Duration.zero,
        thumbnailUrl: '',
        audioUrl: '',
      );
      expect(ep.durationString, '00:00');
    }); */

    /* test('isAvailable reflects audioUrl presence', () {
      final withUrl = BiblePodcastEpisode(
        id: 'a',
        title: 'A',
        book: 'Genesis',
        duration: Duration.zero,
        thumbnailUrl: '',
        audioUrl: 'https://example.com/a.mp3',
      );
      expect(withUrl.isAvailable, isTrue);

      final withoutUrl = BiblePodcastEpisode(
        id: 'b',
        title: 'B',
        book: 'Genesis',
        duration: Duration.zero,
        thumbnailUrl: '',
        audioUrl: '',
      );
      expect(withoutUrl.isAvailable, isFalse);
    }); */
  // });

  group('bibleBooks list', () {
    test('contains all 66 books', () {
      expect(bibleBooks.length, 66);
    });

    test('starts with Genesis and ends with Revelation', () {
      expect(bibleBooks.first, 'Genesis');
      expect(bibleBooks.last, 'Revelation');
    });
  });
}
