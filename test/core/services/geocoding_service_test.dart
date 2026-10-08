// Regression test for the public-geocoder throttle.
//
// The bug it locks down: Nominatim's usage policy allows ONE request per
// second, and photon.komoot.io's public instance is demo-grade. GeocodingService
// had no throttle at all, so every client could fire in parallel. Once an app's
// IP gets blocked, reverse geocoding silently returns null - and to a user that
// is indistinguishable from "the driver was sent to the wrong place".
//
// These tests use the public chain only through the throttle's own behaviour, so
// they make NO network calls: they assert the queue's ordering/timing logic
// directly.
import 'package:church_on_app/core/services/geocoding_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeocodingService provider throttle', () {
    test('serialises concurrent requests instead of firing them in parallel',
        () async {
      var inFlight = 0;
      var maxConcurrent = 0;
      final order = <int>[];

      // Fire five lookups "at once" and assert the throttle kept them serial.
      final futures = List.generate(5, (i) {
        return GeocodingService.throttled(() async {
          inFlight++;
          if (inFlight > maxConcurrent) maxConcurrent = inFlight;
          order.add(i);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          inFlight--;
          return i;
        });
      });

      final results = await Future.wait(futures);

      expect(maxConcurrent, 1,
          reason: 'more than one geocoder request was in flight at once');
      expect(order, [0, 1, 2, 3, 4],
          reason: 'requests must run in the order they were queued');
      expect(results, [0, 1, 2, 3, 4]);
    });

    test('a throwing request does not deadlock the queue behind it', () async {
      // If the failing request never released its slot, this second call would
      // never complete and the test would time out.
      final first = GeocodingService.throttled(() async => throw Exception('provider 500'));
      final second = GeocodingService.throttled(() async => 42);

      await expectLater(first, throwsA(isA<Exception>()));
      expect(await second, 42,
          reason: 'a failed geocoder call must not block later ones');
    });

    test('keeps a minimum gap between consecutive requests', () async {
      final stopwatch = Stopwatch()..start();
      await GeocodingService.throttled(() async => null);
      await GeocodingService.throttled(() async => null);
      stopwatch.stop();

      // Two back-to-back requests must be separated by at least the ~1.1s gap
      // the public providers require.
      expect(stopwatch.elapsedMilliseconds,
          greaterThanOrEqualTo(1000),
          reason: 'two sequential geocoder calls were not throttled');
    });
  });
}
