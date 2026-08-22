import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_on_app/core/utils/connectivity_util.dart';

void main() {
  group('connectivityProvider', () {
    test('connectivityProvider is a StreamProvider<bool>', () {
      expect(connectivityProvider, isA<StreamProvider<bool>>());
    });
  });

  group('OfflineBanner', () {
    testWidgets('shows offline message when connectivity is false', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith((ref) => Stream.value(false)),
            // offlineQueueProvider.overrideWith((ref) => Stream.value(0)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: OfflineBanner(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('YOU ARE OFFLINE'), findsWidgets);
    });

    testWidgets('hides when connectivity is true and queue is empty', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith((ref) => Stream.value(true)),
            // offlineQueueProvider.overrideWith((ref) => Stream.value(0)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: OfflineBanner(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('YOU ARE OFFLINE'), findsNothing);
    });

    testWidgets('banner hidden when online (sync-count badge not part of banner)', (tester) async {
      // NOTE: the OfflineBanner only renders in the offline state; the old
      // "N pending syncs / SYNC NOW" badge lives on the giving screen, not
      // this global banner.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith((ref) => Stream.value(true)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: OfflineBanner(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('YOU ARE OFFLINE'), findsNothing);
      expect(find.textContaining('pending syncs'), findsNothing);
      expect(find.text('SYNC NOW'), findsNothing);
    });
  });

  group('OfflineAwareWrapper', () {
    testWidgets('shows child when online', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith((ref) => Stream.value(true)),
            // offlineQueueProvider.overrideWith((ref) => Stream.value(0)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: OfflineAwareWrapper(
                child: Text('Main Content'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Main Content'), findsOneWidget);
      expect(find.textContaining('YOU ARE OFFLINE'), findsNothing);
    });

    testWidgets('shows banner and child when offline', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith((ref) => Stream.value(false)),
            // offlineQueueProvider.overrideWith((ref) => Stream.value(0)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: OfflineAwareWrapper(
                child: Text('Main Content'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Main Content'), findsOneWidget);
    });
  });
}
