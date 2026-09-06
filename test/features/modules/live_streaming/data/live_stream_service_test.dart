import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:church_on_app/features/modules/live_streaming/data/live_stream_service.dart';
import '../../../../test_mocks.dart';

void main() {
  late MockSupabaseClient mockClient;
  late MockQueryBuilder mockQuery;
  late MockFilterBuilder mockFilter;
  late LiveStreamService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockQuery = MockQueryBuilder();
    mockFilter = MockFilterBuilder();
    service = LiveStreamService(mockClient);
  });

  group('LiveStreamService Fallback and Stream Querying', () {
    // Demo/placeholder streams were deliberately removed so the UI never
    // presents a sample video as a live church service — errors now yield an
    // honest empty list.
    test('getActiveStreams returns empty list when query throws or returns empty', () async {
      when(() => mockClient.from('live_streams')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('status', 'live')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('started_at', ascending: false)).thenThrow(Exception('DB connection failed'));

      final streams = await service.getActiveStreams();

      expect(streams, isEmpty);
    });

    test('getUpcomingStreams returns empty list when query throws', () async {
      when(() => mockClient.from('live_streams')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('status', 'scheduled')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.gte('scheduled_at', any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('scheduled_at')).thenThrow(Exception('DB connection failed'));

      final upcoming = await service.getUpcomingStreams();

      expect(upcoming, isEmpty);
    });

    test('getActiveStreams returns live streams from Supabase on success', () async {
      when(() => mockClient.from('live_streams')).thenAnswer((_) => mockQuery);
      when(() => mockQuery.select(any())).thenAnswer((_) => mockFilter);
      when(() => mockFilter.eq('status', 'live')).thenAnswer((_) => mockFilter);
      when(() => mockFilter.order('started_at', ascending: false)).thenAnswer((_) => mockFilter);

      mockFilter.mockResult = [
        {
          'id': 'stream_101',
          'title': 'Sunday Morning Service Live',
          'status': 'live',
          'started_at': DateTime.now().toIso8601String(),
          'viewer_count': 350,
          'churches': {
            'id': 'c1',
            'name': 'Faith Dome',
          },
        },
      ];

      final streams = await service.getActiveStreams();

      expect(streams.length, 1);
      expect(streams.first['id'], 'stream_101');
      expect(streams.first['title'], 'Sunday Morning Service Live');
      expect(streams.first['viewer_count'], 350);
    });
  });
}
