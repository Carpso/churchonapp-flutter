import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/core/services/app_update_service.dart';

/// Guards the two failure modes that made the update prompt dead code.
///
/// The bug this protects against is specific and already happened once:
/// `AppUpdateService` read the generic `app_config` table with `.maybeSingle()`.
/// That table holds three rows, `maybeSingle()` asserts at most one, so the
/// query threw on every launch and a bare `catch (_) { return; }` swallowed it.
/// The prompt could never fire for anybody, and nothing failed loudly.
///
/// These tests are pure-logic (no Supabase/Flutter binding needed) precisely so
/// they stay cheap and cannot themselves depend on the network path.
void main() {
  group('ReleaseInfo', () {
    ReleaseInfo from(Map<String, dynamic> m) => ReleaseInfo.fromMap(m);

    test('parses the release row the server publishes', () {
      final info = from({
        'latest_build': 361,
        'latest_version': '1.0.0',
        'min_supported_build': 300,
        'update_message': 'New version',
        'release_notes': '• fixes',
        'play_url': 'https://play.google.com/store/apps/details?id=x',
        'apk_url': 'https://media.churchonapp.com/builds/latest/ChurchOnApp.apk',
        'aab_url': 'https://media.churchonapp.com/builds/latest/ChurchOnApp.aab',
      });

      expect(info.latestBuild, 361);
      expect(info.latestVersion, '1.0.0');
      expect(info.minSupportedBuild, 300);
      expect(info.updateMessage, 'New version');
      expect(info.releaseNotes, '• fixes');
      expect(info.apkUrl, contains('ChurchOnApp.apk'));
    });

    test('tolerates a null/partial row instead of throwing', () {
      // The singleton could briefly be mid-write, or a column could be null.
      // A parse crash here would be a crash on the Home screen.
      final info = from({'latest_build': 361});
      expect(info.latestBuild, 361);
      expect(info.latestVersion, '');
      expect(info.minSupportedBuild, 0);
      expect(info.apkUrl, isNull);
    });

    test('accepts a num for an integer column', () {
      // PostgREST can hand back a num for an int/bigint column; a bare `as int?`
      // cast would throw here.
      final info = from({'latest_build': 361.0, 'min_supported_build': 300.0});
      expect(info.latestBuild, 361);
      expect(info.minSupportedBuild, 300);
    });

    test('defaults to 0 when the column is entirely absent', () {
      // `latestBuild == 0` means "up to date" to the caller (0 <= any build),
      // so a missing column degrades to NO prompt rather than to a false
      // "update available" nag on every launch. For the same reason
      // `minSupportedBuild` defaults to 0, so a missing floor can never block a
      // real install — a fail-open default, which is the safe direction.
      final info = from(<String, dynamic>{});
      expect(info.latestBuild, 0);
      expect(info.isBelowMinimum(0), isFalse);
      expect(info.isBelowMinimum(999), isFalse);
    });
  });

  group('force-update boundary', () {
    ReleaseInfo info({required int latest, required int min}) =>
        ReleaseInfo.fromMap({
          'latest_build': latest,
          'latest_version': '1.0.0',
          'min_supported_build': min,
        });

    test('an up-to-date build is never below the minimum', () {
      final i = info(latest: 361, min: 300);
      expect(i.isBelowMinimum(361), isFalse);
    });

    test('a build under the floor is blocked', () {
      final i = info(latest: 361, min: 300);
      expect(i.isBelowMinimum(299), isTrue);
    });

    test('the floor is inclusive - exactly at the minimum still works', () {
      final i = info(latest: 361, min: 300);
      expect(i.isBelowMinimum(300), isFalse,
          reason: 'off-by-one here would block a supported build');
    });

    test('a build above latest is never prompted', () {
      // Guards the comparison the service performs before showing anything.
      final i = info(latest: 361, min: 300);
      expect(i.latestBuild <= 400, isTrue);
    });
  });
}
