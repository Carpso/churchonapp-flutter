import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/bible/data/bible_verse_service.dart';
import 'package:church_on_app/features/bible/data/curated_daily_verses.dart';
import '../../../test_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late BibleVerseService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    service = BibleVerseService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');
  });

  group('fetchLatestVerse', () {
    // The Verse of the Day is now a curated, thematic rotation served by the
    // `get_verse_of_the_day(p_date)` RPC. When the RPC is unreachable (as in
    // these unit tests, where it is unstubbed) the service must fall back to
    // the built-in uplifting set — never to random `bible_verses` rows.
    test('falls back to the curated uplifting set when the RPC is unreachable',
        () async {
      final verse = await service.fetchLatestVerse();
      final refs = kCuratedDailyVerses.map((v) => v.reference).toSet();
      expect(refs.contains(verse.reference), isTrue);
      expect(verse.text.trim(), isNotEmpty);
      expect(verse.theme.trim(), isNotEmpty);
    });

    test('never sources the daily verse from random bible_verses rows',
        () async {
      await service.fetchLatestVerse();
      verifyNever(() => mockClient.from('bible_verses'));
    });

    test('is deterministic for the same calendar day', () async {
      final first = await service.fetchLatestVerse();
      final second = await service.fetchLatestVerse();
      expect(first.reference, second.reference);
      expect(first.text, second.text);
    });
  });

  // postDailyVerse is deprecated: VOTD is served by the curated rotation, so the
  // call is intentionally a no-op and must never write anywhere.
  group('postDailyVerse', () {
    test('does not write to daily_bible_verses', () async {
      // ignore: deprecated_member_use_from_same_package
      await service.postDailyVerse(
          reference: 'John 3:16', text: 'For God so loved');

      verifyNever(() => mockClient.from('daily_bible_verses'));
    });

    test('does not fall back to social_posts', () async {
      // ignore: deprecated_member_use_from_same_package
      await service.postDailyVerse(
          reference: 'Psalm 23', text: 'The Lord is my shepherd');

      verifyNever(() => mockClient.from('social_posts'));
    });
  });
}
