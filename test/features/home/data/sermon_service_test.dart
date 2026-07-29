
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/home/data/sermon_service.dart';
import '../../../test_mocks.dart';

void main() {
  late MockSupabaseClient mockClient;
  late MockAuth mockAuth;
  late MockUser mockUser;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late SermonService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockAuth();
    mockUser = MockUser();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    service = SermonService(mockClient);

    when(() => mockClient.auth).thenReturn(mockAuth);
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    when(() => mockUser.id).thenReturn('user_1');
  });

  group('fetchLatestSermons', () {
    test('returns list of sermons on success', () async {
      when(() => mockClient.from('sermons')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(10)).thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [
        {
          'id': 's1',
          'title': 'Faith in Action',
          'preacher': 'Pastor John',
          'thumbnail_url': 'https://img.url',
          'video_url': 'https://video.url',
          'is_live': false,
          'viewer_count': 100,
          'created_at': DateTime.now().toIso8601String(),
        },
      ];

      final sermons = await service.fetchLatestSermons();
      expect(sermons.length, 1);
      expect(sermons.first.title, 'Faith in Action');
    });

    test('returns empty list when query fails', () async {
      when(() => mockClient.from('sermons')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      when(() => mockFilter.limit(10)).thenThrow(Exception('db error'));

      final sermons = await service.fetchLatestSermons();
      expect(sermons, isEmpty);
    });
  });

  group('reactToSermon', () {
    test('inserts reaction', () async {
      when(() => mockClient.from('sermon_reactions')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.insert(any())).thenAnswer((_) => mockFilter);

      await service.reactToSermon('s1', 'praise');
      verify(() => mockQuery.insert(any(that: containsPair('reaction_type', 'praise')))).called(1);
    });

    test('does nothing when user is null', () async {
      when(() => mockAuth.currentUser).thenReturn(null);

      await service.reactToSermon('s1', 'praise');
    });
  });

  group('searchSermons', () {
    test('searches by text search', () async {
      when(() => mockClient.from('sermons')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select()).thenAnswer((_) => mockFilter);
      when(() => mockFilter.textSearch('fts', 'faith', config: 'english')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('created_at', ascending: false)).thenAnswer((_) => mockFilter);
      mockFilter.mockResult = [];

      final results = await service.searchSermons('faith');
      expect(results, isEmpty);
    });
  });

  group('Sermon model', () {
    test('fromMap parses all fields', () {
      final map = {
        'id': 's1',
        'title': 'Grace',
        'preacher': 'Pastor Hope',
        'thumbnail_url': 'https://img.url',
        'video_url': 'https://vid.url',
        'is_live': true,
        'viewer_count': 500,
        'created_at': DateTime.now().toIso8601String(),
      };
      final sermon = Sermon.fromMap(map);
      expect(sermon.isLive, true);
      expect(sermon.viewerCount, 500);
    });
  });
}
