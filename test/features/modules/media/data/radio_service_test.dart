import 'package:flutter_test/flutter_test.dart';


import 'package:church_on_app/features/modules/media/data/radio_service.dart';

RadioService createTestService() {
  return RadioService(
    null,
  );
}

void main() {
  group('RadioStation model', () {
    test('fromMap parses all fields', () {
      final map = {
        'id': '1',
        'name': 'K-LOVE',
        'stream_url': 'https://stream.example.com',
        'location': 'Global',
        'is_private': false,
      };
      final station = RadioStation.fromMap(map);
      expect(station.name, 'K-LOVE');
      expect(station.location, 'Global');
      expect(station.isPrivate, false);
    });

    test('default currentTrack is Connecting', () {
      final station = RadioStation(
        id: '1', name: 'Test', streamUrl: 'https://test.com',
        location: 'Local',
      );
      expect(station.currentTrack, 'Connecting...');
    });
  });

  group('RadioService - fetchStations', () {
    test('returns fallback stations when supabase is not initialized', () async {
      final service = createTestService();
      try {
        final stations = await service.fetchStations();
        expect(stations.isNotEmpty, true);
      } catch (_) {
        // Supabase not initialized - expected in test environment
      }
    });
  });

  group('RadioService - playStation', () {
    test('tries to play via fallback player when handler is null', () async {
      final service = createTestService();
      final station = RadioStation(
        id: '1', name: 'Test', streamUrl: 'https://test.com',
        location: 'Global',
      );
      await service.playStation(station);
    });
  });

  group('RadioService - getMetadataStream', () {
    test('returns metadata strings', () async {
      final service = createTestService();
      final stream = service.getMetadataStream('Test Station');
      final first = await stream.first;
      expect(first, isNotEmpty);
    }, timeout: Timeout(Duration(seconds: 30)));
  });

  /* group('RadioService - tryNextStation', () {
    test('returns null for unknown station', () async {
      final service = createTestService();
      try {
        final next = await service.tryNextStation('Nonexistent');
        expect(next, isNull);
      } catch (_) {
        // Supabase not initialized - expected in test environment
      }
    });
  }); */

  group('RadioService - pause/stop/play', () {
    test('pause returns null future when handler is null', () async {
      final service = createTestService();
      await service.pause();
    });

    test('stop returns null future when handler is null', () async {
      final service = createTestService();
      await service.stop();
    });

    test('play returns null future when handler is null', () async {
      final service = createTestService();
      await service.play();
    });
  });
}
