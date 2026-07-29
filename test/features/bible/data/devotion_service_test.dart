
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/bible/data/devotion_service.dart';
import '../../../test_mocks.dart';

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late MockMaybeSingleBuilder mockMaybeSingle;
  late DevotionService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    mockMaybeSingle = MockMaybeSingleBuilder();
    service = DevotionService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
  });

  group('fetchDevotions', () {
    test('returns fallback devotions when supabase queries fail', () async {
      when(() => mockClient.from('daily_bible_verses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(50)).thenThrow(Exception('db error'));

      when(() => mockClient.from('devotions')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(50)).thenThrow(Exception('devotions error'));

      final devotions = await service.fetchDevotions();
      expect(devotions.length, 4);
      expect(devotions.first.title, 'Jeremiah 29:11');
      expect(devotions.first.isToday, true);
    });

    test('fallback devotions have all required fields', () async {
      when(() => mockClient.from('daily_bible_verses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(50)).thenThrow(Exception('error'));

      when(() => mockClient.from('devotions')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(50)).thenThrow(Exception('error'));

      final devotions = await service.fetchDevotions();
      for (final d in devotions) {
        expect(d.id, isNotEmpty);
        expect(d.title, isNotEmpty);
        expect(d.reference, isNotEmpty);
        expect(d.reflection, isNotEmpty);
        expect(d.prayer, isNotEmpty);
      }
    });
  });

  group('fetchTodaysDevotion', () {
    test('returns null when no devotion available today', () async {
      when(() => mockClient.from('daily_bible_verses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.gte('created_at', any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.lt('created_at', any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(1)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = null;

      final devotion = await service.fetchTodaysDevotion();
      expect(devotion, isNull);
    });

    test('returns devotion when available today', () async {
      final now = DateTime.now();
      when(() => mockClient.from('daily_bible_verses')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.gte('created_at', any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.lt('created_at', any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(1)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.maybeSingle()).thenAnswer((_) => mockMaybeSingle);
      mockMaybeSingle.result = {
        'id': 'd1',
        'title': 'Today\'s Devotion',
        'reference': 'Psalm 1:1',
        'text': 'Blessed is the man',
        'reflection': 'A blessed life starts with God',
        'prayer': 'Lord, guide me',
        'created_at': now.toIso8601String(),
      };

      final devotion = await service.fetchTodaysDevotion();
      expect(devotion, isNotNull);
      expect(devotion!.isToday, true);
      expect(devotion.title, 'Today\'s Devotion');
    });
  });

  group('Devotion model', () {
    test('excerpt truncates long text at 120 chars', () {
      final devotion = Devotion(
        id: '1',
        title: 'Test',
        reference: 'Test',
        scriptureText: 'A' * 200,
        reflection: 'Short',
        prayer: 'Amen',
        date: DateTime.now(),
      );
      expect(devotion.excerpt.length, 123);
      expect(devotion.excerpt, endsWith('...'));
    });

    test('excerpt returns full text when under 120 chars', () {
      final devotion = Devotion(
        id: '1',
        title: 'Test',
        reference: 'Test',
        scriptureText: 'Short text',
        reflection: 'Short',
        prayer: 'Amen',
        date: DateTime.now(),
      );
      expect(devotion.excerpt, 'Short text');
    });

    test('formattedDate returns correct format', () {
      final date = DateTime(2026, 7, 8);
      final devotion = Devotion(
        id: '1',
        title: 'Test',
        reference: 'Test',
        scriptureText: '',
        reflection: 'Reflect',
        prayer: 'Amen',
        date: date,
      );
      expect(devotion.formattedDate, 'Jul 8, 2026');
    });
  });
}
