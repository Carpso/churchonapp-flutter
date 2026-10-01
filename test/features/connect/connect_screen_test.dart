import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:church_on_app/features/connect/presentation/connect_screen.dart';

/// KNOWN ISSUE — one test in this file still fails, and it is a pre-existing
/// harness limitation, not an app regression.
///
/// `ConnectScreen` mounts the social feed and stories bar, which hit Supabase on
/// first build. Against the dummy client those requests fail and the PostgREST
/// stream retries on a real timer. A `testWidgets` body runs under `fake_async`,
/// so that live retry is still outstanding at teardown and the test dies with
/// "A Timer is still pending even after the widget tree was disposed".
///
/// Initialising Supabase with dummy values is what the error was before this
/// change (`_instance._isInitialized` — the screen never rendered at all, so
/// BOTH tests failed). With the dummy client the FAB test now passes and the
/// screen demonstrably renders; only the strict teardown check remains.
///
/// The proper fix is to make the feed injectable (a `supabaseClientProvider`
/// that defaults to `Supabase.instance.client`) so the test can pass a mock and
/// never touch the network. That is a production refactor of shared code and is
/// deliberately left out of the streaming work.
void main() {
  setUpAll(() async {
    // Supabase's auth storage is SharedPreferences-backed, so mock it first.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://dummy.supabase.co',
      publishableKey: 'dummy-key',
    );
  });

  testWidgets('Connect screen renders without error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: ConnectScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(ConnectScreen), findsOneWidget);
  });

  testWidgets('Connect screen has floating action button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [],
        child: const MaterialApp(home: ConnectScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
