import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/bible/data/bible_verse_service.dart';
import '../../../test_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late MockMaybeSingleBuilder mockMaybeSingle;
  late BibleVerseService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    mockMaybeSingle = MockMaybeSingleBuilder();
    service = BibleVerseService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');
  });

  group('fetchLatestVerse', () {
    // Verse of the Day is now derived deterministically from `bible_verses`
    // (no daily_bible_verses / social_posts lookups any more).
    test('returns the daily verse selected from bible_verses', () async {
      mockMaybeSingle.result = {
        'id': '1',
        'reference': 'John 3:16',
        'text': 'For God so loved the world',
        'book_id': 'john',
        'chapter': 3,
        'verse': 16,
      };

      when(() => mockClient.from('bible_verses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order(any(), ascending: any(named: 'ascending')))
          .thenAnswer((_) => mockFilter);
      when(() => mockFilter.range(any(), any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);

      final verse = await service.fetchLatestVerse();
      expect(verse.reference, 'John 3:16');
      expect(verse.text, 'For God so loved the world');
    });

    test('falls back to the curated default verse when bible_verses fails', () async {
      when(() => mockClient.from('bible_verses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order(any(), ascending: any(named: 'ascending')))
          .thenThrow(Exception('fail'));

      final verse = await service.fetchLatestVerse();
      expect(verse.id, 'default');
      expect(verse.reference, 'Jeremiah 29:11');
      expect(verse.text, isNotEmpty);
    });

    test('returns hardcoded default verse when all queries fail', () async {
      // The service's final fallback is the curated Jeremiah 29:11 verse with
      // id 'default' (the old daily_seeded_ rotation was removed).
      when(() => mockClient.from('daily_bible_verses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(1)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenThrow(Exception('fail'));

      when(() => mockClient.from('social_posts')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('category', 'daily_verse')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(1)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenThrow(Exception('fail too'));

      final verse = await service.fetchLatestVerse();
      expect(verse.id, 'default');
      expect(verse.reference, 'Jeremiah 29:11');
      expect(verse.text, isNotEmpty);
    });
  });

  /* group('getRandomVerse', () {
    test('returns a DailyBibleVerse with valid structure', () async {
      final verse = await service.getRandomVerse();
      expect(verse.id, isNotEmpty);
      expect(verse.reference, isNotEmpty);
      expect(verse.text, isNotEmpty);
    });
  }); */

  /* group('fetchTrendingSermonVerse', () {
    test('returns a trending verse from predefined list', () async {
      final verse = await service.fetchTrendingSermonVerse();
      expect(verse.id, startsWith('trending_'));
      expect(verse.reference, isNotEmpty);
      expect(verse.text, isNotEmpty);
    });

    test('returns different verses across multiple calls', () async {
      final verses = <String>{};
      for (int i = 0; i < 5; i++) {
        verses.add((await service.fetchTrendingSermonVerse()).reference);
      }
      expect(verses.length, greaterThanOrEqualTo(1));
    });
  }); */

  // postDailyVerse is deprecated: VOTD is generated from bible_verses, so the
  // call is intentionally a no-op and must never write anywhere.
  group('postDailyVerse', () {
    test('does not write to daily_bible_verses', () async {
      when(() => mockClient.from(any())).thenAnswer((_) => mockQuery);

      await service.postDailyVerse(reference: 'John 3:16', text: 'For God so loved');

      verifyNever(() => mockClient.from('daily_bible_verses'));
      verifyNever(() => mockQuery.insert(any()));
    });

    test('does not fall back to social_posts', () async {
      when(() => mockClient.from(any())).thenAnswer((_) => mockQuery);

      await service.postDailyVerse(reference: 'Psalm 23', text: 'The Lord is my shepherd');

      verifyNever(() => mockClient.from('social_posts'));
      verifyNever(() => mockQuery.insert(any()));
    });
  });
}
