import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:church_on_app/core/services/smart_prefetch_service.dart';
import '../../test_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSupabaseClient mockClient;
  late SmartPrefetchService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    service = SmartPrefetchService(mockClient);
    SharedPreferences.setMockInitialValues({});
  });

  group('SmartPrefetchService Cache Operations', () {
    test('returns cached devotions when available in SharedPreferences', () async {
      final sampleDevotions = [
        {'id': 'd1', 'title': 'Morning Light', 'date': '2026-07-27'},
        {'id': 'd2', 'title': 'Evening Peace', 'date': '2026-07-26'},
      ];

      SharedPreferences.setMockInitialValues({
        'prefetch_devotions_v1': jsonEncode(sampleDevotions),
      });

      final cached = await service.getCachedDevotions();
      expect(cached.length, 2);
      expect(cached.first['title'], 'Morning Light');
    });

    test('returns empty list when cached devotions do not exist', () async {
      SharedPreferences.setMockInitialValues({});
      final cached = await service.getCachedDevotions();
      expect(cached, isEmpty);
    });

    test('returns cached sermons when available', () async {
      final sampleSermons = [
        {'id': 's1', 'title': 'The Anointing', 'preacher': 'Pastor David'},
      ];

      SharedPreferences.setMockInitialValues({
        'prefetch_sermons_v1': jsonEncode(sampleSermons),
      });

      final cached = await service.getCachedSermons();
      expect(cached.length, 1);
      expect(cached.first['title'], 'The Anointing');
    });

    test('returns cached events when available', () async {
      final sampleEvents = [
        {'id': 'e1', 'title': 'National Prayer Day'},
      ];

      SharedPreferences.setMockInitialValues({
        'prefetch_events_v1': jsonEncode(sampleEvents),
      });

      final cached = await service.getCachedEvents();
      expect(cached.length, 1);
      expect(cached.first['title'], 'National Prayer Day');
    });
  });
}
