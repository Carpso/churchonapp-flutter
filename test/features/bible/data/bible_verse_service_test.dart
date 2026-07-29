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
    test('returns verse from daily_bible_verses table on success', () async {
      mockMaybeSingle.result = {
        'id': '1',
        'reference': 'John 3:16',
        'text': 'For God so loved the world',
        'created_at': DateTime.now().toIso8601String(),
      };

      when(() => mockClient.from('daily_bible_verses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(1)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);

      final verse = await service.fetchLatestVerse();
      expect(verse.id, '1');
      expect(verse.reference, 'John 3:16');
      expect(verse.text, 'For God so loved the world');
    });

    test('falls back to social_posts when daily_bible_verses fails', () async {
      mockMaybeSingle.result = {
        'id': '2',
        'reference': 'Psalm 23:1',
        'text': 'The Lord is my shepherd',
        'created_at': DateTime.now().toIso8601String(),
      };

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
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);

      final verse = await service.fetchLatestVerse();
      expect(verse.id, '2');
      expect(verse.reference, 'Psalm 23:1');
    });

    test('returns default verse when all queries fail', () async {
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
      expect(verse.id, startsWith('daily_seeded_'));
      expect(verse.reference, isNotEmpty);
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

  group('postDailyVerse', () {
    test('inserts into daily_bible_verses on success', () async {
      when(() => mockClient.from('daily_bible_verses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(
        {
          'reference': 'John 3:16',
          'text': 'For God so loved',
          'posted_by': 'user_1',
        },
        defaultToNull: true,
      )).thenAnswer((_) => mockFilter);

      await service.postDailyVerse(reference: 'John 3:16', text: 'For God so loved');

      verify(() => mockQuery.insert(
        {
          'reference': 'John 3:16',
          'text': 'For God so loved',
          'posted_by': 'user_1',
        },
        defaultToNull: true,
      )).called(1);
    });

    test('falls back to social_posts when daily_bible_verses insert fails', () async {
      when(() => mockClient.from('daily_bible_verses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(
        {
          'reference': 'Psalm 23',
          'text': 'The Lord is my shepherd',
          'posted_by': 'user_1',
        },
        defaultToNull: true,
      )).thenThrow(Exception('insert error'));

      when(() => mockClient.from('social_posts')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(
        {
          'user_id': 'user_1',
          'content': 'The Lord is my shepherd',
          'media_url': 'Psalm 23',
          'category': 'daily_verse',
        },
        defaultToNull: true,
      )).thenAnswer((_) => mockFilter);

      await service.postDailyVerse(reference: 'Psalm 23', text: 'The Lord is my shepherd');

      verify(() => mockQuery.insert(
        {
          'user_id': 'user_1',
          'content': 'The Lord is my shepherd',
          'media_url': 'Psalm 23',
          'category': 'daily_verse',
        },
        defaultToNull: true,
      )).called(1);
    });
  });
}
